# 刀 5：示範錄製（Show-once Routine）— 設計稿 v1

> 設計師：小葵  
> 日期：2026-09-08  
> 對應報告：docs/specs/2026-09-08-buzz-grokbot-optimization-report.md §4.5  
> 狀態：拍板前不動 code（**拍板即落地**）

---

## 一、這一刀解決什麼（G6）

**「我示範過一次，現在完全信任它永遠跑下去，效率 2-3 倍。」**

範本不再靠 agent 手動 sync——Blue 在畫布上做一遍流程，系統錄下**節點/連線/參數的誕生序列**，一鍵存為範本。下次說一聲就能重播。

Grok Bot 的 teach-a-task 靠錄螢幕畫面；我們錄的是**結構化操作事件**——重播精確、可編輯、可 diff。這是報告明言「我們能做得比它好的地方」。

## 二、地基盤點（好消息：大半已在）

| 積木 | 現狀 |
|---|---|
| CanvasEventBus | ✅ 已在發結構化事件（nodeAdded/connectionAdded/nodeUpdated…） |
| WorkflowTemplate 模型 | ✅ nodes+connections+params JSON |
| VaultTemplateService.toJson/fromJson | ✅ 序列化已備 |
| 範本匯入（batchLoaded） | ✅ 匯入畫布路徑已通 |
| 排程引擎 | ✅ scheduling engine 既有 |

**缺的**：①錄製器（訂閱事件→累積序列）②錄製 UI（開始/停止/存範本）③重播（範本→開新畫布，其實就是既有匯入）④排程掛鉤。

## 三、設計

### 3.1 RoutineRecorder（核心服務）

```
lib/services/routines/routine_recorder.dart
```

- 單例，訂閱 CanvasEventBus.stream
- start(canvasId) → 錄；stop() → 回傳 RoutineRecording（事件序列+快照）
- 快照法：stop 時抓畫布當下完整 nodes+connections（**最終結果法**，比逐事件重放穩——編輯途中改來改去不影響範本正確性）
- 事件序列只做「人類可讀的操作故事」（顯示用）：「加了 LLM 節點」「連了 input→llm」「改了參數 prompt」

### 3.2 錄製 UI（浮動小條）

畫布工具列加「⏺ 錄製」鈕：
- 點下 → 浮動小條「⏺ 錄製中 · N 個操作 · [停止並存範本] [放棄]」
- 停止 → 對話框：範本名稱＋描述＋分類 → 存入 custom templates
- 放棄 → 事件清空，畫布不動

### 3.3 重播（= 既有範本匯入）

存的範本出現在範本庫（自訂分類「我的示範」）→ 點開即開新畫布載入——**重播不新做引擎，走既有 batchLoaded 路徑**。

### 3.4 排程掛鉤

範本存檔後可選「加入排程」（對接 scheduling engine 既有 UI）——本刀只加掛鉤入口，排程設定沿既有流程。

## 四、落地切片

| # | 內容 | 檔案 |
|---|---|---|
| D5.1 | RoutineRecorder 服務（訂閱+快照+操作故事） | routines/routine_recorder.dart（新） |
| D5.2 | custom templates 持久化（SharedPreferences JSON list） | vault_templates.dart 擴充 |
| D5.3 | 畫布工具列錄製鈕+浮動小條 | canvas v2 工具列 |
| D5.4 | 存範本對話框（名稱/描述/分類） | 同上 |
| D5.5 | 範本庫顯示自訂範本（分類「我的示範」） | 範本庫 UI |

## 五、驗收

- 畫布上建一個小流程 → ⏺ 錄製 → 加節點連線 → 停止 → 存「測試範本」
- 範本庫出現「我的示範」分類＋測試範本
- 點開測試範本 → 新畫布載入完整流程（節點/連線/參數一致）
- lib/ 零 error；新測試 ≥ 3 條綠；profile build 成功

## 六、一句話

**範本不靠打字描述——你做一遍，橋樑記住，永遠會跑。**
