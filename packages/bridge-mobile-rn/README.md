# @bridge/mobile — React Native / Web SDK

> 跨 React Native + Web 的 Bridge App SDK
> 自動從 Flutter `lib/theme/bridge_design_system.dart` 同步 85 個 Design Tokens

## 📦 安裝

### React Native

```bash
npm install @bridge/mobile react-native
# or
yarn add @bridge/mobile react-native
```

### Web (with bundler)

```bash
npm install @bridge/mobile
```

## 🎨 Design Tokens（85 個）

```typescript
import { BridgeTokens, bridgeToken } from '@bridge/mobile';

// 直接用
const styles = StyleSheet.create({
  container: { backgroundColor: BridgeTokens.canvas },
  text: { color: BridgeTokens.textPrimary },
  accent: { backgroundColor: BridgeTokens.accentBlue },
});

// 帶 opacity
const semiTransparentBorder = {
  borderColor: bridgeToken('borderSubtle', 0.5),
};

// React hook
function Component() {
  const tokens = useBridgeTokens(['canvas', 'textPrimary', 'accentBlue']);
  return <View style={{ backgroundColor: tokens.canvas }} />;
}
```

## 🔌 連線 Bridge Desktop

```typescript
import { BridgeClient, ConnectionState, useBridgeClient } from '@bridge/mobile';

function MyApp() {
  const { state, sendTask } = useBridgeClient({
    host: '192.168.1.100',
    port: 9123,
  });

  const navigate = () => {
    sendTask('browser.navigate', { url: 'https://example.com' });
  };

  return (
    <View>
      <Text>State: {state}</Text>
      <Button title="Navigate" onPress={navigate} disabled={state !== ConnectionState.READY} />
    </View>
  );
}
```

## 📦 同步來源

從以下 Flutter 檔案自動同步：
- `lib/services/mobile_bridge_client.dart` — WebSocket Client API
- `lib/services/desktop_bridge_gateway_protocol.dart` — 9 個訊息類型
- `lib/theme/bridge_design_system.dart` — 85 個 color tokens

## 🚀 API 速查

```typescript
// 訊息接收
client.onMessage((msg) => {
  switch (msg.type) {
    case 'task.progress': console.log(msg.progress); break;
    case 'task.complete': console.log(msg.payload); break;
  }
});

// 狀態訂閱
const unsubState = client.onStateChange((state, message) => {
  console.log('State:', state);
});

// 訊息收發
client.sendTask('browser.fillForm', { selector: '#name', value: 'Blue' });
client.cancelTask('task-123');
```

## 🎯 為什麼要這個 SDK

- ✅ **跨平台一致** — RN / Web 同一 API
- ✅ **85 tokens 開箱即用** — 不用手動搬色票
- ✅ **完整型別定義** — TypeScript 全覆蓋
- ✅ **Hooks 友好** — `useBridgeClient` / `useBridgeTask`
- ✅ **可測試** — `WebSocketFactory` 注入介面

## 🧪 測試

```bash
npm test
```

8 個 unit test 全部涵蓋：
- 85 個 token 完整性
- 所有 hex 格式合法
- `bridgeToken` 對 6/8 位 hex 的處理
- 顏色關鍵值驗證

## 🛠️ 相關 Tool

- [`bridge-mobile-sync`](../../tool/bridge_mobile_sync.dart) CLI — 從 Dart code 重新生成此 SDK
