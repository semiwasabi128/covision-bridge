// sprint0_smoke_test.dart
// Sprint 0 驗證測試 — 確認所有介面可編譯、可實例化、可呼叫
// 建立日期: 2026-07-04 by 小葵 (CEO)

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/analyzer_config.dart';
import 'package:bridge_app/services/brain_pipeline/brain_layer_analyzer.dart';
import 'package:bridge_app/services/brain_pipeline/brain_container.dart';
import 'package:bridge_app/services/brain_pipeline/companion_broadcaster.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_result.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/models/agent_activity.dart';

/// 測試用的 stub analyzer——證明 BrainLayerAnalyzer 介面可被實作。
class _StubAnalyzer extends BrainLayerAnalyzer<String, String> {
  @override
  String get layerName => 'Stub Analyzer';

  @override
  int get layerIndex => 0;

  @override
  Future<LayerResult<String>> analyze(String input, PipelineContext context) async {
    return LayerResult<String>(
      value: 'stubbed: $input',
      source: LayerSource.rule,
      confidence: 0.5,
      evidence: 'stub evidence',
      latencyMs: 1,
    );
  }
}

/// 產生一個最小的 BrainReflection 供測試使用。
BrainReflection _dummyReflection() {
  return const BrainReflection(
    userIntent: 'dummy',
    attentionState: AttentionState.clear,
    pendulumSignals: [],
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: HeartMindAlignment.unknown,
    fraileResonance: FraileResonance.weak,
    doorCandidates: [],
    flowState: FlowState.unknown,
    recommendedMove: RecommendedMove.answerDirectly,
    companionExpression: CompanionExpression(
      mood: AgentCompanionMood.curious,
      action: AgentCompanionAction.pointing,
      statusText: 'dummy',
    ),
    guidance: 'dummy',
  );
}

void main() {
  group('LayerResult', () {
    test('can be constructed with all fields', () {
      const result = LayerResult<String>(
        value: 'test',
        source: LayerSource.ai,
        confidence: 0.85,
        evidence: 'LLM said so',
        latencyMs: 120,
      );
      expect(result.value, 'test');
      expect(result.source, LayerSource.ai);
      expect(result.confidence, 0.85);
      expect(result.evidence, 'LLM said so');
      expect(result.latencyMs, 120);
    });

    test('defaults are sensible', () {
      const result = LayerResult<int>(value: 42, source: LayerSource.rule);
      expect(result.confidence, 1.0);
      expect(result.evidence, '');
      expect(result.latencyMs, 0);
    });
  });

  group('AnalyzerConfig', () {
    test('default config has AI disabled', () {
      const config = AnalyzerConfig();
      expect(config.globalAiEnabled, false);
      expect(config.aiTimeoutMs, 3000);
      expect(config.aiMinConfidenceForOverride, 0.6);
    });

    test('kindForLayer defaults to auto', () {
      const config = AnalyzerConfig();
      expect(config.kindForLayer(0), AnalyzerKind.auto);
      expect(config.kindForLayer(6), AnalyzerKind.auto);
    });

    test('layerOverrides are respected', () {
      const config = AnalyzerConfig(
        layerOverrides: {2: AnalyzerKind.ai, 5: AnalyzerKind.rule},
      );
      expect(config.kindForLayer(2), AnalyzerKind.ai);
      expect(config.kindForLayer(5), AnalyzerKind.rule);
      expect(config.kindForLayer(0), AnalyzerKind.auto);
    });

    test('copyWith works', () {
      const original = AnalyzerConfig();
      final modified = original.copyWith(
        globalAiEnabled: true,
        layerOverrides: const {0: AnalyzerKind.ai},
      );
      expect(modified.globalAiEnabled, true);
      expect(original.globalAiEnabled, false);
    });
  });

  group('PipelineContext', () {
    test('can be constructed with defaults', () {
      const ctx = PipelineContext();
      expect(ctx.recentMemories, isEmpty);
      expect(ctx.activeCompanionRole, isNull);
      expect(ctx.priorLayers, isEmpty);
    });

    test('copyWithPriorLayer returns new context with layer added', () {
      const ctx = PipelineContext();
      const result = LayerResult<String>(
        value: 'intent',
        source: LayerSource.rule,
      );
      final ctx2 = ctx.copyWithPriorLayer(0, result);
      expect(ctx.priorLayers, isEmpty);
      expect(ctx2.priorLayers.length, 1);
      expect(ctx2.priorLayers[0]?.value, 'intent');
    });

    test('priorLayers accumulate across multiple layers', () {
      var ctx = const PipelineContext();
      ctx = ctx.copyWithPriorLayer(
        0,
        const LayerResult<String>(value: 'a', source: LayerSource.rule),
      );
      ctx = ctx.copyWithPriorLayer(
        1,
        const LayerResult<String>(value: 'b', source: LayerSource.rule),
      );
      expect(ctx.priorLayers.length, 2);
    });
  });

  group('BrainLayerAnalyzer', () {
    test('stub analyzer implements interface correctly', () async {
      final analyzer = _StubAnalyzer();
      expect(analyzer.layerName, 'Stub Analyzer');
      expect(analyzer.layerIndex, 0);

      const ctx = PipelineContext();
      final result = await analyzer.analyze('hello', ctx);
      expect(result.value, 'stubbed: hello');
      expect(result.source, LayerSource.rule);
      expect(result.confidence, 0.5);
    });
  });

  group('BrainContainer interface', () {
    test('BrainContainerServiceAdapter can be instantiated', () {
      final adapter = BrainContainerServiceAdapter();
      expect(adapter, isA<BrainContainer>());
    });
  });

  group('CompanionBroadcaster', () {
    test('NoopCompanionBroadcaster implements interface', () {
      final broadcaster = NoopCompanionBroadcaster();
      expect(broadcaster, isA<CompanionBroadcaster>());
    });

    test('NoopCompanionBroadcaster broadcast does nothing', () {
      final broadcaster = NoopCompanionBroadcaster();
      broadcaster.broadcast(_dummyReflection());
    });

    test('NoopCompanionBroadcaster stream is empty', () async {
      final broadcaster = NoopCompanionBroadcaster();
      // Stream.empty() never emits — just verify it doesn't throw
      final completer = Completer<void>();
      broadcaster.stream.listen(
        (_) => completer.complete(),
        onError: (_) => completer.completeError('should not error'),
      );
      // Give it 100ms then confirm no events
      Future.delayed(const Duration(milliseconds: 100), completer.complete);
      await completer.future;
    });
  });

  group('PipelineResult', () {
    test('can be constructed with defaults', () {
      final result = PipelineResult(reflection: _dummyReflection());
      expect(result.layerResults, isEmpty);
      expect(result.totalLatencyMs, 0);
      expect(result.source, PipelineSource.allRule);
    });

    test('can hold layer results', () {
      final result = PipelineResult(
        reflection: _dummyReflection(),
        layerResults: {
          'intent': const LayerResult<String>(
            value: 'goal',
            source: LayerSource.rule,
          ),
          'attention': const LayerResult<String>(
            value: 'clear',
            source: LayerSource.rule,
          ),
        },
        totalLatencyMs: 45,
        source: PipelineSource.allRule,
      );
      expect(result.layerResults.length, 2);
      expect(result.layerResults['intent']?.value, 'goal');
    });
  });

  group('BrainReflection layerResults field', () {
    test('BrainReflection accepts layerResults', () {
      final reflection = BrainReflection(
        userIntent: 'test',
        attentionState: AttentionState.clear,
        pendulumSignals: const [],
        importanceLevel: ImportanceLevel.balanced,
        heartMindAlignment: HeartMindAlignment.unknown,
        fraileResonance: FraileResonance.weak,
        doorCandidates: const [],
        flowState: FlowState.unknown,
        recommendedMove: RecommendedMove.answerDirectly,
        companionExpression: const CompanionExpression(
          mood: AgentCompanionMood.curious,
          action: AgentCompanionAction.pointing,
          statusText: 'test',
        ),
        guidance: 'test',
        layerResults: {
          'intent': const LayerResult<String>(
            value: 'goal',
            source: LayerSource.rule,
          ),
        },
      );
      expect(reflection.layerResults.length, 1);
    });

    test('BrainReflection defaults layerResults to empty', () {
      const reflection = BrainReflection(
        userIntent: 'test',
        attentionState: AttentionState.clear,
        pendulumSignals: [],
        importanceLevel: ImportanceLevel.balanced,
        heartMindAlignment: HeartMindAlignment.unknown,
        fraileResonance: FraileResonance.weak,
        doorCandidates: [],
        flowState: FlowState.unknown,
        recommendedMove: RecommendedMove.answerDirectly,
        companionExpression: CompanionExpression(
          mood: AgentCompanionMood.curious,
          action: AgentCompanionAction.pointing,
          statusText: 'test',
        ),
        guidance: 'test',
      );
      expect(reflection.layerResults, isEmpty);
    });
  });
}
