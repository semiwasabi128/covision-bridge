// mixed_pendulum_detector.dart
// Sprint 3 — Layer 2: 擺錘偵測（混合策略）
// 規則版與 AI 版並跑，聯集合併，依 (type, evidence.normalize) 去重。
// 保留兩邊的 source 標籤，讓 panel 能用不同顏色標示。

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../pendulum_detector_rule.dart';
import '../pendulum_detector_ai.dart';

class MixedPendulumDetector
    extends BrainLayerAnalyzer<String, List<PendulumSignal>> {
  final PendulumDetectorRule _rule = PendulumDetectorRule();
  final PipelineLLMClient llmClient;

  MixedPendulumDetector(this.llmClient);

  @override
  String get layerName => 'Pendulum Detector (Mixed)';

  @override
  int get layerIndex => 2;

  @override
  Future<LayerResult<List<PendulumSignal>>> analyze(
    String input,
    PipelineContext context,
  ) async {
    // 1. 同時跑規則版和 AI 版
    final ruleFuture = _rule.analyze(input, context);

    // AI 版需要 LLM client，如果不可用就只回規則版
    if (!llmClient.isAvailable) {
      return ruleFuture;
    }

    final aiAnalyzer = PendulumDetectorAI(llmClient);
    final results = await Future.wait([
      ruleFuture,
      aiAnalyzer.analyze(input, context),
    ]);

    final ruleResult = results[0];
    final aiResult = results[1];

    // 2. 聯集合併，依 dedupKey 去重
    final seen = <String>{};
    final merged = <PendulumSignal>[];

    // 規則版先放（保留 ruleMatch source）
    for (final signal in ruleResult.value) {
      if (seen.add(signal.dedupKey)) {
        merged.add(signal);
      }
    }

    // AI 版後放（保留 aiInferred source），去重
    for (final signal in aiResult.value) {
      if (seen.add(signal.dedupKey)) {
        merged.add(signal);
      }
    }

    return LayerResult<List<PendulumSignal>>(
      value: merged,
      source: LayerSource.mixed,
      confidence: 0.85,
      evidence: merged.isEmpty
          ? '無擺錘訊號 (rule+ai)'
          : 'rule=${ruleResult.value.length}, ai=${aiResult.value.length}, merged=${merged.length}',
      latencyMs: ruleResult.latencyMs + aiResult.latencyMs,
    );
  }
}
