import '../models/bridge_action.dart';
import 'capability_health_service.dart';
import 'local_model_catalog_service.dart';

enum TaskExecutionLane {
  localFirst,
  cloudFirst,
  hybrid,
  askEveryTime,
  setupRequired,
}

enum TaskRoutingRuleMode { auto, localFirst, cloudFirst, askEveryTime }

class TaskRoutingItem {
  final String id;
  final String label;
  final String scenario;
  final TaskExecutionLane lane;
  final String primaryKey;
  final String backupKey;
  final String reason;
  final bool ready;
  final TaskRoutingRuleMode ruleMode;

  const TaskRoutingItem({
    required this.id,
    required this.label,
    required this.scenario,
    required this.lane,
    required this.primaryKey,
    required this.backupKey,
    required this.reason,
    required this.ready,
    this.ruleMode = TaskRoutingRuleMode.auto,
  });

  TaskRoutingItem copyWith({
    TaskExecutionLane? lane,
    String? primaryKey,
    String? backupKey,
    String? reason,
    bool? ready,
    TaskRoutingRuleMode? ruleMode,
  }) {
    return TaskRoutingItem(
      id: id,
      label: label,
      scenario: scenario,
      lane: lane ?? this.lane,
      primaryKey: primaryKey ?? this.primaryKey,
      backupKey: backupKey ?? this.backupKey,
      reason: reason ?? this.reason,
      ready: ready ?? this.ready,
      ruleMode: ruleMode ?? this.ruleMode,
    );
  }
}

class TaskRoutingPlan {
  final String summary;
  final List<TaskRoutingItem> items;

  const TaskRoutingPlan({required this.summary, required this.items});

  int get readyCount => items.where((item) => item.ready).length;

  bool get hasLocalRoute => items.any(
    (item) =>
        item.lane == TaskExecutionLane.localFirst ||
        item.lane == TaskExecutionLane.hybrid,
  );
}

class LocalTaskRoutingService {
  const LocalTaskRoutingService();

  TaskRoutingPlan build({
    required LocalModelPlan localModelPlan,
    required List<CapabilityHealthItem> health,
    Map<String, TaskRoutingRuleMode> rules = const {},
  }) {
    final brainReady = _isReadyByLabel(health, '聊天');
    final imageReady = _isReadyByAction(health, BridgeActionType.generateImage);
    final documentReady = _isReadyByAction(health, BridgeActionType.document);
    final baseItems = [
      _localSensitiveTask(
        id: 'private-draft',
        label: '私人草稿',
        scenario: '想法、日記、未定稿內容',
        task: LocalModelTask.privateDraft,
        localModelPlan: localModelPlan,
        brainReady: brainReady,
      ),
      _localSensitiveTask(
        id: 'memory-tidy',
        label: '記憶整理',
        scenario: '長期記憶、洞察回收、上下文壓縮',
        task: LocalModelTask.memoryTidy,
        localModelPlan: localModelPlan,
        brainReady: brainReady,
      ),
      _balancedTask(
        id: 'quick-chat',
        label: '快速對話',
        scenario: '日常問答、低風險討論',
        task: LocalModelTask.quickChat,
        localModelPlan: localModelPlan,
        brainReady: brainReady,
      ),
      _documentTask(
        localModelPlan: localModelPlan,
        brainReady: brainReady,
        documentReady: documentReady,
      ),
      _balancedTask(
        id: 'coding',
        label: '程式輔助',
        scenario: '讀碼、改碼、產生小工具',
        task: LocalModelTask.coding,
        localModelPlan: localModelPlan,
        brainReady: brainReady,
      ),
      _longReasoningTask(
        localModelPlan: localModelPlan,
        brainReady: brainReady,
      ),
      _creativeTask(imageReady: imageReady),
    ];
    final items = [
      for (final item in baseItems)
        _applyRule(item, rules[item.id] ?? TaskRoutingRuleMode.auto),
    ];

    return TaskRoutingPlan(summary: _summary(items), items: items);
  }

  TaskRoutingItem _applyRule(TaskRoutingItem item, TaskRoutingRuleMode mode) {
    switch (mode) {
      case TaskRoutingRuleMode.auto:
        return item.copyWith(ruleMode: mode);
      case TaskRoutingRuleMode.askEveryTime:
        return item.copyWith(
          lane: item.ready
              ? TaskExecutionLane.askEveryTime
              : TaskExecutionLane.setupRequired,
          primaryKey: item.ready ? '每次詢問' : item.primaryKey,
          backupKey: item.ready ? item.primaryKey : item.backupKey,
          reason: item.ready ? '已指定執行前詢問，讓使用者每次確認使用哪把鑰匙。' : item.reason,
          ruleMode: mode,
        );
      case TaskRoutingRuleMode.localFirst:
        if (_isLocalKey(item.primaryKey)) {
          return item.copyWith(
            lane: TaskExecutionLane.localFirst,
            reason: '已手動指定本地優先，會先使用本地模型處理。',
            ruleMode: mode,
          );
        }
        if (_isLocalKey(item.backupKey)) {
          return item.copyWith(
            lane: TaskExecutionLane.localFirst,
            primaryKey: item.backupKey,
            backupKey: item.primaryKey,
            reason: '已手動指定本地優先，會先使用本地模型處理。',
            ready: true,
            ruleMode: mode,
          );
        }
        return item.copyWith(
          lane: TaskExecutionLane.setupRequired,
          primaryKey: '等待本地模型',
          backupKey: item.primaryKey,
          reason: '已指定本地優先，但需要先連接桌面或下載可用本地模型。',
          ready: false,
          ruleMode: mode,
        );
      case TaskRoutingRuleMode.cloudFirst:
        if (_isCloudKey(item.primaryKey)) {
          return item.copyWith(
            lane: TaskExecutionLane.cloudFirst,
            reason: '已手動指定雲端優先，會先使用主腦或創造鑰匙處理。',
            ruleMode: mode,
          );
        }
        if (_isCloudKey(item.backupKey)) {
          return item.copyWith(
            lane: TaskExecutionLane.cloudFirst,
            primaryKey: item.backupKey,
            backupKey: item.primaryKey,
            reason: '已手動指定雲端優先，會先使用主腦或創造鑰匙處理。',
            ready: true,
            ruleMode: mode,
          );
        }
        return item.copyWith(
          lane: TaskExecutionLane.setupRequired,
          primaryKey: '等待雲端鑰匙',
          backupKey: item.primaryKey,
          reason: '已指定雲端優先，但需要先設定主腦或創造鑰匙。',
          ready: false,
          ruleMode: mode,
        );
    }
  }

  TaskRoutingItem _localSensitiveTask({
    required String id,
    required String label,
    required String scenario,
    required LocalModelTask task,
    required LocalModelPlan localModelPlan,
    required bool brainReady,
  }) {
    final local = _bestLocal(localModelPlan, task);
    if (local != null) {
      return TaskRoutingItem(
        id: id,
        label: label,
        scenario: scenario,
        lane: TaskExecutionLane.localFirst,
        primaryKey: '本地模型 · ${local.model.sizeClass}',
        backupKey: brainReady ? '主腦鑰匙補強' : '等待主腦鑰匙',
        reason: '隱私優先，先交給本地模型；需要更強推理時再請雲端補強。',
        ready: true,
      );
    }
    if (brainReady) {
      return TaskRoutingItem(
        id: id,
        label: label,
        scenario: scenario,
        lane: TaskExecutionLane.cloudFirst,
        primaryKey: '主腦鑰匙',
        backupKey: '等待本地模型',
        reason: '目前尚未完成本地硬體檢測或模型下載，先用雲端主腦處理。',
        ready: true,
      );
    }
    return _setupItem(id: id, label: label, scenario: scenario);
  }

  TaskRoutingItem _balancedTask({
    required String id,
    required String label,
    required String scenario,
    required LocalModelTask task,
    required LocalModelPlan localModelPlan,
    required bool brainReady,
  }) {
    final local = _bestLocal(localModelPlan, task);
    if (local != null && brainReady) {
      return TaskRoutingItem(
        id: id,
        label: label,
        scenario: scenario,
        lane: TaskExecutionLane.hybrid,
        primaryKey: '本地模型 · ${local.model.sizeClass}',
        backupKey: '主腦鑰匙',
        reason: '低成本先本地處理，需要最新能力或更高品質時自動交給雲端。',
        ready: true,
      );
    }
    if (local != null) {
      return TaskRoutingItem(
        id: id,
        label: label,
        scenario: scenario,
        lane: TaskExecutionLane.localFirst,
        primaryKey: '本地模型 · ${local.model.sizeClass}',
        backupKey: '等待主腦鑰匙',
        reason: '已有可用本地模型，先用本地算力保持低成本與低延遲。',
        ready: true,
      );
    }
    if (brainReady) {
      return TaskRoutingItem(
        id: id,
        label: label,
        scenario: scenario,
        lane: TaskExecutionLane.cloudFirst,
        primaryKey: '主腦鑰匙',
        backupKey: '等待本地模型',
        reason: '目前缺少適合的本地模型，先由雲端主腦負責。',
        ready: true,
      );
    }
    return _setupItem(id: id, label: label, scenario: scenario);
  }

  TaskRoutingItem _longReasoningTask({
    required LocalModelPlan localModelPlan,
    required bool brainReady,
  }) {
    final local = _bestLocal(localModelPlan, LocalModelTask.longReasoning);
    final strongLocal =
        local != null &&
        (local.fit == LocalModelFit.excellent ||
            local.fit == LocalModelFit.good);
    if (brainReady && strongLocal) {
      return TaskRoutingItem(
        id: 'long-reasoning',
        label: '長推理',
        scenario: '策略、規劃、複雜判斷',
        lane: TaskExecutionLane.hybrid,
        primaryKey: '主腦鑰匙',
        backupKey: '本地模型 · ${local.model.sizeClass}',
        reason: '高難任務由雲端主腦主導，本地模型可協助草稿與檢查。',
        ready: true,
      );
    }
    if (brainReady) {
      return const TaskRoutingItem(
        id: 'long-reasoning',
        label: '長推理',
        scenario: '策略、規劃、複雜判斷',
        lane: TaskExecutionLane.cloudFirst,
        primaryKey: '主腦鑰匙',
        backupKey: '等待進階本地模型',
        reason: '長推理先交給雲端主腦，之後再用 14B 以上本地模型分擔。',
        ready: true,
      );
    }
    if (local != null) {
      return TaskRoutingItem(
        id: 'long-reasoning',
        label: '長推理',
        scenario: '策略、規劃、複雜判斷',
        lane: TaskExecutionLane.localFirst,
        primaryKey: '本地模型 · ${local.model.sizeClass}',
        backupKey: '等待主腦鑰匙',
        reason: '已有可嘗試的進階本地模型，但複雜任務仍建議加上雲端補強。',
        ready: true,
      );
    }
    return _setupItem(
      id: 'long-reasoning',
      label: '長推理',
      scenario: '策略、規劃、複雜判斷',
    );
  }

  TaskRoutingItem _documentTask({
    required LocalModelPlan localModelPlan,
    required bool brainReady,
    required bool documentReady,
  }) {
    final local = _bestLocal(localModelPlan, LocalModelTask.privateDraft);
    if (local != null && brainReady) {
      return TaskRoutingItem(
        id: 'document-output',
        label: '文件產出',
        scenario: '摘要、筆記、Markdown 文件',
        lane: TaskExecutionLane.hybrid,
        primaryKey: '本地模型 · ${local.model.sizeClass}',
        backupKey: '文件鑰匙',
        reason: '先由本地模型整理草稿，再由文件 adapter 產出格式化文件。',
        ready: true,
      );
    }
    if (documentReady) {
      return const TaskRoutingItem(
        id: 'document-output',
        label: '文件產出',
        scenario: '摘要、筆記、Markdown 文件',
        lane: TaskExecutionLane.cloudFirst,
        primaryKey: '文件鑰匙',
        backupKey: '本地模板',
        reason: '文件 adapter 已可用，若雲端生成失敗會退回本地模板。',
        ready: true,
      );
    }
    return _setupItem(
      id: 'document-output',
      label: '文件產出',
      scenario: '摘要、筆記、Markdown 文件',
    );
  }

  TaskRoutingItem _creativeTask({required bool imageReady}) {
    if (imageReady) {
      return const TaskRoutingItem(
        id: 'creative-image',
        label: '形象與圖片生成',
        scenario: '夥伴造型、角色圖組、素材',
        lane: TaskExecutionLane.cloudFirst,
        primaryKey: '創造鑰匙',
        backupKey: '本地草稿提示詞',
        reason: '圖片生成先由專用服務執行，本地模型負責整理風格線索。',
        ready: true,
      );
    }
    return const TaskRoutingItem(
      id: 'creative-image',
      label: '形象與圖片生成',
      scenario: '夥伴造型、角色圖組、素材',
      lane: TaskExecutionLane.setupRequired,
      primaryKey: '等待創造鑰匙',
      backupKey: '可先使用預設形象',
      reason: '需要先設定圖片生成服務，才能即時召喚形象。',
      ready: false,
    );
  }

  TaskRoutingItem _setupItem({
    required String id,
    required String label,
    required String scenario,
  }) {
    return TaskRoutingItem(
      id: id,
      label: label,
      scenario: scenario,
      lane: TaskExecutionLane.setupRequired,
      primaryKey: '等待鑰匙',
      backupKey: '尚無備援',
      reason: '需要先設定主腦鑰匙，或連接桌面後下載可用本地模型。',
      ready: false,
    );
  }

  LocalModelRecommendation? _bestLocal(
    LocalModelPlan plan,
    LocalModelTask task,
  ) {
    final candidates = plan.recommendations.where(
      (item) =>
          item.model.bestFor.contains(task) &&
          item.fit != LocalModelFit.unknown &&
          item.fit != LocalModelFit.unsupported,
    );
    if (candidates.isEmpty) return null;
    return candidates.reduce((best, next) {
      if (_fitScore(next.fit) > _fitScore(best.fit)) return next;
      if (_fitScore(next.fit) == _fitScore(best.fit) &&
          next.model.recommendedRamGb > best.model.recommendedRamGb) {
        return next;
      }
      return best;
    });
  }

  int _fitScore(LocalModelFit fit) {
    switch (fit) {
      case LocalModelFit.excellent:
        return 4;
      case LocalModelFit.good:
        return 3;
      case LocalModelFit.limited:
        return 2;
      case LocalModelFit.unknown:
        return 1;
      case LocalModelFit.unsupported:
        return 0;
    }
  }

  bool _isReadyByLabel(List<CapabilityHealthItem> health, String label) {
    return health.any(
      (item) =>
          item.label == label && item.status == CapabilityHealthStatus.ready,
    );
  }

  bool _isReadyByAction(
    List<CapabilityHealthItem> health,
    BridgeActionType type,
  ) {
    return health.any(
      (item) =>
          item.type == type && item.status == CapabilityHealthStatus.ready,
    );
  }

  bool _isLocalKey(String value) => value.startsWith('本地模型');

  bool _isCloudKey(String value) =>
      value.contains('主腦鑰匙') ||
      value.contains('創造鑰匙') ||
      value.contains('文件鑰匙');

  String _summary(List<TaskRoutingItem> items) {
    final ready = items.where((item) => item.ready).length;
    final local = items
        .where(
          (item) =>
              item.lane == TaskExecutionLane.localFirst ||
              item.lane == TaskExecutionLane.hybrid,
        )
        .length;
    if (ready == 0) return '尚未設定鑰匙，任務分配會在金鑰就緒後啟動。';
    if (local > 0) {
      return '已建立 $ready 條任務路線，其中 $local 條可使用本地模型分擔。';
    }
    return '已建立 $ready 條雲端路線，本地模型會在桌面檢測與下載後加入。';
  }
}

extension TaskExecutionLaneX on TaskExecutionLane {
  String get label {
    switch (this) {
      case TaskExecutionLane.localFirst:
        return '本地優先';
      case TaskExecutionLane.cloudFirst:
        return '雲端優先';
      case TaskExecutionLane.hybrid:
        return '混合接力';
      case TaskExecutionLane.askEveryTime:
        return '每次詢問';
      case TaskExecutionLane.setupRequired:
        return '待設定';
    }
  }
}

extension TaskRoutingRuleModeX on TaskRoutingRuleMode {
  String get label {
    switch (this) {
      case TaskRoutingRuleMode.auto:
        return '自動判斷';
      case TaskRoutingRuleMode.localFirst:
        return '本地優先';
      case TaskRoutingRuleMode.cloudFirst:
        return '雲端優先';
      case TaskRoutingRuleMode.askEveryTime:
        return '每次詢問';
    }
  }

  static TaskRoutingRuleMode fromName(String value) {
    for (final mode in TaskRoutingRuleMode.values) {
      if (mode.name == value) return mode;
    }
    return TaskRoutingRuleMode.auto;
  }
}
