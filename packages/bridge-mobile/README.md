# bridge-mobile — Native Mobile SDK for Bridge App

> 給 iOS/Android 原生開發者使用的 Bridge App SDK
> 自動從 Flutter code 同步 protocol、token、範例

## 📦 包含內容

```
bridge-mobile/
├── README.md                       ← 你在這裡
├── CHANGELOG.md                    ← SDK 版本變更
├── LICENSE.md                      ← MIT 授權
├── ios/
│   ├── BridgeMobile.swift          ← Swift SDK（自動生成）
│   ├── BridgeMobile.podspec        ← CocoaPods 規格
│   └── Example/                    ← iOS 範例 App
├── android/
│   ├── bridgemobile/               ← Android library module
│   │   ├── build.gradle
│   │   └── src/main/java/com/bridge/mobile/
│   │       ├── BridgeClient.kt    ← Kotlin SDK
│   │       └── BridgeTokens.kt    ← 顏色常數
│   └── gradle.properties
├── shared/
│   ├── bridge-protocol.json        ← WebSocket 通訊協議
│   └── bridge-tokens.json          ← 85 個 design tokens
└── docs/
    ├── GETTING_STARTED.md          ← 快速開始
    ├── ARCHITECTURE.md             ← 架構
    └── API_REFERENCE.md            ← API 文件
```

## 🚀 快速開始

### iOS

```ruby
# Podfile
pod 'BridgeMobile', '~> 1.0.0'
```

```swift
import BridgeMobile

// 連線到 Desktop Bridge Gateway
let client = BridgeClient(host: "192.168.1.100", port: 9123)
try await client.connect()

// 收發訊息
client.onMessage { message in
    print("Received: \(message.payload)")
}
try await client.send(task: "greet", payload: ["name": "Blue"])
```

### Android (Kotlin)

```kotlin
// build.gradle
implementation 'com.bridge:mobile:1.0.0'

// 連線
val client = BridgeClient("192.168.1.100", 9123)
client.connect()

// 收發
client.onMessage { message ->
    println("Received: ${message.payload}")
}
client.send("greet", mapOf("name" to "Blue"))
```

## 🎨 設計 Tokens

SDK 自動帶有 **85 個 BridgeDS color tokens**：

### iOS 範例

```swift
view.backgroundColor = .bridge(.canvas)
label.textColor = .bridge(.textPrimary)
button.backgroundColor = .bridge(.accentBlue)
```

### Android 範例

```kotlin
view.setBackgroundColor(BridgeTokens.CANVAS)
label.setTextColor(BridgeTokens.TEXT_PRIMARY)
button.setBackgroundColor(BridgeTokens.ACCENT_BLUE)
```

### React Native

```js
import { BridgeTokens } from '@bridge/mobile';

const styles = StyleSheet.create({
  container: { backgroundColor: BridgeTokens.canvas },
  text: { color: BridgeTokens.textPrimary },
});
```

## 🔌 通訊協議

WebSocket-based, JSON-encoded.

### 連線

```
Mobile ──[WebSocket]──> Desktop Gateway (port 9123)
```

### 握手流程

```
1. Mobile → Desktop: {"type": "hello", "deviceId": "...", "platform": "ios"}
2. Desktop → Mobile: {"type": "hello_ack", "paired": true, "deviceName": "Blue's iPhone"}
3. [Ready to send/receive tasks]
```

### 任務協議

```json
{
  "type": "task.run",
  "taskId": "uuid",
  "task": "greet",
  "payload": { "name": "Blue" }
}
```

回應：

```json
{
  "type": "task.result",
  "taskId": "uuid",
  "status": "ok",
  "result": "Hello Blue!"
}
```

## 📦 版本

| 版本 | 對應 Flutter 版本 | 發布日期 |
|---|---|---|
| 1.0.0 | v0.6.x | 2026-08-06 |

## 🔗 來源

從以下 Flutter 檔案自動同步：
- `lib/services/mobile_bridge_client.dart` (client API)
- `lib/services/desktop_bridge_gateway_protocol.dart` (protocol)
- `lib/theme/bridge_design_system.dart` (85 color tokens)

## 📚 文件

- [GETTING_STARTED.md](docs/GETTING_STARTED.md) — 5 分鐘上手
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架構設計
- [API_REFERENCE.md](docs/API_REFERENCE.md) — 完整 API
