// [Sprint 18b-1 — 專案門水流追蹤]
// FlowStep：專案門底下的細節推進步驟。
// 每個門有多個 flow step，按 status 分為 pending / in_progress / done / blocked。

class FlowStep {
  final String id;
  final String doorId;
  final String title;
  final String? description;
  final String status; // pending | in_progress | done | blocked
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  // 資產引用閉環（S18c 會接上完整閉環）
  final List<String> linkedAssetIds;
  final List<String> linkedMemoryIds;

  const FlowStep({
    required this.id,
    required this.doorId,
    required this.title,
    this.description,
    required this.status,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.linkedAssetIds = const [],
    this.linkedMemoryIds = const [],
  });

  factory FlowStep.create({
    required String doorId,
    required String title,
    String? description,
    int order = 0,
  }) {
    final now = DateTime.now();
    return FlowStep(
      id: 'flow-${now.microsecondsSinceEpoch}',
      doorId: doorId,
      title: title,
      description: description,
      status: 'pending',
      order: order,
      createdAt: now,
      updatedAt: now,
    );
  }

  FlowStep copyWith({
    String? title,
    String? description,
    String? status,
    int? order,
    DateTime? updatedAt,
    DateTime? completedAt,
    List<String>? linkedAssetIds,
    List<String>? linkedMemoryIds,
  }) {
    return FlowStep(
      id: id,
      doorId: doorId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      order: order ?? this.order,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      completedAt: completedAt ?? this.completedAt,
      linkedAssetIds: linkedAssetIds ?? this.linkedAssetIds,
      linkedMemoryIds: linkedMemoryIds ?? this.linkedMemoryIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'doorId': doorId,
      'title': title,
      if (description != null) 'description': description,
      'status': status,
      'order': order,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      'linkedAssetIds': linkedAssetIds,
      'linkedMemoryIds': linkedMemoryIds,
    };
  }

  factory FlowStep.fromJson(Map<String, dynamic> json) {
    return FlowStep(
      id: json['id']?.toString() ?? '',
      doorId: json['doorId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description'] as String?,
      status: json['status']?.toString() ?? 'pending',
      order: (json['order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      linkedAssetIds: (json['linkedAssetIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      linkedMemoryIds: (json['linkedMemoryIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  bool get isDone => status == 'done';
  bool get isBlocked => status == 'blocked';
  bool get isInProgress => status == 'in_progress';

  /// 看板分組鍵
  static const statusPending = 'pending';
  static const statusInProgress = 'in_progress';
  static const statusDone = 'done';
  static const statusBlocked = 'blocked';

  static const allStatuses = [
    statusPending,
    statusInProgress,
    statusDone,
    statusBlocked,
  ];
}
