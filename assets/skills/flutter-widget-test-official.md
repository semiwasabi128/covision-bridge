---
name: flutter-widget-test-official
description: Flutter 官方 WidgetTester 元件級測試指引——9 步流程 + 互動模式決策樹
trigger_keywords:
  - widget test
  - 元件測試
  - WidgetTester
  - 測試 widget
trigger_patterns:
  - "(widget|元件|組件).*(test|測試)"
  - "WidgetTester"
priority: high
version: 1
source: https://github.com/flutter/agent-plugins/tree/main/skills/flutter-add-widget-test
synced: 2026-09-20
---

# Flutter Widget Test 官方指引（蒸餾版）

## 9 步流程
1. 確認 `flutter_test` 在 dev_dependencies
2. 測試檔放 `test/` 目錄，命名 `<widget>_test.dart`
3. `testWidgets('描述', (tester) async {...})` 開頭
4. `await tester.pumpWidget(MyWidget())` 渲染
5. 用 `find.byType()` / `find.text()` / `find.byKey()` 定位
6. 互動：`await tester.tap()` / `enterText()` / `drag()` / `scroll()`
7. `await tester.pump()` 或 `pumpAndSettle()` 觸發 rebuild
8. `expect(...)` 斷言（畫面存在、狀態改變、回呼被呼叫）
9. `flutter test` 執行驗證

## 互動模式決策樹
- **靜態渲染**：pumpWidget → find → expect（最簡單）
- **State 變化**：tap → pump → expect 新狀態
- **動畫**：用 `pump(Duration)` 逐幀，不要 pumpAndSettle（可能無限動畫會 hang）
- **文字輸入**：`enterText(find.byType(TextField), '內容')` → pump
- **長列表**：`scrollUntilVisible()` / `dragUntilVisible()`，不要硬 drag 固定距離

## 橋樑 App 專屬提醒
- 新增 canvas 節點型別時，至少寫一個 widget test 驗證節點渲染
- BridgeDSColors 驗證：test 中用 `tester.widget<T>(find...)` 檢查顏色是否來自 token（非硬編碼）
- 泡泡頭像 = msg.speakerId：對話 widget test 斷言頭像與訊息關聯

## 完整文件
https://github.com/flutter/agent-plugins/tree/main/skills/flutter-add-widget-test
