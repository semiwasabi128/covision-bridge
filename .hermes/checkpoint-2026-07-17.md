# Checkpoint: 2026-07-17 Phase 0 Track A/B/C 完成

## Git HEAD
`6d3beac` — Phase 0 Track A/B/C: MCP 工具整合 + 人格分身層 + 自主迴圈 + 桌面動態效果 + Homepage

## 本次完成清單

### Commit `18a3b59` — Phase 0（桌面版召喚流程）
- `bridge_motion.dart` (817行) — 動態系統：ScaleIn/SlideIn/PulseDot/GlowButton(4狀態)/GlowProgress/SuccessCheck/PageTransitions
- `persona_template.dart` (156行) — 3 人格模板（研究型INTP/創作型ENFP/管家型ESTJ），含 toClues()
- `desktop_welcome_screen.dart` (550行) — Hero + API設定(6 provider chip + URL/Key + 測試亮燈鎖定) + 召喚入口
- `desktop_summon_screen.dart` (711行) — 模板選擇→命名→微調slider→召喚動畫→完成頁
- `companion.dart` — +3欄位(proactivity/verbosity/preferredTools)，向下相容
- `app.dart` — 路由重構：桌面 /desktop-welcome 初始 + Key→Companion→Desktop redirect + 手機改 /bridge-pairing
- `onboarding_detector.dart` — 新增 hasCompanion 偵測

### Commit `6d3beac` — Track A/B/C + 動態效果 + Homepage（12 files, 1,563 insertions）

**Track A — MCP 工具整合:**
- `mcp_canvas_tools.dart` — 11 MCP 端點包裝成 AgentTool（get_state/screenshot/annotations/add_node/connect/remove/execute/navigate/send_chat/list/load），直接走 callback 不走 HTTP
- `agent_tool_registry.dart` — 工具註冊到 AgentToolRegistry，新增 mcpCanvasExecutor 參數
- `agent_loop_prompt_builder.dart` — System Prompt 擴充畫布工具使用原則（先看再做、邊做邊說、破壞性操作需確認）
- `chat_controller.dart` — MCP executor 屬性注入
- `desktop_chat_panel.dart` — 接收 mcpCanvasExecutor 參數傳給 ChatController
- `bridge_desktop_screen.dart` — `_DesktopMcpCanvasExecutor` 實作（直接包裝 CanvasMcpServer callback），含 WorkflowNodeType 字串轉換

**Track B — 人格分身層:**
- `persona_manager.dart` — PersonaManager（人格切換 + system prompt 組裝 + 行為參數指導 proactivity/verbosity/preferredTools）

**Track C — 自主迴圈:**
- `agent_event_bus.dart` — 7 事件類型(userAnnotation/workflowCompleted/workflowError/canvasChanged/userMessage/userIdle/brainMemoryAdded) + 60秒idle偵測 + broadcast StreamController（以利沙 24 測試全過）
- `agent_safety.dart` — 三層邊界：prohibitedActions(禁止) / confirmationRequired(需確認) / destructiveActions(紅色警告) + needsConfirmation(autoExecute例外) + buildConfirmationMessage/buildProhibitedMessage
- `native_agent_loop.dart` — 事件驅動 + 60秒idle兜底迴圈，含 annotation/workflow/idle 事件處理

**桌面動態效果:**
- `bridge_desktop_screen.dart` tab轉場 — 升級為 Miro 無限畫布風格（scale+fade+slide，用 BridgeDS.transitionCanvas/transitionSlide 曲線）

**Homepage:**
- `desktop_homepage_screen.dart` — 教學引導4卡片(對話/畫布/大腦/設定) + 社群市集佔位
- `app.dart` — 新增 /desktop-homepage 路由

## App 資料已清除（初始狀態）
- ✅ SharedPreferences plist（327MB對話歷史+設定）— 已刪
- ✅ bridge_state（conversations.json + canvases.json）— 已刪
- ✅ brain_container.db — 已刪
- ✅ bridge_media（圖片、文件）— 已刪
- ✅ backgroundDownloader — 已刪
- ⏸️ Keychain API tokens — 保留
- ⏸️ flutter_gemma 本地模型（175MB）— 保留

## 驗證狀態
- `dart analyze lib/` — 0 errors
- `flutter build macos --debug` — ✅ build 成功
- App 資料已清空，開起來會走歡迎頁流程

## 5 拍板決策（2026-07-17 Blue 確認）
1. 迴圈 = 事件驅動 + 60秒 idle 兜底
2. 確認 = 對話框（非 UI 彈窗），破壞性操作加紅色警告
3. 人格 = 3 模板 + 可自命名
4. Hermes 關係 = 指派任務為主
5. autoExecute 預設全 false

## 下一步 = Phase 1：實機測試 + UI 打磨
- 開 App 跑完整流程：歡迎頁 → 設Key → 召喚 → 桌面主畫面
- 測試 Miro 風格 tab 轉場動態效果
- 測試 MCP 工具是否正確注入 Agent Loop
- 測試人格切換 + system prompt 組裝
- UI 細節打磨（按鈕移入移出、對話欄移入、功能欄冒出）

## 恢復關鍵字
貼上：「接續橋樑 App Phase 1 測試，HEAD=6d3beac，App 資料已清空」
