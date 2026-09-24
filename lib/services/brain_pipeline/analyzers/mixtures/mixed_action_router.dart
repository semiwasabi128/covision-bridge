// mixed_action_router.dart
// Sprint 2 — Layer 7 混合策略器（覆蓋模式 + metadata）
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 策略：
// 1. 規則版先跑（保證有結果）
// 2. 只在 user 訊息含「宣告/確認/我要做/從今天起」等觸發詞時才跑 AI 版
// 3. AI 結果覆蓋規則版的 move
// 4. evidence 合併（rule: ... | ai: ...）
// 5. metadata 從 AI 版帶 intentionText
//
// 這跟 S4 的「覆蓋+metadata 模式」一致，但觸發條件更嚴格——
// 只在宣告/確認/完成觸發詞命中時才叫 LLM，省 token。

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../../text_utils.dart';
import '../action_router_rule.dart';
import '../action_router_ai.dart';

/// 宣告/確認/完成觸發詞——只有命中這些詞時才啟用 AI 版
const _aiTriggers = [
  '宣告',
  '我要做',
  '我打算',
  '從今天起',
  '從現在起',
  '我決定',
  '我承諾',
  '我立志',
  '定目標',
  '確認',
  '做完',
  '已執行',
  '完成',
  '搞定了',
  '做完了',
  '已完成',
  'done',
  'finished',
];

/// Layer 7 混合策略器。
///
/// 規則版先跑 → 命中觸發詞時跑 AI 版 → AI 覆蓋 move。
class MixedActionRouter
    extends BrainLayerAnalyzer<String, ActionRouterResult> {
  final PipelineLLMClient _llmClient;

  MixedActionRouter(this._llmClient);

  @override
  String get layerName => 'Action Router (Mixed)';

  @override
  int get layerIndex => 7;

  @override
  Future<LayerResult<ActionRouterResult>> analyze(
    String input,
    PipelineContext context,
  ) async {
    // 1. 規則版先跑（保證有結果）
    final ruleAnalyzer = ActionRouterRule();
    final ruleResult = await ruleAnalyzer.analyze(input, context);

    // 2. 如果 LLM 不可用，直接回規則版
    if (!_llmClient.isAvailable) {
      return ruleResult;
    }

    // 3. 只在命中觸發詞時才跑 AI 版（省 token）
    final text = normalize(input);
    if (!containsAny(text, _aiTriggers)) {
      return ruleResult;
    }

    // 4. 跑 AI 版
    final aiAnalyzer = ActionRouterAI(_llmClient);
    final aiResult = await aiAnalyzer.analyze(input, context);

    // 5. 如果 AI fallback 到 rule（LLM 失敗），直接回 rule 版
    if (aiResult.source == LayerSource.rule) {
      return ruleResult;
    }

    // 6. AI 覆蓋 move，保留規則版的 expression/guidance 作為基底
    final aiValue = aiResult.value;
    final ruleValue = ruleResult.value;

    // 只有 declareIntention 和 recordWaterAction 才覆蓋 move
    // 其他情況保留規則版的 move（規則版已經很準了）
    final finalMove = (aiValue.move == RecommendedMove.declareIntention ||
            aiValue.move == RecommendedMove.recordWaterAction)
        ? aiValue.move
        : ruleValue.move;

    return LayerResult<ActionRouterResult>(
      value: ActionRouterResult(
        move: finalMove,
        expression: aiValue.expression,
        guidance: aiValue.guidance,
      ),
      source: finalMove != ruleValue.move
          ? LayerSource.mixed
          : LayerSource.rule,
      confidence: 0.85,
      evidence: 'rule: ${ruleResult.evidence} | ai: ${aiResult.evidence}',
      metadata: aiResult.metadata,
    );
  }
}
