// agent_event_bus.dart
// 事件驅動系統 — Track C 自主迴圈的事件中樞。
//
// 設計決策（使用者 2026-07-17 拍板）：
// - 迴圈 = 事件驅動 + 60 秒 idle 兜底（非純定時輪詢）
// - broadcast StreamController，多個訂閱者（Agent Loop、UI、大腦）同時監聽
// - userIdle 事件由內建 Timer 偵測：60 秒無任何活動 → emit userIdle
// - 所有事件帶 timestamp，方便排序與去重
//
// 事件流示意：
//   使用者畫塗鴉 → userAnnotation → Agent 感知 → 回應
//   工作流跑完   → workflowCompleted → Agent 報告結果
//   60 秒沒動    → userIdle → Agent 觀察畫布 → 主動建議
//
// [Phase 0 Track C 2026-07-17]

import 'dart:async';

/// Agent 事件類型
///
/// 每種事件對應一種「Agent 應該感知並可能行動」的情境。
enum AgentEventType {
  /// 使用者在畫布上畫了塗鴉標注（圈、箭頭、文字）
  userAnnotation,

  /// 工作流執行完畢（所有節點 visualState = done）
  workflowCompleted,

  /// 工作流執行錯誤（某節點失敗）
  workflowError,

  /// 畫布結構變化（新增/刪除節點、連線變動）
  canvasChanged,

  /// 使用者發了訊息（現有 ChatController 觸發）
  userMessage,

  /// 使用者一段時間沒動作（60 秒 idle 兜底）
  userIdle,

  /// 大腦寫入新記憶（Brain Pipeline 回饋）
  brainMemoryAdded,

  /// 外部任務注入（透過 AgentTaskInbox 檔案系統 IPC）
  externalTask,
}

/// 單一 Agent 事件
///
/// 所有事件統一格式：類型 + 資料 + 時間戳。
/// data 內容因事件類型而異，由發射端和接收端約定。
class AgentEvent {
  /// 事件類型
  final AgentEventType type;

  /// 事件附帶資料（可為空）
  final Map<String, dynamic> data;

  /// 事件發生時間
  final DateTime timestamp;

  AgentEvent({
    required this.type,
    this.data = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'AgentEvent($type, $timestamp, data: $data)';
}

/// Agent 事件匯流排
///
/// 全域事件中樞——所有子系統（畫布、聊天、工作流引擎、大腦）
/// 透過此 bus 發射和訂閱事件，實現解耦的事件驅動迴圈。
///
/// 使用方式：
/// ```dart
/// final bus = AgentEventBus();
/// bus.events.listen((event) {
///   if (event.type == AgentEventType.userAnnotation) { ... }
/// });
/// bus.emit(AgentEventType.userAnnotation, data: {'count': 3});
/// ```
///
/// [Phase 0 Track C 2026-07-17]
class AgentEventBus {
  /// 廣播 StreamController——多訂閱者同時監聽
  final StreamController<AgentEvent> _controller =
      StreamController<AgentEvent>.broadcast();

  /// Idle 偵測計時器——60 秒無活動觸發 userIdle
  Timer? _idleTimer;

  /// Idle 閾值（使用者拍板：60 秒）
  static const Duration idleThreshold = Duration(seconds: 60);

  /// 上一次 emit 的時間（用於 idle 偵測）
  DateTime _lastActivityTime = DateTime.now();

  /// 是否已啟用 idle 偵測
  bool _idleDetectionEnabled = false;

  /// 事件流——訂閱者透過此 Stream 接收事件
  Stream<AgentEvent> get events => _controller.stream;

  /// 目前是否已關閉
  bool get isClosed => _controller.isClosed;

  /// 發射事件
  ///
  /// 同時重設 idle 計時器（任何事件都算「使用者有活動」）。
  void emit(AgentEventType type, {Map<String, dynamic>? data}) {
    if (_controller.isClosed) return;

    final event = AgentEvent(type: type, data: data ?? {});
    _controller.add(event);

    // 任何事件都重設 idle 計時器
    _lastActivityTime = DateTime.now();
    _resetIdleTimer();
  }

  /// 啟用 idle 偵測
  ///
  /// 啟用後，若 [idleThreshold]（60 秒）內無任何事件發射，
  /// 自動 emit [AgentEventType.userIdle]。
  void enableIdleDetection() {
    if (_idleDetectionEnabled) return;
    _idleDetectionEnabled = true;
    _lastActivityTime = DateTime.now();
    _resetIdleTimer();
  }

  /// 停用 idle 偵測
  void disableIdleDetection() {
    _idleDetectionEnabled = false;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// 重設 idle 計時器
  void _resetIdleTimer() {
    if (!_idleDetectionEnabled) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleThreshold, _onIdleTimeout);
  }

  /// Idle 超時回調——發射 userIdle 事件
  ///
  /// 注意：userIdle 事件本身不重設 idle 計時器（避免無限迴圈），
  /// 而是直接 add 到 controller。
  void _onIdleTimeout() {
    if (_controller.isClosed || !_idleDetectionEnabled) return;

    final idleDuration = DateTime.now().difference(_lastActivityTime);
    _controller.add(AgentEvent(
      type: AgentEventType.userIdle,
      data: {
        'idleDurationSeconds': idleDuration.inSeconds,
        'lastActivityTime': _lastActivityTime.toIso8601String(),
      },
    ));

    // idle 事件後重新啟動計時器，等待下一個 idle 週期
    _resetIdleTimer();
  }

  /// 關閉事件匯流排，釋放資源
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleDetectionEnabled = false;
    _controller.close();
  }
}
