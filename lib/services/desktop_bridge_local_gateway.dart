import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'desktop_bridge_gateway_protocol.dart';
import 'desktop_bridge_pairing_contract.dart';

typedef DesktopBridgeRuntimePayloadProvider = Map<String, dynamic> Function();
typedef DesktopBridgeGatewayLifecycleListener = void Function();
typedef DesktopBridgeGatewayRequestListener =
    void Function(DesktopBridgeGatewayRequest request);

class DesktopBridgeLocalGatewayConfig {
  final String host;
  final int port;
  final String path;

  const DesktopBridgeLocalGatewayConfig({
    this.host = '0.0.0.0', // Sprint 15a: 綁 0.0.0.0 讓手機可以從 LAN 連入
    this.port = 8790,
    this.path = '/bridge',
  });

  Uri endpointFor(int boundPort) {
    return Uri(scheme: 'ws', host: host, port: boundPort, path: path);
  }
}

/// 已連線的 WebSocket client（手機端）。
///
/// Sprint 19a: Gateway 需要追蹤已連線的 socket 才能主動 push 訊息。
/// 每個 socket 代表一台已配對的手機。
class _ConnectedClient {
  final WebSocket socket;
  final DateTime connectedAt;

  _ConnectedClient(this.socket, this.connectedAt);

  /// 發送 push 訊息。如果 socket 已關閉則安全跳過。
  void sendPush(DesktopBridgeGatewayPush push) {
    try {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode(push.toJson()));
      }
    } catch (_) {
      // socket 已關閉，安全跳過
    }
  }
}

/// Gateway 執行 handle。持有 HttpServer 和已連線 client 列表。
///
/// Sprint 19a 擴充：
/// - [pushToAll] — 向所有已連線手機 push 訊息
/// - [pushMessage] — 向特定 client push（透過 BridgePushMessage 介面）
class DesktopBridgeLocalGatewayHandle {
  final HttpServer _server;
  final Uri endpoint;

  /// 已連線的 client 列表。push 訊息時遍歷這個列表。
  final List<_ConnectedClient> _clients = [];

  DesktopBridgeLocalGatewayHandle._({
    required HttpServer server,
    required this.endpoint,
  }) : _server = server;

  int get port => _server.port;

  /// 目前已連線的 client 數量
  int get clientCount => _clients.length;

  /// 向所有已連線手機推播訊息。
  ///
  /// 用於 task 進度更新、任務完成通知等。
  void pushToAll(DesktopBridgeGatewayPush push) {
    for (final client in _clients) {
      client.sendPush(push);
    }
  }

  /// 向第一個已連線手機推播（v1 只支援單手機）。
  void pushToFirst(DesktopBridgeGatewayPush push) {
    if (_clients.isNotEmpty) {
      _clients.first.sendPush(push);
    }
  }

  /// 內部：新增已連線 client
  void _addClient(WebSocket socket) {
    _clients.add(_ConnectedClient(socket, DateTime.now()));
  }

  /// 內部：移除已斷線 client
  void _removeClient(WebSocket socket) {
    _clients.removeWhere((c) => c.socket == socket);
  }

  Future<void> close() => _server.close(force: true);
}

/// 連線層配對閘門——WebSocket 升級後、驗碼前擋下一切請求。
/// [小葵 2026-09-24 開源安全域] 未配對的 socket 不能跳過 hello 直送 taskRun。
class _PairingGate {
  final String _expectedCode;
  bool admitted = false;

  _PairingGate(this._expectedCode);

  /// 回 true 表示這則訊息是帶正確配對碼的 hello（通過閘門）。
  bool tryAdmit(Object? raw) {
    if (admitted) return true;
    if (raw is! String) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final typeName = decoded['type'];
      if (typeName != 'hello') return false;
      final payload = decoded['payload'];
      if (payload is! Map) return false;
      if (payload['pairingCode'] == _expectedCode) {
        admitted = true;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// 桌面端 WebSocket Gateway Server。
///
/// Sprint 14: 基礎同步 request-response（hello / runtimeSnapshot / capabilityList）
/// Sprint 19a: 擴充長任務支援
/// - 收到 `taskRun` → 委派給 [GatewayTaskHandler] 非同步執行
/// - 收到 `taskCancel` → 委派給 [GatewayTaskHandler] 取消
/// - 任務進度/完成透過 push 推播回手機
/// - `taskProgress` / `taskComplete` / `taskAwaitingConfirmation` 是 push-only，
///   手機不應發送，收到時回 error
class DesktopBridgeLocalGateway {
  final DesktopBridgeGatewayProtocol protocol;

  /// 長任務處理器（S19b BrowserAutomationService / S19c TaskQueue 注入）。
  /// null 時 taskRun/taskCancel 回 error。
  final GatewayTaskHandler? taskHandler;

  const DesktopBridgeLocalGateway({
    this.protocol = const DesktopBridgeGatewayProtocol(),
    this.taskHandler,
  });

  Future<DesktopBridgeLocalGatewayHandle> start({
    required DesktopBridgePairingContract pairingContract,
    required DesktopBridgeRuntimePayloadProvider runtimePayloadProvider,
    DesktopBridgeLocalGatewayConfig config =
        const DesktopBridgeLocalGatewayConfig(),
    DesktopBridgeGatewayLifecycleListener? onClientConnected,
    DesktopBridgeGatewayLifecycleListener? onClientDisconnected,
    DesktopBridgeGatewayRequestListener? onRequest,
  }) async {
    final server = await HttpServer.bind(
      InternetAddress(config.host),
      config.port,
    );

    final handle = DesktopBridgeLocalGatewayHandle._(
      server: server,
      endpoint: config.endpointFor(server.port),
    );

    server.listen(
      (request) => _handleRequest(
        request,
        config: config,
        pairingContract: pairingContract,
        runtimePayloadProvider: runtimePayloadProvider,
        onClientConnected: onClientConnected,
        onClientDisconnected: onClientDisconnected,
        onRequest: onRequest,
        handle: handle,
      ),
    );

    return handle;
  }

  Future<void> _handleRequest(
    HttpRequest request, {
    required DesktopBridgeLocalGatewayConfig config,
    required DesktopBridgePairingContract pairingContract,
    required DesktopBridgeRuntimePayloadProvider runtimePayloadProvider,
    DesktopBridgeGatewayLifecycleListener? onClientConnected,
    DesktopBridgeGatewayLifecycleListener? onClientDisconnected,
    DesktopBridgeGatewayRequestListener? onRequest,
    required DesktopBridgeLocalGatewayHandle handle,
  }) async {
    if (request.uri.path != config.path) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    // [小葵 2026-09-24 開源安全域] 連線層配對閘門：
    // 舊版未配對 socket 可跳過 hello 直送 taskRun/runtimeSnapshot。
    // 現在：升級後第一訊息必須是帶正確 pairingCode 的 hello，5 秒內未過閘即斷線。
    final gate = _PairingGate(pairingContract.pairingCode);
    onClientConnected?.call();

    try {
      await for (final raw in socket) {
        if (!gate.admitted) {
          if (!gate.tryAdmit(raw)) {
            socket.add(jsonEncode(
              DesktopBridgeGatewayResponse(
                requestId: 'unknown',
                type: DesktopBridgeGatewayMessageType.error,
                ok: false,
                error: 'Pairing required: send hello with pairingCode first.',
              ).toJson(),
            ));
            await socket.close(); // 未配對即斷線——不讓未授權連線存在
            break;
          }
          // 過閘——此時才把 client 納入 push 廣播清單
          handle._addClient(socket);
        }
        final response = await _responseFor(
          raw,
          pairingContract: pairingContract,
          runtimePayloadProvider: runtimePayloadProvider,
          onRequest: onRequest,
          handle: handle,
          socket: socket,
        );
        if (response != null) {
          socket.add(jsonEncode(response.toJson()));
        }
      }
    } finally {
      handle._removeClient(socket);
      onClientDisconnected?.call();
    }
  }

  /// 處理收到的訊息。
  ///
  /// 回傳 [DesktopBridgeGatewayResponse] 表示需要回應手機（同步 request-response）。
  /// 回傳 null 表示不需要回應（push-only 或已透過 push 機制回應）。
  Future<DesktopBridgeGatewayResponse?> _responseFor(
    Object? raw, {
    required DesktopBridgePairingContract pairingContract,
    required DesktopBridgeRuntimePayloadProvider runtimePayloadProvider,
    DesktopBridgeGatewayRequestListener? onRequest,
    required DesktopBridgeLocalGatewayHandle handle,
    required WebSocket socket,
  }) async {
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! Map<String, dynamic>) {
        return const DesktopBridgeGatewayResponse(
          requestId: 'unknown',
          type: DesktopBridgeGatewayMessageType.error,
          ok: false,
          error: 'Gateway request must be a JSON object.',
        );
      }
      final request = DesktopBridgeGatewayRequest.fromJson(decoded);
      onRequest?.call(request);

      // --- Task 請求：由 Gateway 直接處理（需要 push 機制）---
      if (request.type == DesktopBridgeGatewayMessageType.taskRun) {
        return _handleTaskRun(request, handle);
      }
      if (request.type == DesktopBridgeGatewayMessageType.taskCancel) {
        return _handleTaskCancel(request);
      }

      // --- 同步請求：委派給 protocol ---
      return protocol.handleRequest(
        request: request,
        pairingContract: pairingContract,
        runtimePayload: runtimePayloadProvider(),
      );
    } on Object catch (error) {
      return DesktopBridgeGatewayResponse(
        requestId: 'unknown',
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'Gateway request parse failed: $error',
      );
    }
  }

  /// 處理 taskRun 請求。
  ///
  /// 立即回傳 taskId（成功啟動）或 error（啟動失敗），
  /// 任務在背景執行，進度/結果透過 push 推播。
  DesktopBridgeGatewayResponse _handleTaskRun(
    DesktopBridgeGatewayRequest request,
    DesktopBridgeLocalGatewayHandle handle,
  ) {
    final handler = taskHandler;
    if (handler == null) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'No task handler registered. Browser automation not available.',
      );
    }

    final taskType = request.payload['taskType'] as String? ?? 'unknown';
    final taskPayload = request.payload['payload'];
    final payload = taskPayload is Map<String, dynamic>
        ? taskPayload
        : <String, dynamic>{};

    try {
      // 先宣告 taskId 變數，讓 callback 可以引用
      late String taskId;
      taskId = handler.startTask(
        taskType: taskType,
        payload: payload,
        onProgress: (progress, message) {
          handle.pushToFirst(DesktopBridgeGatewayPush(
            type: DesktopBridgeGatewayMessageType.taskProgress,
            payload: {
              'taskId': taskId,
              'progress': progress,
              'message': message,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        },
        onComplete: (success, result, error) {
          handle.pushToFirst(DesktopBridgeGatewayPush(
            type: DesktopBridgeGatewayMessageType.taskComplete,
            payload: {
              'taskId': taskId,
              'success': success,
              'result': result,
              if (error != null) 'error': error,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        },
        onAwaitingConfirmation: (reason, context) {
          handle.pushToFirst(DesktopBridgeGatewayPush(
            type: DesktopBridgeGatewayMessageType.taskAwaitingConfirmation,
            payload: {
              'taskId': taskId,
              'reason': reason,
              'context': context,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        },
      );

      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.taskRun,
        ok: true,
        payload: {
          'taskId': taskId,
          'taskType': taskType,
          'status': 'started',
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'Failed to start task: $e',
      );
    }
  }

  /// 處理 taskCancel 請求。
  DesktopBridgeGatewayResponse _handleTaskCancel(
    DesktopBridgeGatewayRequest request,
  ) {
    final handler = taskHandler;
    if (handler == null) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'No task handler registered.',
      );
    }

    final taskId = request.payload['taskId'] as String? ?? '';
    final cancelled = handler.cancelTask(taskId);

    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.taskCancel,
      ok: cancelled,
      payload: {
        'taskId': taskId,
        'status': cancelled ? 'cancelled' : 'not_found',
      },
      error: cancelled ? null : 'Task not found or already completed.',
    );
  }
}
