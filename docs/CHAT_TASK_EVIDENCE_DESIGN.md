# P0.5 對話任務證據設計：讓「做了事」留下可看見的結果

> **狀態**：v0.1 設計合約 · 2026-08-07
> **上游**：[P0 對話頁設計診斷卡](CHAT_P0_DESIGN_DIAGNOSIS.md)
> **決策**：一般對話不顯示工作面板；只有 AI 實際呼叫工具、改變資料或產出可交付物時，才顯示任務證據。

---

## 0. 從失敗學到的事

P0 第一版曾把 `ThinkingPanel` 與 Agent Loop 進度包成單一元件。對「短訊息 → 純文字回答」而言，使用者看到的仍只是：

```text
思考中／轉圈 → 回答
```

這沒有新增資訊，也不值得留在產品。

**修正後的準則：**

> 不要讓 AI 的內在狀態變成裝飾。只有 AI 做了會改變使用者下一步的工作，才留下可以核對的證據。

---

## 1. 什麼情況完全不顯示？

以下是普通對話，不增加 status bar、spinner 或「工作錨點」：

- 問答、解釋、改寫、腦暴；
- AI 只使用語言模型完成回覆；
- AI 雖然短暫思考，但沒有呼叫任何可見工具；
- 回答本身就是唯一交付物。

使用者只應看到自然的回覆，不必理解 Agent Loop、turn 或 token。

---

## 2. 什麼情況需要留下任務證據？

| 使用者感受的任務 | 真實工具／結果 | 回答下方應留下的證據 | 使用者可做的下一步 |
|---|---|---|---|
| 「幫我找資料」 | `web_search`、`browse`、`memory_search` | `已查閱 N 個來源` + 最多 3 個可開啟來源 | 查看來源、追問、換搜尋方向 |
| 「讀／改這份程式」 | `read_source_file`、`patch_source_file`、`run_terminal` | 檔案名、變更摘要、analyze/test 結果 | 看 diff、要求修正、回復 |
| 「幫我生成圖片」 | `generate_image`，含 `mediaUrl` | 圖片縮圖 + 產出完成 | 開啟、重新生成、加入 Canvas |
| 「把它放進 Canvas」 | `canvas_place`、`canvas_connect`、`canvas_remove` | `Canvas 已變更：+N 節點／+N 連線` | 查看 Canvas、還原、繼續編排 |
| 「整理我的檔案」 | `desktop_files`、`document` | 涉及資料夾、計畫／結果、異動數量 | 查看計畫、確認、撤銷 |
| 「交給多個 AI 做」 | `delegate_subagent`、`delegate_batch` | `N 個任務：X 完成、Y 失敗` | 展開摘要、重跑失敗項 |
| 「檢查設定」 | `check_capability_status`、設定／導航工具 | 可用／缺少的能力和前往位置 | 前往設定、稍後處理 |

### 不屬於 evidence 的事

- 第幾個 LLM turn；
- 原始 prompt；
- 工具完整 raw output；
- 本機絕對路徑、token、secret、未清洗 log；
- 模型內部思考過程。

它們可能對 Agent 有用，但不是使用者的工作證據。

---

## 3. 產品語言：任務結果卡，不是狀態錨點

使用者永遠不會看到「工作狀態錨點」這個詞。

使用者會在 final assistant reply 的下方看到一張低干擾的**任務結果卡（Task Evidence Card）**：

```text
✓ 已查閱 3 個來源                         [查看來源]
  公司公告 · 技術文件 · 官方 API 文件
```

```text
✓ Canvas 已更新                            [查看 Canvas]
  新增 2 個節點、1 條連線
```

```text
✓ 生成 1 張圖片                            [開啟] [加入 Canvas]
  [縮圖]
```

### 3.1 三種結果，不做第四種

| 狀態 | 語言 | 視覺 | 必要動作 |
|---|---|---|---|
| 完成 | `已…` | 安靜的成功色，不做慶祝動畫 | 查看交付物 |
| 部分完成 | `已完成 X；仍缺 Y` | 中性色／警示色 | 補資料、重試、繼續 |
| 失敗 | `未能…` + 人話原因 | 錯誤色，但不堆 stack trace | 重試、調整方向、查看設定 |

**進行中不做常駐卡。** 只有預期超過短暫等待、而且使用者可採取安全行動時，才以一行暫態文字提示：

```text
正在查閱來源；你可以補充方向或繼續等待。
```

它完成後必須被最終證據卡取代；不能停在「轉圈」。

---

## 4. 真實資料現況與缺口

### 4.1 已有資料

`AgentToolResult` 已包含：

```dart
success
content
mediaUrl
metadata
```

`AgentLoopResult.turns` 保留每一輪 `toolCall + toolResult`。目前 `ChatController` 也已能從 turns 取出 `mediaUrl`，附到 assistant message。

### 4.2 現在被壓扁的地方

目前 `ChatController.onAgentLoopProgress` 只傳：

```dart
turnIndex, maxTurns, toolName, success|failed, llmSnippet
```

因此 UI 遺失了能形成證據的 `content`、`metadata`、`mediaUrl`。

### 4.3 最小資料契約：`TaskEvidence`

不要把 raw `AgentToolResult` 直接交給 UI。新增一層白名單 mapper：

```text
AgentLoopTurn / AgentToolResult
        ↓  僅工具名稱對應的 safe mapper 可讀 metadata
TaskEvidence
        ↓
Assistant Message metadata（持久化）
        ↓
TaskEvidenceCard
```

`TaskEvidence` 最小欄位：

```dart
kind            // search / canvas / file / image / delegation / capability
outcome         // completed / partial / failed
headline        // 「Canvas 已更新」
summary         // 「新增 2 個節點、1 條連線」
actions         // 僅真實存在的 action
safeReferences  // URL、message id、canvas id、檔案顯示名等經過清洗的參照
mediaUrl         // 可選；只限既有可顯示媒體
```

### 4.4 白名單與安全邊界

| 可進入 UI | 只能停在 Agent context／log |
|---|---|
| 工具類型、成功／失敗、經摘要的數量 | raw tool args |
| 已清洗 URL、顯示檔名、Canvas node count | 絕對路徑、token、cookie、連線字串 |
| 已驗證可顯示的 media URL | 完整 command output、完整 page dump |
| 工具特定 metadata 的白名單 key | 任意 metadata map 直接 serialize |

任務卡的 action 也必須遵守：**沒有可用 listener 就不顯示按鈕。**

---

## 5. 實作順序（由可驗證結果優先）

### P0.5a：先做「已完成證據」，不做進度條

1. 在 Agent Loop final result 時，從 `turns` 建立 `List<TaskEvidence>`。
2. 先支援三種有明確交付物的 mapper：
   - `generate_image` → image evidence；
   - `canvas_*` → Canvas evidence；
   - `delegate_batch` → 任務數量 evidence。
3. 將 evidence 存到 assistant `Message.metadata`，所以重開 App 後仍可見。
4. 在 `MessageBubble` 下方渲染靜態、可點回交付物的卡。

### P0.5b：搜尋與檔案操作

需要工具端回傳結構化、已清洗 metadata；不從 `content` 字串猜數量或解析路徑。

### P0.5c：暫態進行中提示

只在有可採取的安全行動時才加，例如長任務的停止／補充方向；這是中風險互動，需獨立 Call-Site Trace。

---

## 6. 驗收句

任務卡不是為了讓 AI 看起來忙，而是為了讓使用者可以說：

> 「我知道它替我做了什麼，也知道結果在哪裡。」

每一張卡都要能回答至少一題：

1. 它做了什麼？
2. 它改變了什麼？
3. 結果在哪？
4. 我下一步可以做什麼？

若四題都答不上，就不應該顯示那張卡。
