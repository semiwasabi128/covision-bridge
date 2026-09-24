// Bridge WebSocket Client
// 從 lib/services/mobile_bridge_client.dart 同步
// 為 React Native + Web 提供一致的 API

export enum ConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  HANDSHAKING = 'handshaking',
  READY = 'ready',
  ERROR = 'error',
}

export type TaskPayload = Record<string, unknown>;

export interface BridgeClientOptions {
  /** Bridge Desktop Gateway IP（區網） */
  host: string;
  /** Gateway port (預設 9123) */
  port?: number;
  /** 重連間隔（毫秒） */
  reconnectIntervalMs?: number;
  /** 心跳間隔（毫秒） */
  heartbeatIntervalMs?: number;
  /** 自動重連 (預設 true) */
  autoReconnect?: boolean;
  /** 自訂 deviceId */
  deviceId?: string;
  /** 自訂 platform（預設 'rn'） */
  platform?: 'rn' | 'web' | 'node';
  /** appVersion (預設 '1.0.0') */
  appVersion?: string;
  /** 使用 react-native 的 WebSocket (預設 false = browser) */
  useReactNativeWebSocket?: boolean;
}

export interface BridgeMessage {
  type: string;
  taskId?: string;
  taskType?: string;
  payload?: TaskPayload;
  success?: boolean;
  progress?: number;
  message?: string;
}

type MessageHandler = (message: BridgeMessage) => void;
type StateHandler = (state: ConnectionState, message?: string) => void;

/**
 * WebSocketFactory 介面
 * - React Native 需要 import WebSocket from 'react-native' 或 'global'
 * - Browser 使用 globalThis.WebSocket
 * - 可注入自訂實作（mock / test）
 */
type WebSocketFactory = () => WebSocketLike;

export interface WebSocketLike {
  readyState: number;
  onopen: ((ev: unknown) => void) | null;
  onclose: ((ev: { code: number; reason: string }) => void) | null;
  onerror: ((ev: unknown) => void) | null;
  onmessage: ((ev: { data: string }) => void) | null;
  send(data: string): void;
  close(code?: number, reason?: string): void;
}

export class BridgeClient {
  readonly host: string;
  readonly port: number;
  readonly options: Required<Omit<BridgeClientOptions, 'host'>>;

  state: ConnectionState = ConnectionState.DISCONNECTED;
  private ws: WebSocketLike | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private readonly messageHandlers = new Set<MessageHandler>();
  private readonly stateHandlers = new Set<StateHandler>();
  private readonly wsFactory: WebSocketFactory;

  constructor(opts: BridgeClientOptions, wsFactory?: WebSocketFactory) {
    this.host = opts.host;
    this.port = opts.port ?? 9123;
    this.options = {
      port: this.port,
      reconnectIntervalMs: opts.reconnectIntervalMs ?? 3000,
      heartbeatIntervalMs: opts.heartbeatIntervalMs ?? 30000,
      autoReconnect: opts.autoReconnect ?? true,
      deviceId: opts.deviceId ?? crypto.randomUUID?.() ?? `rn-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      platform: opts.platform ?? 'rn',
      appVersion: opts.appVersion ?? '1.0.0',
      useReactNativeWebSocket: opts.useReactNativeWebSocket ?? true,
    };
    this.wsFactory = wsFactory ?? this.defaultWebSocketFactory();
  }

  private defaultWebSocketFactory(): WebSocketFactory {
    return () => {
      const url = `ws://${this.host}:${this.port}`;
      if (this.options.useReactNativeWebSocket) {
        // React Native: 透過 require 取得 WebSocket
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const RNWS = require('react-native').WebSocket ?? globalThis.WebSocket;
        return new RNWS(url) as WebSocketLike;
      }
      return new globalThis.WebSocket(url);
    };
  }

  // ─────────────────────────────────────────────
  // 生命週期
  // ─────────────────────────────────────────────

  async connect(): Promise<void> {
    if (this.state === ConnectionState.CONNECTING ||
        this.state === ConnectionState.CONNECTED ||
        this.state === ConnectionState.HANDSHAKING ||
        this.state === ConnectionState.READY) {
      return;
    }
    this.updateState(ConnectionState.CONNECTING);
    this.ws = this.wsFactory();
    this.attachHandlers();

    return new Promise((resolve, reject) => {
      const onFirstOpen = () => {
        this.ws!.onopen = null;
        this.updateState(ConnectionState.CONNECTED);
        this.sendHello();
        this.updateState(ConnectionState.HANDSHAKING);
        this.startHeartbeat();
        resolve();
      };
      const onFirstError = (err: unknown) => {
        this.ws!.onerror = null;
        this.updateState(ConnectionState.ERROR, String(err));
        reject(err);
      };
      this.ws.onopen = onFirstOpen;
      this.ws.onerror = onFirstError;
    });
  }

  disconnect(): void {
    this.clearReconnect();
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close(1000, 'client closing');
      this.ws = null;
    }
    this.updateState(ConnectionState.DISCONNECTED);
  }

  // ─────────────────────────────────────────────
  // 訊息收發
  // ─────────────────────────────────────────────

  private sendHello(): void {
    this.send({
      type: 'hello',
      deviceId: this.options.deviceId,
      platform: this.options.platform,
      appVersion: this.options.appVersion,
    });
  }

  sendTask(
    taskType: string,
    payload: TaskPayload,
    taskId?: string,
  ): string {
    const id = taskId ?? crypto.randomUUID?.() ?? `task-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    this.send({
      type: 'task.run',
      taskId: id,
      taskType,
      payload,
    });
    return id;
  }

  cancelTask(taskId: string): void {
    this.send({ type: 'task.cancel', taskId });
  }

  private send(message: Record<string, unknown>): void {
    if (!this.ws || this.ws.readyState !== 1 /* OPEN */) {
      throw new Error('WebSocket not connected');
    }
    this.ws.send(JSON.stringify(message));
  }

  // ─────────────────────────────────────────────
  // WebSocket 事件處理
  // ─────────────────────────────────────────────

  private attachHandlers(): void {
    const ws = this.ws!;
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data) as Record<string, unknown>;
        const message: BridgeMessage = {
          type: data['type'] as string,
          taskId: data['taskId'] as string | undefined,
          taskType: data['taskType'] as string | undefined,
          payload: (data['payload'] as TaskPayload) ?? {},
          success: data['success'] as boolean | undefined,
          progress: data['progress'] as number | undefined,
          message: data['message'] as string | undefined,
        };
        this.fireMessage(message);

        if (message.type === 'hello_ack') {
          this.updateState(ConnectionState.READY);
        }
      } catch (err) {
        this.updateState(ConnectionState.ERROR, `Parse error: ${String(err)}`);
      }
    };

    ws.onclose = (ev) => {
      this.stopHeartbeat();
      if (ev.code === 1000) {
        this.updateState(ConnectionState.DISCONNECTED);
      } else {
        this.updateState(ConnectionState.ERROR, `Closed: ${ev.code}`);
        this.scheduleReconnect();
      }
    };

    ws.onerror = () => {
      this.updateState(ConnectionState.ERROR, 'WebSocket error');
    };
  }

  private scheduleReconnect(): void {
    if (!this.options.autoReconnect) return;
    this.clearReconnect();
    this.reconnectTimer = setTimeout(() => {
      this.connect().catch(() => {});
    }, this.options.reconnectIntervalMs);
  }

  private clearReconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      try {
        this.send({ type: 'heartbeat', timestamp: Date.now() });
      } catch {
        // 連線可能已斷
      }
    }, this.options.heartbeatIntervalMs);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  // ─────────────────────────────────────────────
  // 事件訂閱
  // ─────────────────────────────────────────────

  onMessage(handler: MessageHandler): () => void {
    this.messageHandlers.add(handler);
    return () => this.messageHandlers.delete(handler);
  }

  onStateChange(handler: StateHandler): () => void {
    this.stateHandlers.add(handler);
    return () => this.stateHandlers.delete(handler);
  }

  private fireMessage(message: BridgeMessage): void {
    for (const h of this.messageHandlers) {
      try {
        h(message);
      } catch {
        // 不讓單一 handler 影響其他
      }
    }
  }

  private updateState(state: ConnectionState, message?: string): void {
    this.state = state;
    for (const h of this.stateHandlers) {
      try {
        h(state, message);
      } catch {
        // 不讓單一 handler 影響其他
      }
    }
  }
}
