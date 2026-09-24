// task.dart
// 長任務模型 + 狀態機。
// TaskQueue 管理的任務單元，狀態流轉：
// pending → running → awaiting_confirmation → completed / failed / cancelled
// Sprint 19c by 教練 Agent (CEO)

/// 任務狀態。
enum TaskStatus {
  /// 等待執行
  pending,
  /// 正在執行
  running,
  /// 暫停，等待使用者確認（如偵測到登入/付款頁）
  awaitingConfirmation,
  /// 成功完成
  completed,
  /// 執行失敗
  failed,
  /// 被使用者取消
  cancelled,
}

/// 長任務模型。
///
/// 一個任務代表手機端請求桌面端執行的非同步操作（瀏覽器自動化、檔案處理等）。
/// 任務在背景執行，進度透過 push 推播回手機。
class Task {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  TaskStatus status;
  double progress;
  String? message;
  Map<String, dynamic>? result;
  String? error;
  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;

  Task({
    required this.id,
    required this.type,
    this.payload = const {},
    this.status = TaskStatus.pending,
    this.progress = 0.0,
    this.message,
    this.result,
    this.error,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 是否已結束（終態）
  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.cancelled;

  /// 是否正在執行中
  bool get isActive =>
      status == TaskStatus.running ||
      status == TaskStatus.awaitingConfirmation;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'status': status.name,
      'progress': progress,
      if (message != null) 'message': message,
      if (result != null) 'result': result,
      if (error != null) 'error': error,
      'createdAt': createdAt.toIso8601String(),
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    };
  }
}
