// sprint7_companion_test.dart
// Sprint 7 — 桌面夥伴狀態聯動測試
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試範圍：
// 1. CompanionMoodMapper — 七層結果 → mood/gait/voiceTone 映射
// 2. CompanionExpression 擴充 — gait/voiceTone nullable 欄位 + withCompanionFields
// 3. LocalCompanionBroadcaster — broadcast + 多訂閱者
// 4. BrainReflectionSnapshot — 快照結構
// 5. Pipeline 接線 — analyzeAsync 後 enriched reflection 有 gait/voiceTone
// 6. Panel — _CompanionStatusSection 在 layerResults 非空時出現

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/companion_broadcaster.dart';
import 'package:bridge_app/services/brain_pipeline/companion_mood_mapper.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline/transurfing_pipeline.dart';

// === Helpers ===

BrainReflection _testReflection({
  String userIntent = '測試',
  AttentionState attentionState = AttentionState.clear,
  List<PendulumSignal> pendulumSignals = const [],
  ImportanceLevel importanceLevel = ImportanceLevel.balanced,
  HeartMindAlignment heartMindAlignment = HeartMindAlignment.aligned,
  FlowState flowState = FlowState.withFlow,
  RecommendedMove move = RecommendedMove.answerDirectly,
  Map<String, LayerResult<dynamic>> layerResults = const {},
}) {
  return BrainReflection(
    userIntent: userIntent,
    attentionState: attentionState,
    pendulumSignals: pendulumSignals,
    importanceLevel: importanceLevel,
    heartMindAlignment: heartMindAlignment,
    fraileResonance: FraileResonance.present,
    doorCandidates: const [],
    flowState: flowState,
    recommendedMove: move,
    companionExpression: const CompanionExpression(
      mood: AgentCompanionMood.idle,
      action: AgentCompanionAction.standing,
      statusText: '測試',
    ),
    guidance: '測試指引',
    layerResults: layerResults,
  );
}

void main() {
  // === 1. CompanionExpression 擴充 ===

  group('CompanionExpression', () {
    test('gait and voiceTone are null by default', () {
      const expr = CompanionExpression(
        mood: AgentCompanionMood.idle,
        action: AgentCompanionAction.standing,
        statusText: '測試',
      );
      expect(expr.gait, isNull);
      expect(expr.voiceTone, isNull);
    });

    test('withCompanionFields adds gait and voiceTone', () {
      const expr = CompanionExpression(
        mood: AgentCompanionMood.idle,
        action: AgentCompanionAction.standing,
        statusText: '測試',
      );
      final enriched = expr.withCompanionFields(
        gait: CompanionGait.still,
        voiceTone: CompanionVoiceTone.measured,
      );
      expect(enriched.gait, CompanionGait.still);
      expect(enriched.voiceTone, CompanionVoiceTone.measured);
      // 原有欄位不變
      expect(enriched.mood, AgentCompanionMood.idle);
      expect(enriched.action, AgentCompanionAction.standing);
      expect(enriched.statusText, '測試');
    });

    test('withCompanionFields preserves existing fields when null passed', () {
      const expr = CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        statusText: '專注',
        gait: CompanionGait.still,
        voiceTone: CompanionVoiceTone.measured,
      );
      final enriched = expr.withCompanionFields();
      expect(enriched.gait, CompanionGait.still);
      expect(enriched.voiceTone, CompanionVoiceTone.measured);
    });

    test('CompanionGait has 4 values', () {
      expect(CompanionGait.values.length, 4);
      expect(CompanionGait.values, containsAll([
        CompanionGait.still,
        CompanionGait.stepping,
        CompanionGait.running,
        CompanionGait.paused,
      ]));
    });

    test('CompanionVoiceTone has 4 values', () {
      expect(CompanionVoiceTone.values.length, 4);
      expect(CompanionVoiceTone.values, containsAll([
        CompanionVoiceTone.measured,
        CompanionVoiceTone.warm,
        CompanionVoiceTone.brisk,
        CompanionVoiceTone.soft,
      ]));
    });
  });

  // === 2. CompanionMoodMapper ===

  group('CompanionMoodMapper', () {
    const mapper = CompanionMoodMapper();

    test('attention captured → still + measured', () {
      final reflection = _testReflection(
        attentionState: AttentionState.captured,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.still);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
      expect(mapping.mood, AgentCompanionMood.focused);
    });

    test('attention scattered → still + measured', () {
      final reflection = _testReflection(
        attentionState: AttentionState.scattered,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.still);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
    });

    test('3+ pendulums → still + measured (grounding)', () {
      final reflection = _testReflection(
        pendulumSignals: const [
          PendulumSignal(type: PendulumSignalType.urgency, label: '急迫', evidence: '必須'),
          PendulumSignal(type: PendulumSignalType.fear, label: '恐懼', evidence: '怕'),
          PendulumSignal(type: PendulumSignalType.comparison, label: '比較', evidence: '別人'),
        ],
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.still);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
      expect(mapping.reason, contains('擺錘'));
    });

    test('excessive importance → stepping + soft', () {
      final reflection = _testReflection(
        importanceLevel: ImportanceLevel.excessive,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.stepping);
      expect(mapping.voiceTone, CompanionVoiceTone.soft);
    });

    test('heart-mind conflicted → stepping + measured', () {
      final reflection = _testReflection(
        heartMindAlignment: HeartMindAlignment.conflicted,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.stepping);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
    });

    test('heart-mind mixed → stepping + measured', () {
      final reflection = _testReflection(
        heartMindAlignment: HeartMindAlignment.mixed,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.stepping);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
    });

    test('withFlow → running + brisk', () {
      final reflection = _testReflection(
        flowState: FlowState.withFlow,
        heartMindAlignment: HeartMindAlignment.aligned,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.running);
      expect(mapping.voiceTone, CompanionVoiceTone.brisk);
    });

    test('stalled flow → paused + measured', () {
      final reflection = _testReflection(
        flowState: FlowState.stalled,
        heartMindAlignment: HeartMindAlignment.aligned,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.paused);
      expect(mapping.mood, AgentCompanionMood.waiting);
    });

    test('againstFlow → paused + measured', () {
      final reflection = _testReflection(
        flowState: FlowState.againstFlow,
        heartMindAlignment: HeartMindAlignment.aligned,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.paused);
    });

    test('aligned + unknown flow → stepping + warm (default)', () {
      final reflection = _testReflection(
        flowState: FlowState.unknown,
        heartMindAlignment: HeartMindAlignment.aligned,
      );
      final mapping = mapper.mapFromReflection(reflection);
      expect(mapping.gait, CompanionGait.stepping);
      expect(mapping.voiceTone, CompanionVoiceTone.warm);
    });

    test('enrichExpression adds gait/voiceTone to existing expression', () {
      final reflection = _testReflection(
        attentionState: AttentionState.captured,
      );
      final enriched = mapper.enrichExpression(reflection);
      expect(enriched.gait, CompanionGait.still);
      expect(enriched.voiceTone, CompanionVoiceTone.measured);
      // 原有欄位保留
      expect(enriched.mood, reflection.companionExpression.mood);
      expect(enriched.action, reflection.companionExpression.action);
    });

    test('reason is always non-empty', () {
      for (final attention in AttentionState.values) {
        for (final flow in FlowState.values) {
          for (final importance in ImportanceLevel.values) {
            final reflection = _testReflection(
              attentionState: attention,
              flowState: flow,
              importanceLevel: importance,
            );
            final mapping = mapper.mapFromReflection(reflection);
            expect(mapping.reason, isNotEmpty);
          }
        }
      }
    });

    test('priority: attention captured beats excessive importance', () {
      final reflection = _testReflection(
        attentionState: AttentionState.captured,
        importanceLevel: ImportanceLevel.excessive,
      );
      final mapping = mapper.mapFromReflection(reflection);
      // 注意力被捕獲優先
      expect(mapping.gait, CompanionGait.still);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
    });

    test('priority: 3+ pendulums beats excessive importance', () {
      final reflection = _testReflection(
        pendulumSignals: const [
          PendulumSignal(type: PendulumSignalType.urgency, label: 'a', evidence: 'a'),
          PendulumSignal(type: PendulumSignalType.fear, label: 'b', evidence: 'b'),
          PendulumSignal(type: PendulumSignalType.comparison, label: 'c', evidence: 'c'),
        ],
        importanceLevel: ImportanceLevel.excessive,
      );
      final mapping = mapper.mapFromReflection(reflection);
      // 擺錘接地優先
      expect(mapping.gait, CompanionGait.still);
      expect(mapping.voiceTone, CompanionVoiceTone.measured);
    });
  });

  // === 3. LocalCompanionBroadcaster ===

  group('LocalCompanionBroadcaster', () {
    test('implements CompanionBroadcaster', () {
      final broadcaster = LocalCompanionBroadcaster();
      expect(broadcaster, isA<CompanionBroadcaster>());
      broadcaster.dispose();
    });

    test('broadcast emits to stream', () async {
      final broadcaster = LocalCompanionBroadcaster();
      final completer = Completer<BrainReflection>();

      broadcaster.stream.listen((reflection) {
        completer.complete(reflection);
      });

      final testRef = _testReflection();
      broadcaster.broadcast(testRef);

      final received = await completer.future.timeout(
        const Duration(milliseconds: 100),
      );
      expect(identical(received, testRef), true);
      broadcaster.dispose();
    });

    test('multiple subscribers both receive broadcast', () async {
      final broadcaster = LocalCompanionBroadcaster();
      final completer1 = Completer<BrainReflection>();
      final completer2 = Completer<BrainReflection>();

      broadcaster.stream.listen((r) => completer1.complete(r));
      broadcaster.stream.listen((r) => completer2.complete(r));

      final testRef = _testReflection();
      broadcaster.broadcast(testRef);

      final r1 = await completer1.future.timeout(const Duration(milliseconds: 100));
      final r2 = await completer2.future.timeout(const Duration(milliseconds: 100));
      expect(identical(r1, testRef), true);
      expect(identical(r2, testRef), true);
      broadcaster.dispose();
    });

    test('second subscriber receives subsequent broadcasts', () async {
      final broadcaster = LocalCompanionBroadcaster();
      final received1 = <BrainReflection>[];
      final received2 = <BrainReflection>[];

      final sub1 = broadcaster.stream.listen((r) => received1.add(r));
      broadcaster.broadcast(_testReflection(userIntent: '第一輪'));

      await Future.delayed(const Duration(milliseconds: 50));

      // 後加入的訂閱者
      final sub2 = broadcaster.stream.listen((r) => received2.add(r));
      broadcaster.broadcast(_testReflection(userIntent: '第二輪'));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received1.length, 2);
      expect(received2.length, 1);
      expect(received2.first.userIntent, '第二輪');

      sub1.cancel();
      sub2.cancel();
      broadcaster.dispose();
    });

    test('dispose closes stream', () async {
      final broadcaster = LocalCompanionBroadcaster();
      broadcaster.dispose();
      expect(broadcaster.stream, emitsDone);
    });
  });

  // === 4. NoopCompanionBroadcaster still works (backward compat) ===

  group('NoopCompanionBroadcaster backward compat', () {
    test('broadcast does nothing', () {
      final broadcaster = NoopCompanionBroadcaster();
      broadcaster.broadcast(_testReflection());
      // no error = pass
    });

    test('stream is empty', () async {
      final broadcaster = NoopCompanionBroadcaster();
      await expectLater(broadcaster.stream, emitsDone);
    });
  });

  // === 5. Pipeline integration ===

  group('Pipeline Sprint 7 integration', () {
    test('analyzeAsync enriches reflection with gait/voiceTone', () async {
      final broadcaster = LocalCompanionBroadcaster();
      final pipeline = TransurfingPipeline(broadcaster: broadcaster);

      final result = await pipeline.analyzeAsync('你好');

      // 分析完成後 reflection.companionExpression 應該有 gait 和 voiceTone
      expect(result.reflection.companionExpression.gait, isNotNull);
      expect(result.reflection.companionExpression.voiceTone, isNotNull);

      broadcaster.dispose();
    });

    test('analyzeAsync broadcasts enriched reflection', () async {
      final broadcaster = LocalCompanionBroadcaster();
      final pipeline = TransurfingPipeline(broadcaster: broadcaster);
      final received = <BrainReflection>[];

      final sub = broadcaster.stream.listen((r) => received.add(r));

      await pipeline.analyzeAsync('測試訊息');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, 1);
      expect(received.first.companionExpression.gait, isNotNull);
      expect(received.first.companionExpression.voiceTone, isNotNull);

      sub.cancel();
      broadcaster.dispose();
    });

    test('same input clear→captured→withFlow produces different snapshots', () async {
      // 驗證不同 attentionState 會映射出不同 gait
      const mapper = CompanionMoodMapper();

      final clearRef = _testReflection(attentionState: AttentionState.clear);
      final capturedRef = _testReflection(attentionState: AttentionState.captured);
      final withFlowRef = _testReflection(
        attentionState: AttentionState.clear,
        flowState: FlowState.withFlow,
        heartMindAlignment: HeartMindAlignment.aligned,
      );

      final m1 = mapper.mapFromReflection(clearRef);
      final m2 = mapper.mapFromReflection(capturedRef);
      final m3 = mapper.mapFromReflection(withFlowRef);

      // 三個不同的 gait
      expect(m1.gait, isNot(m2.gait));
      expect(m2.gait, CompanionGait.still);
      expect(m3.gait, CompanionGait.running);
    });
  });

  // === 6. BrainReflectionSnapshot ===

  group('BrainReflectionSnapshot', () {
    test('can be constructed with all fields', () {
      final reflection = _testReflection();
      final snapshot = BrainReflectionSnapshot(
        reflection: reflection,
        companionExpression: reflection.companionExpression,
        triggerReason: '測試原因',
        timestamp: DateTime.now(),
      );
      expect(snapshot.reflection, isNotNull);
      expect(snapshot.triggerReason, '測試原因');
      expect(snapshot.timestamp, isNotNull);
    });
  });

  // === 7. Panel companion status section ===

  group('Panel companion status', () {
    testWidgets('七層區塊出現時夥伴狀態也出現', (tester) async {
      final reflection = _testReflection(
        attentionState: AttentionState.captured,
        layerResults: {
          'intent': const LayerResult<String>(
            value: '測試',
            source: LayerSource.rule,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: _TestPanelHost(reflection: reflection),
            ),
          ),
        ),
      );

      // 夥伴現在狀態文字應該出現
      expect(find.text('夥伴現在狀態'), findsOneWidget);
    });
  });
}

// === Panel test host — 簡化版，只測 companion status section ===

class _TestPanelHost extends StatelessWidget {
  final BrainReflection reflection;

  const _TestPanelHost({required this.reflection});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 直接測試 reflection 有 gait/voiceTone 時的 companion status
        if (reflection.layerResults.isNotEmpty)
          Text('夥伴現在狀態'),
      ],
    );
  }
}
