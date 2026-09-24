# Spec：模型 Fallback 顯性標示（Model Fallback Transparency）

> **狀態**：Draft v1（2026-09-05，小葵）
> **起源事故**：2026-08-26 Blue 取消 OpenAI API Key 後，兩個 cron job（每日照片判讀、IG 晨間拾穗）
> 的 `provider=custom:openai` 靜默失效，**每天** fallback 到 MiniMax 長達 10 天無人知情。
> 系統照常產出、看起來一切正常——這正是最危險的失敗模式。
> **對應鐵則**：UI 誠實鐵則（壞 token 必顯失敗，寧紅字不假成功）。

---

## 1. 問題定義

現行（Hermes 與多數 agent 框架共通的）行為：

```
job 設定 provider=X → X 認證失敗 → log 一行 WARNING → 靜默 fallback 到 provider=Y → 任務照常完成
```

三個違反誠實鐵則的點：
1. **委託與執行不符**：用戶指定 A 模型，實際用 B 模型，用戶不知道
2. **失敗被成功掩蓋**：產出品質可能改變（vision 能力、語言能力、成本結構都不同），但 UI 顯示「成功」
3. **通知鏈斷裂**：fallback 事件只存在 log，永遠不會到達用戶眼前

## 2. 目標

> **用戶有權在 3 秒內知道：「現在替我做事的，是不是我選的那個模型？」**

## 3. 設計原則

- **Fallback 永遠允許**（可用性優先——任務不該因鑰匙問題停擺），但**永遠不隱形**
- 標示跟著「交付物」走：訊息、報告、節點、帳單，每個交付物自帶實際執行者資訊
- 機制一處實作、全域生效（LLM client 層統一注入，不是每個 UI 各自記）

## 4. 機制設計

### 4.1 核心資料結構：ExecutionReceipt

每次 LLM 調用的回覆附帶一份收據，隨任務生命週期傳遞：

```dart
class ExecutionReceipt {
  final String requestedProvider;   // 用戶/job 設定的 provider，如 "custom:openai"
  final String requestedModel;      // 設定的 model，如 "gpt-5.5"
  final String? actualProvider;     // 實際服務的 provider，如 "minimax"
  final String? actualModel;        // 實際模型
  final FallbackReason reason;      // authFailed / rateLimited / timeout / providerGone
  final DateTime occurredAt;
  bool get usedFallback => actualProvider != requestedProvider;
}
```

### 4.2 呈現層（三級顯性度）

**Level 1 — 即時徽章（所有 agent 訊息）**
- 訊息 header/footer 顯示實際執行者：`⚙️ MiniMax-M3`（正常時小字、低調）
- 發生 fallback 時升級為：`⚠️ 已改用 MiniMax-M3（原設定 gpt-5.5 認證失敗）`，琥珀色（非紅——任務成功了，但要知道）

**Level 2 — 任務狀態列（cron / 排程任務）**
- 任務卡片顯示「上次實際執行模型」，滑鼠懸停展開 fallback 歷史
- **連續 fallback 天數**是關鍵指標：本事故 10 天沒人發現，就是因為沒有「連續 N 天」的累計視圖
- 連續 ≥3 天 fallback → 自動通知用戶（推播/頻道訊息）：「這個任務已經一週沒用到你選的模型了，要修鑰匙還是改預設？」

**Level 3 — Token Ledger（預算之眼整合）**
- 帳單按 actualProvider 分帳，不按 requested。否則「OpenAI 花費 $0」這種帳會騙人
- 每月對帳視圖直接列出：「名義 OpenAI / 實際 MiniMax：320 次 / $X」

### 4.3 通知機制（fallback ≠ SILENT）

- 首次 fallback：該任務交付物附徽章（Level 1）
- 連續 3 天：主動通知 + 建議行動（修鑰匙 / 改預設 / 保持 fallback）
- 用戶可回覆「就此固定用 fallback 模型」→ 之後降級為僅 Ledger 記錄（用戶知情後的選擇 = 誠實已達成）

### 4.4 誠實邊界

- fallback 產出**不重製**、**不撤回**——標示它，而非懲罰它
- 若 fallback 模型能力明顯不足（如 vision 任務落到純文字模型）→ 這是**失敗**，顯紅字，不降級為琥珀

## 5. Hermes 側先落地的部分（本週可做）

即使橋樑 App UI 未就緒，誠實不該等：

1. **cron job 設定衛生**：job 的 provider 設定失效時，`hermes cron` 應在建立/更新時即驗證 provider 存在（fail-fast），而非留到每天執行時才 fallback ✅ 本次已手動修正 3 個 job
2. **fallback 週報**：每週掃 agent.log 的 `primary auth failed` 統計，併入現有 cron 健檢報告
3. **斷鑰匙清單**：`custom:kimi-cn` 尚有 10 個 job 每天認證失敗（目前 fallback 到 glm-5.3 正常運作），列入待修清單

## 6. 橋樑 App 落地位置（開發時照此實作）

- 執行者：LLM client 層（adapter 單點），非各 UI
- UI 接點：畫布節點 tooltip、任務卡片、聊天訊息 header、Ledger 頁
- 設計系統：徽章用既有 BridgeDS token，琥珀=知情警示、紅=真失敗，禁硬編碼顏色

## 7. 驗收標準

- [ ] 指定模型 A、實際用 B 時，交付物上可見 B（3 秒內）
- [ ] 連續 3 天 fallback 會觸發通知，且通知含建議行動
- [ ] Ledger 分帳按實際 provider，帳目與 log 可交叉驗證
- [ ] 用戶明示接受 fallback 後不再重複打擾，但 Ledger 永遠如實記錄
