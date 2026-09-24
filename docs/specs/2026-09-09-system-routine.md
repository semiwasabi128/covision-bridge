# 刀 5 延伸：全電腦示範錄製（System Routine）— 設計稿 v1

> 設計師：小葵
> 日期：2026-09-09（Blue 拍板：偵察 B → 開工令）
> 偵察結論：docs/specs 無；tmp_recon/test_event_tap.swift 已驗證 CGEventTap+AX 可行
> 狀態：**開工中**（Blue 已拍板「好👌開工」）

---

## 一、這刀解決什麼

**「示範錄製只能錄橋樑 App 嗎？」→ 不。錄全電腦。**

Blue 的令：錄製全部電腦的動作，agent 一學就會——解決 **MCP 不完備時的 agent 代操作軟體**問題。任何 App 都有 Accessibility 樹，等於全 macOS 免費獲得通用 MCP。

## 二、架構第一約束（Blue 令：將來要做在 Windows）

**分層——Dart 層平台中立，原生層各平台實作：**

```
Dart 層（跨平台共用）
  SystemRoutineEvent schema（正規化 JSON）：
    { seq, t, app, windowTitle, role, title, value?,
      action: click|key|scroll|type, x?, y?, keyCode?, masked? }
  錄製器 / 故事產生 / 隱私遮罩 / 重播調度
        │ MethodChannel: bridge.computer_use.macos.v1（既有多工復用）
        │ + 新增 listen 頻道（EventChannel 或 MethodChannel 回調）
  macOS 後端（Swift）——CGEventTap + AXUIElement
  Windows 後端（未來）——SetWindowsHookEx + UIA（觀念一一對應）
```

**鐵則**：routine 檔是平台中立 JSON；「找元素（role+title）→動作」重播指令正規化；座標只是退路。

## 三、地基盤點（ComputerUseNative.swift 505 行——大半已在）

| 積木 | 現狀 | 本刀動作 |
|---|---|---|
| CGEventTap（Esc 開關用） | ✅ 已有 | 擴充：listen-only 模式收點擊/鍵盤/滾輪 |
| AX 點位查詢（isProtectedField） | ✅ 已有 | 擴充：查詢時帶回完整描述（app/role/title/value） |
| InputInjector（click/typeText/key 注入） | ✅ 已有（帶圍欄） | 直接用=重播的手 |
| 密碼欄保護 | ✅ AXSecureTextField 拒絕 | 錄製端同步遮罩 |
| TCC 權限 | ✅ 已有 | 直接用 |
| **缺**：全域事件→Dart 串流 | ❌ | **新增**（SR.1 核心） |
| **缺**：Dart 錄製器 | ❌ | **新增**（SR.2 核心） |

## 四、落地切片

| # | 內容 | 檔案 |
|---|---|---|
| SR.1 | Swift：listen tap（點擊/鍵/滾輪→AX 快照→sink 回 Dart） | ComputerUseNative.swift 擴充 |
| SR.2 | Dart：SystemRoutineRecorder（事件流→schema→故事＋遮罩） | lib/services/routines/system_routine_recorder.dart（新） |
| SR.3 | 錄製 UI：托盤「示範錄製（全電腦）」入口＋即時事件指示 | tray_service + 簡單面板 |
| SR.4 | 重播：走既有 InputInjector（gate.arm 帶 taskId 圍欄） | system_routine_player.dart（新） |
| SR.5 | 測試：schema 正規化/遮罩/故事（Dart 純函式可測） | test/services/routines/ |

## 五、隱私鐵則（最高約束）

1. 全程本地——事件不上雲不入訓練
2. 密碼框（AXSecureTextField）值一律 `****`；一般輸入框值截 30 字
3. 錄製中托盤/面板恆亮指示（loop 鐵則可見）
4. 暫停熱鍵（⌘⇧P）一鍵暫停
5. 重播必經 gate.arm（既有真人接管狀態機——Esc 隨時接管）

## 六、驗收

- 錄：開錄→點別的 App 的按鈕/打字→停→事件故事「Safari · 按了『加入購物車』」
- 密碼框錄製顯示 [已遮罩]
- 重播：agent 走 InputInjector 重現操作（帶圍欄）
- lib/ 零 error；Dart 測試綠；build 成功

## 七、一句話

**任何 App 都是 MCP——你示範一遍，agent 用輔助使用樹學會代操作。**
