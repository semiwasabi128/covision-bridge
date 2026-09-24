// door_flow_detector_rule.dart
// Sprint 1 — Layer 6: 門與水流偵測（規則版）
// 原始邏輯：TransurfingBrainService._detectDoors + _detectDoorDecision + _detectFlow
// + _detectContextualDoorDecision + _detectFlowContinuationDecision
// + _capabilityLooksRelated，行為不變。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

/// Layer 6 的輸出：門候選 + 門決策 + 水流狀態。
class DoorFlowResult {
  final List<DoorCandidate> doors;
  final DoorDecision? doorDecision;
  final FlowState flowState;

  const DoorFlowResult({
    required this.doors,
    this.doorDecision,
    required this.flowState,
  });
}

class DoorFlowDetectorRule
    extends BrainLayerAnalyzer<String, DoorFlowResult> {
  @override
  String get layerName => 'Door & Flow Detector';

  @override
  int get layerIndex => 6;

  @override
  Future<LayerResult<DoorFlowResult>> analyze(
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

    final fraileResult = context.priorLayers[5];
    final fraile =
        fraileResult?.value as FraileResonance? ?? FraileResonance.weak;

    final doorContext = context.doorContext;

    // --- _detectDoors ---
    final doors = <DoorCandidate>[];
    final activeProject = doorContext.activeProjectTitle?.trim();
    if (activeProject != null && activeProject.isNotEmpty) {
      doors.add(
        DoorCandidate(
          kind: DoorKind.ownDoor,
          label: activeProject,
          reason: '目前已建立專案門「$activeProject」，這輪對話會優先掛回該主線。',
          source: DoorCandidateSource.contextDriven,
        ),
      );
    }
    if (fraile == FraileResonance.strong ||
        fraile == FraileResonance.present) {
      doors.add(
        const DoorCandidate(
          kind: DoorKind.ownDoor,
          label: '自己的門',
          reason: '訊息中有自己的需求、喜好或創作方向。',
        ),
      );
    }
    if (containsAny(text, ['下一步', '繼續', '開始做', '執行'])) {
      doors.add(
        const DoorCandidate(
          kind: DoorKind.currentLink,
          label: '目前 transfer chain 的下一環',
          reason: '使用者正在要求推進已確認的路徑。',
        ),
      );
    }
    if (attentionState == AttentionState.captured) {
      doors.add(
        const DoorCandidate(
          kind: DoorKind.foreignDoor,
          label: '外部平台的門',
          reason: '訊息焦點被新服務、新聞或平台能力吸引。',
        ),
      );
    }
    if (containsAny(text, ['快速致富', '躺著賺', '不用努力', '保證成功'])) {
      doors.add(
        const DoorCandidate(
          kind: DoorKind.falseDoor,
          label: '假門',
          reason: '訊息含有不合理承諾或捷徑誘惑。',
        ),
      );
    }

    // --- _detectDoorDecision ---
    DoorDecision? doorDecision = _detectContextualDoorDecision(text, doorContext);
    doorDecision ??= _detectFlowContinuationDecision(text, doorContext);

    if (doorDecision == null) {
      final hasBranchLanguage = containsAny(text, [
        '分支', '支線', '主線', '大分支', '回到主線', '回來', '先跳過',
        '先完成', '不同的下一步', '下一步邏輯', '兩者', '哪一步', '哪一個',
      ]);
      final hasRouteChoice = containsAny(text, [
        '建議', '你覺得', '該怎麼走', '走哪', '先把它完成', '先回到', '或者', '還是',
      ]);
      if (hasBranchLanguage && hasRouteChoice) {
        final recommendsMainline = containsAny(text, [
          '主線', '先回到主線', '先完成後', '先把主線',
        ]);
        final recommended = recommendsMainline
            ? DoorDecisionChoice.mainline
            : DoorDecisionChoice.branch;
        doorDecision = DoorDecision(
          id: 'door-${text.hashCode.abs()}',
          title: '偵測到重大分支門',
          summary: '現在有兩條路都合理：一條保護目前主線，一條進入新支線補足能力。',
          mainlineLabel: '先走主線',
          mainlineReason: '先把目前使用流程走通，避免支線過長讓主體體驗卡住。',
          branchLabel: '先進支線',
          branchReason: '先補足新分支，讓後續主線可以使用更完整的能力。',
          recommendedChoice: recommended,
          recommendationReason: recommendsMainline
              ? '目前訊息已明確提到主線與回流，適合先保護主線，再把支線列為待回流門。'
              : '目前訊息焦點集中在新分支，適合短暫進支線，但要保存回流點。',
          returnPrompt: recommendsMainline
              ? '回到剛才暫存的支線門：補足真正 adapter / 正式橋能力。'
              : '回到剛才暫存的主線門：完成橋樑 APP 核心使用流程。',
        );
      }
    }

    // --- _detectFlow ---
    FlowState flow;
    if (doorContext.hasActiveProject) {
      flow = FlowState.withFlow;
    } else if (containsAny(text, ['卡住', '複雜', '不知道怎麼', '一直失敗'])) {
      flow = FlowState.againstFlow;
    } else if (importanceLevel == ImportanceLevel.excessive) {
      flow = FlowState.againstFlow;
    } else if (doors.any((door) => door.kind == DoorKind.currentLink) ||
        containsAny(text, ['很棒', '太棒', '順', '自然', '繼續'])) {
      flow = FlowState.withFlow;
    } else if (containsAny(text, ['沒進展', '停住', '空轉'])) {
      flow = FlowState.stalled;
    } else {
      flow = FlowState.unknown;
    }

    return LayerResult<DoorFlowResult>(
      value: DoorFlowResult(doors: doors, doorDecision: doorDecision, flowState: flow),
      source: LayerSource.rule,
      evidence: 'doors=${doors.length}, decision=${doorDecision != null}, flow=${flow.name}',
    );
  }

  // --- 以下為原 TransurfingBrainService 的 private 方法，原樣搬過來 ---

  DoorDecision? _detectContextualDoorDecision(
    String text,
    DoorDecisionContext context,
  ) {
    if (context.hasPendingBridgeTask &&
        context.hasRequestedCapability &&
        !_capabilityLooksRelated(
          context.requestedCapabilityLabel!,
          context.pendingBridgeTaskTitle!,
          context.pendingBridgeTaskMissing,
        )) {
      return DoorDecision(
        id: 'door-context-${text.hashCode.abs()}',
        title: '偵測到能力支線門',
        summary:
            '目前還有「${context.pendingBridgeTaskTitle}」這個卡點，同時你又提出「${context.requestedCapabilityLabel}」的新能力需求。',
        mainlineLabel: '先回原卡點',
        mainlineReason:
            '先完成「${context.pendingBridgeTaskTitle}」，避免能力開通流程變成多條支線一起打開。',
        branchLabel: '先開新能力',
        branchReason:
            '如果「${context.requestedCapabilityLabel}」更急，可以先開新能力，但系統會保存原卡點。',
        recommendedChoice: DoorDecisionChoice.mainline,
        recommendationReason: '已有未完成能力卡點時，優先回到原任務會讓使用者比較不迷路。',
        returnPrompt: '回到剛才暫存的新能力支線：${context.requestedCapabilityLabel}。',
      );
    }

    if (context.hasPendingReturn &&
        containsAny(text, ['下一步', '繼續', '完成', '回來', '回到', '接下來'])) {
      return DoorDecision(
        id: 'door-return-${text.hashCode.abs()}',
        title: '偵測到待回流門',
        summary: '系統記得你之前暫存了「${context.pendingReturnLabel}」，現在可以決定是否回去補足。',
        mainlineLabel: '繼續目前主線',
        mainlineReason: '如果目前流程還沒收尾，先完成眼前這一步，降低切換成本。',
        branchLabel: '回到待回流門',
        branchReason: '如果目前主線已穩，可以回去補足「${context.pendingReturnLabel}」。',
        recommendedChoice: DoorDecisionChoice.mainline,
        recommendationReason: '先確認目前階段是否完成，再回到待回流門，能避免半途切換。',
        returnPrompt: '回到待回流門：${context.pendingReturnLabel}。',
      );
    }

    if (context.hasPendingBridgeTask &&
        containsAny(text, ['下一步', '繼續', '接下來', '開始做'])) {
      return DoorDecision(
        id: 'door-pending-${text.hashCode.abs()}',
        title: '偵測到未完成卡點',
        summary:
            '目前仍有「${context.pendingBridgeTaskTitle}」未完成；下一步可以先處理卡點，或暫時另開支線。',
        mainlineLabel: '先處理卡點',
        mainlineReason:
            '完成「${context.pendingBridgeTaskMissing ?? context.pendingBridgeTaskTitle}」後，原本任務才能自動回來續跑。',
        branchLabel: '另開支線',
        branchReason: '如果現在有更重要的想法，可以先暫存卡點再走新方向。',
        recommendedChoice: DoorDecisionChoice.mainline,
        recommendationReason: '有能力卡點時，先補能力通常最能推進主線。',
        returnPrompt: '回到未完成卡點：${context.pendingBridgeTaskTitle}。',
      );
    }

    return null;
  }

  DoorDecision? _detectFlowContinuationDecision(
    String text,
    DoorDecisionContext context,
  ) {
    final isSliceOrPolish = containsAny(text, [
      ' v0', 'v0', 'slice', '細節', '收尾', '優化', '修正', '更正', '校準',
      '調整', '這個階段', '這一輪', '下一個門走', '下一個門',
    ]);
    if (!isSliceOrPolish) return null;

    final isMajorBranch = containsAny(text, [
      '大分支', '比較大的分支', '不同的下一步邏輯', '主線或支線', '先把它完成',
      '先回到主線', '或者先', '還是先',
    ]);
    if (isMajorBranch) return null;

    final mainlineLabel =
        context.currentMainlineLabel?.trim().isNotEmpty == true
            ? context.currentMainlineLabel!.trim()
            : '回到主線之門';

    return DoorDecision(
      id: 'flow-${text.hashCode.abs()}',
      navigationKind: NavigationDecisionKind.flow,
      title: '偵測到同一水流的細節收尾',
      summary: '這比較像在同一條工作水流裡優化一個細節，不是需要另開主線/支線的門。',
      mainlineLabel: '順著水流收尾',
      mainlineReason: '先把目前這個小環節修準，完成後自然回到主線，不需要另開一扇門。',
      branchLabel: mainlineLabel,
      branchReason: '如果這個細節已經足夠，可以停止微調，回到目前主線繼續推進。',
      recommendedChoice: DoorDecisionChoice.mainline,
      recommendationReason: '這是低阻力的細節水流：修完就回主線，避免把小收尾誤判成新門。',
      returnPrompt: '回到主線之門：$mainlineLabel。',
    );
  }

  bool _capabilityLooksRelated(
    String requestedCapability,
    String pendingTitle,
    String? pendingMissing,
  ) {
    final requested = normalize(requestedCapability);
    final pending = normalize('$pendingTitle ${pendingMissing ?? ''}');
    if (pending.contains(requested) || requested.contains(pending)) {
      return true;
    }
    const capabilityKeywords = [
      '音樂', '圖片', '影片', '瀏覽', '網頁', '新聞', '文件', '桌面', '檔案', '辨識',
    ];
    return capabilityKeywords.any(
      (keyword) => requested.contains(keyword) && pending.contains(keyword),
    );
  }
}
