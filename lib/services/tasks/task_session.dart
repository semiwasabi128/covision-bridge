// task_session.dart
// [隊友訊息流 第 1 刀 C1 2026-09-08]
// TaskSession = 一次派工的會話本體。設計稿：docs/specs/2026-09-08-teammate-inbox.md
//
// 設計要點：
// - 不中斷鐵則（設計稿 §5.2）：活在 service 層，不綁 widget 生命週期
// - 這也是第 4 刀「房間即工作」的種子——房間 = TaskSession 的空間化版本
// - 審計數據（狀態流轉/耗時）→ 第 2 刀夥伴身份卡直接吃

/// 任務狀態機：dispatched → working → awaitingReview → delivered
///                                    ↘ failed / cancelled（任一態可轉入）
enum TaskStatus { dispatched, working, awaitingReview, delivered, failed, cancelled }

TaskStatus taskStatusFromName(String name) => TaskStatus.values
    .firstWhere((s) => s.name == name, orElse: () => TaskStatus.dispatched);

String taskStatusLabel(TaskStatus s) => switch (s) {
      TaskStatus.dispatched => '已派工',
      TaskStatus.working => '進行中',
      TaskStatus.awaitingReview => '等待確認',
      TaskStatus.delivered => '已完成',
      TaskStatus.failed => '失敗',
      TaskStatus.cancelled => '已取消',
    };

/// 任務步驟——來自 AgentLoop turn 記錄（直播視圖的資料源，設計稿 §5.1）
class TaskStep {
  final String id;
  final String tool; // 工具名（如 canvas_place / generate_image）
  final String summary; // 一句話摘要
  final DateTime at;

  const TaskStep({
    required this.id,
    required this.tool,
    required this.summary,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool,
        'summary': summary,
        'at': at.toIso8601String(),
      };

  factory TaskStep.fromJson(Map<String, dynamic> json) => TaskStep(
        id: json['id'] as String,
        tool: json['tool'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// 產出物指標——交付卡縮圖列的資料源
class TaskDeliverable {
  final String kind; // image / text / file / canvas
  final String ref; // 檔案路徑或 canvasId
  final String caption; // 一句話描述

  const TaskDeliverable({
    required this.kind,
    required this.ref,
    required this.caption,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'ref': ref,
        'caption': caption,
      };

  factory TaskDeliverable.fromJson(Map<String, dynamic> json) => TaskDeliverable(
        kind: json['kind'] as String? ?? 'text',
        ref: json['ref'] as String? ?? '',
        caption: json['caption'] as String? ?? '',
      );
}

/// 派工會話——一次「幫我做 X」的完整生命週期
class TaskSession {
  final String id;
  final String conversationId; // 主對話（交付訊息落點）
  final String companionId; // 接單夥伴
  final String workCanvasId; // 派工時自動建立的工作畫布
  final String title; // 從白話指令摘出的任務標題
  final String instruction; // 原始白話指令
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finishedAt;
  final List<TaskStep> steps;
  final List<TaskDeliverable> deliverables;
  final String? finalSummary;
  final String? failureReason;

  const TaskSession({
    required this.id,
    required this.conversationId,
    required this.companionId,
    required this.workCanvasId,
    required this.title,
    required this.instruction,
    this.status = TaskStatus.dispatched,
    required this.createdAt,
    required this.updatedAt,
    this.finishedAt,
    this.steps = const [],
    this.deliverables = const [],
    this.finalSummary,
    this.failureReason,
  });

  /// 仍在進行中的狀態（UI 的「進行中任務卡 / chip 列」依此過濾）
  bool get isActive =>
      status == TaskStatus.dispatched ||
      status == TaskStatus.working ||
      status == TaskStatus.awaitingReview;

  factory TaskSession.create({
    required String conversationId,
    required String companionId,
    required String workCanvasId,
    required String title,
    required String instruction,
  }) {
    final now = DateTime.now();
    return TaskSession(
      id: 'task-${now.millisecondsSinceEpoch}-${now.microsecondsSinceEpoch % 1000}',
      conversationId: conversationId,
      companionId: companionId,
      workCanvasId: workCanvasId,
      title: title,
      instruction: instruction,
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskSession copyWith({
    TaskStatus? status,
    DateTime? updatedAt,
    DateTime? finishedAt,
    List<TaskStep>? steps,
    List<TaskDeliverable>? deliverables,
    String? finalSummary,
    String? failureReason,
  }) =>
      TaskSession(
        id: id,
        conversationId: conversationId,
        companionId: companionId,
        workCanvasId: workCanvasId,
        title: title,
        instruction: instruction,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        steps: steps ?? this.steps,
        deliverables: deliverables ?? this.deliverables,
        finalSummary: finalSummary ?? this.finalSummary,
        failureReason: failureReason ?? this.failureReason,
      );

  /// 狀態流轉（含合法性和時間戳維護）
  /// 非法流轉（如 delivered → working）直接丟 ArgumentError——
  /// UI 誠實鐵則：狀態機被違反時寧可炸出來，不要靜默吞掉。
  TaskSession transitionTo(TaskStatus next, {String? reason}) {
    const legal = {
      TaskStatus.dispatched: [
        TaskStatus.working,
        TaskStatus.failed,
        TaskStatus.cancelled,
      ],
      TaskStatus.working: [
        TaskStatus.awaitingReview,
        TaskStatus.delivered,
        TaskStatus.failed,
        TaskStatus.cancelled,
      ],
      TaskStatus.awaitingReview: [
        TaskStatus.delivered,
        TaskStatus.working, // 「修改」→ 打回重做
        TaskStatus.cancelled,
      ],
      TaskStatus.delivered: [],
      TaskStatus.failed: [],
      TaskStatus.cancelled: [],
    };
    if (!legal[status]!.contains(next)) {
      throw ArgumentError('非法狀態流轉：$status → $next');
    }
    final now = DateTime.now();
    final terminal = next == TaskStatus.delivered ||
        next == TaskStatus.failed ||
        next == TaskStatus.cancelled;
    return copyWith(
      status: next,
      updatedAt: now,
      finishedAt: terminal ? now : finishedAt,
      failureReason: reason ?? failureReason,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'companionId': companionId,
        'workCanvasId': workCanvasId,
        'title': title,
        'instruction': instruction,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'steps': steps.map((s) => s.toJson()).toList(),
        'deliverables': deliverables.map((d) => d.toJson()).toList(),
        'finalSummary': finalSummary,
        'failureReason': failureReason,
      };

  factory TaskSession.fromJson(Map<String, dynamic> json) => TaskSession(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String? ?? '',
        companionId: json['companionId'] as String? ?? '',
        workCanvasId: json['workCanvasId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        instruction: json['instruction'] as String? ?? '',
        status: taskStatusFromName(json['status'] as String? ?? 'dispatched'),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
        finishedAt: json['finishedAt'] == null
            ? null
            : DateTime.tryParse(json['finishedAt'] as String),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        deliverables: (json['deliverables'] as List<dynamic>? ?? [])
            .map((e) => TaskDeliverable.fromJson(e as Map<String, dynamic>))
            .toList(),
        finalSummary: json['finalSummary'] as String?,
        failureReason: json['failureReason'] as String?,
      );
}
