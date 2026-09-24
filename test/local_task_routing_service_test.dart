import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/services/capability_health_service.dart';
import 'package:bridge_app/services/local_model_catalog_service.dart';
import 'package:bridge_app/services/local_task_routing_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = LocalTaskRoutingService();
  const catalog = LocalModelCatalogService();

  test('routes to cloud when only brain and creative keys are ready', () {
    final plan = service.build(
      localModelPlan: catalog.buildPlan(),
      health: const [
        CapabilityHealthItem(
          type: BridgeActionType.unknown,
          label: '聊天',
          status: CapabilityHealthStatus.ready,
          providerLabel: 'Kimi',
          detail: 'ready',
        ),
        CapabilityHealthItem(
          type: BridgeActionType.generateImage,
          label: '生成圖片',
          status: CapabilityHealthStatus.ready,
          providerLabel: 'OpenAI Images',
          detail: 'ready',
        ),
      ],
    );

    final privateDraft = plan.items.firstWhere(
      (item) => item.id == 'private-draft',
    );
    final creative = plan.items.firstWhere(
      (item) => item.id == 'creative-image',
    );

    expect(privateDraft.lane, TaskExecutionLane.cloudFirst);
    expect(privateDraft.primaryKey, '主腦鑰匙');
    expect(creative.lane, TaskExecutionLane.cloudFirst);
    expect(plan.summary, contains('雲端路線'));
  });

  test('routes sensitive work to local model when desktop fit exists', () {
    final localPlan = catalog.buildPlan(
      hardware: const LocalHardwareProfile(
        source: 'test',
        ramGb: 32,
        vramGb: 8,
        chipLabel: 'Test Mac · 32GB',
        desktopConnected: true,
      ),
    );
    final plan = service.build(
      localModelPlan: localPlan,
      health: const [
        CapabilityHealthItem(
          type: BridgeActionType.unknown,
          label: '聊天',
          status: CapabilityHealthStatus.ready,
          providerLabel: 'Kimi',
          detail: 'ready',
        ),
      ],
    );

    final privateDraft = plan.items.firstWhere(
      (item) => item.id == 'private-draft',
    );
    final quickChat = plan.items.firstWhere((item) => item.id == 'quick-chat');

    expect(privateDraft.lane, TaskExecutionLane.localFirst);
    expect(privateDraft.primaryKey, contains('本地模型'));
    expect(quickChat.lane, TaskExecutionLane.hybrid);
    expect(plan.hasLocalRoute, isTrue);
    expect(plan.summary, contains('本地模型分擔'));
  });

  test('marks routes as setup required when no key is ready', () {
    final plan = service.build(
      localModelPlan: catalog.buildPlan(),
      health: const [],
    );

    expect(plan.readyCount, 0);
    expect(
      plan.items.every((item) => item.lane == TaskExecutionLane.setupRequired),
      isTrue,
    );
    expect(plan.summary, contains('尚未設定鑰匙'));
  });

  test('applies manual ask every time rule to ready routes', () {
    final plan = service.build(
      localModelPlan: catalog.buildPlan(),
      health: const [
        CapabilityHealthItem(
          type: BridgeActionType.unknown,
          label: '聊天',
          status: CapabilityHealthStatus.ready,
          providerLabel: 'Kimi',
          detail: 'ready',
        ),
      ],
      rules: const {'private-draft': TaskRoutingRuleMode.askEveryTime},
    );

    final privateDraft = plan.items.firstWhere(
      (item) => item.id == 'private-draft',
    );

    expect(privateDraft.lane, TaskExecutionLane.askEveryTime);
    expect(privateDraft.primaryKey, '每次詢問');
    expect(privateDraft.ruleMode, TaskRoutingRuleMode.askEveryTime);
  });

  test('manual local first waits for local model when unavailable', () {
    final plan = service.build(
      localModelPlan: catalog.buildPlan(),
      health: const [
        CapabilityHealthItem(
          type: BridgeActionType.unknown,
          label: '聊天',
          status: CapabilityHealthStatus.ready,
          providerLabel: 'Kimi',
          detail: 'ready',
        ),
      ],
      rules: const {'private-draft': TaskRoutingRuleMode.localFirst},
    );

    final privateDraft = plan.items.firstWhere(
      (item) => item.id == 'private-draft',
    );

    expect(privateDraft.lane, TaskExecutionLane.setupRequired);
    expect(privateDraft.primaryKey, '等待本地模型');
    expect(privateDraft.ready, isFalse);
  });
}
