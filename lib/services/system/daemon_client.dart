// daemon_client.dart
// P5: App 端 WebSocket client — 連接 daemon，接收即時排程觸發事件
//
// 功能:
// - 連線到 ws://127.0.0.1:18472
// - 接收 daemon 推送的 schedule_fired 事件
// - 連線斷開時自動重連（5秒間隔）
// - 提供 Stream 給 UI 訂閱觸發事件

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Daemon 推送的排程觸發事件
class ScheduleFireEvent {
  final String jobId;
  final String title;
  final String canvasId;
  final Map<String, dynamic> params;
  final DateTime firedAt;

  const ScheduleFireEvent({
    required this.jobId,
    required this.title,
    required this.canvasId,
    required this.params,
    required this.firedAt,
  });

  factory ScheduleFireEvent.fromJson(Map<String, dynamic> json) {
    return ScheduleFireEvent(
      jobId: json['jobId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      canvasId: json['canvasId'] as String? ?? 'default',
      params: (json['params'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? const {},
      firedAt: DateTime.tryParse(json['firedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Daemon 連線狀態
enum DaemonConnectionState { disconnected, connecting, connected }

/// Daemon WebSocket client
class DaemonClient {
  static final DaemonClient _instance = DaemonClient._internal();
  factory DaemonClient() => _instance;
  DaemonClient._internal();

  static const int defaultPort = 18472;
  static const Duration reconnectInterval = Duration(seconds: 5);

  final int port = defaultPort;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _stateController = StreamController<DaemonConnectionState>.broadcast();
  final _eventController = StreamController<ScheduleFireEvent>.broadcast();

  /// Daemon 連線狀態 stream
  Stream<DaemonConnectionState> get stateStream => _stateController.stream;

  /// 排程觸發事件 stream
  Stream<ScheduleFireEvent> get eventStream => _eventController.stream;

  /// 目前是否已連線
  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

  // P5+: 供 UI 查詢的狀態
  int _jobsCount = 0;
  DateTime? _lastFireTime;
  String? _lastFireTitle;

  int get jobsCount => _jobsCount;
  DateTime? get lastFireTime => _lastFireTime;
  String? get lastFireTitle => _lastFireTitle;

  /// 啟動 client — 自動連線 + 斷線重連
  void start() {
    _disposed = false;
    _connect();
  }

  /// 連線到 daemon
  Future<void> _connect() async {
    if (_disposed) return;

    _stateController.add(DaemonConnectionState.connecting);
    debugPrint('[DaemonClient] 連線中... ws://127.0.0.1:$port');

    try {
      _socket = await WebSocket.connect('ws://127.0.0.1:$port');
      _stateController.add(DaemonConnectionState.connected);
      debugPrint('[DaemonClient] 已連線');

      _socket!.listen(
        (data) {
          _handleMessage(data);
        },
        onDone: () {
          debugPrint('[DaemonClient] 連線斷開');
          _socket = null;
          _stateController.add(DaemonConnectionState.disconnected);
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint('[DaemonClient] 連線錯誤: $e');
          _socket = null;
          _stateController.add(DaemonConnectionState.disconnected);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[DaemonClient] 連線失敗: $e');
      _stateController.add(DaemonConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// 排程重連
  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectInterval, _connect);
  }

  /// 處理 daemon 推送的訊息
  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'schedule_fired':
          final event = ScheduleFireEvent.fromJson(json);
          _lastFireTime = event.firedAt;
          _lastFireTitle = event.title;
          debugPrint('[DaemonClient] 收到排程觸發: ${event.title} (${event.jobId})');
          _eventController.add(event);
          break;

        case 'daemon_status':
          _jobsCount = json['jobsCount'] as int? ?? 0;
          final status = json['status'] as String? ?? 'unknown';
          debugPrint('[DaemonClient] Daemon 狀態: $status, $_jobsCount 個排程');
          break;

        default:
          debugPrint('[DaemonClient] 未知事件類型: $type');
      }
    } catch (e) {
      debugPrint('[DaemonClient] 解析訊息失敗: $e');
    }
  }

  /// 釋放資源
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _socket?.close();
    _socket = null;
    await _stateController.close();
    await _eventController.close();
  }
}
