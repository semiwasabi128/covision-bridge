# P0 對話頁設計診斷卡：清醒的工作狀態錨點

> **狀態**：v0.1 診斷 · 2026-08-07
> **範圍**：`/chat`（`lib/screens/chat_screen.dart`）與 Canvas 內嵌對話（`lib/widgets/canvas/canvas_chat_panel.dart`）。
> **上游**：[核心頁面設計統合地圖](BRIDGE_CORE_PAGE_DESIGN_MAP.md) — P0 對話。
> **本輪不改功能**：本文件只定義現況、設計缺口、改造邊界與驗收。

---

## 1. 對話頁的核心承諾

對話是 Bridge 的主工作線。它不只是訊息收發器；它是使用者與 AI 同時追蹤任務、工具、資料與下一步的地方。

P0 的驗收句：

> **在任何時刻，使用者都能用一眼知道：AI 是否在工作、它正在做什麼、我現在能做什麼、完成後結果在哪裡。**

這對應統合設計語言的三種能力：

- **清醒**：工作狀態不可藏在多處，不能靠猜。
- **有回應**：送出、執行工具、成功、失敗、停止，都有明確後果。
- **不中斷**：切換 Canvas、對話、模型或回來後，使用者仍能接回工作主線。

---

## 2. 真實現況（程式碼已驗證）

### 2.1 對話主畫面結構

`ChatScreen.build()` 的實際順序：

```text
ChatAppBar
  └─ 對話標題、夥伴、目前模式、本地模型、token、Brain Reflection 入口

主訊息區
  ├─ EmptyChatState 或 MessageBubble ListView
  ├─ ThinkingPanel                     （isLoading）
  └─ AgentLoopProgress                 （isLoading + 有 turn）

輸入區
  ├─ 回覆目標 preview
  ├─ VoiceButton + VoiceStatusIndicator
  ├─ AgentModelSelector
  └─ ChatInputBar

Stack overlay
  └─ CompanionPresenceLayer
```

證據：`chat_screen.dart` 約第 1271–1504 行。

### 2.2 已有、但分散的工作狀態資料

| 狀態資料 | 真正來源 | 現在可見位置 | 問題 |
|---|---|---|---|
| `isLoading` | `ChatController` | ThinkingPanel、輸入框 loading | 只回答「忙不忙」，不回答「在做什麼」 |
| `thoughtStage` / `thoughtTelemetry` | `ChatController` | Brain Reflection panel | 資料存在，但藏在另一個入口 |
| `activeBridgeActionLabel` | `ChatController` | Brain Reflection panel | 可說明當前行動，但非主狀態錨點 |
| turn／toolName／toolStatus | `onAgentLoopProgress` callback | AgentLoopProgress | 只有 Agent Loop 路徑才出現，與 ThinkingPanel 分離 |
| 聲音對話狀態 | VoiceEngine | VoiceStatusIndicator | 疊在 VoiceButton 上，與 AI 工作狀態平行而非統一 |
| 模型／provider 狀態 | AgentModelSelector | 輸入框上方 | selector 載入時完全隱藏，使用者可能不知道現在用哪種模型 |
| Canvas context | ChatController / Canvas snapshot | prompt 內靜默注入 | UI 刻意不顯示，使用者無法知道 AI 是否已看見畫布變化 |

### 2.3 Canvas 對話的連續性風險

Canvas 的 `CanvasChatPanel` 會建立自己的 `ChatController`，而且其註解明確排除 Agent Loop progress、卡片系統等主對話能力。

這是合理的效能／複雜度選擇，但會產生設計風險：

```text
主對話：可見 Thinking + 工具輪次 + 複雜卡片
Canvas 對話：精簡訊息與發送
```

如果兩者沒有共同的「工作狀態摘要」，使用者從 Chat 進 Canvas 時會感到 AI 的工作消失了，違反「不中斷」。

---

## 3. P0 設計診斷

### D-01：一件工作，五個狀態出口

**症狀**：ThinkingPanel、AgentLoopProgress、Brain Reflection panel、Voice indicator、Model selector 各自表達部分真相。

**使用者感受**：

> 「它是不是正在做事？是在想、在查工具、在等模型、還是卡住？」

**違反能力**：清醒、有回應。

**設計判斷**：不是新增一個更大的面板；是把現有資料收成一條**固定位置、可展開但不搶訊息的工作狀態錨點**。

---

### D-02：忙碌狀態與可採取行動沒有相連

`isLoading` 可讓輸入列進入 loading，但使用者看不到清楚的「現在可插話、可停止、可等待、可轉去 Canvas」的行動語意。

**違反能力**：有回應。

**設計判斷**：狀態列需同時提供：

```text
目前狀態 + 正在處理的對象 + 可做的安全動作
```

例如：

```text
正在查找 3 個 Vault 來源     [停止] [補充方向]
正在把節點放入 Canvas         [查看 Canvas]
等待本地模型回應              [改用雲端] [查看連線]
```

此處的按鈕只能在對應功能真的存在時出現；不可重演 showcase 的「看似可按、實際無 listener」問題。

---

### D-03：模型身分在關鍵時刻可能不可見

AgentModelSelector 初始化時直接回傳空 widget；而 AppBar 與 selector 分散顯示 provider／local state。

**違反能力**：清醒、可信。

**設計判斷**：P0 不重做選擇器；先讓工作狀態錨點在「執行中」明確陳述本次任務的 provider／模型／本地或雲端。模型切換仍留在既有 selector。

---

### D-04：Canvas 已同步，但人不知道 AI 看見了什麼

畫布 snapshot／event 會以 `silent` metadata 注入 project Canvas conversation；這對 prompt 是正確的，但 UI 沒有可見確認。

**違反能力**：不中斷、共視。

**設計判斷**：不要把靜默系統訊息塞進聊天紀錄。應以不干擾的狀態語意表達，例如：

```text
已同步目前畫布：12 個節點、14 條連線
```

這屬 P1 Canvas × P0 Chat 的交界，不能在沒有 Canvas call-site trace 前直接做。

---

## 4. 建議的 P0 最小改造：`ChatWorkStatusAnchor`

### 4.1 它是什麼

一個置於**訊息區與輸入區交界**的單一狀態元件；它取代「多個零碎工作提示」作為使用者第一眼的工作真相。

它不是常駐儀表板：閒置時壓縮為一行，工作中可展開為詳情。

```text
閒置：
  ● 準備好對話 · 雲端模型

工作中：
  ◌ 第 2 / 6 輪 · 正在查詢 Vault
  已閱讀 3 個來源 · 你可以補充方向或停止

完成後（短暫保留）：
  ✓ 已完成 · 3 個來源已帶入回答        [查看依據]
```

### 4.2 它讀取哪些既有資料

| 欄位 | 來源 | 是否需改 service |
|---|---|---|
| busy／idle | `ChatController.isLoading` | 否 |
| thinking stage | `thoughtStage` | 否 |
| current bridge action | `activeBridgeActionLabel` | 否 |
| turn / max turns / tool name / result | 現有 `onAgentLoopProgress` 已寫入 ChatScreen state | 否 |
| provider / local state | 既有 model state / selector | 初版可只讀，需確認公開 getter |
| stop | `ChatController.stopAgent()` | 否，但需驗證 UI 是否已有按鈕 |
| inject direction | `ChatController.injectUserMessage()` | 否；初版可先不露出，避免誤改輸入行為 |

### 4.3 初版明確不做

- 不改 `sendMessage()`。
- 不改 Agent Loop prompt、tool registry、工具執行或 cancellation 機制。
- 不改 Canvas snapshot 的 `silent` 資料模型。
- 不合併或刪除 CanvasChatPanel 的獨立 controller。
- 不把粒子／Atmosphere 放進常駐工作狀態。

這些都是高風險行為改造，須先完成 Call-Site Trace。

---

## 5. 改造風險分級

| 變更 | 分級 | 依據 |
|---|---|---|
| 將 ThinkingPanel 與 AgentLoopProgress 包進單一 status anchor | 低 | 讀既有 UI state；不改 controller 行為 |
| 在 anchor 顯示目前工具／輪次／action label | 低 | 現有 callback / getter 已提供 |
| 加入 Stop UI 並接 `stopAgent()` | 中 | 改變使用者可以取消的入口，需實機驗收 |
| 顯示 provider / local runtime 的精確狀態 | 中 | 需追 AgentModelSelector 與 runtime state 的來源 |
| 顯示 Canvas 已同步摘要 | 高 | 需 trace Canvas snapshot → controller → UI 的同步與隱私邊界 |
| 統一 ChatScreen / CanvasChatPanel controller | 高 | 牽涉對話持久化、Canvas conversation、Agent Loop 與多個 caller |

---

## 6. 實作前必要 Call-Site Trace

在任何 P0 widget 改動前，先 trace：

1. `ChatController.sendMessage()` 的所有 caller。
2. `ChatController.stopAgent()` 是否已有 UI caller、取消後如何回到 idle。
3. `onAgentLoopProgress` 在 ChatScreen／CanvasChatPanel 的設定與清除時機。
4. `thoughtStage`、`activeBridgeActionLabel` 的寫入／清除路徑。
5. `AgentModelSelector` 取得本地／雲端狀態的實際資料源。
6. Canvas snapshot 靜默注入的完整呼叫鏈與使用者可見性邊界。

完成 trace 後，才能把 `ChatWorkStatusAnchor` 定義成獨立 widget，先以低風險讀取資料的版本切入。

### 6.1 已完成 Call-Site Trace（2026-08-07）

| 對象 | 真實 caller／寫入鏈 | P0 結論 |
|---|---|---|
| `sendMessage()` | `ChatScreen`、`DesktopChatPanel`、`CanvasChatPanel`、語音轉送、圖片送出、`BridgeDesktopScreen` 自動送訊息 | **不可改 signature／不可在 controller 內塞 UI**；status anchor 必須是呼叫端 UI 的讀取層 |
| `stopAgent()` | `DesktopChatPanel`、`CanvasChatPanel` 有明確停止按鈕；主 `/chat` 沒找到直接 caller | 主 Chat 若補 Stop 是**中風險可做**，需驗證 `isLoading → false`、thought state 清除、Agent Loop 取消與 UI 回復 |
| `onAgentLoopProgress` | Controller 在 AgentLoop `onProgress` 呼叫；Chat／Desktop／Canvas 各自設定 callback；語音轉送暫存、覆寫、完成後還原 callback | 初版 anchor 只能讀 `ChatScreen` 已存的 turn/tool state；**不可搬成全域 callback 或改 callback 生命週期** |
| `thoughtStage` / `activeBridgeActionLabel` | `begin/finish` 狀態 helper、background brain reflection、一般回覆／Bridge action 完成路徑都會寫入與清除 | 可作為 anchor 的唯讀來源；要保留 controller 原有 reset 時機 |
| 模型 provider | `AgentModelSelector` 私有載入：`StorageService.getProvider()` + `LocalModelRuntimeService.inspectBridgeRuntime()` | 初版不直接讀 selector 私有 state；provider 摘要需先抽唯讀資料源，避免複製 runtime 邏輯 |
| Canvas snapshot | `CanvasV2Workspace → CanvasSnapshotService.onInject → injectCanvasSystemMessage()`，僅 project Canvas conversation 且以 `silent` metadata 不顯示 | 保持現在的 prompt／隱私模型；Canvas 同步摘要屬後續 P1 交界工作 |

### 6.2 行為等價性合約

P0 初版即使替換工作狀態的視覺呈現，也必須保持：

1. 任一既有 `sendMessage()` caller 的訊息、圖片、語音與自動送出行為不變。
2. 語音轉送暫時覆寫 progress callback 後，完成／錯誤時仍回復原 callback。
3. Agent Loop 的工具輪次與取消條件不變；status anchor 只讀、不干預。
4. Canvas snapshot 仍是 silent prompt context，不會突然變成使用者可見聊天訊息。
5. `stopAgent()` 若在主 Chat 新增入口，按下後必須和既有 desktop／canvas caller 同樣回到 idle。


---

## P0.5 後續：任務證據，而不是狀態裝飾

P0 的 spinner 收束實驗已撤回：對一般短對話沒有可感知價值。

下一步採用 [對話任務證據設計](CHAT_TASK_EVIDENCE_DESIGN.md)：只有工具實際產生來源、檔案、Canvas 變更、圖片或子任務成果時，才在最終回答下方留下可驗證的結果卡。

---

## 7. P0 視覺驗收

不驗收「更炫」，只驗收這些問題能否在兩秒內回答：

| 情境 | 使用者兩秒內應知道 |
|---|---|
| 剛送出訊息 | AI 已收到，正在處理什麼 |
| Agent 用工具 | 第幾輪、正在使用哪個工具、結果是否成功 |
| 本地模型等待 | 目前是本地／雲端，是否正在等待或失敗 |
| 使用者想中止 | 可否停止、停止後會怎樣 |
| 回到一個仍在跑的對話 | 工作尚未消失，最後進度在哪裡 |
| 從 Canvas 回來 | AI 是否仍保有畫布脈絡 |

> **P0 成功不是多一個面板，而是使用者再也不必問：「它現在到底在幹嘛？」**
