/**
 * Bridge Controller - 外部自動化測試橋接器
 * 允許 OpenClaw CEO 透過 postMessage 操作 Flutter Web App
 * 
 * 使用方法：
 *   window.postMessage({ type: 'bridge', action: 'fillSettings', ... }, '*')
 */

(function() {
  'use strict';

  // 全局回調（Flutter 會覆寫這個）
  window.__bridgeCallbacks = {};

  // 儲存待處理的命令（Flutter 還沒 ready 時先排隊）
  window.__bridgeQueue = [];

  // 標記 Flutter 是否已 ready
  window.__bridgeFlutterReady = false;

  /**
   * 註冊 Flutter 端回調
   * Flutter 啟動後會呼叫這個
   */
  window.__bridgeRegister = function(callbacks) {
    window.__bridgeFlutterReady = true;
    window.__bridgeCallbacks = callbacks;
    console.log('[BridgeController] Flutter ready, callbacks registered');
    
    // 處理排隊中的命令
    while (window.__bridgeQueue.length > 0) {
      const cmd = window.__bridgeQueue.shift();
      _dispatchToFlutter(cmd);
    }
  };

  /**
   * 發送命令到 Flutter
   */
  function _dispatchToFlutter(data) {
    if (!window.__bridgeFlutterReady || !window.__bridgeCallbacks[data.action]) {
      console.warn('[BridgeController] Action not supported or Flutter not ready:', data.action);
      return;
    }
    try {
      const result = window.__bridgeCallbacks[data.action](data.payload || {});
      // 回傳結果給 sender
      if (data._replyId) {
        window.postMessage({
          type: 'bridge-reply',
          replyId: data._replyId,
          result: result
        }, '*');
      }
    } catch (e) {
      console.error('[BridgeController] Error dispatching action:', e);
      if (data._replyId) {
        window.postMessage({
          type: 'bridge-reply',
          replyId: data._replyId,
          error: e.message
        }, '*');
      }
    }
  }

  /**
   * 監聽來自外部的 postMessage
   */
  window.addEventListener('message', function(event) {
    const data = event.data;
    
    // 只處理 bridge 類型的訊息
    if (!data || data.type !== 'bridge') return;
    
    console.log('[BridgeController] Received action:', data.action, data.payload);
    
    if (!window.__bridgeFlutterReady) {
      // Flutter 還沒 ready，先排隊
      window.__bridgeQueue.push(data);
      console.log('[BridgeController] Queued (Flutter not ready yet)');
    } else {
      _dispatchToFlutter(data);
    }
  });

  /**
   * 輔助：取得目前 App 狀態（供外部查詢）
   */
  window.__bridgeGetState = function() {
    return {
      flutterReady: window.__bridgeFlutterReady,
      supportedActions: Object.keys(window.__bridgeCallbacks),
      queuedCommands: window.__bridgeQueue.length
    };
  };

  console.log('[BridgeController] Initialized. Waiting for Flutter...');
})();
