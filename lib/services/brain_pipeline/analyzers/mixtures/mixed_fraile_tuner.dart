// mixed_fraile_tuner.dart
// Sprint 4 — Layer 5b: 頻率共振（混合策略）
// 規則版先跑，AI 版可用時覆蓋結果並攜帶 fraileEvidence。
// evidence 同時保留規則版的依據 + AI 版的趨勢說明。

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../fraile_tuner_rule.dart';
import '../fraile_tuner_ai.dart';

class MixedFraileTuner
    extends BrainLayerAnalyzer<String, FraileResonance> {
  final FraileTunerRule _rule = FraileTunerRule();
  final PipelineLLMClient llmClient;

  MixedFraileTuner(this.llmClient);

  @override
  String get layerName => 'Fraile Tuner (Mixed)';

  @override
  int get layerIndex => 5;

  @override
  Future<LayerResult<FraileResonance>> analyze(
    String input,
    PipelineContext context,
  ) async {
    // 1. 先跑規則版
    final ruleResult = await _rule.analyze(input, context);

    // 2. LLM 不可用 → 只回規則版
    if (!llmClient.isAvailable) {
      return ruleResult;
    }

    // 3. 跑 AI 版
    final aiAnalyzer = FraileTunerAI(llmClient);
    final aiResult = await aiAnalyzer.analyze(input, context);

    // 4. AI 結果覆蓋，evidence 合併，metadata 攜帶 fraileEvidence
    return LayerResult<FraileResonance>(
      value: aiResult.value,
      source: LayerSource.mixed,
      confidence: aiResult.confidence,
      evidence: 'rule: ${ruleResult.evidence} | ai: ${aiResult.evidence}',
      latencyMs: ruleResult.latencyMs + aiResult.latencyMs,
      metadata: aiResult.metadata,
    );
  }
}
