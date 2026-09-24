import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/models/companion_runtime.dart';
import 'package:bridge_app/services/agent_activity_store.dart';
import 'package:bridge_app/services/companion_runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AgentActivityStore.instance.resetForTest();
    CompanionRuntimeStore.instance.resetForTest();
  });

  tearDown(() {
    AgentActivityStore.instance.resetForTest();
    CompanionRuntimeStore.instance.resetForTest();
  });

  test('runtime tracks active companion identity', () {
    final store = CompanionRuntimeStore.instance;
    final companion = Companion(
      id: 'cmp_runtime',
      name: '霧橋',
      mbtiCode: 'INFJ',
      role: CompanionRole.research,
    );

    store.setActiveCompanion(companion);

    expect(store.current.activeCompanionId, 'cmp_runtime');
    expect(store.current.activeCompanionName, '霧橋');
    expect(store.current.activeCompanionRole, '研究夥伴');
  });

  test('runtime mirrors agent activity updates', () {
    final activityStore = AgentActivityStore.instance;
    final runtime = CompanionRuntimeStore.instance;

    activityStore.update(
      stage: AgentActivityStage.bridge,
      pulse: true,
      telemetry: const AgentActivityTelemetry(
        messages: 4,
        bridgeActions: 2,
        tokens: 900,
      ),
    );

    expect(runtime.current.activity.stage, AgentActivityStage.bridge);
    expect(runtime.current.activity.mood, AgentCompanionMood.bridging);
    expect(runtime.current.activity.action, AgentCompanionAction.spinning);
    expect(runtime.current.statusText, '正在執行橋樑能力');
    expect(runtime.current.toJson()['activity']['telemetry']['tokens'], 900);

    activityStore.idle();
    expect(runtime.current.statusText, '自由待機');
    expect(runtime.current.activity.active, isFalse);
  });

  test('runtime carries first action card for post-summon handoff', () {
    final store = CompanionRuntimeStore.instance;

    store.setFirstAction(
      const CompanionFirstAction(
        title: '讓我接住你的第一件事',
        detail: '先釐清目標，再替你拆成可執行步驟。',
        prompt: '幫我整理第一件事',
        ctaLabel: '開始第一件事',
      ),
    );

    expect(store.current.firstAction?.title, '讓我接住你的第一件事');
    expect(store.current.toJson()['firstAction']['prompt'], '幫我整理第一件事');

    store.clearFirstAction();

    expect(store.current.firstAction, isNull);
    expect(store.current.toJson()['firstAction'], isNull);
  });

  test('runtime carries latest bridge execution evidence', () {
    final store = CompanionRuntimeStore.instance;

    store.reportBridgeEvidence(
      summary: '執行證據：本次選擇 雲端 / 主路線 創造鑰匙；實際 provider fake',
      completed: true,
    );

    final evidence = store.current.latestBridgeEvidence;
    final json = store.current.toJson();

    expect(evidence?.status, 'completed');
    expect(evidence?.reply, '我剛剛替你完成了一次橋樑任務。');
    expect(store.current.statusText, '我剛剛替你完成了一次橋樑任務。');
    expect(json['latestBridgeEvidence']['status'], 'completed');
    expect(json['latestBridgeEvidence']['summary'], contains('本次選擇 雲端'));
    expect(store.current.activity.mood, AgentCompanionMood.proud);
    expect(store.current.activity.action, AgentCompanionAction.bouncing);
  });

  test('runtime carries local model runtime signal', () {
    final store = CompanionRuntimeStore.instance;

    store.reportLocalRuntimeSignal(
      phase: 'downloading',
      title: 'Bridge Local Runtime',
      detail: '平衡 7B 指令模型下載任務已建立。',
      label: '下載中',
      progress: 0.42,
    );

    final signal = store.current.latestLocalRuntimeSignal;
    final json = store.current.toJson();

    expect(signal?.phase, 'downloading');
    expect(signal?.progress, 0.42);
    expect(store.current.statusText, '我正在替你準備本地主腦 42%。');
    expect(store.current.activity.active, isTrue);
    expect(store.current.activity.mood, AgentCompanionMood.bridging);
    expect(store.current.activity.action, AgentCompanionAction.spinning);
    expect(json['latestLocalRuntimeSignal']['phase'], 'downloading');
    expect(json['latestLocalRuntimeSignal']['detail'], contains('7B'));
  });
}
