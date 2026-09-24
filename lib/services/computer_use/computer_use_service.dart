// 橋樑 Computer Use — Phase 0 安全機制 + 三件套 Dart 端
//

// Spec: docs/specs/2026-09-05-bridge-computer-use.md
// Channel: bridge.computer_use.macos.v1

// 安全鐵則：所有注入必經 TakeoverGate（Swift 端單點強制），
// Dart 端不重複實作判斷，只負責狀態顯示與 UX。
import 'dart:async';
import 'package:flutter/services.dart';

/// 接管狀態機（與 Swift 端 TakeoverState 對應）
enum TakeoverState { idle, armed, active, suspended }

class TakeoverStatus {
  final TakeoverState state;
  final String? taskId;
  final String? lastSuspendReason;
  final DateTime? lastHumanEventAt;

  const TakeoverStatus({
    required this.state,
    this.taskId,
    this.lastSuspendReason,
    this.lastHumanEventAt,
  });

  bool get canInject => state == TakeoverState.active;
}

class ComputerUseService {
  static const MethodChannel _ch =
      MethodChannel('bridge.computer_use.macos.v1');

  ComputerUseService._();
  static final ComputerUseService instance = ComputerUseService._();

  final _statusController = StreamController<TakeoverStatus>.broadcast();
  Stream<TakeoverStatus> get statusStream => _statusController.stream;

  Timer? _pollTimer;
  TakeoverStatus _last = const TakeoverStatus(state: TakeoverState.idle);
  TakeoverStatus get lastStatus => _last;

  /// 啟動狀態輪詢（狀態變化即時反映到 UI；Swift 端事件 tap 觸發 suspend）
  void startMonitoring({Duration interval = const Duration(seconds: 1)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => refresh());
    refresh();
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<TakeoverStatus> refresh() async {
    try {
      final raw = await _ch.invokeMethod('gate.state') as Map;
      final status = TakeoverStatus(
        state: _stateOf(raw['state'] as String? ?? 'idle'),
        taskId: raw['taskId'] as String?,
        lastSuspendReason: raw['lastSuspendReason'] as String?,
        lastHumanEventAt: raw['lastHumanEventAt'] == null ||
                raw['lastHumanEventAt'] == Null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                ((raw['lastHumanEventAt'] as num) * 1000).round()),
      );
      _last = status;
      _statusController.add(status);
      return status;
    } on PlatformException {
      // 非 macOS 平台 / channel 未就緒 → 維持 idle
      return _last;
    } on MissingPluginException {
      return _last;
    }
  }

  /// 安全機制 ================================================

  /// 進入 armed（需要 TCC Accessibility 已授權；未授權回傳原因）
  Future<String?> arm(String taskId) async {
    try {
      await _ch.invokeMethod('gate.arm', {'taskId': taskId});
      await refresh();
      return null; // 成功
    } on PlatformException catch (e) {
      return e.message; // 失敗原因（多為 TCC 未授權）
    }
  }

  Future<bool> activate() async {
    try {
      await _ch.invokeMethod('gate.activate');
      await refresh();
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> suspend(String reason) async {
    await _ch.invokeMethod('gate.suspend', {'reason': reason});
    await refresh();
  }

  /// 任務結束 / 使用者喊停 → 回 idle
  Future<void> disarm() async {
    await _ch.invokeMethod('gate.disarm');
    await refresh();
  }

  /// TCC 權限 ================================================

  Future<({bool accessibility, bool screen})> tccStatus() async {
    final raw = await _ch.invokeMethod('tcc.status') as Map;
    return (
      accessibility: raw['accessibility'] as bool? ?? false,
      screen: raw['screen'] as bool? ?? false,
    );
  }

  /// 請求 Accessibility 權限（彈系統設定，使用者手動勾選）
  Future<void> requestAccessibility() async {
    await _ch.invokeMethod('tcc.requestAccessibility');
  }

  /// 眼睛：AX 樹 =============================================

  /// 取前景視窗（或指定 pid）的 UI 樹。回 null = 無權限或無視窗。
  Future<Map<Object?, Object?>?> windowTree({int? pid, int maxDepth = 6}) async {
    try {
      final tree = await _ch.invokeMethod('ax.windowTree', {
        'pid': pid,
        'maxDepth': maxDepth,
      });
      return tree as Map<Object?, Object?>?;
    } on PlatformException {
      return null;
    }
  }

  /// 圍欄查詢：該座標是否為受保護欄位（密碼欄）
  Future<bool> isProtectedAt(double x, double y) async {
    try {
      final raw = await _ch
          .invokeMethod('ax.isProtectedAt', {'x': x, 'y': y}) as Map;
      return raw['protected'] as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 手：事件注入（Swift 端每步必經狀態機檢查，這裡只轉發）====

  Future<bool> click(double x, double y,
      {String button = 'left', int count = 1}) async {
    return _ok('input.click',
        {'x': x, 'y': y, 'button': button, 'count': count});
  }

  Future<bool> drag(double fromX, double fromY, double toX, double toY,
      {int durationMs = 300}) async {
    return _ok('input.drag', {
      'fromX': fromX, 'fromY': fromY, 'toX': toX, 'toY': toY,
      'durationMs': durationMs,
    });
  }

  Future<bool> scroll(double dx, double dy) =>
      _ok('input.scroll', {'dx': dx, 'dy': dy});

  Future<bool> typeText(String text) => _ok('input.typeText', {'text': text});

  Future<bool> key(int keyCode, {bool down = true}) =>
      _ok('input.key', {'keyCode': keyCode, 'down': down});

  Future<bool> _ok(String method, Map<String, dynamic> args) async {
    try {
      final raw = await _ch.invokeMethod(method, args) as Map;
      return raw['ok'] as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }

  TakeoverState _stateOf(String s) {
    switch (s) {
      case 'armed':
        return TakeoverState.armed;
      case 'active':
        return TakeoverState.active;
      case 'suspended':
        return TakeoverState.suspended;
      default:
        return TakeoverState.idle;
    }
  }
}
