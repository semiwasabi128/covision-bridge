# 設計稿：隊友訊息流（Teammate Inbox）— 優化七刀 · 第 1 刀

> 日期：2026-09-08 ｜ 狀態：✅ Blue 拍板 A（五條全按建議值）＋ v2 增補（見 §0）
> 來源報告：`docs/specs/2026-09-08-buzz-grokbot-optimization-report.md`（刀 1）
> 一句話定位：**把主對話頁升級為派工收件匣——白話派工、夥伴背景開畫布做事、回來交付；畫布從「操作場所」降級為「共視場所」。**

## 0. v2 增補（Blue 09-08 口諭，即時入稿）

1. **不中斷鐵則**：Agent 無論切到任何畫面/頁面，任務不中斷。
2. **關窗背景續跑**：即使使用者把 App 視窗關掉，App 仍在背景跑；**唯有小圖示右鍵選「關閉 App」才真正終止**。
3. **工作流直播視圖**：使用者想看 agent 工作流時有明確入口。
4. 進度回報（動態摘要）→ 對應既有「背景工作 App 內必見進度」原則。

---

## 1. TL;DR

Blue 在主對話頁說「幫我把這週農場照片整理成週報」，夥伴不要求他打開畫布：agent 自己建一張**工作畫布**（不干擾他正在看的任何畫布）、組工作流、執行、在主對話頁以**任務卡**回報進度與交付。需要判斷時才 @Blue。

這是 Grok Bot「零學習曲線派工」的精髓，用我們已有的引擎（Agent Loop 操盤、canvas_place 正宮路徑、BudgetLedger、工作流體檢）承載——**不新增任何 AI 能力，只新增編排與 UI**。

## 2. 設計理念三句話（壓力測試預答）

1. **North Star**：得意的助手住我電腦裡能動手做事——「動手」的極致是「我不用起身開畫布，事就做完了」。畫布是我們的差異化共視空間，但共視空間不該是派工的前置條件。
2. **護城河**：Grok Bot 的背景 bot 是雲端黑箱；我們的派工全程本地——工作畫布可打開共視、每一步有 BudgetLedger 帳、執行前有體檢預報。**看得見的隊友 vs 黑箱隊友。**
3. **vanity 風險自首**：任務卡的「即時步驟滾動」若做太吵，會變成另一種微管理 dashboard。設計上進度卡預設收合（一行狀態），展開才看步驟——安靜時刻原則。另外派工意圖誤判（把閒聊當派工）是最大風險，閘門見 §10。

## 3. 現有基礎（實掃 code 錨點，2026-09-08）

| 現有資產 | 位置 | 狀態 |
|---|---|---|
| 主對話頁 Agent Loop | `controllers/chat_controller.dart` L1430 實例化、L1832 `run()`（hardMaxTurns 安全閥） | ✅ 可直接用 |
| 建畫布＋綁對話管線 | `screens/bridge_desktop_screen.dart` L1497-1531 `_duplicateCanvas`：`CanvasStore.create(conversationId:)` → `conv.copyWith(canvasId:)` → `ConversationStore.save` | ✅ 可抽公用方法 |
| MCP canvas 正宮路徑 | `CanvasMcpRegistry`（canvas_place 等工具，08-16 教訓） | ✅ 可直接用 |
| 付費閘門＋體檢 | `PaidActionGate`（BridgeActionExecutor 咽喉點）＋ `WorkflowInspector`（執行前預報） | ✅ 派工天然繼承 |
| 畫布對話獨立控制器 | `canvas_chat_panel.dart` `_controller.sendMessage()` | ✅ 參考不依賴 |
| 系統事件不喚醒 Loop | `_lastMessageWasSystemEvent` 旗標（$33 教訓） | ✅ 交付回報必須走此通道防迴路 |
| canvas tab Offstage 保活 | 08-16 已做（切頁不中斷） | ✅ 工作畫布背景跑的前提 |

**Gap（本設計要補的）**：
- `canvas_*` 工具綁定的是 registry 的 active 畫布——**沒有「任務專屬工作畫布」概念**，agent 派工會污染使用者眼前的畫布
- 主對話頁沒有「任務」這個一等 UI 物件——交付物沒有歸宿，只能落成一條普通訊息
- `_duplicateCanvas` 是「切過去」模式——需要「不切、背景、不打斷」模式

## 4. 核心概念：TaskSession（派工會話）

一次派工 = 一個 TaskSession。**這也是第 4 刀「房間即工作」的種子**——房間 = TaskSession 的空間化版本。

```dart
class TaskSession {
  final String id;
  final String conversationId;   // 主對話（回報落點）
  final String companionId;      // 接單夥伴
  final String workCanvasId;     // 派工時自動建立的工作畫布
  final String title;            // 從白話指令摘出的任務標題
  TaskStatus status;             // dispatched→working→awaitingReview→delivered→failed→cancelled
  final DateTime createdAt;
  List<Deliverable> deliverables;// 產出物（圖/文/檔）指標
  String? finalSummary;          // 交付摘要
}

enum TaskStatus { dispatched, working, awaitingReview, delivered, failed, cancelled }

class Deliverable {
  final String kind;       // image / text / file / canvas
  final String ref;        // 檔案路徑或 canvasId
  final String caption;    // 一句話描述
}
```

### 4.1 派工路由（誰決定「這是派工」）

兩條路，漸進上線：
- **Phase 1（明示派工）**：輸入框右側「派工」按鈕（紙飛機圖標）——按下去 = 明確 TaskSession。零誤判，先讓管線跑通。
- **Phase 2（意圖派工）**：IntentSpine 增「任務型意圖」分類（多步驟/產出物/跨工具關鍵詞），命中即自動派工，並在任務卡上顯示「已派工，誤判請點取消」。誤判可一鍵轉普通對話。

### 4.2 工作畫布（Work Canvas）機制

派工時 `CanvasStore.create(title: 任務標題, conversationId: 主對話id)`，並**在 AgentLoop 的 context 注入 `workCanvasId`**：
- agent 的 `canvas_*` 工具呼叫一律路由到工作畫布（registry 增「session 畫布」概念：工具層帶 canvasId 參數，default = active，session 覆寫 = workCanvasId）
- 使用者目前觀看的畫布**完全不動**
- 工作畫布建完即出現在畫布列表（命名慣例：`〔任務〕標題`），隨時可切過去共視

### 4.3 交付與防迴路

- Agent Loop 結束 → 產出 TaskSession 交付訊息（系統事件通道，`_lastMessageWasSystemEvent=true`）→ 不會喚醒另一輪 Loop（$33 鐵則）
- 交付訊息本體 = **任務卡 widget**（見 §6），不是純文字
- 產出物圖檔走既有 trustworthy-media-handoff 管線

## 5. 頁面樹與 UI 變動點

```
BridgeDesktopScreen
├── Tab 0 主對話（本刀主戰場）
│   ├── 訊息流
│   │   ├── …一般對話泡泡（不動）
│   │   ├── 🆕 進行中任務卡（working 時常駍訊息流末端的 sticky 卡）
│   │   └── 🆕 交付任務卡（delivered 時插入訊息流）
│   └── 輸入區
│       ├── 🆕 派工鈕（紙飛機，Phase 1 明示派工）
│       └── 🆕 進行中任務 chip 列（多任務並行時的快速切換/查看）
├── Tab 1 畫布
│   └── 畫布列表 🆕 標記〔任務〕工作畫布 + 夥伴頭像角標（誰的）
└── （其他 tab 不動）
```

### 任務卡（收合態＝預設，安靜原則）

```
┌────────────────────────────────────────────┐
│ 🐝 小葵 · 整理農場週報        [working ●]  │  ← 一行：夥伴頭像+任務標題+狀態
│ 步驟 3/5：生成圖卡中…          ▾ 展開      │  ← 一行：當前步驟（收合也看得到）
└────────────────────────────────────────────┘
```

展開態：步驟清單（來自 AgentLoop turn 記錄）＋已花費（BudgetLedger 即時餘額）＋「查看畫布」按鈕（跳 Tab 1 並 loadCanvasById(workCanvasId)）＋「取消」。

### 交付卡（delivered）

```
┌────────────────────────────────────────────┐
│ ✅ 完成 · 整理農場週報                      │
│ 產出 3 項：[縮圖][縮圖][📄週報.md]          │  ← Deliverable 縮圖列，點開即看
│ 「摘要一句話…」             [查看畫布]      │
└────────────────────────────────────────────┘
```

awaitingReview 態：交付卡＋頂部黃條「需要你的判斷：○ 確認 / △ 修改 / ✕ 取消」（對接既有 D002 確認框哲學：危險動作人點頭）。

### 5.1 工作流直播視圖（v2 新增）

使用者在**任何時刻**想看 agent 怎麼做事，三層入口（淺→深）：

1. **任務卡展開**（最淺）：步驟清單即時滾動——來自 AgentLoop turn 記錄（工具名＋一句摘要＋耗時），零額外開銷。
2. **〔任務〕工作畫布直播**（中）：點「查看畫布」→ 跳 Tab 1 `loadCanvasById(workCanvasId)`——agent 每建一個節點/連一條線，**畫布即時長出來**（canvas 事件流本來就是即時的，等于看 agent 蓋房子的實況）。
3. **全屏直播模式**（深，C7）：任務卡選單→「全屏直播」——工作畫布＋步驟時間軸並列的全屏視圖，像看人開實況打遊戲。看的是**同一份 TaskSession 事件流**，只是渲染密度不同。

設計原則：直播是**旁觀**不是控制——看的人不暫停 agent（不中斷鐵則），想介入就走確認/取消。

### 5.2 不中斷鐵則（v2 新增）

任務一旦派出，**任何 UI 操作都不中斷**：切 tab/切頁/切畫布/開別的對話——TaskSession 與 AgentLoop 活在 service 層（ChangeNotifier），不綁在任何 widget 生命週期上。widget 只是觀察者，死了重來照樣顯示。

### 5.3 關窗背景續跑（v2 新增 → C7）

- macOS：攔 `onWindowClose` → `hide()` 視窗（App 行程不死）→ dock 小圖示右鍵選單「顯示視窗 / 關閉 App」；關閉 App 前**必有進行中任務確認框**（有任務時）。
- 行程活著 = AgentLoop 照跑 = 任務照交付。重開視窗（點 dock 圖示）→ 任務卡狀態無縫接回。
- 這是從「視窗生命週期 = App 生命週期」翻轉成「**任務生命週期 ≠ 視窗生命週期**」。

## 6. 資料流（三階段）

**派工瞬間**：
```
輸入框文字 + 派工鈕
  → ChatController.dispatchTask(text)
  → CanvasStore.create(workCanvas) + TaskSession 建立（status=dispatched）
  → ConversationStore 綁定（不加新對話，主對話上綁 session id）
  → AgentLoop.run(指令, context 注入 workCanvasId + taskSessionId)
  → 訊息流插入「進行中任務卡」（sticky）
```

**執行中**：AgentLoop 每個 turn 完成回報 → TaskSession.status=working、步驟計數更新 → 任務卡 setState（走 ChangeNotifier，不重建訊息流）。使用者此時可自由切 tab、繼續聊天——**Offstage 保活保證 Loop 不中斷**。

**交付**：
```
AgentLoop 結果
  → 收集 deliverables（turn 產物掃描：imagePath/節點產出）
  → status=delivered（或 awaitingReview：若本輪有付費生成且閘門要求確認）
  → 交付訊息（系統事件通道，防迴路旗標）+ 任務卡轉交付卡
  → BudgetLedger 結帳寫入 TaskSession（審計軌跡→第 2 刀身份卡直接吃）
```

## 7. Service 設計（純新增，不動引擎）

```
lib/services/tasks/
├── task_session.dart          # 模型（§4）
├── task_session_store.dart    # JSON 持久化（~/Library/.../task_sessions.json，
│                              #   沿用 ConversationStore 慣例；含 rolling backup）
├── task_dispatcher.dart       # 派工編排：建畫布→建 session→喚醒 Loop→訂閱 turn
└── task_progress_card.dart    # widget（訊息流內嵌卡）
```

修改點（最小侵入）：
- `chat_controller.dart`：+`dispatchTask()`；AgentLoop 建構處注入 workCanvasId（`AgentToolRegistry` 的 canvas 工具帶 session 覆寫）
- `agent_loop.dart`：run() 增可選 `taskSessionId`——turn 完成回調（已有 receipt 機制可掛）
- `bridge_desktop_screen.dart`：輸入區 + 派工鈕；畫布列表 + 〔任務〕標記
- MCP `canvas_*` executor：接受 canvasId 參數（default=active）——**這是唯一動到工具層的點，向後相容**

## 8. Commit 計畫（6 commits，計 7.5 工作天）

| # | 範圍 | 驗收 | 天 |
|---|---|---|---|
| C1 | TaskSession 模型+store+dispatcher 骨架；`canvas_*` executor 增 canvasId 參數（default 行為不變） | 單元測試：建 session/持久化/round-trip；現有 canvas 工具測試全綠（零回歸） | 1.5 |
| C2 | ChatController.dispatchTask：明示派工全鏈（建工作畫布→Loop→turn 訂閱→防迴路交付） | console 直跑：派工→背景建〔任務〕畫布→Loop 完→conversations.json 驗屍有交付訊息且無二次喚醒 | 2 |
| C3 | 任務卡 UI（收合/展開/步驟/查看畫布/取消）＋訊息流嵌入 | profile build + 截圖驗收：working 態卡→展開步驟→點查看畫布跳轉正確 | 1.5 |
| C4 | 交付卡＋Deliverable 縮圖列＋awaitingReview 確認條 | 真實派工生圖任務跑通：交付卡顯示縮圖、點開即看、確認後 delivered | 1.5 |
| C5 | 畫布列表〔任務〕標記＋夥伴角標＋多任務並行 chip 列 | 同時派 2 任務：兩工作畫布互不干擾、chip 切換、各自交付 | 1 |
| C6 | IntentSpine 任務型意圖分類（Phase 2 自動派工）＋誤判一鍵轉對話 | 白話測試 10 句（Blue 風格農場題材）：任務句觸發率、閒聊句零誤派 | 0.5 |
| C7 | 關窗背景續跑：`onWindowClose`→hide；dock/menu bar 小圖示（顯示視窗/關閉 App；關閉前有任務確認框）；全屏直播視圖 | ①派工後關窗 → 行程仍活（ps 可見）→ 任務交付至 conversations.json；②點 dock 圖示重開 → 任務卡無縫接回；③小圖示右鍵「關閉 App」有任務時出現確認框 | 1.5 |

## 9. 風險評估

| 風險 | 級別 | 對策 |
|---|---|---|
| 派工誤判（閒聊變任務） | 高 | Phase 1 明示鈕先上；Phase 2 有誤判轉回；IntentSpine 訓練句用 Blue 真實對話 |
| Agent Loop 長跑被切頁/關窗打斷 | 高 | Offstage 保活已有；關窗前有進行中任務→確認框（沿用 canvas 中斷確認哲學） |
| canvas_* 帶 canvasId 參數改動炸現有路徑 | 中 | 參數可選+default=active，C1 全量回歸測試把關 |
| 任務卡卡在 working（Loop 死掉） | 中 | 心跳逾時（120s 無 turn 進展→failed+原因顯示，UI 誠實鐵則） |
| 工作畫布氾濫（列表被〔任務〕淹沒） | 低 | 交付 7 天後自動收合進「任務歸檔」分組；失敗/取消的畫布自動清理（標記不刪，羅盤哲學） |

## 10. 🟡 待 Blue 拍板（5 條）

1. **派工入口**：Phase 1 明示鈕 + Phase 2 自動意圖，還是直接上自動（我建議漸進）？
2. **awaitingReview 範圍**：哪些交付要人點頭？（我建議：凡本輪觸發付費生成→確認；純文字/整理→直接交付）
3. **工作畫布壽命**：任務完成後保留（可追溯/共視）vs 自動收合歸檔？（我建議保留+歸檔分組）
4. **多任務上限**：同時進行中 TaskSession 上限？（我建議 3，配合每日額度閘門）
5. **任務卡視覺**：收合卡一行制的「安靜」程度——連步驟都不顯示（只有狀態燈）vs 顯示當前一步（我的設計）？

## 11. 與後續刀的銜接

- 刀 2 身份卡：TaskSession 審計數據（成功率/花費/時長）直接餵夥伴身份卡
- 刀 3 收據搜尋：TaskSession + deliverables 進聯合搜尋索引
- 刀 4 房間即工作：TaskSession 空間化 = 房間（本刀的種子設計）
- 刀 6 信任曲線：TaskSession 完成記錄 = 信任方程式的分子

## 12. 附錄：驗證策略

- 每個 commit 依 §8 驗收欄實測，不接受「宣稱完成」
- C2 驗屍三件套：conversations.json（交付訊息+無二次喚醒）＋ plist canvas_state（工作畫布節點落地）＋ BudgetLedger 結帳記錄
- C6 用 Blue 式白話零術語測句（農場題材）跑意圖分類
- 最終：Blue 真人派工一次農場任務（測試停留 8-10 秒的隱藏參數，我知道的）
