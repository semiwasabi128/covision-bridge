---
name: flutter-integration-test-official
description: Flutter 官方 Integration Test 指引——Flutter Driver + MCP 探索轉永久 E2E 測試
trigger_keywords:
  - integration test
  - 整合測試
  - e2e測試
  - 端到端測試
trigger_patterns:
  - "(integration|整合|端到端|e2e).*(test|測試)"
priority: high
version: 1
source: https://github.com/flutter/agent-plugins/tree/main/skills/flutter-add-integration-test
synced: 2026-09-20
---

# Flutter Integration Test 官方指引（蒸餾版）

## 三層結構
1. **啟用 extension**：`integration_test/` 目錄 + `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`
2. **探索 UI**：Agent（或真人）透過 MCP / Flutter Driver 觀察 widget tree——tap 哪、輸入什麼、預期看到什麼
3. **固化為測試**：把探索到的互動序列寫成 `testWidgets`，用 `find.byType/Key/Text` 重現每一步

## 核心模式
```dart
// integration_test/app_test.dart
final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
testWidgets('完整流程', (tester) async {
  app.main();
  await binding.traceAction(() async {
    await tester.pumpAndSettle();
    // 互動序列...
  });
});
```
- 執行：`flutter test integration_test/`（模擬器或真機）
- 每個 E2E 測試 = 一條用戶旅程（登入 → 建節點 → 連線 → 儲存）

## 橋樑 App 專屬提醒
- 優先把「高價值旅程」固化：建立夥伴 → 對話 → 切換夥伴（companionId 驗證）
- canvas 連線流程：port 點擊 → 連線意圖 → port 命中（UX 鐵則的自動化驗證）
- 用 `flutter drive --driver=integration_test/driver.dart` 可截圖存證

## 完整文件
https://github.com/flutter/agent-plugins/tree/main/skills/flutter-add-integration-test
