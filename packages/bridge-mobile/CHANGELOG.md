# Changelog

## 1.0.0 (2026-08-06)

### 新增

- ✅ 初始發布
- ✅ Swift SDK（iOS 13+ / macOS）：連線 / 訊息收發 / **85 個完整 UIColor tokens**（自動生成）
- ✅ Kotlin SDK（Android API 21+）：連線 / 訊息收發 / OkHttp WebSocket
- ✅ Design Tokens：Android Compose Color 物件（85 tokens）
- ✅ 範例 App 程式碼（iOS + Android）
- ✅ 完整 WebSocket 協議文檔（`shared/bridge-protocol.json`）
- ✅ Getting Started 教學（`docs/GETTING_STARTED.md`）

### 工具

- `dart run tool/gen_bridge_swift_tokens.dart` — 從 BridgeDS 自動生成 Swift tokens

### 同步來源

- `lib/services/mobile_bridge_client.dart` — Flutter client API
- `lib/services/desktop_bridge_gateway_protocol.dart` — 9 個訊息類型
- `lib/theme/bridge_design_system.dart` — 85 個 color tokens

### 已知限制

- iOS Swift 顏色只有 12 個核心 token（完整 85 個待 PR 補完）
- 沒有 React Native / Flutter plugin SDK（未來計劃）
- 沒有訊息加密（金鑰配對已完成）

## 0.9.0-beta (內部)

- 早期測試版本，僅內部使用
