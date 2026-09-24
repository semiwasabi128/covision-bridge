import '../models/agent_activity.dart';
import '../models/intent_spine.dart';
import '../models/transurfing_brain.dart';
import 'intent_spine_service.dart';
import 'brain_pipeline/layer_result.dart';
import 'brain_pipeline/pipeline/transurfing_pipeline.dart';
import 'brain_pipeline/pipeline_result.dart';

class TransurfingBrainService {
  const TransurfingBrainService();

  /// 原 sync analyze() — 保留向下相容。
  /// chat_controller.dart 目前呼叫這個。
  /// Sprint 1 不改這裡的邏輯，只加 analyzeAsync() 作為新管線入口。
  BrainReflection analyze(
    String message, {
    List<String> recentMemories = const [],
    String? activeCompanionRole,
    DoorDecisionContext doorContext = const DoorDecisionContext(),
  }) {
    final text = _normalize(message);
    final pendulumSignals = _detectPendulums(text);
    final attentionState = _detectAttention(text, pendulumSignals);
    final importanceLevel = _detectImportance(
      text,
      pendulumSignals,
      doorContext,
    );
    final alignment = _detectHeartMindAlignment(text);
    final fraile = _detectFraileResonance(text, alignment, pendulumSignals);
    final doors = _detectDoors(text, fraile, attentionState, doorContext);
    final doorDecision = _detectDoorDecision(text, doorContext);
    final flow = _detectFlow(text, doors, importanceLevel, doorContext);
    final move = _chooseMove(
      text: text,
      attentionState: attentionState,
      importanceLevel: importanceLevel,
      alignment: alignment,
      doors: doors,
      flow: flow,
    );

    return BrainReflection(
      userIntent: _clarifyIntent(text, activeCompanionRole),
      attentionState: attentionState,
      pendulumSignals: pendulumSignals,
      importanceLevel: importanceLevel,
      heartMindAlignment: alignment,
      fraileResonance: fraile,
      doorCandidates: doors,
      doorDecision: doorDecision,
      flowState: flow,
      recommendedMove: move,
      companionExpression: _expressionFor(move, attentionState, flow),
      guidance: _guidanceFor(move, doors, pendulumSignals),
      // [教練 Agent 2026-07-05] 修復：規則版 analyze() 也要填入 layerResults，
      // 否則七層卡片、擺錘週報、心腦對話全部因 isNotEmpty 檢查而不顯示。
      layerResults: {
        'intent': LayerResult<String>(
          value: _clarifyIntent(text, activeCompanionRole),
          source: LayerSource.rule,
          evidence: '規則版意圖判斷',
        ),
        'attention': LayerResult<AttentionState>(
          value: attentionState,
          source: LayerSource.rule,
          evidence: '規則版注意力偵測',
        ),
        'pendulum': LayerResult<List<PendulumSignal>>(
          value: pendulumSignals,
          source: LayerSource.rule,
          evidence: pendulumSignals.isNotEmpty
              ? '命中 ${pendulumSignals.length} 個擺錘信號'
              : '無擺錘信號',
        ),
        'importance': LayerResult<ImportanceLevel>(
          value: importanceLevel,
          source: LayerSource.rule,
          evidence: '規則版重要性判斷',
        ),
        'heartMind': LayerResult<HeartMindAlignment>(
          value: alignment,
          source: LayerSource.rule,
          evidence: '規則版心腦對齊',
        ),
        'fraile': LayerResult<FraileResonance>(
          value: fraile,
          source: LayerSource.rule,
          evidence: '規則版脆弱度共鳴',
        ),
        'doorFlow': LayerResult<FlowState>(
          value: flow,
          source: LayerSource.rule,
          evidence: '規則版門流判斷',
        ),
        'actionRouter': LayerResult<RecommendedMove>(
          value: move,
          source: LayerSource.rule,
          evidence: '規則版行動路由',
        ),
      },
    );
  }

  String _normalize(String message) {
    return message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _clarifyIntent(String text, String? activeCompanionRole) {
    final role = activeCompanionRole == null ? '' : '$activeCompanionRole：';
    final intentSpine = const IntentSpineService().analyze(text);
    if (intentSpine.mode != IntentSpineMode.casual) {
      return '$role${intentSpine.userFacingSummary}';
    }
    if (_containsAny(text, _aiServiceMarkers)) {
      return '$role想把外部 AI 服務轉成自己的可用能力。';
    }
    if (_containsAny(text, ['繼續', '下一步', '開始做', '執行'])) {
      return '$role想推進目前橋樑計畫的下一個可交付切片。';
    }
    if (_containsAny(text, ['值得', '審視', '評估', '判斷'])) {
      return '$role想重新判斷方向是否符合真正目標。';
    }
    if (_containsAny(text, ['卡住', '不知道', '不懂', '複雜'])) {
      return '$role想降低阻力，找到能走進去的門。';
    }
    return '$role想獲得回應並維持目前對話水流。';
  }

  List<PendulumSignal> _detectPendulums(String text) {
    final signals = <PendulumSignal>[];
    _addSignalIfAny(signals, text, PendulumSignalType.urgency, '急迫感', [
      '趕快',
      '立刻',
      '馬上',
      '來不及',
      '錯過',
      '一定要',
      '必須',
    ]);
    _addSignalIfAny(signals, text, PendulumSignalType.fear, '恐懼與焦慮', [
      '怕',
      '焦慮',
      '完了',
      '失敗',
      '不安',
      '怎麼辦',
      '撐不住',
    ]);
    _addSignalIfAny(signals, text, PendulumSignalType.comparison, '比較與跟風', [
      '大家都',
      '別人',
      '新聞說',
      '很紅',
      '流行',
      '巨頭',
      '最新',
    ]);
    _addSignalIfAny(signals, text, PendulumSignalType.proving, '證明自己', [
      '證明',
      '不輸',
      '贏過',
      '看得起',
      '我是不是不懂',
    ]);
    _addSignalIfAny(signals, text, PendulumSignalType.guilt, '義務與愧疚', [
      '應該',
      '對不起',
      '愧疚',
      '都是我的錯',
      '不得不',
    ]);
    _addSignalIfAny(
      signals,
      text,
      PendulumSignalType.platformPull,
      '平台拉力',
      _aiServiceMarkers,
    );
    return signals;
  }

  void _addSignalIfAny(
    List<PendulumSignal> signals,
    String text,
    PendulumSignalType type,
    String label,
    List<String> markers,
  ) {
    final marker = _firstMarker(text, markers);
    if (marker == null) return;
    signals.add(PendulumSignal(type: type, label: label, evidence: marker));
  }

  AttentionState _detectAttention(
    String text,
    List<PendulumSignal> pendulumSignals,
  ) {
    final hasPlatformPull = pendulumSignals.any(
      (signal) => signal.type == PendulumSignalType.platformPull,
    );
    if (hasPlatformPull &&
        _containsAny(text, ['新聞', '看到', '很多', '一堆', '不知道怎麼用'])) {
      return AttentionState.captured;
    }
    if (_containsAny(text, ['好多', '一堆', '每個都', '不知道從哪裡', '一直看'])) {
      return AttentionState.scattered;
    }
    return AttentionState.clear;
  }

  ImportanceLevel _detectImportance(
    String text,
    List<PendulumSignal> pendulumSignals,
    DoorDecisionContext context,
  ) {
    if (context.hasActiveProject) return ImportanceLevel.elevated;
    var score = pendulumSignals.length;
    if (_containsAny(text, ['一切都完了', '非做不可', '沒有退路'])) score += 3;
    if (_containsAny(text, ['必須', '一定要', '不能失敗'])) score += 2;
    if (_containsAny(text, ['趕快', '怕', '焦慮'])) score += 1;

    if (score >= 5) return ImportanceLevel.excessive;
    if (score >= 3) return ImportanceLevel.elevated;
    if (score == 0) return ImportanceLevel.low;
    return ImportanceLevel.balanced;
  }

  HeartMindAlignment _detectHeartMindAlignment(String text) {
    final hasContrast = _containsAny(text, ['可是', '但是', '但', '不過']);
    final hasWant = _containsAny(text, ['想', '希望', '喜歡', '需要']);
    final hasDiscomfort = _containsAny(text, ['不想', '壓力', '痛苦', '勉強', '卡住']);
    final hasEnergy = _containsAny(text, ['喜歡', '太棒', '興奮', '有感覺', '自然']);

    if (hasDiscomfort && (hasWant || hasContrast)) {
      return HeartMindAlignment.conflicted;
    }
    if (hasContrast && hasWant) return HeartMindAlignment.mixed;
    if (hasEnergy) return HeartMindAlignment.aligned;
    return HeartMindAlignment.unknown;
  }

  FraileResonance _detectFraileResonance(
    String text,
    HeartMindAlignment alignment,
    List<PendulumSignal> pendulumSignals,
  ) {
    if (alignment == HeartMindAlignment.aligned &&
        _containsAny(text, ['自己', '我的', '喜歡', '創作', '夥伴', '風格'])) {
      return FraileResonance.strong;
    }
    if (_containsAny(text, ['我的需求', '我的喜好', '自己取', '自己的名字'])) {
      return FraileResonance.present;
    }
    if (pendulumSignals.any(
      (signal) =>
          signal.type == PendulumSignalType.comparison ||
          signal.type == PendulumSignalType.platformPull,
    )) {
      return FraileResonance.obscured;
    }
    return FraileResonance.weak;
  }

  List<DoorCandidate> _detectDoors(
    String text,
    FraileResonance fraile,
    AttentionState attentionState,
    DoorDecisionContext context,
  ) {
    final doors = <DoorCandidate>[];
    final activeProject = context.activeProjectTitle?.trim();
    if (activeProject != null && activeProject.isNotEmpty) {
      doors.add(
        DoorCandidate(
          kind: DoorKind.ownDoor,
          label: activeProject,
          reason: '目前已建立專案門「$activeProject」，這輪對話會優先掛回該主線。',
        ),
      );
    }
    if (fraile == FraileResonance.strong || fraile == FraileResonance.present) {
      doors.add(
        const DoorCandidate(
          kind: DoorKind.ownDoor,
          label: '自己的門',
          reason: '訊息中有自己的需求、喜好或創作方向。',
        ),
      );
    }
    if (_containsAny(text, ['下一步', '繼續', '開始做', '執行'])) {
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
    if (_containsAny(text, ['快速致富', '躺著賺', '不用努力', '保證成功'])) {
      doors.add(
        const DoorCandidate(
          kind: DoorKind.falseDoor,
          label: '假門',
          reason: '訊息含有不合理承諾或捷徑誘惑。',
        ),
      );
    }
    return doors;
  }

  DoorDecision? _detectDoorDecision(String text, DoorDecisionContext context) {
    final contextualDecision = _detectContextualDoorDecision(text, context);
    if (contextualDecision != null) return contextualDecision;

    final flowDecision = _detectFlowContinuationDecision(text, context);
    if (flowDecision != null) return flowDecision;

    final hasBranchLanguage = _containsAny(text, [
      '分支',
      '支線',
      '主線',
      '大分支',
      '回到主線',
      '回來',
      '先跳過',
      '先完成',
      '不同的下一步',
      '下一步邏輯',
      '兩者',
      '哪一步',
      '哪一個',
    ]);
    final hasRouteChoice = _containsAny(text, [
      '建議',
      '你覺得',
      '該怎麼走',
      '走哪',
      '先把它完成',
      '先回到',
      '或者',
      '還是',
    ]);
    if (!hasBranchLanguage || !hasRouteChoice) return null;

    final recommendsMainline = _containsAny(text, [
      '主線',
      '先回到主線',
      '先完成後',
      '先把主線',
    ]);
    final recommended = recommendsMainline
        ? DoorDecisionChoice.mainline
        : DoorDecisionChoice.branch;

    return DoorDecision(
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

  DoorDecision? _detectFlowContinuationDecision(
    String text,
    DoorDecisionContext context,
  ) {
    final isSliceOrPolish = _containsAny(text, [
      ' v0',
      'v0',
      'slice',
      '細節',
      '收尾',
      '優化',
      '修正',
      '更正',
      '校準',
      '調整',
      '這個階段',
      '這一輪',
      '下一個門走',
      '下一個門',
    ]);
    if (!isSliceOrPolish) return null;

    final isMajorBranch = _containsAny(text, [
      '大分支',
      '比較大的分支',
      '不同的下一步邏輯',
      '主線或支線',
      '先把它完成',
      '先回到主線',
      '或者先',
      '還是先',
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
        _containsAny(text, ['下一步', '繼續', '完成', '回來', '回到', '接下來'])) {
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
        _containsAny(text, ['下一步', '繼續', '接下來', '開始做'])) {
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

  bool _capabilityLooksRelated(
    String requestedCapability,
    String pendingTitle,
    String? pendingMissing,
  ) {
    final requested = _normalize(requestedCapability);
    final pending = _normalize('$pendingTitle ${pendingMissing ?? ''}');
    if (pending.contains(requested) || requested.contains(pending)) {
      return true;
    }
    const capabilityKeywords = [
      '音樂',
      '圖片',
      '影片',
      '瀏覽',
      '網頁',
      '新聞',
      '文件',
      '桌面',
      '檔案',
      '辨識',
    ];
    return capabilityKeywords.any(
      (keyword) => requested.contains(keyword) && pending.contains(keyword),
    );
  }

  FlowState _detectFlow(
    String text,
    List<DoorCandidate> doors,
    ImportanceLevel importanceLevel,
    DoorDecisionContext context,
  ) {
    if (context.hasActiveProject) return FlowState.withFlow;
    if (_containsAny(text, ['卡住', '複雜', '不知道怎麼', '一直失敗'])) {
      return FlowState.againstFlow;
    }
    if (importanceLevel == ImportanceLevel.excessive) {
      return FlowState.againstFlow;
    }
    if (doors.any((door) => door.kind == DoorKind.currentLink) ||
        _containsAny(text, ['很棒', '太棒', '順', '自然', '繼續'])) {
      return FlowState.withFlow;
    }
    if (_containsAny(text, ['沒進展', '停住', '空轉'])) {
      return FlowState.stalled;
    }
    return FlowState.unknown;
  }

  RecommendedMove _chooseMove({
    required String text,
    required AttentionState attentionState,
    required ImportanceLevel importanceLevel,
    required HeartMindAlignment alignment,
    required List<DoorCandidate> doors,
    required FlowState flow,
  }) {
    if (importanceLevel == ImportanceLevel.excessive ||
        alignment == HeartMindAlignment.conflicted) {
      return RecommendedMove.reduceImportance;
    }
    if (attentionState == AttentionState.captured ||
        attentionState == AttentionState.scattered) {
      return RecommendedMove.convertToOutput;
    }
    if (_containsAny(text, ['圖片', '影片', '音樂', '文件', '生成'])) {
      return RecommendedMove.routeBridge;
    }
    if (flow == FlowState.withFlow ||
        doors.any((door) => door.kind == DoorKind.currentLink)) {
      return RecommendedMove.takeNextAction;
    }
    if (doors.isEmpty && alignment == HeartMindAlignment.unknown) {
      return RecommendedMove.askClarifyingQuestion;
    }
    return RecommendedMove.answerDirectly;
  }

  CompanionExpression _expressionFor(
    RecommendedMove move,
    AttentionState attentionState,
    FlowState flow,
  ) {
    if (attentionState != AttentionState.clear) {
      return const CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        statusText: '正在收束注意力',
      );
    }
    if (move == RecommendedMove.reduceImportance) {
      return const CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.standing,
        statusText: '先降低重要性',
      );
    }
    if (move == RecommendedMove.routeBridge) {
      return const CompanionExpression(
        mood: AgentCompanionMood.bridging,
        action: AgentCompanionAction.spinning,
        statusText: '準備接上橋樑能力',
      );
    }
    if (flow == FlowState.withFlow) {
      return const CompanionExpression(
        mood: AgentCompanionMood.proud,
        action: AgentCompanionAction.bouncing,
        statusText: '水流順暢，推進下一環',
      );
    }
    return const CompanionExpression(
      mood: AgentCompanionMood.curious,
      action: AgentCompanionAction.pointing,
      statusText: '正在辨識門與水流',
    );
  }

  String _guidanceFor(
    RecommendedMove move,
    List<DoorCandidate> doors,
    List<PendulumSignal> pendulumSignals,
  ) {
    switch (move) {
      case RecommendedMove.reduceImportance:
        return '先放下非做不可的重量，找一個安全網，再走下一步。';
      case RecommendedMove.convertToOutput:
        return '把外部資訊轉成自己的輸出，先選一個最貼近目標的成果。';
      case RecommendedMove.takeNextAction:
        return '目前像是在水流裡，適合推進 transfer chain 的下一環。';
      case RecommendedMove.routeBridge:
        return '這可以交給橋樑能力處理，但仍要對齊使用者自己的目標。';
      case RecommendedMove.askClarifyingQuestion:
        return '門還不清楚，先問一個能分辨自己目標與外部目標的問題。';
      case RecommendedMove.answerDirectly:
        if (doors.any((door) => door.kind == DoorKind.ownDoor)) {
          return '這裡有自己的門的訊號，可以支持並整理路徑。';
        }
        if (pendulumSignals.isNotEmpty) {
          return '有鐘擺訊號，但強度不高，提醒即可。';
        }
        return '目前可以直接回應，保持清醒與簡潔。';
      case RecommendedMove.declareIntention:
        return '偵測到宣告意圖，把這個意圖寫進大腦容器，等待確認。';
      case RecommendedMove.recordWaterAction:
        return '記錄已完成的行動，讓水流趨勢可以被追蹤。';
    }
  }

  bool _containsAny(String text, List<String> markers) {
    return markers.any(text.contains);
  }

  String? _firstMarker(String text, List<String> markers) {
    for (final marker in markers) {
      if (text.contains(marker)) return marker;
    }
    return null;
  }

  /// Sprint 1 新增：用七層管線跑分析，回傳 PipelineResult。
  /// 行為與 [analyze] 完全一致，只是走新的 pipeline 架構。
  /// Sprint 2+ 的 chat_controller 可以切換呼叫這個。
  Future<PipelineResult> analyzeAsync(
    String message, {
    List<String> recentMemories = const [],
    String? activeCompanionRole,
    DoorDecisionContext doorContext = const DoorDecisionContext(),
  }) {
    final pipeline = TransurfingPipeline();
    return pipeline.analyzeAsync(
      message,
      recentMemories: recentMemories,
      activeCompanionRole: activeCompanionRole,
      doorContext: doorContext,
    );
  }
}

const _aiServiceMarkers = [
  'ai 服務',
  'ai服務',
  '影片生成',
  '音樂生成',
  '圖片生成',
  '新工具',
  '新平台',
  '平台',
  'discord',
  'openai',
  'kimi',
  'gimi',
  'claude',
  'gemini',
  'midjourney',
  'runway',
  'suno',
];
