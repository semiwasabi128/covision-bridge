# 橋樑 App — Agent 工作守則

## ⚠️ 唯一正確專案路徑
**本尊（唯一）**：`~/Developer/bridge_app`（系統碟，2026-08-04 搬移完成）

舊副本已封存：
- 外接備份碟上的舊副本 — 文件用，**不得修改**

所有 grep / read_file / patch / flutter build 一律在**系統碟本尊** `~/Developer/bridge_app` 進行。
派工給 subagent 時，prompt 內務必明寫絕對路徑 `$HOME/Developer/bridge_app`，並要求第一步用
`pwd && wc -l lib/screens/chat_screen.dart` 確認在本尊
（chat_screen.dart 應為 ~8765 行；若行數不符代表讀到舊副本，立即停止）。

## 專案規模索引
- `lib/screens/chat_screen.dart` ~8765 行（對話主畫面，最大）
- `lib/controllers/chat_controller.dart` ~4700 行
- chat_screen 超大，務必 grep + 分段 read_file，不要一次全讀

## 已知死代碼（畫線框圖/設計時排除）
- `chat_screen.dart` `_showSkillPanel`（7 chip）— 無 UI 觸發點
- `chat_screen.dart` `_showModeSelector`（5 靈魂模式）— 死代碼，無呼叫處（舊「靈魂切換」殘骸，概念已演進為多 Agent 切換）
- `chat_screen.dart` `_showMemoryOverlay` — 死代碼

## 📱 手機版狀態
**手機版已正式宣告刪除（2026-08-10），不再干擾桌面 APP 開發進度。**
- 未來手機版將重新設計
- **方向對位（2026-09-20 Blue 令 + Orca 借鑑）**：手機 companion = 「出門時能看見 Agent 在畫布上做什麼 + 丟 follow-up」。**不是另一個桌面，不是被動遙控器**——共視的「同處」精神要從桌面延伸到口袋
- 完整規格 + 痛點對位 + 攔截風險在 [Phase G Timeline §3.5 借鑑 1](docs/PHASE_G_TIMELINE.md)（高優先 ⭐⭐⭐）
- 手機版相關檔案保留但不再被路由觸發：
  - `lib/screens/mobile_bridge_pairing_screen.dart`
  - `lib/screens/mobile_design_showcase_screen.dart`
  - `lib/services/mobile_bridge_client.dart`
  - `lib/widgets/mobile/`（app_bar_mobile.dart, mobile_navigation.dart）
- `_isDesktopPlatform` 已改為永遠 `true`——所有平台一律走桌面流程

## 🧹 settings_screen.dart 已刪除（2026-08-11）
**`lib/screens/settings_screen.dart` 已刪除——不再存在。**
- API key 管理 → 統一在 `bridge_desktop_screen.dart` 主腦 API 設定（鎖定/測試/解除鎖定）
- API key 也可以在 `capability_center_screen.dart` 能力中心管理
- DB 路徑設定 → 搬到 `lib/widgets/settings/db_location_card.dart`（顯示在 bridge_desktop 系統設定頁）
- SemiDAO 三項（審查金鑰/Pinata/錢包）→ `lib/screens/desktop/settings/semidao_settings_page.dart`（placeholder，SemiDAO 啟動時填充）
- 向量 DB 設定 → 已由 `vault_screen.dart` 取代（向量資料庫 tab）
- 密碼鎖/生物鑒別/排程 Daemon/跨裝置連接 → 手機版遺留，直接刪除
- 所有 `/settings` 導航 → 改為 `BridgeDesktopScreen.navigateTo('system')`
- `/settings` 路由保留但 redirect 到 `/`（向後相容）

## 尚未完成（2026-06-27 盤點確認真的沒做）
- 手機 responsive 地基：`lib/core/responsive.dart`、`lib/widgets/adaptive_scaffold.dart`、`lib/widgets/adaptive_card.dart`、`lib/core/spacing.dart` — **全部不存在**，待 Opus 親手建立並 stat 驗證

## 📐 設計原則索引（必讀）
- **[共視宣言 (Covision Manifesto)](docs/COVISION_MANIFESTO.md)** — v1.0，2026-08-09 啟用 ⭐
  - 橋樑計畫的**產品定位錨點**：人機共視是全球 open-source 生態中的空白位
  - 共視三層：共同看見 → 共同感覺 → 共同建造
  - 產品指標方向：共視時長、共同指向頻率、建造完成率
  - 開源溝通建議：README 第一句 = "The Covision App for Humans and AI"
- **[資料主權宣言 (Data Sovereignty Manifesto)](docs/DATA_SOVEREIGNTY_MANIFESTO.md)** — v1.0，2026-09-15 啟用 ⭐
  - 資料主權的產品錨點：金鑰匙/DataPathGate/除痕≠刪除三原則
  - 五層主權動線：Welcome 字卡→匯入泡泡→路徑徽章→總覽卡→除痕
  - 開源時可直接作為對外文案（真實數據+commit 鏈可考）
- **[橋樑核心發想 Phase F](docs/BRIDGE_CORE_IDEAS_PHASE_F.md)** — v0.1 草稿，2026-08-09
  - 三個核心發想的實現規格：共視時長指標、發想素材池節點化、走你的橋
- **[Phase F Sprint Plan](docs/PHASE_F_SPRINT_PLAN.md)** — ✅ 已收尾（2026-09-13）
  - 共視功能化 sprint；資產移交 Phase G
- **[Phase G Timeline](docs/PHASE_G_TIMELINE.md)** — v0.1，2026-09-13 ⭐ 現行主線
  - 三大主軸：時間感（L2-L4）/ 因果引擎（Phase 0/1/L4 狀態分叉）/ Agent 平台（匯入器+大搬家）
  - 全部以 git log 錨定，不憑記憶
  - **§3.5 Orca 借鑑項目（2026-09-20）**：7 條 + 3 條不借鑑切割——手機 companion、畫布 CLI、狀態單一真相源、設計系統 lint gate、per-task 設定檔、AGENTS.md 拆分、同題多解並列評分
- **[Rig 封存復盤](docs/RIG_RETROSPECTIVE.md)** — 2026-09-13
  - 為什麼嘗試/為什麼收尾/保留什麼——防未來重啟死路
- **[橋樑排版設計原則 (Bridge Typography Design Principles)](docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)** — v1.0，2026-08-04 啟用
  - 9 級距字體 token、6 級距圖示 token、33 個 BridgeDSColors token
  - 主題包（Theme Pack）擴充介面設計 — 未來開源社群可下載主題包
  - **所有新 UI 程式碼必須遵守此原則**，違規 PR 不可 merge
- **[DESIGN.md](DESIGN.md)** — 5 套設計系統融合的原始規範（xAI / Raycast / Stripe / Figma / Miro）
- **[Bridge 統合設計語言 (Bridge Unified Design Language)](docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)** — v1.0，2026-08-08 啟用
  - 六源蒸餾 → 六種 Bridge 能力 → 第七個結果：共視
  - 三層不反轉：功能骨架(A) → 關係推演(B) → 事件氣氛(C)
  - 衝突裁決順序 + 元件設計六問
- **[橋樑色塊設計規範 (Bridge Color Block Design Guide)](docs/BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md)** — v1.0，2026-08-04 啟用
  - 從 V2 Canvas 抽出的「眼睛舒服」配色標準
  - 三層視覺架構、配色規則、卡片標準結構
  - **所有 UI 必須照這個做，違規 PR 不可 merge**
- **[橋樑 Tier 系統 (Bridge Tier System)](docs/BRIDGE_TIER_SYSTEM.md)** — v1.0，2026-08-05 啟用
  - 33 個語意化 tier（list.item.title、card.body、bg.panel.base 等）
  - 三層架構：widget → tier manifest → BridgeDSColors token
  - 三大防呆：禁寫死顏色 / token 名拼錯 build 失敗 / 未定義 throw
  - **未來開源社群改主題包就能一鍵對齊全 App，不用碰 widget 程式碼**
  - ⚠️（2026-09-21 Blue 抓包）**新元件（AlertDialog/彈窗/SnackBar）文字層級必走 Tier、顏色必走 BridgeDSColors——禁 `Theme.of(context).textTheme` 與 Material 預設**，dialog 內對應表見該文件「AlertDialog 鐵則」節
- **[橋樑氣氛設計語言 (Bridge Atmosphere Design Language)](docs/BRIDGE_ATMOSPHERE_LANGUAGE.md)** — v0.1 草稿，2026-08-06 啟用
  - Active Theory 設計紀律的蒸餾 + SemiMaker 時刻表（24h 內 21 次時針分針重疊）
  - LOGO 形狀規則（鎖死 5 條 + 社群可改事項）
  - 主題包架構：社群設計者可獨立設計氣氛主題包，不影響功能層
  - GPU 預算 ≤ 5% / CPU ≤ 8% / 記憶體 ≤ 200MB（與 Active Theory 自家紀律一致）
- 死代碼（2026-08-04 清理）：`lib/widgets/canvas/open_canvas_workspace.dart` (2139 行) — V2 取代

## 🗺️ 架構地圖（必讀）
**[docs/APP_ARCHITECTURE_MAP.md](docs/APP_ARCHITECTURE_MAP.md) — 每次修改前必讀**

- 「想改 X → 去哪改」索引表（最快定位）
- 啟動鏈、API 呼叫鏈、本地模型啟動鏈
- Swift↔Dart 橋接點（含兩端都要改的陷阱）
- 已知陷阱清單
- 修改後必須同步更新地圖（特別是新增功能或新陷阱）

**規則：每次修改 / 修復 / 重構前，先查這份地圖的「快速導航」表。**
**找不到再 grep，找到了就在地圖上補一筆——地圖过期 = 下次改錯地方。**
**改完程式碼後，如果行號變了或新增了檔案/功能/陷阱，必須同步更新地圖。**
**未來手機版初稿完成後，手機版地圖也要加入 APP_ARCHITECTURE_MAP.md。**

## 驗收鐵則
- `flutter analyze 2>&1 | tail -20` 零錯誤才算完成
- subagent 宣稱「建檔/改檔完成」必須由主 session 親自 `ls`/`wc`/`grep` 驗證，不可僅憑宣稱
