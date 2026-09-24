import '../models/bridge_action.dart';
import 'capability_health_service.dart';
import 'local_hardware_profile_store.dart';
import 'local_model_catalog_service.dart';
import 'local_task_routing_service.dart';
import 'task_routing_rule_store.dart';

enum BridgeActionExecutionMode {
  automatic,
  localFirst,
  cloudFirst,
  hybrid,
  askEveryTime,
  blocked,
}

enum BridgeActionExecutionOverride { none, automatic, localFirst, cloudFirst }

class BridgeActionExecutionDecision {
  final BridgeActionExecutionMode mode;
  final String taskId;
  final String label;
  final String primaryKey;
  final String backupKey;
  final String reason;
  final bool shouldAskUser;
  final bool canExecute;
  final BridgeActionExecutionOverride override;

  const BridgeActionExecutionDecision({
    required this.mode,
    required this.taskId,
    required this.label,
    required this.primaryKey,
    required this.backupKey,
    required this.reason,
    required this.shouldAskUser,
    required this.canExecute,
    this.override = BridgeActionExecutionOverride.none,
  });

  Map<String, Object?> toMetadata() {
    return {
      'mode': mode.name,
      'taskId': taskId,
      'label': label,
      'primaryKey': primaryKey,
      'backupKey': backupKey,
      'reason': reason,
      'shouldAskUser': shouldAskUser,
      'canExecute': canExecute,
      'override': override.name,
    };
  }
}

class BridgeActionExecutionDecisionService {
  const BridgeActionExecutionDecisionService({
    this.healthService,
    this.hardwareStore = const LocalHardwareProfileStore(),
    this.ruleStore = const TaskRoutingRuleStore(),
    this.localModelCatalog = const LocalModelCatalogService(),
    this.routingService = const LocalTaskRoutingService(),
  });

  final CapabilityHealthService? healthService;
  final LocalHardwareProfileStore hardwareStore;
  final TaskRoutingRuleStore ruleStore;
  final LocalModelCatalogService localModelCatalog;
  final LocalTaskRoutingService routingService;

  Future<BridgeActionExecutionDecision> decide(
    BridgeAction action, {
    BridgeActionExecutionOverride override = BridgeActionExecutionOverride.none,
  }) async {
    final taskId = _taskIdFor(action);
    if (taskId == null) {
      return BridgeActionExecutionDecision(
        mode: BridgeActionExecutionMode.blocked,
        taskId: 'unsupported',
        label: action.displayType,
        primaryKey: '尚未接入',
        backupKey: '無',
        reason: '這個橋樑動作尚未接入任務分配規則。',
        shouldAskUser: false,
        canExecute: false,
        override: override,
      );
    }

    final hardware = await hardwareStore.load();
    final health = await (healthService ?? CapabilityHealthService()).inspect();
    final rules = Map<String, TaskRoutingRuleMode>.from(await ruleStore.load());
    _applyOneShotOverride(rules, taskId, override);
    final localModelPlan = localModelCatalog.buildPlan(hardware: hardware);
    final routingPlan = routingService.build(
      localModelPlan: localModelPlan,
      health: health,
      rules: rules,
    );
    final item = routingPlan.items.firstWhere(
      (candidate) => candidate.id == taskId,
      orElse: () => TaskRoutingItem(
        id: taskId,
        label: action.displayType,
        scenario: action.prompt,
        lane: TaskExecutionLane.setupRequired,
        primaryKey: '等待鑰匙',
        backupKey: '無',
        reason: '找不到對應任務路線。',
        ready: false,
      ),
    );

    return BridgeActionExecutionDecision(
      mode: _modeFor(item.lane),
      taskId: item.id,
      label: item.label,
      primaryKey: item.primaryKey,
      backupKey: item.backupKey,
      reason: item.reason,
      shouldAskUser: item.lane == TaskExecutionLane.askEveryTime,
      canExecute: item.ready && item.lane != TaskExecutionLane.setupRequired,
      override: override,
    );
  }

  void _applyOneShotOverride(
    Map<String, TaskRoutingRuleMode> rules,
    String taskId,
    BridgeActionExecutionOverride override,
  ) {
    switch (override) {
      case BridgeActionExecutionOverride.none:
        return;
      case BridgeActionExecutionOverride.automatic:
        rules.remove(taskId);
      case BridgeActionExecutionOverride.localFirst:
        rules[taskId] = TaskRoutingRuleMode.localFirst;
      case BridgeActionExecutionOverride.cloudFirst:
        rules[taskId] = TaskRoutingRuleMode.cloudFirst;
    }
  }

  String? _taskIdFor(BridgeAction action) {
    switch (action.type) {
      case BridgeActionType.generateImage:
        return 'creative-image';
      case BridgeActionType.generateAnimation:
        return 'creative-animation';
      case BridgeActionType.document:
        return 'document-output';
      case BridgeActionType.desktopFiles:
        return null;
      case BridgeActionType.generateMusic:
      case BridgeActionType.generateVideo:
      case BridgeActionType.browse:
      case BridgeActionType.vision:
      case BridgeActionType.unknown:
        return null;
    }
  }

  BridgeActionExecutionMode _modeFor(TaskExecutionLane lane) {
    switch (lane) {
      case TaskExecutionLane.localFirst:
        return BridgeActionExecutionMode.localFirst;
      case TaskExecutionLane.cloudFirst:
        return BridgeActionExecutionMode.cloudFirst;
      case TaskExecutionLane.hybrid:
        return BridgeActionExecutionMode.hybrid;
      case TaskExecutionLane.askEveryTime:
        return BridgeActionExecutionMode.askEveryTime;
      case TaskExecutionLane.setupRequired:
        return BridgeActionExecutionMode.blocked;
    }
  }
}
