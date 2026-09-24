import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/services/agent_activity_store.dart';
import 'package:bridge_app/services/companion_runtime_outlet.dart';
import 'package:bridge_app/services/companion_runtime_store.dart';
import 'package:bridge_app/services/js_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CompanionRuntimeOutlet.instance.resetForTest();
    AgentActivityStore.instance.resetForTest();
    CompanionRuntimeStore.instance.resetForTest();
    JsBridge.instance.appState.value = {'screen': 'unknown', 'ready': false};
  });

  tearDown(() {
    CompanionRuntimeOutlet.instance.resetForTest();
    AgentActivityStore.instance.resetForTest();
    CompanionRuntimeStore.instance.resetForTest();
  });

  test('runtime outlet publishes initial bridge desktop payload', () {
    CompanionRuntimeOutlet.instance.start();

    final payload =
        JsBridge.instance.appState.value['companionRuntime']
            as Map<String, dynamic>;

    expect(payload['schema'], CompanionRuntimeOutlet.schema);
    expect(payload['source'], CompanionRuntimeOutlet.source);
    expect(payload['exportedAt'], isA<String>());
    expect(payload['runtime']['activeCompanionName'], '你的 Agent');
    expect(payload['runtime']['statusText'], '自由待機');
    expect(payload['runtime']['activity']['active'], isFalse);
  });

  test('runtime outlet republishes companion and activity changes', () {
    CompanionRuntimeOutlet.instance.start();

    CompanionRuntimeStore.instance.setActiveCompanion(
      Companion(
        id: 'cmp_desktop',
        name: '博士',
        mbtiCode: 'INTJ',
        role: CompanionRole.research,
      ),
    );
    AgentActivityStore.instance.update(
      stage: AgentActivityStage.context,
      telemetry: const AgentActivityTelemetry(messages: 2, tokens: 320),
      pulse: true,
    );

    final payload =
        JsBridge.instance.appState.value['companionRuntime']
            as Map<String, dynamic>;
    final runtime = payload['runtime'] as Map<String, dynamic>;
    final activity = runtime['activity'] as Map<String, dynamic>;

    expect(runtime['activeCompanionId'], 'cmp_desktop');
    expect(runtime['activeCompanionName'], '博士');
    expect(runtime['activeCompanionRole'], '研究夥伴');
    expect(runtime['statusText'], '正在整理上下文');
    expect(activity['stage'], '上下文');
    expect(activity['mood'], 'focused');
    expect(activity['action'], 'reading');
    expect(activity['telemetry']['tokens'], 320);
  });

  test('runtime outlet publishes bridge execution evidence', () {
    CompanionRuntimeOutlet.instance.start();

    CompanionRuntimeStore.instance.reportBridgeEvidence(
      summary: '執行證據：決策 雲端優先；實際 provider fake',
      completed: true,
    );

    final payload =
        JsBridge.instance.appState.value['companionRuntime']
            as Map<String, dynamic>;
    final runtime = payload['runtime'] as Map<String, dynamic>;
    final evidence = runtime['latestBridgeEvidence'] as Map<String, dynamic>;

    expect(runtime['statusText'], '我剛剛替你完成了一次橋樑任務。');
    expect(evidence['status'], 'completed');
    expect(evidence['reply'], '我剛剛替你完成了一次橋樑任務。');
    expect(evidence['summary'], contains('雲端優先'));
  });
}
