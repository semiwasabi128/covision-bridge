import '../services/brain_pipeline/layer_result.dart';
import 'agent_activity.dart';

enum AttentionState { clear, captured, scattered }

enum PendulumSignalType {
  urgency,
  fear,
  comparison,
  proving,
  guilt,
  platformPull,
  // Sprint 3 新增：AI 語意偵測才會出現的三種新擺錘
  infoPoisoning,
  platformCapture,
  clipConsumption,
}

/// 擺錘訊號的來源標記。
/// 規則版為 ruleMatch；AI 版為 aiInferred。
/// Sprint 3 的混合策略器會合併兩種來源。
enum PendulumSignalSource { ruleMatch, aiInferred }

class PendulumSignal {
  final PendulumSignalType type;
  final String label;
  final String evidence;
  final PendulumSignalSource source;

  const PendulumSignal({
    required this.type,
    required this.label,
    required this.evidence,
    this.source = PendulumSignalSource.ruleMatch,
  });

  /// Sprint 3: 用於混合策略器去重——(type, evidence.normalize) 相同視為同一條。
  String get dedupKey => '${type.name}:${evidence.toLowerCase().trim()}';

  @override
  String toString() => 'PendulumSignal(${type.name}, "$evidence", ${source.name})';
}

enum ImportanceLevel { low, balanced, elevated, excessive }

enum HeartMindAlignment { aligned, mixed, conflicted, unknown }

enum FraileResonance { strong, present, weak, obscured }

/// Sprint 4 新增：AI 版心腦/重要性/頻率層的引導提示。
/// 只有 AI analyzer 跑過的層才會填值，規則版全部 null。
/// Panel 拿到非 null 的 hint 才顯示展開鈕，否則只顯示原 enum 文字。
class GuidanceHint {
  /// 重要性層：幽默化解句（例如「試著把這件事寫成笑話給朋友聽」）
  final String? humorHint;

  /// 心腦層：使用者理智立場（一句話）
  final String? mindStatement;

  /// 心腦層：使用者心立場（一句話）
  final String? heartStatement;

  /// 心腦層：兩者最尖銳對立的詞（原文，例如「可是」「但是」）
  final String? splitMarker;

  /// 心腦層：整合引導句（例如「如果兩邊都對，你最想先聽哪邊？」）
  final String? integrationPrompt;

  /// 頻率層：頻率趨勢說明（例如「過去 7 天的行動反映你的頻率趨勢是 X」）
  final String? fraileEvidence;

  const GuidanceHint({
    this.humorHint,
    this.mindStatement,
    this.heartStatement,
    this.splitMarker,
    this.integrationPrompt,
    this.fraileEvidence,
  });

  /// 是否有任何非 null 值（決定 Panel 是否顯示展開鈕）
  bool get hasAny =>
      humorHint != null ||
      mindStatement != null ||
      heartStatement != null ||
      splitMarker != null ||
      integrationPrompt != null ||
      fraileEvidence != null;

  /// 合併兩個 partial hint（各層只填自己的欄位，pipeline 最後 merge）
  GuidanceHint merge(GuidanceHint other) {
    return GuidanceHint(
      humorHint: humorHint ?? other.humorHint,
      mindStatement: mindStatement ?? other.mindStatement,
      heartStatement: heartStatement ?? other.heartStatement,
      splitMarker: splitMarker ?? other.splitMarker,
      integrationPrompt: integrationPrompt ?? other.integrationPrompt,
      fraileEvidence: fraileEvidence ?? other.fraileEvidence,
    );
  }
}

enum DoorKind { ownDoor, foreignDoor, falseDoor, currentLink }

/// Sprint 1 新增：門候選的來源標記。
/// 規則版全部為 ruleMatch；Sprint 5 的 AI 版會產生 aiInferred / contextDriven。
enum DoorCandidateSource { ruleMatch, aiInferred, contextDriven }

class DoorCandidate {
  final DoorKind kind;
  final String label;
  final String reason;
  final DoorCandidateSource source;

  const DoorCandidate({
    required this.kind,
    required this.label,
    required this.reason,
    this.source = DoorCandidateSource.ruleMatch,
  });
}

enum DoorDecisionChoice { mainline, branch, pause }

enum NavigationDecisionKind { door, flow }

class DoorDecision {
  final String id;
  final NavigationDecisionKind navigationKind;
  final String title;
  final String summary;
  final String mainlineLabel;
  final String mainlineReason;
  final String branchLabel;
  final String branchReason;
  final DoorDecisionChoice recommendedChoice;
  final String recommendationReason;
  final String returnPrompt;

  const DoorDecision({
    required this.id,
    this.navigationKind = NavigationDecisionKind.door,
    required this.title,
    required this.summary,
    required this.mainlineLabel,
    required this.mainlineReason,
    required this.branchLabel,
    required this.branchReason,
    required this.recommendedChoice,
    required this.recommendationReason,
    required this.returnPrompt,
  });

  DoorDecisionPendingReturn defer(DoorDecisionChoice chosen) {
    final deferredChoice = switch (chosen) {
      DoorDecisionChoice.mainline => DoorDecisionChoice.branch,
      DoorDecisionChoice.branch => DoorDecisionChoice.mainline,
      DoorDecisionChoice.pause => DoorDecisionChoice.branch,
    };
    return DoorDecisionPendingReturn(
      decisionId: id,
      title: _choiceLabel(deferredChoice),
      chosenLabel: _choiceLabel(chosen),
      deferredLabel: _choiceLabel(deferredChoice),
      returnPrompt: returnPrompt,
      sourceSummary: summary,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      navigationKind: navigationKind,
    );
  }

  String _choiceLabel(DoorDecisionChoice choice) {
    return switch (choice) {
      DoorDecisionChoice.mainline => mainlineLabel,
      DoorDecisionChoice.branch => branchLabel,
      DoorDecisionChoice.pause =>
        navigationKind == NavigationDecisionKind.flow ? '暫存水流' : '暫存門',
    };
  }
}

class DoorDecisionPendingReturn {
  final String decisionId;
  final String title;
  final String chosenLabel;
  final String deferredLabel;
  final String returnPrompt;
  final String sourceSummary;
  final int createdAtMs;
  final NavigationDecisionKind navigationKind;

  const DoorDecisionPendingReturn({
    required this.decisionId,
    required this.title,
    required this.chosenLabel,
    required this.deferredLabel,
    required this.returnPrompt,
    required this.sourceSummary,
    required this.createdAtMs,
    this.navigationKind = NavigationDecisionKind.door,
  });

  Map<String, dynamic> toJson() {
    return {
      'decisionId': decisionId,
      'title': title,
      'chosenLabel': chosenLabel,
      'deferredLabel': deferredLabel,
      'returnPrompt': returnPrompt,
      'sourceSummary': sourceSummary,
      'createdAtMs': createdAtMs,
      'navigationKind': navigationKind.name,
    };
  }

  static DoorDecisionPendingReturn? fromJson(Map<String, dynamic> json) {
    final decisionId = json['decisionId']?.toString().trim();
    final title = json['title']?.toString().trim();
    final chosenLabel = json['chosenLabel']?.toString().trim();
    final deferredLabel = json['deferredLabel']?.toString().trim();
    final returnPrompt = json['returnPrompt']?.toString().trim();
    final sourceSummary = json['sourceSummary']?.toString().trim();
    final createdAtMs = int.tryParse(json['createdAtMs']?.toString() ?? '');
    final navigationKind = _navigationDecisionKindFromName(
      json['navigationKind']?.toString(),
    );
    if (decisionId == null ||
        decisionId.isEmpty ||
        title == null ||
        title.isEmpty ||
        chosenLabel == null ||
        chosenLabel.isEmpty ||
        deferredLabel == null ||
        deferredLabel.isEmpty ||
        returnPrompt == null ||
        returnPrompt.isEmpty ||
        sourceSummary == null ||
        sourceSummary.isEmpty ||
        createdAtMs == null) {
      return null;
    }
    return DoorDecisionPendingReturn(
      decisionId: decisionId,
      title: title,
      chosenLabel: chosenLabel,
      deferredLabel: deferredLabel,
      returnPrompt: returnPrompt,
      sourceSummary: sourceSummary,
      createdAtMs: createdAtMs,
      navigationKind: navigationKind,
    );
  }

  static NavigationDecisionKind _navigationDecisionKindFromName(String? name) {
    for (final kind in NavigationDecisionKind.values) {
      if (kind.name == name) return kind;
    }
    return NavigationDecisionKind.door;
  }
}

class DoorDecisionContext {
  final String? currentMainlineLabel;
  final String? activeProjectTitle;
  final String? activeProjectFlow;
  final String? pendingBridgeTaskTitle;
  final String? pendingBridgeTaskMissing;
  final String? pendingReturnLabel;
  final String? requestedCapabilityLabel;

  const DoorDecisionContext({
    this.currentMainlineLabel,
    this.activeProjectTitle,
    this.activeProjectFlow,
    this.pendingBridgeTaskTitle,
    this.pendingBridgeTaskMissing,
    this.pendingReturnLabel,
    this.requestedCapabilityLabel,
  });

  bool get hasPendingBridgeTask =>
      pendingBridgeTaskTitle != null &&
      pendingBridgeTaskTitle!.trim().isNotEmpty;

  bool get hasPendingReturn =>
      pendingReturnLabel != null && pendingReturnLabel!.trim().isNotEmpty;

  bool get hasRequestedCapability =>
      requestedCapabilityLabel != null &&
      requestedCapabilityLabel!.trim().isNotEmpty;

  bool get hasActiveProject =>
      activeProjectTitle != null && activeProjectTitle!.trim().isNotEmpty;
}

enum FlowState { withFlow, againstFlow, stalled, unknown }

enum RecommendedMove {
  answerDirectly,
  askClarifyingQuestion,
  reduceImportance,
  convertToOutput,
  takeNextAction,
  routeBridge,
  // Sprint 2 新增：宣告/確認/行動閉環（純擴充，不破壞既有 6 個值）
  declareIntention,
  recordWaterAction,
}

/// Sprint 7 新增：夥伴步態——桌面夥伴的移動方式。
enum CompanionGait {
  /// 注意力被捕獲時——停下來
  still,
  /// 正常狀態——緩步
  stepping,
  /// 水流順暢——快步
  running,
  /// 水流停滯——暫停
  paused,
}

/// Sprint 7 新增：夥伴語氣——桌面夥伴的語音音調。
enum CompanionVoiceTone {
  /// 心腦衝突——沉穩量測
  measured,
  /// 心腦對齊——溫暖
  warm,
  /// 下一步行動——輕快
  brisk,
  /// 過度重要——柔和
  soft,
}

class CompanionExpression {
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final String statusText;

  /// Sprint 7 新增：夥伴步態（nullable——規則版 action_router 不填，由 CompanionMoodMapper 計算）。
  final CompanionGait? gait;

  /// Sprint 7 新增：夥伴語氣（nullable——同上）。
  final CompanionVoiceTone? voiceTone;

  const CompanionExpression({
    required this.mood,
    required this.action,
    required this.statusText,
    this.gait,
    this.voiceTone,
  });

  /// Sprint 7：複製並加上 gait / voiceTone（不破壞既有欄位）。
  CompanionExpression withCompanionFields({
    CompanionGait? gait,
    CompanionVoiceTone? voiceTone,
  }) {
    return CompanionExpression(
      mood: mood,
      action: action,
      statusText: statusText,
      gait: gait ?? this.gait,
      voiceTone: voiceTone ?? this.voiceTone,
    );
  }
}

class BrainReflection {
  final String userIntent;
  final AttentionState attentionState;
  final List<PendulumSignal> pendulumSignals;
  final ImportanceLevel importanceLevel;
  final HeartMindAlignment heartMindAlignment;
  final FraileResonance fraileResonance;
  final List<DoorCandidate> doorCandidates;
  final DoorDecision? doorDecision;
  final FlowState flowState;
  final RecommendedMove recommendedMove;
  final CompanionExpression companionExpression;
  final String guidance;

  /// Sprint 4 新增：AI 版引導提示（humorHint / mindStatement / heartStatement / integrationPrompt / fraileEvidence）。
  /// 規則版全部 null。Pipeline 從各層 metadata 收集後 merge。
  final GuidanceHint? guidanceHint;

  /// Sprint 0 新增：每層的 LayerResult，供監控面板 v2 (Sprint 6) 顯示。
  /// key = 層名（'intent', 'attention', 'pendulum', 'importance',
  /// 'heartMind', 'fraile', 'doorFlow', 'actionRouter'）。
  /// 規則版（Sprint 1）會填入；現有 TransurfingBrainService.analyze() 不填，預設空。
  final Map<String, LayerResult<dynamic>> layerResults;

  const BrainReflection({
    required this.userIntent,
    required this.attentionState,
    required this.pendulumSignals,
    required this.importanceLevel,
    required this.heartMindAlignment,
    required this.fraileResonance,
    required this.doorCandidates,
    this.doorDecision,
    required this.flowState,
    required this.recommendedMove,
    required this.companionExpression,
    required this.guidance,
    this.guidanceHint,
    this.layerResults = const {},
  });

  bool get hasPendulumSignals => pendulumSignals.isNotEmpty;

  bool get needsAttentionGate =>
      attentionState == AttentionState.captured ||
      attentionState == AttentionState.scattered;

  bool get shouldReduceImportance =>
      importanceLevel == ImportanceLevel.elevated ||
      importanceLevel == ImportanceLevel.excessive;
}
