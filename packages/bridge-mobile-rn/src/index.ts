// Bridge Mobile SDK — TypeScript 入口
// 從 Flutter `lib/services/mobile_bridge_client.dart` 同步
// 為 React Native + Web 提供一致的 API

// ──────────────────────────────────────────────
// Design Tokens (85 個 UIColor)
// 從 lib/theme/bridge_design_system.dart 自動生成
// 用法：`backgroundColor: BridgeTokens.canvas`
// ──────────────────────────────────────────────
export {
  BridgeTokens,
  type BridgeTokenName,
  bridgeToken,
  // ── Style helpers ──
  bridgeStyle,
  bridgeColors,
} from './tokens';

// ──────────────────────────────────────────────
// Bridge Client (WebSocket)
// ──────────────────────────────────────────────
export {
  BridgeClient,
  ConnectionState,
  type BridgeClientOptions,
  type BridgeMessage,
  type TaskPayload,
} from './BridgeClient';

// ──────────────────────────────────────────────
// React Hook (optional)
// ──────────────────────────────────────────────
export { useBridgeClient, useBridgeTokens } from './hooks';

// ──────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────
export const BRIDGE_PROTOCOL_VERSION = '1.0.0';
export const BRIDGE_DEFAULT_PORT = 9123;
export const BRIDGE_HEARTBEAT_INTERVAL_MS = 30000;
export const BRIDGE_RECONNECT_INTERVAL_MS = 3000;
