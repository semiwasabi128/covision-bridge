# 因果引擎架構提案 — Causal Reasoning Architecture

> **狀態**：v1.0 提案（2026-09-11，Blue 拍板立案）
> **起源**：Blue 提問「Agent 有沒有真正意義上的因果邏輯思維能力」→ 對談收斂出本架構
> **一句話**：模型的因果能力是租來的，環境的因果能力是蓋出來的——我們是那個能蓋的人。

---

## 0. 核心洞察（為什麼這個架構成立）

以 Judea Pearl 因果階梯為診斷框架：

| 階 | 問句 | LLM 權重層的真實狀態 |
|---|---|---|
| 1. 關聯（Seeing） | 什麼跟什麼一起出現？ | 原生強項（訓練分布內） |
| 2. 干預（Doing） | 如果我動手改 X 會怎樣？ | 脆弱；靠行動迴圈補 |
| 3. 反事實（Imagining） | 如果當時不是這樣呢？ | 最弱；靠狀態分叉補 |

研究佐證：Kıcıman et al. 2023（arXiv:2305.00050）指出 LLM 因果問答有「不可預測的失敗模式」；CLadder（NeurIPS 2023）與 Microsoft RE-IMAGINE（ICLR 2025 Workshop）實測：表面線索中和後，結構相同的題目準確率普遍下降約 20%，反事實題可掉至接近亂猜。"Causal Parrots" 一語道破：會講因果 ≠ 懂因果。

**本提案的槓桿點**：小橋（App Agent）的身體是我們自己寫的。因果階梯的第 2、3 階**本來就不是模型能力，是環境屬性**——

- 環境能被精確干預（ 凍結其他變數、只動一個 ）→ 才有第 2 階
- 環境能被分叉重演 → 才有第 3 階

物理世界做不到完美干預，所以人類要靠隨機對照實驗硬湊。小橋的世界是 Dart code + 可序列化狀態——**我們可以給他一個完美實驗室**。這是「在本源結構裡升級」的精確根據：不是換更大的模型，是讓他擁有訓練資料裡不存在、只有他自己能生成的私有因果數據。

---

## 1. 四層因果器官總覽

| # | 器官 | 對應階梯 | 一句話 | 階段 |
|---|---|---|---|---|
| L1 | 介入帳本 Causal Ledger | 第 2 階 | 每次干預強制記帳：do(X)→觀測(Y)+證據等級 | Phase 0 |
| L2 | 證據等級標籤 Evidence Grade | 誠實層 | 推測/觀測/干預驗證/反事實模擬——把誠實從道德變型別 | Phase 0 |
| L3 | 帳本反饋查詢 Ledger Recall | 第 2 階 | 遇同類問題先查帳本，不重新猜 | Phase 1 |
| L4 | 狀態分叉 State Fork | 第 3 階 | 快照→fork A/B→各自干預→diff=可執行的反事實 | Phase 2 |

設計原則：**每一層都是結構，不是紀律。** 紀律住在對話層（prompt），換模型就掉；結構住在 runtime，誰來執行都生效。

---

## 2. L1 介入帳本（Causal Ledger）

### 目的
把 agent 的行動從「做了就算」升級為「做了就記、記了可查、查了可用」。累積出的條目是訓練資料裡不存在的私有因果知識庫。

### 資料結構（新表 `causal_ledger`，掛 brain_container.db 或獨立 db，實作時定案）

```sql
CREATE TABLE causal_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,        -- 歸屬對話/任務
  companion_id TEXT NOT NULL,      -- 哪個 agent 做的（歸人記帳，同 LedgerEntry）
  action_type TEXT NOT NULL,       -- 工具名/操作類型
  intervention TEXT NOT NULL,      -- do(什麼)：具體改了什麼
  context_digest TEXT NOT NULL,    -- 干預前環境摘要（足夠辨認「同類情境」）
  observed_outcome TEXT NOT NULL,  -- 觀測到什麼
  hypothesis TEXT,                 -- agent 事前假設（可空=沒先想）
  evidence_grade TEXT NOT NULL,    -- speculated / observed / intervened / counterfactual
  verified INTEGER NOT NULL DEFAULT 0,  -- 假設被證實/證偽/未判定
  created_at TEXT NOT NULL
);
```

### 介面（新服務 `lib/services/causal/causal_ledger_service.dart`）

```dart
class CausalLedgerService {
  /// AgentLoop 工具執行後自動調用（掛載點見 §6 執行機制）
  Future<void> recordIntervention(CausalEntry entry);
  /// L3 用：按情境相似度檢索歷史干預
  Future<List<CausalEntry>> recallSimilar(String contextDigest, {int limit});
  /// 統計：某類 action 的成功率（Trust 公式可消費）
  Future<Map<String, double>> successRateByAction();
}
```

### 驗收
- [ ] AgentLoop 每次工具執行（含 canvas_*、搜尋、檔案操作）產生 ≥1 筆條目，含 intervention + observed_outcome
- [ ] 條目歸人：companion_id 正確（同 PaidActionGate 歸人邏輯）
- [ ] 寫入失敗 fail-open 但留錯誤痕跡（素描服務前車之鑑：fail-open 也要看得到）
- [ ] 帳本成長率合理（每輪行動 ≤ 數筆，不得每 token 記）
- [ ] conversations.json 驗屍可對照：有行動必有條目

---

## 3. L2 證據等級標籤（Evidence Grade）

### 目的
把「小葵知道自己在階梯第幾階」從自我感覺變成可顯示、可審計的狀態。UI 鐵則「寧紅字不假成功」的因果層版本。

### 四級定義（固定詞彙，UI 直接渲染）

| 等級 | 詞彙 | 定義 |
|---|---|---|
| 0 | `推測` | 只有相關性聯想，沒動手驗證 |
| 1 | `觀測` | 讀到真實狀態（log/DB/截圖）但未干預 |
| 2 | `干預驗證` | 動了一個變數、其他凍結、看到結果 |
| 3 | `反事實模擬` | 狀態分叉對照得出的結論（Phase 2 後才有） |

### 執行機制
- Agent 對話回覆中的因果宣稱（「X 造成 Y」句式），由意圖分類器（同 C6 純規則架構）標註等級，訊息氣泡顯示等級 chip
- **等級 0 的宣稱 chip 用警示色**——不是禁止猜測，是強制標價
- system prompt 注入四級定義（同設計知識雙層注入模式：靜態注入 + 羅盤可查）

### 驗收
- [ ] 訊息氣泡可見等級 chip，等級 0 視覺醒目
- [ ] 等級判定可追溯：chip 點開看到依據（對應帳本條目 ID）
- [ ] 注入鏈驗證：agent system prompt builder 鏈上找得到四級定義（羅盤規則生效機制=雙層的檢驗法）

---

## 4. L3 帳本反饋查詢（Ledger Recall）

### 目的
驗證「帳本能不能真的反哺判斷」——這是最小閉環兩週實驗的核心問題。Agent 遇到同類問題時，先查帳本裡的 do→Y 記錄，而不是重新猜。

### 執行機制
- AgentLoop 問題解決路徑前置一步：`recallSimilar(當前情境)` → 命中條目注入 context（「上次同情境做 X 得到 Y，證據等級 2」）
- 檢索用既有身份嵌入管線（IdentityEmbedText 同款思路：context_digest 嵌入向量檢索），不另造搜尋引擎（單一真相：VaultSearchFacade 模式）
- 命中閾值寬鬆起步（寧多勿漏），兩週後按命中率數據校準（鹿角蕨 0.55→0.50 校準史為鑑）

### 驗收（兩週實驗的成敗標準）
- [ ] agent 在同類 bug 情境下，回覆中引用歷史條目 ≥ 1 次可觀測（對話記錄可查）
- [ ] 同類問題第二次出現時，平均解決輪次下降（對話記錄統計）
- [ ] 誤反哺率監控：引用的歷史條目與當前情境不相關的比例 < 20%
- [ ] 誠實邊界：帳本空或無命中時，agent 不得假裝查過（回覆需顯性「帳本無記錄，重新推理」）

---

## 5. L4 狀態分叉（State Fork）

### 目的
 Hermes 環境給不了、我們能給的：真正的第 3 階。快照→fork→各自干預→diff，「如果當時沒做 X」從敘事變成可執行查詢。

### 設計草圖（Phase 2 立項時展開成獨立設計稿）
- **可分叉域**：App 內部狀態（畫布 JSON、工作流 DAG、vault 查詢結果、agent context）——全部可序列化
- **不可分叉域**：外部世界（使用者行為、外部 API 回應、檔案系統外部變化）——誠實標記為「邊界外」
- fork 生命週期：限時（如 10 分鐘自動回收）、限量（併發 ≤2）、禁止巢狀（防指數爆炸）
- UI：人機共視——分叉執行時使用者看得到 A/B 對照卡（同任務卡直播模式）

### 驗收（Phase 2 屆時細化）
- [ ] 「如果當時不執行這個節點」可分叉重演並 diff 出結果差異
- [ ] 邊界外事件在分叉中凍結為快照值並標記
- [ ] 分叉回收後不留殭屍（24/7 記憶體治理前車之鑑）

---

## 6. 執行機制與掛載點（規則不是裝飾品）

依羅盅規則 `agent.ruleEnforcement`：每條規則必須指出自動執行機制。

| 規則 | 掛載點 | 生效方式 |
|---|---|---|
| L1 帳本記錄 | AgentLoop 工具執行完成點（BridgeActionExecutor.execute 後置 hook，同 PaidActionGate 咽喉點模式） | 結構性：執行即記，不靠 agent 自覺 |
| L2 等級標籤 | ① system prompt 注入（靜態） ② 回覆渲染層 chip（意圖分類器） | 雙層：注入化 + 行為化 |
| L3 反饋查詢 | AgentLoop 問題解決意圖觸發點（意圖分類前置） | 行為化：命中注入 context |
| L4 分叉 | 獨立工具 causal_fork（Phase 2 註冊） | 工具化 |

---

## 7. 分階段驗收總表

| 階段 | 內容 | 期程 | 成敗指標 |
|---|---|---|---|
| **Phase 0** | L1 帳本 + L2 標籤，掛現有行動迴圈 | 兩週 | §2 §3 驗收全綠；帳本累積 ≥ 500 條 |
| **Phase 1** | L3 反饋查詢上線 | Phase 0 通過後 | §4 兩週實驗四項指標 |
| **Phase 2** | L4 狀態分叉 | Phase 1 通過後 | 獨立設計稿定案 |
| **Phase 3** | provenance 貫穿（所有結論可追溯階梯等級） | 隨 Phase 2 | 覆蓋率審計 |

**Gate 紀律**：每階段通過才開下一階段；Phase 0 失敗則回頭修設計，不硬上。

---

## 8. 羅盤登記（邊蓋邊登記）

- 器官：`agent.causality`（服務群）——因果引擎（介入帳本×證據等級×狀態分叉）
- 規則三條（behavioral）：`agent.causality.ledger` / `agent.causality.evidenceGrade` / `agent.causality.ledgerFeedback`
- 每階段完成時，本文件 §7 勾驗收項 + 羅盤規則 params 更新實際掛載點（_changes 留軌跡）

---

## 9. 誠實邊界聲明

- 本文件是設計提案，**Phase 0 尚未實作**——羅盤規則 params 中明確標記掛載點狀態，未掛載前不假裝生效
- 分叉的第 3 階有物理極限：只能重演小橋世界內的狀態，世界外事實不可分叉（§5 已標記）
- 「兩週實驗」的成敗標準是 §4 四項指標，不是帳本條數本身——條數是必要非充分條件
