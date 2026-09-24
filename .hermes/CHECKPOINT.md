# 橋樑 App Checkpoint — 2026-07-18 Session 3

## Git
- commit: `03a91ed` — feat: P1+P2+App自拍+截圖清理+完成偵測
- 上一個: `d9eb36a` — checkpoint: Step2 按鈕功能測試全7頁完成
- 再上一個: `b061a3c` — checkpoint: render error 修復完成, UX導航7頁通過

## 本 Session 完成

### Step 2 按鈕功能測試（第一輪）
- 6 個測試任務透過任務注入通道派給小橋
- Home Page 5 按鈕全通過、Companion Hall 通過、Chat/Canvas/Brain/System TopBar 導航全通過
- 發現 P1（Home 缺系統入口）+ P2（ui_get_state 只覆蓋 TopBar）

### 四項修復全部完成並驗證

1. ✅ **P1: Home Page 加「系統」入口**
   - 在功能區加了第 6 個 `_HomeTile`（系統，設定與管理）
   - 位置：`bridge_desktop_screen.dart` L1778-1789

2. ✅ **P2: ui_get_state 擴充 tappable**
   - Brain 頁面：tappable 新增「統計」「圖譜」
   - System 頁面：tappable 新增「模型下載」「配對管理」「檔案總管」「設定」+ 子頁面「返回系統」
   - tap() 也加了對應的點擊處理
   - 驗證：小橋成功點擊所有頁面內部按鈕

3. ✅ **App 自拍功能（Blue 提議）**
   - 新增 `FlutterSelfCaptureExecutor`（RepaintBoundary + toImage）
   - 不需要螢幕錄製權限、不受前景/背景影響、截 App 自己的畫面
   - 在 build() 最外層包 `RepaintBoundary(key: _selfCaptureKey)`
   - 取代 `MacScreenCaptureExecutor`（CGWindowListCreateImage 截全螢幕）
   - 驗證：`[自拍] 截圖完成：...screenshot_xxx.png (185944 bytes)` — 截到的是 App 畫面不是全螢幕

4. ✅ **截圖自動清理（ring buffer）**
   - 內建在 `FlutterSelfCaptureExecutor._cleanupOldScreenshots()`
   - 只保留最近 20 張，超過自動刪最舊的

5. ✅ **forceToolUse 完成偵測**
   - 新增 `_looksLikeCompletion()` 方法
   - 判斷：已用過工具 + 回覆 > 50 字元 + 含完成指示詞 = 自然結束不 nudge
   - 驗證：`[AgentLoop] 偵測到完成總結，自然結束（不 nudge）` — 循環問題解決

### 驗證結果
- 小橋自主完成 Brain + System 頁面內部按鈕測試（13 步全通過）
- 自拍截圖確認是 App 畫面不是全螢幕
- 完成偵測正常觸發，小橋做完就停不循環
- 零 render error

## 核心理念記錄
- 小葵是教練不是選手：小橋卡住要建能力+教自救，不代做
- 第一輪測試小葵有出手（截圖+vision 補位）— 因為小橋缺能力
- 修復後小橋獨立跑完全程，小葵純旁觀

## 回復關鍵字（貼上開新 session）
```
橋樑App checkpoint 03a91ed，P1(Home系統入口)+P2(ui_get_state頁面內按鈕)+App自拍(RepaintBoundary)+截圖ring buffer+forceToolUse完成偵測 全部修復驗證通過，下一步Step3全局測試
```

## 下一步
1. **Step 3 總檢查** — 全局運作測試（小葵手做）
2. **完整重跑 Step2** — 用新能力跑全 7 頁按鈕測試，確認頁面內部按鈕全覆蓋
3. **onboarding 階段啟動自主心跳**（缺口 1，待修）
4. **設計審查 Step 1 剩餘** — 其他 7 頁字體階層修復

## 關鍵檔案
- `lib/screens/bridge_desktop_screen.dart` — Home 系統 tile、_DesktopUiActionExecutor 擴充、RepaintBoundary 接線
- `lib/services/agent_loop/agent_loop_tools/flutter_self_capture_executor.dart` — 新檔案，App 自拍 executor
- `lib/services/agent_loop/agent_loop.dart` — _looksLikeCompletion() 完成偵測

## App 啟動方式
- 開發看 log: `cd bridge_app && flutter run -d macos`
- token 注入: `source ~/.hermes/profiles/ceo/.env && defaults write farm.semiwasabi.bridgeApp "flutter.fallback_api_token_v2_openai" "$OPENAI_API_KEY"`
- 截 App 視窗（開發用）: `swift -e '...'` 取 window ID → `screencapture -l <id> /tmp/xxx.png`

## 任務注入
- 寫 JSON 到 `~/Library/Containers/farm.semiwasabi.bridgeApp/Data/Library/Application Support/farm.semiwasabi.bridgeApp/agent_tasks/pending/`
- 格式: `{task_id, prompt, force_tool_use, max_steps, created_at}`
- 結果在 `done/` 目錄

## 模型設定
- LLM: gpt-5.4 (Tier 1, maxTurns=25)
- _defaultModel: `api_service.dart` = `gpt-5.4`

## 已知問題
- `ui_tap("召喚夥伴")` 會殺死小橋（導航離開 BridgeDesktopScreen → dispose → Agent Loop 停）
- `restart_app` 工具會自殺
- onboarding 階段（DesktopWelcomeScreen）未啟動自主心跳
