import 'flow_step.dart';

class ProjectDoor {
  final String id;
  final String title;
  final String sourceIntent;
  final String currentFlow;
  final List<String> intakeQuestions;
  final List<String> requiredBridges;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;
  final String secondBrainEntryId;
  final String? conversationId; // [Sprint 11] 綁定的對話 ID

  // [Sprint 18b] 水流追蹤 + 分岔 + 資產引用
  final List<FlowStep> flowSteps;
  final String? parentDoorId; // 分岔來源的門 ID
  final List<String> linkedAssetIds;
  final List<String> linkedMemoryIds;

  const ProjectDoor({
    required this.id,
    required this.title,
    required this.sourceIntent,
    required this.currentFlow,
    required this.intakeQuestions,
    required this.requiredBridges,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.secondBrainEntryId,
    this.conversationId,
    this.flowSteps = const [],
    this.parentDoorId,
    this.linkedAssetIds = const [],
    this.linkedMemoryIds = const [],
  });

  factory ProjectDoor.create({
    required String title,
    required String sourceIntent,
    List<String>? intakeQuestions,
    List<String>? requiredBridges,
  }) {
    final now = DateTime.now();
    final id = 'project-door-${now.microsecondsSinceEpoch}';
    return ProjectDoor(
      id: id,
      title: title,
      sourceIntent: sourceIntent,
      currentFlow: '目標定義',
      intakeQuestions:
          intakeQuestions ??
          const [
            '你要銷售或推進的核心產品/服務是什麼？',
            '目標受眾是誰？他們目前最痛的問題是什麼？',
            '你希望 AI 角色扮演什麼定位：專家、陪伴、娛樂、銷售，還是混合？',
            '第一版成功標準是什麼：成交、名單、觀看數、內容產出，還是品牌曝光？',
            '你希望第一版 MVP 在幾天內完成？',
          ],
      requiredBridges:
          requiredBridges ??
          const ['影片生成橋', '語音/音樂橋', '直播平台橋', '商品資料橋', '金流/物流橋'],
      createdAt: now,
      updatedAt: now,
      status: 'intake',
      secondBrainEntryId: 'second-brain-$id',
    );
  }

  ProjectDoor copyWith({
    String? title,
    String? sourceIntent,
    String? currentFlow,
    List<String>? intakeQuestions,
    List<String>? requiredBridges,
    DateTime? updatedAt,
    String? status,
    String? secondBrainEntryId,
    String? conversationId,
    List<FlowStep>? flowSteps,
    String? parentDoorId,
    List<String>? linkedAssetIds,
    List<String>? linkedMemoryIds,
  }) {
    return ProjectDoor(
      id: id,
      title: title ?? this.title,
      sourceIntent: sourceIntent ?? this.sourceIntent,
      currentFlow: currentFlow ?? this.currentFlow,
      intakeQuestions: intakeQuestions ?? this.intakeQuestions,
      requiredBridges: requiredBridges ?? this.requiredBridges,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      status: status ?? this.status,
      secondBrainEntryId: secondBrainEntryId ?? this.secondBrainEntryId,
      conversationId: conversationId ?? this.conversationId,
      flowSteps: flowSteps ?? this.flowSteps,
      parentDoorId: parentDoorId ?? this.parentDoorId,
      linkedAssetIds: linkedAssetIds ?? this.linkedAssetIds,
      linkedMemoryIds: linkedMemoryIds ?? this.linkedMemoryIds,
    );
  }

  /// [Sprint 11 以西結審查 R2] 清除 conversationId（Dart nullable param 無法區分不傳 vs 傳 null）
  ProjectDoor clearConversationId() => ProjectDoor(
        id: id,
        title: title,
        sourceIntent: sourceIntent,
        currentFlow: currentFlow,
        intakeQuestions: intakeQuestions,
        requiredBridges: requiredBridges,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        status: status,
        secondBrainEntryId: secondBrainEntryId,
        conversationId: null,
        flowSteps: flowSteps,
        parentDoorId: parentDoorId,
        linkedAssetIds: linkedAssetIds,
        linkedMemoryIds: linkedMemoryIds,
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'sourceIntent': sourceIntent,
      'currentFlow': currentFlow,
      'intakeQuestions': intakeQuestions,
      'requiredBridges': requiredBridges,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status,
      'secondBrainEntryId': secondBrainEntryId,
      if (conversationId != null) 'conversationId': conversationId,
      'flowSteps': flowSteps.map((s) => s.toJson()).toList(),
      if (parentDoorId != null) 'parentDoorId': parentDoorId,
      'linkedAssetIds': linkedAssetIds,
      'linkedMemoryIds': linkedMemoryIds,
    };
  }

  factory ProjectDoor.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return ProjectDoor(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      sourceIntent: json['sourceIntent']?.toString() ?? '',
      currentFlow: json['currentFlow']?.toString() ?? '目標定義',
      intakeQuestions:
          (json['intakeQuestions'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      requiredBridges:
          (json['requiredBridges'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: json['status']?.toString() ?? 'intake',
      secondBrainEntryId: json['secondBrainEntryId']?.toString() ?? '',
      conversationId: json['conversationId'] as String?,
      flowSteps: (json['flowSteps'] as List?)
              ?.map((item) =>
                  FlowStep.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList() ??
          const [],
      parentDoorId: json['parentDoorId'] as String?,
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

  bool get isValid => id.trim().isNotEmpty && title.trim().isNotEmpty;

  // [Sprint 18b] 看板狀態常數
  static const statusIntake = 'intake';
  static const statusActive = 'active';
  static const statusWaiting = 'waiting';
  static const statusCompleted = 'completed';

  static const kanbanStatuses = [statusActive, statusWaiting, statusCompleted];

  /// 看板分組用的顯示狀態（將 intake 歸到 active）
  String get kanbanStatus {
    switch (status) {
      case statusCompleted:
        return statusCompleted;
      case statusWaiting:
        return statusWaiting;
      default:
        return statusActive; // intake 和 active 都歸到進行中
    }
  }

  /// 水流進度統計
  int get completedFlowCount =>
      flowSteps.where((s) => s.isDone).length;
  int get totalFlowCount => flowSteps.length;
  double get flowProgress =>
      totalFlowCount == 0 ? 0 : completedFlowCount / totalFlowCount;
}
