// mixed_importance_coordinator.dart
// Sprint 4 — Layer 4: 重要性協調（混合策略）
// 規則版先跑，AI 版可用時覆蓋結果並攜帶 humorHint。
// evidence 同時保留規則版的計分 + AI 版的語意解釋。

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../importance_coordinator_rule.dart';
import '../importance_coordinator_ai.dart';

class MixedImportanceCoordinator
    extends BrainLayerAnalyzer<String, ImportanceLevel> {
  final ImportanceCoordinatorRule _rule = ImportanceCoordinatorRule();
  final PipelineLLMClient llmClient;

  MixedImportanceCoordinator(this.llmClient);

  @override
  String get layerName => 'Importance Coordinator (Mixed)';

  @override
  int get layerIndex => 3;

  @override
  Future<LayerResult<ImportanceLevel>> analyze(
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
    final aiAnalyzer = ImportanceCoordinatorAI(llmClient);
    final aiResult = await aiAnalyzer.analyze(input, context);

    // 4. AI 結果覆蓋，evidence 合併，metadata 攜帶 humorHint
    return LayerResult<ImportanceLevel>(
      value: aiResult.value,
      source: LayerSource.mixed,
      confidence: aiResult.confidence,
      evidence: 'rule: ${ruleResult.evidence} | ai: ${aiResult.evidence}',
      latencyMs: ruleResult.latencyMs + aiResult.latencyMs,
      metadata: aiResult.metadata,
    );
  }
}
