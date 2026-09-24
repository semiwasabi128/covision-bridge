# Getting Started with BridgeMobile

> 5 分鐘上手 Bridge iOS / Android SDK

## 📋 前提

- macOS / Windows / Linux 任一
- iOS 13+ / Android API 21+
- 桌面 Bridge App 在跑（且啟動 mobile gateway）

## 📦 安裝

### iOS (CocoaPods)

```ruby
# 在 Podfile 加入
pod 'BridgeMobile', '~> 1.0.0'
```

```bash
pod install
```

### iOS (Swift Package Manager)

```swift
// 在 Package.swift
dependencies: [
    .package(url: "https://github.com/bridge-app/bridge-mobile.git", from: "1.0.0")
]
```

### Android

```gradle
// 在 app/build.gradle
dependencies {
    implementation 'com.bridge:mobile:1.0.0'
}
```

## 🚀 基本連線

### iOS

```swift
import BridgeMobile

@MainActor
class MyViewController: UIViewController {
    private var client: BridgeClient?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupClient()
    }

    func setupClient() {
        client = BridgeClient(host: "192.168.1.100", port: 9123)

        client?.onStateChange { event in
            print("Bridge state: \(event.state.rawValue)")
        }

        client?.onMessage { message in
            print("Bridge: \(message.type) — \(message.payload)")
        }

        Task {
            do {
                try await client?.connect()
            } catch {
                print("Connection failed: \(error)")
            }
        }
    }
}
```

### Android (Kotlin)

```kotlin
import com.bridge.mobile.BridgeClient

class MainActivity : AppCompatActivity() {
    private lateinit var client: BridgeClient

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupClient()
    }

    private fun setupClient() {
        client = BridgeClient("192.168.1.100", 9123)

        client.onStateChange { event ->
            Log.d("Bridge", "State: ${event.state}")
        }

        client.onMessage { message ->
            Log.d("Bridge", "${message.type}: ${message.payload}")
        }

        lifecycleScope.launch {
            try {
                client.connect()
            } catch (e: Exception) {
                Log.e("Bridge", "Connect failed", e)
            }
        }
    }
}
```

## 🎨 用 Design Tokens

### iOS

```swift
view.backgroundColor = .bridge(.canvas)
label.textColor = .bridge(.textPrimary)
button.backgroundColor = .bridge(.accentBlue)
```

### Android

```kotlin
view.setBackgroundColor(BridgeTokens.CANVAS)
label.setTextColor(BridgeTokens.TEXT_PRIMARY)
button.setBackgroundColor(BridgeTokens.ACCENT_BLUE)
```

## 🔥 跑任務

### 瀏覽器自動化

```swift
Task {
    try await client?.sendTask(
        taskType: "browser.navigate",
        payload: ["url": "https://example.com"]
    )
}
```

```kotlin
client.sendTask(
    taskType = "browser.navigate",
    payload = mapOf("url" to "https://example.com")
)
```

### 收任務結果

```swift
client?.onMessage { message in
    switch message.type {
    case "task.progress":
        let progress = message.payload["progress"] as? Double ?? 0.0
        updateProgress(progress)
    case "task.complete":
        let success = message.payload["success"] as? Bool ?? false
        showResult(success: success)
    default:
        break
    }
}
```

## ❌ 取消任務

```swift
try await client?.cancelTask(taskId: "abc-123")
```

```kotlin
client.cancelTask("abc-123")
```

## 🔌 完整協議

見 `shared/bridge-protocol.json`。

## 🚧 故障排除

### 連不上

**Q**: `WebSocket failed`
**A**: 確認桌面 Bridge App 在跑，且 IP / port 對。

### 手機找不到桌面

**Q**: QR 掃不到
**A**: 確認手機跟桌面在同一 WiFi。

### 收到 hello_ack 但 state 沒變 ready

**A**: 確認 desktop 有配對你的 device（手機 Bridge App → 配對畫面 → 確認）。
