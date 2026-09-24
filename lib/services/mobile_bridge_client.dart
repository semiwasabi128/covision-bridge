// mobile_bridge_client.dart
// 手機端 WebSocket client — 連接 Bridge Desktop Gateway。
// 負責：connect / hello 握手 / 自動重連 / 收發訊息 / 狀態廣播 / push 訊息接收
// Sprint 15a by 教練 Agent (CEO)
// Sprint 19a: 加 push 訊息接收 + sendTaskRun / sendTaskCancel

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'desktop_bridge_gateway_protocol.dart';

/// 連線狀態
enum BridgeConnectionState {
  disconnected,
  connecting,
  connected,
  handshaking,
  ready,
  error,
}

/// 連線狀態變化事件
class BridgeConnectionEvent {
  final BridgeConnectionState state;
  final String? message;

  const BridgeConnectionEvent(this.state, {this.message});
}

/// 桌面端 push 訊息（task 進度、完成通知等）
class BridgePushEvent {
  final DesktopBridgeGatewayMessageType type;
  final Map<String, dynamic> payload;

  const BridgePushEvent({required this.type, this.payload = const {}});

  String? get taskId => payload['taskId'] as String?;
  double? get progress => (payload['progress'] as num?)?.toDouble();
  String? get message => payload['message'] as String?;
  bool? get success => payload['success'] as bool?;
  String? get error => payload['error'] as String?;
  String? get reason => payload['reason'] as String?;
}

/// 手機端 Bridge Desktop WebSocket client。
///
/// **Singleton** — 連線生命週期跟 App 綁定，不跟畫面綁定。
/// 配對畫面只引用 instance，不 dispose 它。
///
/// 生命週期：
/// 1. connect() → connecting
/// 2. WebSocket 連上 → handshaking
/// 3. hello 握手成功 → ready
/// 4. 斷線 → disconnected → 自動重連（如果 enabled）
///
/// Sprint 19a: 加 [pushStream] — 桌面主動推播的 task 訊息透過此 stream 廣播。
/// UI 層 listen pushStream 即可收到任務進度/完成通知。
class MobileBridgeClient with ChangeNotifier {
  // Singleton — App 層級生命週期
  static final MobileBridgeClient instance = MobileBridgeClient._();
  MobileBridgeClient._();

  WebSocket? _socket;
  StreamSubscription? _socketSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  BridgeConnectionState _state = BridgeConnectionState.disconnected;
  String? _lastError;
  String? _connectedEndpoint;

  // 連線目標
  String? _host;
  int? _port;
  String? _pairingCode;

  // 重連
  bool _autoReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // --- Sprint 19a: push 訊息 stream ---
  final StreamController<BridgePushEvent> _pushController =
      StreamController<BridgePushEvent>.broadcast();

  /// 桌面主動推播訊息 stream。
  ///
  /// 收到 taskProgress / taskComplete / taskAwaitingConfirmation 時透過此 stream 廣播。
  /// UI 層用 `client.pushStream.listen((event) { ... })` 接收。
  Stream<BridgePushEvent> get pushStream => _pushController.stream;

  /// 目前連線狀態
  BridgeConnectionState get state => _state;
  String? get lastError => _lastError;
  String? get connectedEndpoint => _connectedEndpoint;
  bool get isConnected =>
      _state == BridgeConnectionState.ready ||
      _state == BridgeConnectionState.connected;

  /// 連線到指定桌面端。
  ///
  /// [host] 桌面端 LAN IP
  /// [port] Gateway port（通常 8787）
  /// [pairingCode] 配對碼（BRIDGE-XXXXXX）
  Future<bool> connect({
    required String host,
    required int port,
    required String pairingCode,
  }) async {
    _host = host;
    _port = port;
    _pairingCode = pairingCode;
    _autoReconnect = true;
    _reconnectAttempts = 0;

    return _doConnect();
  }

  Future<bool> _doConnect() async {
    if (_host == null || _port == null || _pairingCode == null) {
      _setError('連線參數不完整');
      return false;
    }

    final endpoint = 'ws://$_host:$_port/bridge';
    _setState(BridgeConnectionState.connecting, message: '連線中…');

    try {
      _socket = await WebSocket.connect(endpoint);
      _connectedEndpoint = endpoint;

      _setState(BridgeConnectionState.handshaking, message: '握手中…');

      // 發送 hello
      _socket!.add(jsonEncode(
        DesktopBridgeGatewayRequest(
          id: 'mobile-hello',
          type: DesktopBridgeGatewayMessageType.hello,
          payload: {'pairingCode': _pairingCode},
        ).toJson(),
      ));

      // 監聽回應
      _socketSub = _socket!.listen(
        _onMessage,
        onError: (e) => _onDisconnect('WebSocket error: $e'),
        onDone: () => _onDisconnect('連線已關閉'),
        cancelOnError: true,
      );

      _startHeartbeat();
      return true;
    } catch (e) {
      _setError('連線失敗：$e');
      _scheduleReconnect();
      return false;
    }
  }

  void _onMessage(dynamic data) {
    try {
      final decoded = jsonDecode(data as String);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String?;
      final ok = decoded['ok'] as bool?;
      final payload = decoded['payload'] is Map
          ? Map<String, dynamic>.from(decoded['payload'] as Map)
          : <String, dynamic>{};

      // --- 同步 response（hello / runtimeSnapshot / capabilityList / error）---
      if (type == 'hello' && ok == true) {
        // 握手成功
        _setState(BridgeConnectionState.ready,
            message: '已連線到 ${payload['desktopName'] ?? 'Bridge Desktop'}');
      } else if (type == 'hello' && ok == false) {
        // 配對碼錯誤
        _setError('配對碼錯誤：${decoded['error'] ?? 'unknown'}');
        _autoReconnect = false; // 配對碼錯不重連
        disconnect();
      } else if (type == 'runtimeSnapshot') {
        // 收到 runtime snapshot
        debugPrint('[MobileBridge] runtimeSnapshot: $payload');
      } else if (type == 'taskRun' && ok == true) {
        // taskRun 同步回應 — 任務已啟動，taskId 在 payload 裡
        debugPrint('[MobileBridge] task started: ${payload['taskId']}');
      } else if (type == 'taskCancel') {
        // taskCancel 同步回應
        debugPrint('[MobileBridge] task cancel: ${payload['taskId']} status=${payload['status']}');
      } else if (type == 'error') {
        _setError('Gateway 錯誤：${decoded['error'] ?? 'unknown'}');
      }

      // --- push 訊息（桌面主動推播）---
      // push 訊息沒有 requestId 和 ok 欄位，只有 type + payload
      if (type == 'taskProgress' ||
          type == 'taskComplete' ||
          type == 'taskAwaitingConfirmation') {
        final msgType = DesktopBridgeGatewayMessageType.values.firstWhere(
          (m) => m.name == type,
          orElse: () => DesktopBridgeGatewayMessageType.error,
        );
        _pushController.add(BridgePushEvent(
          type: msgType,
          payload: payload,
        ));
        debugPrint('[MobileBridge] push: $type taskId=${payload['taskId']}');
      }
    } catch (e) {
      debugPrint('[MobileBridge] 訊息解析失敗: $e');
    }
  }

  /// 發送 runtimeSnapshot 請求
  Future<void> requestRuntimeSnapshot() async {
    if (_socket == null || !isConnected) return;
    _socket!.add(jsonEncode(
      const DesktopBridgeGatewayRequest(
        id: 'mobile-runtime',
        type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
      ).toJson(),
    ));
  }

  /// 發送 capabilityList 請求
  Future<void> requestCapabilityList() async {
    if (_socket == null || !isConnected) return;
    _socket!.add(jsonEncode(
      const DesktopBridgeGatewayRequest(
        id: 'mobile-capabilities',
        type: DesktopBridgeGatewayMessageType.capabilityList,
      ).toJson(),
    ));
  }

  // --- Sprint 19a: 長任務 API ---

  /// 啟動一個長任務。
  ///
  /// [taskType] 任務類型，如 "browser.navigate"
  /// [payload] 任務參數（如 url, selector, value 等）
  ///
  /// 回傳 taskId（成功啟動）或 null（啟動失敗）。
  /// 任務進度/結果透過 [pushStream] 推播。
  Future<String?> sendTaskRun({
    required String taskType,
    Map<String, dynamic> payload = const {},
  }) async {
    if (_socket == null || !isConnected) return null;

    final requestId = 'task-${DateTime.now().millisecondsSinceEpoch}';
    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: requestId,
        type: DesktopBridgeGatewayMessageType.taskRun,
        payload: {
          'taskType': taskType,
          'payload': payload,
        },
      ).toJson(),
    ));

    // 同步回應會在 _onMessage 處理，taskId 從 response payload 取得
    // 但因為 _onMessage 是 callback 模式，這裡不等待。
    // UI 層應該 listen pushStream 等待 taskProgress/taskComplete。
    // v1 簡化：回傳一個本地生成的暫時 ID，真實 taskId 從 push 訊息取得
    return requestId;
  }

  /// 取消進行中的任務。
  Future<bool> sendTaskCancel(String taskId) async {
    if (_socket == null || !isConnected) return false;

    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: 'cancel-${DateTime.now().millisecondsSinceEpoch}',
        type: DesktopBridgeGatewayMessageType.taskCancel,
        payload: {'taskId': taskId},
      ).toJson(),
    ));
    return true;
  }

  /// 主動斷線
  void disconnect() {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socketSub?.cancel();
    _socket?.close();
    _socket = null;
    _setState(BridgeConnectionState.disconnected);
  }

  void _onDisconnect(String reason) {
    _heartbeatTimer?.cancel();
    _socket = null;
    _socketSub = null;

    if (_autoReconnect) {
      _setState(BridgeConnectionState.disconnected, message: reason);
      _scheduleReconnect();
    } else {
      _setState(BridgeConnectionState.disconnected, message: reason);
    }
  }

  void _scheduleReconnect() {
    if (!_autoReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setError('已達最大重連次數（$_maxReconnectAttempts），請手動重連');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    debugPrint('[MobileBridge] ${delay.inSeconds}s 後重連（第 $_reconnectAttempts 次）');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_autoReconnect && _host != null) {
        _doConnect();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_socket != null && _socket!.readyState == WebSocket.open) {
        // 發一個 runtimeSnapshot 當 heartbeat
        requestRuntimeSnapshot();
      }
    });
  }

  void _setState(BridgeConnectionState state, {String? message}) {
    _state = state;
    if (message != null) _lastError = message;
    debugPrint('[MobileBridge] state=$state, msg=$message');
    notifyListeners();
  }

  void _setError(String error) {
    _lastError = error;
    _setState(BridgeConnectionState.error, message: error);
  }

  /// 解析 QR payload: bridge://pair?host=192.168.1.5&port=8787&code=BRIDGE-123456
  static ({String host, int port, String code})? parseQrPayload(String payload) {
    if (!payload.startsWith('bridge://pair?')) return null;
    final query = payload.substring('bridge://pair?'.length);
    final params = <String, String>{};
    for (final pair in query.split('&')) {
      final kv = pair.split('=');
      if (kv.length == 2) params[kv[0]] = kv[1];
    }
    final host = params['host'];
    final port = int.tryParse(params['port'] ?? '');
    final code = params['code'];
    if (host == null || port == null || code == null) return null;
    return (host: host, port: port, code: code);
  }
}
