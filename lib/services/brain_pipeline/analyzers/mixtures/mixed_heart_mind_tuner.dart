// mixed_heart_mind_tuner.dart
// Sprint 4 — Layer 5a: 心腦合一（混合策略）
// 規則版先跑，AI 版可用時覆蓋結果並攜帶 mindStatement/heartStatement/splitMarker/integrationPrompt。
// evidence 同時保留規則版的判斷依據 + AI 版的抽取結果。

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../heart_mind_tuner_rule.dart';
import '../heart_mind_tuner_ai.dart';

class MixedHeartMindTuner
    extends BrainLayerAnalyzer<String, HeartMindAlignment> {
  final HeartMindTunerRule _rule = HeartMindTunerRule();
  final PipelineLLMClient llmClient;

  MixedHeartMindTuner(this.llmClient);

  @override
  String get layerName => 'Heart-Mind Tuner (Mixed)';

  @override
  int get layerIndex => 4;

  @override
  Future<LayerResult<HeartMindAlignment>> analyze(
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
    final aiAnalyzer = HeartMindTunerAI(llmClient);
    final aiResult = await aiAnalyzer.analyze(input, context);

    // 4. AI 結果覆蓋，evidence 合併，metadata 攜帶 hint
    return LayerResult<HeartMindAlignment>(
      value: aiResult.value,
      source: LayerSource.mixed,
      confidence: aiResult.confidence,
      evidence: 'rule: ${ruleResult.evidence} | ai: ${aiResult.evidence}',
      latencyMs: ruleResult.latencyMs + aiResult.latencyMs,
      metadata: aiResult.metadata,
    );
  }
}
