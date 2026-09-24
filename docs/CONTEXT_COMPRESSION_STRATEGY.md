# Bridge App — Context 壓縮策略設計稿

**作者**：小葵
**日期**：2026-09-20
**觸發**：9/19 gpt-6-astra cache writes 燒 $35 事件
**狀態**：草案（待 Blue 拍板後實作）

---

## 0. 為什麼需要這個

Agent Loop 跑長任務時，messages 陣列會膨脹：
- `排程任務測試` 對話：179 則訊息（~6 萬字 / ~3 萬 tokens 純歷史）
- `專案畫布對話`：36 則
- 工單/排程對話：動輒 50-100 輪

問題不是「記憶不夠大」，是 **每輪都把整串歷史重送一次**：

1. **Cache 命中率**：1️⃣ 已修（真多輪 messages array 直送，prefix 凍結）
2. **Context 本身太肥**：旗艦模型拿 5 萬 tokens 歷史只是為了產生 100 tokens 回覆——attention 浪費在無關舊輪，推理品質反而下降
3. **浪費不只是錢**：長 context 推理速度變慢，連帶影響 loop 收斂速度

---

## 1. 三層壓縮架構（從穩到激進）

### 第 1 層：靜態分段（永遠開啟，零成本）

把 messages 切成三段：

```
[
  system_prompt,                       // 🔒 不動，永遠 prefix
  initial_user_task,                   // 🔒 不動，保留任務原意
  ...compressible_middle...,            // ⬇️ 中間可壓縮
  last_k_recent_turns,                 // 🟢 不壓，保留近期原貌
]
```

**壓縮啟動條件**：當 `compressible_middle.length > N` 條時觸發。
**預設 N=10**（保留最近 10 則原文）。
**特點**：
- `system_prompt` 和 `initial_user_task` 永遠不動 → prefix 完全凍結
- `last_k_recent_turns` 永遠保留原文 → 模型看得到當下最新狀態
- 中間區段可任意壓縮 → cache write 只在壓縮觸發那輪產生，之後讀的是 compact cache

### 第 2 層：語義摘要（智能壓縮）

中間區段用 LLM 摘要成 1 則 user 訊息：

```
[歷史摘要 - 3 步已完成：
1. 排查 schedule_sync_service.dart 的 _nodeRunner 注入問題
2. 測試：commit 1a5590b4 修復後藍排程工作
3. 教練驗證：實物查核 commit 0ab9ee4a 上線 ✓
當前狀態：等待 Blue 對終點畫面描述回饋]
```

**壓縮模型**：階梯最便宜那階（gpt-4o-mini / glm-4.5）
- 理由：摘要任務不需要旗艦推理，便宜款品質夠
- 預期成本：~1k tokens × 旗艦牌價 / 8 階梯 = 比用 astra 壓縮便宜 10x

**壓縮觸發頻率**：每累積 10 輪中間訊息壓一次（不每輪壓，省 compression 自身成本）
**失敗處理**：摘要 LLM 失敗 → 退回到第 3 層粗暴截斷

### 第 3 層：粗暴截斷（fallback / 本地模式）

完全沒 LLM 幫忙時（本地模式 / 第 2 層失敗）：

```
保留：system + initial_user_task + [歷史摘要一行] + 最近 8 輪
```

第 3 層就是現在 `_truncateOldTurns` 的行為，但改為：永遠做這件事（不只 local 才用）。

---

## 2. 設計細節

### 2.1 誰負責壓縮？——獨立 service `ContextCompressor`

```dart
class ContextCompressor {
  /// 對 messages 陣列做第 1+2 層壓縮。
  /// - 永遠做第 1 層分段
  /// - 中間區段超過 threshold 才呼叫第 2 層摘要
  /// - 結果：壓縮後的 messages 陣列 + 摘要 metadata
  static CompressedContext compress(
    List<Map<String, dynamic>> messages, {
    required int recentKeep,         // 第 1 層：保留最近 N 則原文
    required int middleCompressAt,   // 第 2 層：超過 N 則觸發摘要
    required Future<String> Function(String prompt) summarizer,
  });
}
```

放在 `lib/services/context_compressor.dart`。

### 2.2 摘要的 prompt 模板

```
你正在為一個 agent 壓縮對話歷史。請保留：
1. 已完成的工作（commit hash、驗證結果）
2. 使用者最近的具體指示與決定
3. 還沒完成的工作清單
4. 任何已知的失敗/陷阱/被警告的錯誤

請刪除：
1. 重複的同義改寫
2. 純粹禮貌/招呼
3. 太長的原始碼輸出（保留「改了哪幾個檔案 + 改什麼」即可）
4. 已被新訊息覆蓋的計劃

限制 200 字以內。
```

### 2.3 壓縮的時機

壓縮在 **`complete()` 呼叫之前** 做，而不是每輪結束後做。理由：
- Agent Loop 結構：先構建 messages → 送 LLM
- 我們在「構建 messages 最後一步」做壓縮
- 等同「送出去前才瘦身」，cache 寫一次，之後每輪讀 compact cache

```dart
// agent_loop.dart 內
for (int turn = 0; ...) {
  if (turn > 0 && _shouldCompress(messages)) {
    messages = await ContextCompressor.compress(messages, ...);
  }
  // ... 呼叫 LLM
}
```

### 2.4 計程車表的整合

每次壓縮的「成本/節省」也要寫入 ledger：
- 壓縮本身花了多少 tokens（呼叫摘要模型）
- 壓縮前 vs 壓縮後的 input tokens 差

讓 Blue 看得到「壓縮省了 $X」，驗證壓縮策略是否真的省錢。

---

## 3. 預期效益（量級估算）

假設一個 50 輪的 agent loop：

| 策略 | 平均 input tokens/輪 | 累計 cost（astra 牌價） |
|---|---|---|
| 不壓縮（現在） | 30,000 | $1.88 |
| 第 1 層分段 + 第 2 層摘要 | 8,000 | $0.50 |
| 第 3 層截斷（粗暴） | 12,000 | $0.75 |

**預期砍 60-75%**。驗證方式：計程車表落地後跑實際任務比對。

---

## 4. 風險與緩解

### 風險 1：摘要掉了重要細節
- 緩解：摘要 prompt 明說「保留 commit hash、驗證結果」
- 緩衝：保留 `last_k_recent_turns=10` 原文，重要事件通常在最近 10 輪
- 驗證：壓縮後做 round-trip test（壓縮 → LLM 答 → 對比不壓縮的答案）

### 風險 2：摘要本身的成本吃掉省下的成本
- 緩解：摘要用最便宜階梯，且只在 `compressible_middle > 10` 時觸發
- 監控：計程車表記錄每次摘要花費

### 風險 3：摘要太頻繁，cache write 又被觸發
- 緩解：摘要結果作為 user message 注入（不是 system），prefix 仍凍結
- 驗證：實際跑下來看 cache hit rate 有沒有提升

---

## 5. 實作順序（待 Blue 拍板）

1. **第一步**：`lib/services/context_compressor.dart` 純函式庫，無 IO
2. **第二步**：在 `production_agent_loop_llm_client.dart` 串接
3. **第三步**：計程車表加壓縮條目
4. **第四步**：跑幾個真實任務做 A/B 對照

預估工作量：3-4 小時（含測試與驗證）。

---

## 6. 待 Blue 拍板

1. **threshold 預設值**：recent_keep=10 / middle_compress_at=10 可以嗎？
2. **是否要做 round-trip test 套件**？建議做，但會增加約 1 小時。
3. **是否要讓使用者看到「這輪壓縮省了 $X」的 UI 條目**？建議做（計程車表延伸）。
