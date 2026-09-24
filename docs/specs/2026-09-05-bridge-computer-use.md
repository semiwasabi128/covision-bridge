# Spec：橋樑 Computer Use — 接管電腦三件套（Bridge Computer Use Trilogy）

> **狀態**：Draft v1（2026-09-05，小葵）
> **決策**：Blue 2026-09-05 定調——安全機制先建，再建三件套，為 CAD / SketchUp / 其他專業軟體鋪路
> **北極星**：使用者在橋樑 App 用任一模型（GPT-6 Astra / Claude / 本地模型），Agent 都能「看著螢幕、動手操作」，替使用者完成需要專業軟體才能產出的數位資產（CAD 檔、SketchUp 模型、文件、簡報）。
> **核心原則（模型不可知）**：App 提供手和眼，鑰匙決定大腦。computer use 三件套是橋樑的資產，不是某模型的附屬功能——這是對 ChatGPT 鎖死在自家 app 的最大差異化。

---

## 0. 定位與差異化

| | ChatGPT Desktop / Codex | 橋樑 App |
|---|---|---|
| 大腦 | 只有 OpenAI 模型 | 任一鑰匙（模型市集） |
| 手眼 | 自家封閉 | 開源三件套，模型不可知 |
| 過程 | 多為黑箱 | 每步投影到畫布（共同看見、可喊停） |
| 安全 | 平台方決定 | 使用者主權（接管授權閘門＋緊急停止） |

## 1. Phase 0：安全機制（先於一切功能，硬性前置）

> 鐵則來源：Blue 08-31 測試紀律「Blue 在電腦前＝絕不注入鍵鼠」＋ UI 誠實鐵則＋人機共駕。

### 1.1 接管授權閘門（Takeover Gate）
- 全域狀態機：`idle`（永不注入）→ `armed`（已授權待命）→ `active`（正在操作）→ `suspended`（暫停）
- **進入 active 的唯一路徑**：使用者明確動作（按鈕/指令）＋ TCC Accessibility 權限已授予
- 授權以「任務」為單位，不是常駐：一次接管綁定一個任務（例：「用 SketchUp 建出這個櫃體」），任務結束或喊停即回 idle
- App 重啟後一律回 idle，授權不跨 session 保存

### 1.2 真人在場偵測（Human Presence Guard）
- 復用既有 `CGEventSource.secondsSinceLastEventType`（MainFlutterWindow.swift 已實作，螢保在用）
- **反向應用**：接管進行中，若偵測到「最近 N 秒內有真人輸入且非 Agent 注入的事件」→ 立即 suspend
- 區分來源：Agent 注入的事件用 `CGEventSource` 私有標記（`eventSourceUserData` / 獨立 event source id），真人輸入來自 combinedSessionState 的其他 source——凡是無法歸屬 Agent 的新鍵鼠事件 = 真人到場 = 停手
- 預設 N = 3 秒（真人輸入後 3 秒內 Agent 不動）

### 1.3 緊急停止（Kill Switch）
- **硬體級**：使用者按住 `Esc` 連續 1.5 秒 → 立即中止所有注入、退出 active（全域 hotkey，不走模型）
- **視覺級**：接管進行中，螢幕邊緣顯示細幅狀態條（琥珀色）＋「停止接管」按鈕常駐可點
- 停止後：Agent 收到 abort 信號，畫布任務卡片標記「已由使用者中止」（誠實記錄，不假裝完成）

### 1.4 操作圍欄（Action Fence）
- 預設禁區：鑰匙/密碼欄位、系統設定、檔案刪除對話框、付款頁面（以 AXUIElement role 判斷：`AXSecureTextField` 一律拒絕輸入）
- 檔案系統寫入限定：App sandbox + 使用者明確授權的輸出資料夾（預設 `~/Bridge Workspace/` 或使用者指定）
- 每個動作可回放：全部注入事件寫入 takevoer log（時間戳＋座標＋內容摘要），事後可審計

### 1.5 經濟圍欄（接 Ledger / 預算之眼）
- computer use 任務即時顯示 token 消耗截圖輪數（每輪 = 一次視覺調用）
- 預算上限到達 → 自動 suspend 並回報，不靜默續跑

### 1.6 誠實標示（接 fallback 顯性標示 spec）
- 接管過程的每一步在畫布上可見：截圖縮圖 → 模型判讀結論 → 動作 → 驗證截圖
- 模型 fallback 發生時（例如指定 Astra 但鑰匙失效）→ 琥珀徽章＋中止確認，不自動降級續跑

## 2. Phase 1：三件套本體

### 2.1 眼睛 — 螢幕循環（Screen Loop）
- **既有資產**：`bridge.screen_capture.macos.v1` 已有 `captureWindow` / `listWindows`（截圖三件套之一已存在 ✅）
- 擴充：全螢幕截圖、指定區域截圖、多螢幕支援、主動式截圖節流（畫面無變化不重抓，比對 hash）
- 輸出格式統一：PNG bytes + 視窗/區域 metadata，直接餵 vision 端點

### 2.2 讀取 — UI 樹（AXUIElement Bridge）
- 新 channel：`bridge.ax.macos.v1`
- 方法：`getFocusedWindow` / `getWindowTree`（深度限制參數）/ `findElements`（by role/title/座標） / `getElementBounds`
- 這是可靠度的關鍵：模型問「『擠出』按鈕在哪」，AX 給精確座標與可點性，而非純像素猜測
- 效能鐵則：UI 樹查詢限深（預設 6 層）、限寬（單層 200 節點），避免 CAD 軟體巨型樹拖垮

### 2.3 手 — 事件注入（CGEvent Injector）
- 新 channel：`bridge.cginput.macos.v1`
- 方法：`moveMouse(x,y)` / `click(button,count)` / `drag(from,to)` / `scroll(dx,dy)` / `keyDown/Up(code)` / `typeText(text)`（用 CGEventKeyboardSetUnicodeString 處理中文，不依賴鍵盤佈局）
- 全部事件帶 Agent 標記（1.2 的來源區分）
- 注入節流：最小間隔 50ms，拖曳用曲線插值（真人節奏，也避免被軟體的反自動化拒絕）

### 2.4 Agent 循環（Dart 層 orchestrator）
```
loop:
  1. 截圖（畫面 hash 沒變且無待驗證動作 → 跳過本輪）
  2. 組 prompt：截圖 + AX 樹摘要 + 任務目標 + 前幾步結果
  3. 呼叫鑰匙選定的模型（vision 能力），取得下一動作（結構化 JSON：
     {think, action: click/type/scroll/drag/done/fail, target, expect}）
  4. 安全檢查（1.2~1.4 全過）→ 執行注入
  5. 驗證截圖比對 expect，失敗重試 ≤2 次
  6. 每步投影到畫布（共同看見）；
     done → 產出檔案驗證存在 → 存入資產庫＋ExecutionReceipt
```

## 3. Phase 2：專業軟體直通車（Script API 優先於 GUI）

> 原則（Agent 鐵則放大版）：先盤點目標軟體原生能力，有 API 走 API，沒有才接管 GUI。API 快 100 倍且零點擊失誤。

| 軟體 | 直通車 | 產出 |
|---|---|---|
| SketchUp | Ruby API（`sketchup -RubyStartup` / 執行中 via `sudo` pipe） | .skp 模型 |
| Blender | Python（`blender --background --python script.py`） | .blend / OBJ / FBX |
| FreeCAD | Python（headless 可） | STEP / BIM（接 Blue 室設/建築/BIM/建材計算計畫） |
| LibreOffice | UNO API | 文件/試算表/簡報 |
| 其他 | 通用 GUI 接管（Phase 1 能力） | 任何軟體可存的檔案 |

- 架構：`SoftwareAdapter` 介面——每個專業軟體一個 adapter（generate(params) → script → 執行 → 驗證產出檔案存在＋格式 sniff）
- 腳本生成由模型負責（這是 LLM 強項），App 負責沙盒執行與驗證
- 產出一律進數位資產庫（副檔名魔數 sniffImageExtension 同款紀律：副檔名不符 = 拒收）

## 4. 落地順序與驗收

| Phase | 內容 | 驗收標準 |
|---|---|---|
| **P0 安全** | 狀態機＋真人在場偵測＋Esc kill switch＋圍欄 | ①真人動滑鼠 3 秒內 Agent 停手 ②Esc 1.5 秒中止 ③ secure 欄位輸入被拒 ④重啟後回 idle |
| **P1a 眼+手** | 全螢幕截圖循環＋CGEvent 注入＋最小 agent loop | 示範：模型操作 Finder 建資料夾＋改名，全程畫布可見、可喊停 |
| **P1b AX** | AXUIElement bridge | 同任務點擊成功率從像素猜測升到 AX 導引（量化對照 ≥95%） |
| **P2 直通車** | SketchUp Ruby adapter 先行 | 「一句話生成一個 90×60×45 櫃體 .skp」——檔案存在＋SketchUp 可開＋尺寸正確 |

## 5. 工程掛點（依 APP_ARCHITECTURE_MAP 慣例）

- Swift 端：`MainFlutterWindow.swift` 註冊 `bridge.ax.macos.v1`、`bridge.cginput.macos.v1`（比照 screenChannel 模式，獨立 handler class）
- Dart 端：`lib/services/computer_use/`（takeover_gate.dart / screen_loop.dart / ax_bridge.dart / input_injector.dart / agent_loop.dart）
- UI：畫布任務卡片新增「接管中」類型（琥珀狀態條＋逐步截圖縮圖）；能力中心新增「電腦接管」區塊（權限狀態＋授權按鈕）
- 安全狀態機為全域單例，任何注入路徑必經其檢查（單點強制，不靠各處自覺）
- 修改後同步更新 APP_ARCHITECTURE_MAP.md（新增 channel＋服務層）

## 6. 風險清單

- TCC Accessibility 授權 UX（首次引導要一次講清楚「為什麼需要」，參照 $33 五層根治的 TCC 代按經驗）
- macOS Sequoia+ 的「每週重新授權螢幕錄製」政策——截圖循環要能優雅降級（提示而非靜默失敗）
- 點擊座標在不同縮放（Retina scaling）的換算——以 AX bounds 為準而非像素絕對值
- 模型幻覺座標：一律 AX 優先，AX 找不到才允許視覺猜測，且猜測動作標記低信心
