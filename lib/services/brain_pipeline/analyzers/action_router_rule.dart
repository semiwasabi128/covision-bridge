// action_router_rule.dart
// Sprint 1 — Layer 7: 動作路由（規則版）
// 原始邏輯：TransurfingBrainService._chooseMove + _expressionFor + _guidanceFor
// 行為不變。

import '../../../models/agent_activity.dart';
import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';
import 'door_flow_detector_rule.dart';

/// Layer 7 的輸出：建議動作 + 夥伴表情 + 引導句。
class ActionRouterResult {
  final RecommendedMove move;
  final CompanionExpression expression;
  final String guidance;

  const ActionRouterResult({
    required this.move,
    required this.expression,
    required this.guidance,
  });
}

class ActionRouterRule
    extends BrainLayerAnalyzer<String, ActionRouterResult> {
  @override
  String get layerName => 'Action Router';

  @override
  int get layerIndex => 7;

  @override
  Future<LayerResult<ActionRouterResult>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);

    // 從 priorLayers 拿前面層的結果
    final attentionResult = context.priorLayers[1];
    final attentionState =
        attentionResult?.value as AttentionState? ?? AttentionState.clear;

    final importanceResult = context.priorLayers[3];
    final importanceLevel =
        importanceResult?.value as ImportanceLevel? ?? ImportanceLevel.balanced;

    final alignmentResult = context.priorLayers[4];
    final alignment = alignmentResult?.value as HeartMindAlignment? ??
        HeartMindAlignment.unknown;

    final doorFlowResult = context.priorLayers[6];
    final doorFlow = doorFlowResult?.value as DoorFlowResult?;
    final doors = doorFlow?.doors ?? const <DoorCandidate>[];
    final flow = doorFlow?.flowState ?? FlowState.unknown;

    // --- _chooseMove ---
    RecommendedMove move;
    if (importanceLevel == ImportanceLevel.excessive ||
        alignment == HeartMindAlignment.conflicted) {
      move = RecommendedMove.reduceImportance;
    } else if (attentionState == AttentionState.captured ||
        attentionState == AttentionState.scattered) {
      move = RecommendedMove.convertToOutput;
    } else if (containsAny(text, ['圖片', '影片', '音樂', '文件', '生成'])) {
      move = RecommendedMove.routeBridge;
    } else if (flow == FlowState.withFlow ||
        doors.any((door) => door.kind == DoorKind.currentLink)) {
      move = RecommendedMove.takeNextAction;
    } else if (doors.isEmpty && alignment == HeartMindAlignment.unknown) {
      move = RecommendedMove.askClarifyingQuestion;
    } else {
      move = RecommendedMove.answerDirectly;
    }

    // --- _expressionFor ---
    CompanionExpression expression;
    if (attentionState != AttentionState.clear) {
      expression = const CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        statusText: '正在收束注意力',
      );
    } else if (move == RecommendedMove.reduceImportance) {
      expression = const CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.standing,
        statusText: '先降低重要性',
      );
    } else if (move == RecommendedMove.routeBridge) {
      expression = const CompanionExpression(
        mood: AgentCompanionMood.bridging,
        action: AgentCompanionAction.spinning,
        statusText: '準備接上橋樑能力',
      );
    } else if (flow == FlowState.withFlow) {
      expression = const CompanionExpression(
        mood: AgentCompanionMood.proud,
        action: AgentCompanionAction.bouncing,
        statusText: '水流順暢，推進下一環',
      );
    } else {
      expression = const CompanionExpression(
        mood: AgentCompanionMood.curious,
        action: AgentCompanionAction.pointing,
        statusText: '正在辨識門與水流',
      );
    }

    // --- _guidanceFor ---
    String guidance;
    switch (move) {
      case RecommendedMove.reduceImportance:
        guidance = '先放下非做不可的重量，找一個安全網，再走下一步。';
      case RecommendedMove.convertToOutput:
        guidance = '把外部資訊轉成自己的輸出，先選一個最貼近目標的成果。';
      case RecommendedMove.takeNextAction:
        guidance = '目前像是在水流裡，適合推進 transfer chain 的下一環。';
      case RecommendedMove.routeBridge:
        guidance = '這可以交給橋樑能力處理，但仍要對齊使用者自己的目標。';
      case RecommendedMove.askClarifyingQuestion:
        guidance = '門還不清楚，先問一個能分辨自己目標與外部目標的問題。';
      case RecommendedMove.answerDirectly:
        if (doors.any((door) => door.kind == DoorKind.ownDoor)) {
          guidance = '這裡有自己的門的訊號，可以支持並整理路徑。';
        } else if (context.priorLayers[2]?.value
            case List<PendulumSignal> signals when signals.isNotEmpty) {
          guidance = '有鐘擺訊號，但強度不高，提醒即可。';
        } else {
          guidance = '目前可以直接回應，保持清醒與簡潔。';
        }
      case RecommendedMove.declareIntention:
        guidance = '偵測到宣告意圖，把這個意圖寫進大腦容器，等待確認。';
      case RecommendedMove.recordWaterAction:
        guidance = '記錄已完成的行動，讓水流趨勢可以被追蹤。';
    }

    return LayerResult<ActionRouterResult>(
      value: ActionRouterResult(move: move, expression: expression, guidance: guidance),
      source: LayerSource.rule,
      evidence: 'move=${move.name}',
    );
  }
}
