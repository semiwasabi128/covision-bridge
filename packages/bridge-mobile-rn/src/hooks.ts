// React Hooks for @bridge/mobile
// 提供 React / React Native 友好的 hook

import { useEffect, useState, useRef } from 'react';
import { BridgeClient, ConnectionState } from './BridgeClient';
import { BridgeTokens, type BridgeTokenName } from './tokens';

/**
 * React hook：在 component lifecycle 內管理 BridgeClient
 *
 * @example
 * function MyComponent() {
 *   const { state, client, sendTask } = useBridgeClient({
 *     host: '192.168.1.100',
 *   });
 *   useEffect(() => {
 *     if (state === ConnectionState.READY) {
 *       sendTask('browser.navigate', { url: 'https://example.com' });
 *     }
 *   }, [state]);
 * }
 */
export function useBridgeClient(opts: {
  host: string;
  port?: number;
  enabled?: boolean;
}) {
  const enabled = opts.enabled ?? true;
  const clientRef = useRef<BridgeClient | null>(null);
  const [state, setState] = useState<ConnectionState>(ConnectionState.DISCONNECTED);
  const [error, setError] = useState<string | null>(null);

  if (!clientRef.current) {
    clientRef.current = new BridgeClient(opts);
  }

  useEffect(() => {
    if (!enabled) return;
    const client = clientRef.current!;
    const unsubState = client.onStateChange((s, msg) => {
      setState(s);
      setError(msg ?? null);
    });
    client.connect().catch((e) => setError(String(e)));
    return () => {
      unsubState();
      client.disconnect();
    };
  }, [enabled, opts.host, opts.port]);

  const sendTask = (taskType: string, payload: Record<string, unknown>, taskId?: string) => {
    return clientRef.current!.sendTask(taskType, payload, taskId);
  };

  return { state, error, client: clientRef.current, sendTask };
}

/**
 * 訂閱特定任務類型的結果
 */
export function useBridgeTask(
  client: BridgeClient | null,
  taskType: string,
  onResult?: (msg: import('./BridgeClient').BridgeMessage) => void,
) {
  const [lastMessage, setLastMessage] = useState<import('./BridgeClient').BridgeMessage | null>(null);
  useEffect(() => {
    if (!client) return;
    const unsub = client.onMessage((msg) => {
      if (msg.taskType === taskType || msg.type.endsWith(taskType)) {
        setLastMessage(msg);
        onResult?.(msg);
      }
    });
    return unsub;
  }, [client, taskType]);
  return lastMessage;
}

/**
 * 取得 token 列表 — 用於動態 StyleSheet
 */
export function useBridgeTokens(names: BridgeTokenName[]) {
  const [tokens] = useState(() => {
    const result: Partial<Record<BridgeTokenName, string>> = {};
    for (const name of names) {
      result[name] = BridgeTokens[name];
    }
    return result as Record<BridgeTokenName, string>;
  });
  return tokens;
}
