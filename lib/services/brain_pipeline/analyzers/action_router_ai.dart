// action_router_ai.dart
// Sprint 2 — Layer 7: 動作路由（AI 版）
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 送給 LLM 的 prompt 包含前六層 LayerResult + 最近 intention/確認/行動清單。
// 要求 LLM 輸出 JSON：{ move, reason, intentionText? }。
//
// 只在 user 訊息含「宣告/確認/我要做/從今天起」等觸發詞時啟用 AI 升級；
// 其他情況保持規則版（Sprint 1 的 ActionRouterRule）。

import '../../../models/agent_activity.dart';
import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';
import '../text_utils.dart';
import 'action_router_rule.dart';
import 'door_flow_detector_rule.dart';

/// AI 版動作路由器的 prompt 模板。
const _systemPrompt = '''你是一個思維儀表第七層「動作路由器」的 AI 版本。
根據前面六層的判斷結果，決定最適合的下一步行動。

輸出格式：一行 JSON：
{"move": "enum值", "reason": "一句話理由", "intentionText": "宣告摘要或空字串"}

move 可選值：
- answerDirectly — 直接回應
- askClarifyingQuestion — 先釐清
- reduceImportance — 降重要性
- convertToOutput — 轉成輸出
- takeNextAction — 推進下一步
- routeBridge — 接橋
- declareIntention — 使用者在宣告意圖/目標/承諾
- recordWaterAction — 使用者表示完成了行動

判斷規則：
1. 含宣告/承諾/決定詞 → declareIntention，intentionText 填意圖摘要
2. 表示完成行動 → recordWaterAction
3. 重要性過高或心腦衝突 → reduceImportance
4. 注意力被捕獲或分散 → convertToOutput
5. 門明確且水流順暢 → takeNextAction
6. 需要外部能力 → routeBridge
7. 門不清楚 → askClarifyingQuestion
8. 預設 → answerDirectly

只輸出 JSON，不要加其他文字。''';

/// AI 版動作路由器。
///
/// 與 [ActionRouterRule] 相同的介面，但使用 LLM 判斷。
/// 混合策略器 ([MixedActionRouter]) 會先跑規則版，再決定是否呼叫此 AI 版。
class ActionRouterAI
    extends BrainLayerAnalyzer<String, ActionRouterResult> {
  final PipelineLLMClient _llmClient;

  ActionRouterAI(this._llmClient);

  @override
  String get layerName => 'Action Router (AI)';

  @override
  int get layerIndex => 7;

  @override
  Future<LayerResult<ActionRouterResult>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);

    // 組裝前六層摘要
    final layerSummary = _buildLayerSummary(context);

    // 組裝近期記憶
    final memorySummary = context.recentMemories.isEmpty
        ? '（無近期記憶）'
        : context.recentMemories.take(5).map((m) => '- $m').join('\n');

    final userPrompt = '使用者訊息：$input\n\n'
        '前六層判斷摘要：\n$layerSummary\n\n'
        '近期記憶：\n$memorySummary\n\n'
        '請輸出 JSON。';

    final response = await _llmClient.complete(
      systemPrompt: _systemPrompt,
      userPrompt: userPrompt,
    );

    if (!response.succeeded) {
      // LLM 失敗 → 回傳 rule 版的預設
      return _fallbackToRule(input, context);
    }

    final json = safeJsonParse(response.content);
    if (json == null || json is! Map) {
      return _fallbackToRule(input, context);
    }

    // 解析 move
    final moveStr = json['move'] as String? ?? '';
    RecommendedMove? aiMove;
    for (final m in RecommendedMove.values) {
      if (m.name == moveStr) {
        aiMove = m;
        break;
      }
    }
    if (aiMove == null) {
      return _fallbackToRule(input, context);
    }

    final reason = json['reason'] as String? ?? '';
    final intentionText = json['intentionText'] as String? ?? '';

    // 用 AI 的 move + 規則版的 expression/guidance 作為基底
    final ruleResult = await ActionRouterRule().analyze(input, context);
    final ruleValue = ruleResult.value;

    // 如果 AI 說 declareIntention 或 recordWaterAction，覆蓋 move
    final finalMove = (aiMove == RecommendedMove.declareIntention ||
            aiMove == RecommendedMove.recordWaterAction)
        ? aiMove!
        : ruleValue.move;

    // 保留規則版的 expression，但更新 statusText
    final expression = CompanionExpression(
      mood: ruleValue.expression.mood,
      action: ruleValue.expression.action,
      statusText: reason.isNotEmpty ? reason : ruleValue.expression.statusText,
    );

    // guidance 用 AI 的 reason，如果沒有就用規則版的
    final guidance = reason.isNotEmpty ? reason : ruleValue.guidance;

    return LayerResult<ActionRouterResult>(
      value: ActionRouterResult(
        move: finalMove,
        expression: expression,
        guidance: guidance,
      ),
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: 'ai: move=${finalMove.name}, reason=$reason'
          '${intentionText.isNotEmpty ? ', intention=$intentionText' : ''}',
      metadata: intentionText.isNotEmpty
          ? {'intentionText': intentionText}
          : const {},
    );
  }

  /// 組裝前六層判斷摘要給 LLM
  String _buildLayerSummary(PipelineContext context) {
    final parts = <String>[];

    final attention = context.priorLayers[1]?.value;
    if (attention is AttentionState) {
      parts.add('注意力: ${attention.name}');
    }

    final pendulum = context.priorLayers[2]?.value;
    if (pendulum is List<PendulumSignal>) {
      parts.add('擺錘: ${pendulum.length} 個');
    }

    final importance = context.priorLayers[3]?.value;
    if (importance is ImportanceLevel) {
      parts.add('重要性: ${importance.name}');
    }

    final alignment = context.priorLayers[4]?.value;
    if (alignment is HeartMindAlignment) {
      parts.add('心腦: ${alignment.name}');
    }

    final fraile = context.priorLayers[5]?.value;
    if (fraile is FraileResonance) {
      parts.add('頻率: ${fraile.name}');
    }

    final doorFlow = context.priorLayers[6]?.value as DoorFlowResult?;
    if (doorFlow != null) {
      parts.add('門: ${doorFlow.doors.length} 個, 水流: ${doorFlow.flowState.name}');
    }

    return parts.isEmpty ? '（無前層資料）' : parts.join('\n');
  }

  /// LLM 失敗時 fallback 到規則版
  Future<LayerResult<ActionRouterResult>> _fallbackToRule(
    String input,
    PipelineContext context,
  ) async {
    final ruleResult = await ActionRouterRule().analyze(input, context);
    return LayerResult<ActionRouterResult>(
      value: ruleResult.value,
      source: LayerSource.rule,
      evidence: 'ai_fallback: ${ruleResult.evidence}',
    );
  }
}
