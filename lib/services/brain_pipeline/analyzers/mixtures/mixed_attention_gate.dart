// mixed_attention_gate.dart
// Sprint 3 — Layer 1: 注意力閘門（混合策略）
// 規則版先跑，confidence < 0.6 或文字 > 80 字才叫 AI 版，AI 結果覆蓋。
// evidence 同時保留規則版的「命中字」+ AI 版的「語意解釋」。

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../attention_gate_rule.dart';
import '../attention_gate_ai.dart';

class MixedAttentionGate
    extends BrainLayerAnalyzer<String, AttentionState> {
  final AttentionGateRule _rule = AttentionGateRule();
  final PipelineLLMClient llmClient;

  MixedAttentionGate(this.llmClient);

  @override
  String get layerName => 'Attention Gate (Mixed)';

  @override
  int get layerIndex => 1;

  @override
  Future<LayerResult<AttentionState>> analyze(
    String input,
    PipelineContext context,
  ) async {
    // 1. 先跑規則版
    final ruleResult = await _rule.analyze(input, context);

    // 2. 判斷是否需要 AI
    final needsAi = ruleResult.confidence < 0.6 || input.length > 80;

    if (!needsAi || !llmClient.isAvailable) {
      return ruleResult;
    }

    // 3. 跑 AI 版
    final aiAnalyzer = AttentionGateAI(llmClient);
    final aiResult = await aiAnalyzer.analyze(input, context);

    // 4. AI 結果覆蓋，evidence 合併
    return LayerResult<AttentionState>(
      value: aiResult.value,
      source: LayerSource.mixed,
      confidence: aiResult.confidence,
      evidence: 'rule: ${ruleResult.evidence} | ai: ${aiResult.evidence}',
      latencyMs: ruleResult.latencyMs + aiResult.latencyMs,
    );
  }
}
