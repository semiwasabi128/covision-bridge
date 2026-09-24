// lib/models/chat_card_data.dart
// [以利沙 Sprint 1 2026-06-24]
// Card data models extracted from chat_screen.dart for cross-file reuse.

// ── Card prefix constants ────────────────────────────────────────────────────

const capabilityCardPrefix = 'BRIDGE_CAPABILITY_CARD_V1:';
const capabilityAdvisorCardPrefix = 'CAPABILITY_ADVISOR:';
const projectDoorCardPrefix = 'BRIDGE_PROJECT_DOOR_CARD_V1:';
const projectContextTransferCardPrefix =
    'BRIDGE_PROJECT_CONTEXT_TRANSFER_CARD_V1:';
const digitalAssetInvocationCardPrefix =
    'BRIDGE_DIGITAL_ASSET_INVOCATION_CARD_V1:';
const digitalAssetReusePlanCardPrefix =
    'BRIDGE_DIGITAL_ASSET_REUSE_PLAN_CARD_V1:';
const projectForkCompleteCardPrefix = 'BRIDGE_PROJECT_FORK_COMPLETE_CARD_V1:';
const projectForkIntroCardPrefix = 'BRIDGE_PROJECT_FORK_INTRO_CARD_V1:';
const digitalAssetResultCardPrefix = 'BRIDGE_DIGITAL_ASSET_RESULT_CARD_V1:';
const managedFolderRulePickerCardPrefix =
    'BRIDGE_MANAGED_FOLDER_RULE_PICKER_CARD_V1:';
const canvasImportCardPrefix = 'BRIDGE_CANVAS_IMPORT_CARD_V1:';

// ── Card data models ─────────────────────────────────────────────────────────

class CapabilityGapCardData {
  final String title;
  final String request;
  final String missing;
  final String status;
  final String route;
  final String routeLabel;
  final String iconName;
  final List<String> steps;
  final List<String> providerHints;
  final String? pendingTaskId;

  const CapabilityGapCardData({
    required this.title,
    required this.request,
    required this.missing,
    required this.status,
    required this.route,
    required this.routeLabel,
    required this.iconName,
    required this.steps,
    this.providerHints = const [],
    this.pendingTaskId,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'request': request,
      'missing': missing,
      'status': status,
      'route': route,
      'routeLabel': routeLabel,
      'iconName': iconName,
      'steps': steps,
      'providerHints': providerHints,
      if (pendingTaskId != null) 'pendingTaskId': pendingTaskId,
    };
  }

  static CapabilityGapCardData? fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString().trim();
    final request = json['request']?.toString().trim();
    final missing = json['missing']?.toString().trim();
    final status = json['status']?.toString().trim();
    final route = json['route']?.toString().trim();
    final routeLabel = json['routeLabel']?.toString().trim();
    final iconName = json['iconName']?.toString().trim();
    if (title == null ||
        title.isEmpty ||
        request == null ||
        request.isEmpty ||
        missing == null ||
        missing.isEmpty ||
        status == null ||
        status.isEmpty ||
        route == null ||
        route.isEmpty ||
        routeLabel == null ||
        routeLabel.isEmpty ||
        iconName == null ||
        iconName.isEmpty) {
      return null;
    }
    return CapabilityGapCardData(
      title: title,
      request: request,
      missing: missing,
      status: status,
      route: route,
      routeLabel: routeLabel,
      iconName: iconName,
      steps:
          (json['steps'] as List<dynamic>?)
              ?.map((step) => step.toString())
              .where((step) => step.trim().isNotEmpty)
              .toList() ??
          const [],
      providerHints:
          (json['providerHints'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      pendingTaskId: json['pendingTaskId']?.toString(),
    );
  }

  CapabilityGapCardData copyWith({String? pendingTaskId}) {
    return CapabilityGapCardData(
      title: title,
      request: request,
      missing: missing,
      status: status,
      route: route,
      routeLabel: routeLabel,
      iconName: iconName,
      steps: steps,
      providerHints: providerHints,
      pendingTaskId: pendingTaskId ?? this.pendingTaskId,
    );
  }
}

class ProjectDoorCardData {
  final String title;
  final String sourceIntent;
  final String firstFlow;
  final List<String> intakeQuestions;
  final List<String> requiredBridges;
  final double confidence;
  final List<String> confidenceSignals;
  final bool forkFromConversation;
  final String? sourceConversationId;
  final String? sourceConversationTitle;
  final List<String> contextLines;

  const ProjectDoorCardData({
    required this.title,
    required this.sourceIntent,
    required this.firstFlow,
    required this.intakeQuestions,
    required this.requiredBridges,
    this.confidence = 0.72,
    this.confidenceSignals = const [],
    this.forkFromConversation = false,
    this.sourceConversationId,
    this.sourceConversationTitle,
    this.contextLines = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'sourceIntent': sourceIntent,
      'firstFlow': firstFlow,
      'intakeQuestions': intakeQuestions,
      'requiredBridges': requiredBridges,
      'confidence': confidence,
      'confidenceSignals': confidenceSignals,
      'forkFromConversation': forkFromConversation,
      'sourceConversationId': sourceConversationId,
      'sourceConversationTitle': sourceConversationTitle,
      'contextLines': contextLines,
    };
  }

  static ProjectDoorCardData? fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString().trim();
    final sourceIntent = json['sourceIntent']?.toString().trim();
    final firstFlow = json['firstFlow']?.toString().trim();
    if (title == null ||
        title.isEmpty ||
        sourceIntent == null ||
        sourceIntent.isEmpty ||
        firstFlow == null ||
        firstFlow.isEmpty) {
      return null;
    }
    return ProjectDoorCardData(
      title: title,
      sourceIntent: sourceIntent,
      firstFlow: firstFlow,
      intakeQuestions:
          (json['intakeQuestions'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      requiredBridges:
          (json['requiredBridges'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      confidence:
          double.tryParse(
            json['confidence']?.toString() ?? '',
          )?.clamp(0.0, 1.0) ??
          0.72,
      confidenceSignals:
          (json['confidenceSignals'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      forkFromConversation: json['forkFromConversation'] == true,
      sourceConversationId: json['sourceConversationId']?.toString(),
      sourceConversationTitle: json['sourceConversationTitle']?.toString(),
      contextLines:
          (json['contextLines'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class ProjectContextTransferCardData {
  final String targetProjectId;
  final String targetProjectTitle;
  final String sourceConversationId;
  final String sourceConversationTitle;
  final String ideaSummary;
  final List<String> contextLines;

  const ProjectContextTransferCardData({
    required this.targetProjectId,
    required this.targetProjectTitle,
    required this.sourceConversationId,
    required this.sourceConversationTitle,
    required this.ideaSummary,
    required this.contextLines,
  });

  Map<String, dynamic> toJson() {
    return {
      'targetProjectId': targetProjectId,
      'targetProjectTitle': targetProjectTitle,
      'sourceConversationId': sourceConversationId,
      'sourceConversationTitle': sourceConversationTitle,
      'ideaSummary': ideaSummary,
      'contextLines': contextLines,
    };
  }

  static ProjectContextTransferCardData? fromJson(Map<String, dynamic> json) {
    final targetProjectId = json['targetProjectId']?.toString().trim();
    final targetProjectTitle = json['targetProjectTitle']?.toString().trim();
    final sourceConversationId = json['sourceConversationId']
        ?.toString()
        .trim();
    final sourceConversationTitle = json['sourceConversationTitle']
        ?.toString()
        .trim();
    final ideaSummary = json['ideaSummary']?.toString().trim();
    if (targetProjectId == null ||
        targetProjectId.isEmpty ||
        targetProjectTitle == null ||
        targetProjectTitle.isEmpty ||
        sourceConversationId == null ||
        sourceConversationId.isEmpty ||
        sourceConversationTitle == null ||
        sourceConversationTitle.isEmpty ||
        ideaSummary == null ||
        ideaSummary.isEmpty) {
      return null;
    }
    return ProjectContextTransferCardData(
      targetProjectId: targetProjectId,
      targetProjectTitle: targetProjectTitle,
      sourceConversationId: sourceConversationId,
      sourceConversationTitle: sourceConversationTitle,
      ideaSummary: ideaSummary,
      contextLines:
          (json['contextLines'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class DigitalAssetInvocationCardData {
  final String assetId;
  final String assetTitle;
  final String assetKind;
  final String assetSummary;
  final String sourceLabel;
  final List<String> capabilities;
  final List<String> reusableScenes;
  final List<String> matchReasons;
  final String targetProjectId;
  final String targetProjectTitle;
  final String request;

  const DigitalAssetInvocationCardData({
    required this.assetId,
    required this.assetTitle,
    required this.assetKind,
    required this.assetSummary,
    required this.sourceLabel,
    required this.capabilities,
    required this.reusableScenes,
    required this.matchReasons,
    required this.targetProjectId,
    required this.targetProjectTitle,
    required this.request,
  });

  Map<String, dynamic> toJson() {
    return {
      'assetId': assetId,
      'assetTitle': assetTitle,
      'assetKind': assetKind,
      'assetSummary': assetSummary,
      'sourceLabel': sourceLabel,
      'capabilities': capabilities,
      'reusableScenes': reusableScenes,
      'matchReasons': matchReasons,
      'targetProjectId': targetProjectId,
      'targetProjectTitle': targetProjectTitle,
      'request': request,
    };
  }

  static DigitalAssetInvocationCardData? fromJson(Map<String, dynamic> json) {
    final assetId = json['assetId']?.toString().trim();
    final assetTitle = json['assetTitle']?.toString().trim();
    final assetKind = json['assetKind']?.toString().trim();
    final targetProjectId = json['targetProjectId']?.toString().trim();
    final targetProjectTitle = json['targetProjectTitle']?.toString().trim();
    final request = json['request']?.toString().trim();
    if (assetId == null ||
        assetId.isEmpty ||
        assetTitle == null ||
        assetTitle.isEmpty ||
        assetKind == null ||
        assetKind.isEmpty ||
        targetProjectId == null ||
        targetProjectId.isEmpty ||
        targetProjectTitle == null ||
        targetProjectTitle.isEmpty ||
        request == null ||
        request.isEmpty) {
      return null;
    }
    return DigitalAssetInvocationCardData(
      assetId: assetId,
      assetTitle: assetTitle,
      assetKind: assetKind,
      assetSummary: json['assetSummary']?.toString().trim() ?? '',
      sourceLabel: json['sourceLabel']?.toString().trim() ?? '',
      capabilities:
          (json['capabilities'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      reusableScenes:
          (json['reusableScenes'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      matchReasons:
          (json['matchReasons'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      targetProjectId: targetProjectId,
      targetProjectTitle: targetProjectTitle,
      request: request,
    );
  }
}

class DigitalAssetReusePlanCardData {
  final String assetId;
  final String assetTitle;
  final String assetKind;
  final String targetProjectId;
  final String targetProjectTitle;
  final String request;
  final String suggestedAction;
  final String planSummary;
  final List<String> nextSteps;
  final List<String> capabilities;
  final List<String> reusableScenes;

  const DigitalAssetReusePlanCardData({
    required this.assetId,
    required this.assetTitle,
    required this.assetKind,
    required this.targetProjectId,
    required this.targetProjectTitle,
    required this.request,
    required this.suggestedAction,
    required this.planSummary,
    required this.nextSteps,
    required this.capabilities,
    required this.reusableScenes,
  });

  String get readableSummary {
    return [
      '已引用資產：$assetTitle',
      '目前專案：$targetProjectTitle',
      '下一步任務：$suggestedAction',
      if (planSummary.trim().isNotEmpty) '草案摘要：$planSummary',
      if (nextSteps.isNotEmpty) '執行順序：${nextSteps.join(' / ')}',
      if (capabilities.isNotEmpty) '帶入能力：${capabilities.take(5).join('、')}',
      if (reusableScenes.isNotEmpty) '可用場景：${reusableScenes.take(5).join('、')}',
    ].join('\n');
  }

  Map<String, dynamic> toJson() {
    return {
      'assetId': assetId,
      'assetTitle': assetTitle,
      'assetKind': assetKind,
      'targetProjectId': targetProjectId,
      'targetProjectTitle': targetProjectTitle,
      'request': request,
      'suggestedAction': suggestedAction,
      'planSummary': planSummary,
      'nextSteps': nextSteps,
      'capabilities': capabilities,
      'reusableScenes': reusableScenes,
    };
  }

  static DigitalAssetReusePlanCardData? fromJson(Map<String, dynamic> json) {
    final assetId = json['assetId']?.toString().trim();
    final assetTitle = json['assetTitle']?.toString().trim();
    final assetKind = json['assetKind']?.toString().trim();
    final targetProjectId = json['targetProjectId']?.toString().trim();
    final targetProjectTitle = json['targetProjectTitle']?.toString().trim();
    final request = json['request']?.toString().trim();
    final suggestedAction = json['suggestedAction']?.toString().trim();
    if (assetId == null ||
        assetId.isEmpty ||
        assetTitle == null ||
        assetTitle.isEmpty ||
        assetKind == null ||
        assetKind.isEmpty ||
        targetProjectId == null ||
        targetProjectId.isEmpty ||
        targetProjectTitle == null ||
        targetProjectTitle.isEmpty ||
        request == null ||
        request.isEmpty ||
        suggestedAction == null ||
        suggestedAction.isEmpty) {
      return null;
    }
    return DigitalAssetReusePlanCardData(
      assetId: assetId,
      assetTitle: assetTitle,
      assetKind: assetKind,
      targetProjectId: targetProjectId,
      targetProjectTitle: targetProjectTitle,
      request: request,
      suggestedAction: suggestedAction,
      planSummary: json['planSummary']?.toString().trim() ?? '',
      nextSteps:
          (json['nextSteps'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      capabilities:
          (json['capabilities'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      reusableScenes:
          (json['reusableScenes'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class ProjectForkCompleteCardData {
  final String targetProjectId;
  final String targetProjectTitle;
  final String sourceProjectId;
  final String sourceProjectTitle;
  final int contextCount;
  final String assetTitle;

  const ProjectForkCompleteCardData({
    required this.targetProjectId,
    required this.targetProjectTitle,
    required this.sourceProjectId,
    required this.sourceProjectTitle,
    required this.contextCount,
    required this.assetTitle,
  });

  Map<String, dynamic> toJson() {
    return {
      'targetProjectId': targetProjectId,
      'targetProjectTitle': targetProjectTitle,
      'sourceProjectId': sourceProjectId,
      'sourceProjectTitle': sourceProjectTitle,
      'contextCount': contextCount,
      'assetTitle': assetTitle,
    };
  }

  static ProjectForkCompleteCardData? fromJson(Map<String, dynamic> json) {
    final targetProjectId = json['targetProjectId']?.toString().trim();
    final targetProjectTitle = json['targetProjectTitle']?.toString().trim();
    final sourceProjectId = json['sourceProjectId']?.toString().trim();
    final sourceProjectTitle = json['sourceProjectTitle']?.toString().trim();
    if (targetProjectId == null ||
        targetProjectId.isEmpty ||
        targetProjectTitle == null ||
        targetProjectTitle.isEmpty ||
        sourceProjectTitle == null ||
        sourceProjectTitle.isEmpty) {
      return null;
    }
    return ProjectForkCompleteCardData(
      targetProjectId: targetProjectId,
      targetProjectTitle: targetProjectTitle,
      sourceProjectId: sourceProjectId ?? '',
      sourceProjectTitle: sourceProjectTitle,
      contextCount:
          int.tryParse(json['contextCount']?.toString() ?? '')?.clamp(0, 999) ??
          0,
      assetTitle: json['assetTitle']?.toString().trim() ?? '',
    );
  }
}

class ProjectForkIntroCardData {
  final String projectTitle;
  final String sourceProjectTitle;
  final String forkReason;
  final List<String> contextLines;
  final String currentFlow;
  final List<String> intakeQuestions;
  final List<String> requiredBridges;
  final String assetTitle;

  const ProjectForkIntroCardData({
    required this.projectTitle,
    required this.sourceProjectTitle,
    required this.forkReason,
    required this.contextLines,
    required this.currentFlow,
    required this.intakeQuestions,
    required this.requiredBridges,
    required this.assetTitle,
  });

  Map<String, dynamic> toJson() {
    return {
      'projectTitle': projectTitle,
      'sourceProjectTitle': sourceProjectTitle,
      'forkReason': forkReason,
      'contextLines': contextLines,
      'currentFlow': currentFlow,
      'intakeQuestions': intakeQuestions,
      'requiredBridges': requiredBridges,
      'assetTitle': assetTitle,
    };
  }

  static ProjectForkIntroCardData? fromJson(Map<String, dynamic> json) {
    final projectTitle = json['projectTitle']?.toString().trim();
    final sourceProjectTitle = json['sourceProjectTitle']?.toString().trim();
    final forkReason = json['forkReason']?.toString().trim();
    final currentFlow = json['currentFlow']?.toString().trim();
    if (projectTitle == null ||
        projectTitle.isEmpty ||
        sourceProjectTitle == null ||
        sourceProjectTitle.isEmpty ||
        forkReason == null ||
        forkReason.isEmpty ||
        currentFlow == null ||
        currentFlow.isEmpty) {
      return null;
    }
    return ProjectForkIntroCardData(
      projectTitle: projectTitle,
      sourceProjectTitle: sourceProjectTitle,
      forkReason: forkReason,
      currentFlow: currentFlow,
      contextLines:
          (json['contextLines'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      intakeQuestions:
          (json['intakeQuestions'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      requiredBridges:
          (json['requiredBridges'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      assetTitle: json['assetTitle']?.toString().trim() ?? '',
    );
  }
}

class DigitalAssetResultCardData {
  final String assetId;
  final String assetTitle;
  final String assetKind;
  final String assetSummary;
  final String sourceProjectTitle;
  final List<String> capabilities;
  final List<String> reusableScenes;
  final List<String> availableProjects;

  const DigitalAssetResultCardData({
    required this.assetId,
    required this.assetTitle,
    required this.assetKind,
    required this.assetSummary,
    required this.sourceProjectTitle,
    required this.capabilities,
    required this.reusableScenes,
    required this.availableProjects,
  });

  Map<String, dynamic> toJson() {
    return {
      'assetId': assetId,
      'assetTitle': assetTitle,
      'assetKind': assetKind,
      'assetSummary': assetSummary,
      'sourceProjectTitle': sourceProjectTitle,
      'capabilities': capabilities,
      'reusableScenes': reusableScenes,
      'availableProjects': availableProjects,
    };
  }

  static DigitalAssetResultCardData? fromJson(Map<String, dynamic> json) {
    final assetId = json['assetId']?.toString().trim();
    final assetTitle = json['assetTitle']?.toString().trim();
    final assetKind = json['assetKind']?.toString().trim();
    if (assetId == null ||
        assetId.isEmpty ||
        assetTitle == null ||
        assetTitle.isEmpty ||
        assetKind == null ||
        assetKind.isEmpty) {
      return null;
    }
    return DigitalAssetResultCardData(
      assetId: assetId,
      assetTitle: assetTitle,
      assetKind: assetKind,
      assetSummary: json['assetSummary']?.toString().trim() ?? '',
      sourceProjectTitle: json['sourceProjectTitle']?.toString().trim() ?? '',
      capabilities:
          (json['capabilities'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      reusableScenes:
          (json['reusableScenes'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      availableProjects:
          (json['availableProjects'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class ManagedFolderRulePickerItem {
  final String id;
  final String ruleTitle;
  final String folderLabel;
  final String folderPath;
  final String rulePath;
  final String modeLabel;
  final String categorySummary;
  final bool builtIn;

  const ManagedFolderRulePickerItem({
    required this.id,
    required this.ruleTitle,
    required this.folderLabel,
    required this.folderPath,
    required this.rulePath,
    required this.modeLabel,
    required this.categorySummary,
    required this.builtIn,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ruleTitle': ruleTitle,
      'folderLabel': folderLabel,
      'folderPath': folderPath,
      'rulePath': rulePath,
      'modeLabel': modeLabel,
      'categorySummary': categorySummary,
      'builtIn': builtIn,
    };
  }

  static ManagedFolderRulePickerItem? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final ruleTitle = json['ruleTitle']?.toString().trim();
    final folderLabel = json['folderLabel']?.toString().trim();
    final folderPath = json['folderPath']?.toString().trim();
    final rulePath = json['rulePath']?.toString().trim();
    if (id == null ||
        id.isEmpty ||
        ruleTitle == null ||
        ruleTitle.isEmpty ||
        folderLabel == null ||
        folderLabel.isEmpty ||
        folderPath == null ||
        folderPath.isEmpty ||
        rulePath == null ||
        rulePath.isEmpty) {
      return null;
    }
    return ManagedFolderRulePickerItem(
      id: id,
      ruleTitle: ruleTitle,
      folderLabel: folderLabel,
      folderPath: folderPath,
      rulePath: rulePath,
      modeLabel: json['modeLabel']?.toString().trim() ?? '安全模式：先偵測與建議',
      categorySummary: json['categorySummary']?.toString().trim() ?? '',
      builtIn: json['builtIn'] == true,
    );
  }
}

class ManagedFolderRulePickerCardData {
  final String request;
  final List<ManagedFolderRulePickerItem> rules;
  final String? targetFolderPath;
  final String? targetFolderLabel;

  const ManagedFolderRulePickerCardData({
    required this.request,
    required this.rules,
    this.targetFolderPath,
    this.targetFolderLabel,
  });

  Map<String, dynamic> toJson() {
    return {
      'request': request,
      'rules': rules.map((rule) => rule.toJson()).toList(),
      if (targetFolderPath != null) 'targetFolderPath': targetFolderPath,
      if (targetFolderLabel != null) 'targetFolderLabel': targetFolderLabel,
    };
  }

  static ManagedFolderRulePickerCardData? fromJson(Map<String, dynamic> json) {
    final request = json['request']?.toString().trim();
    if (request == null || request.isEmpty) return null;
    return ManagedFolderRulePickerCardData(
      request: request,
      rules:
          (json['rules'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (item) => ManagedFolderRulePickerItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .whereType<ManagedFolderRulePickerItem>()
              .toList() ??
          const [],
      targetFolderPath: json['targetFolderPath']?.toString().trim(),
      targetFolderLabel: json['targetFolderLabel']?.toString().trim(),
    );
  }
}

// ── Project semantic routing ─────────────────────────────────────────────────

enum ProjectSemanticRouteKind {
  none,
  createProjectDoor,
  transferContext,
  invokeDigitalAsset,
}

class ProjectSemanticRoute {
  final ProjectSemanticRouteKind kind;
  final double confidence;
  final List<String> signals;
  final ProjectDoorCardData? projectDoor;
  final ProjectContextTransferCardData? contextTransfer;
  final DigitalAssetInvocationCardData? digitalAssetInvocation;

  const ProjectSemanticRoute._({
    required this.kind,
    this.confidence = 0,
    this.signals = const [],
    this.projectDoor,
    this.contextTransfer,
    this.digitalAssetInvocation,
  });

  const ProjectSemanticRoute.none()
    : this._(kind: ProjectSemanticRouteKind.none);

  ProjectSemanticRoute.projectDoor(ProjectDoorCardData card)
    : this._(
        kind: ProjectSemanticRouteKind.createProjectDoor,
        confidence: card.confidence,
        signals: card.confidenceSignals,
        projectDoor: card,
      );

  ProjectSemanticRoute.contextTransfer(
    ProjectContextTransferCardData card, {
    required List<String> signals,
  }) : this._(
         kind: ProjectSemanticRouteKind.transferContext,
         confidence: 0.82,
         signals: signals,
         contextTransfer: card,
       );

  ProjectSemanticRoute.digitalAssetInvocation(
    DigitalAssetInvocationCardData card, {
    required List<String> signals,
  }) : this._(
         kind: ProjectSemanticRouteKind.invokeDigitalAsset,
         confidence: 0.78,
         signals: signals,
         digitalAssetInvocation: card,
       );

  bool get hasRoute => kind != ProjectSemanticRouteKind.none;

  String get label {
    switch (kind) {
      case ProjectSemanticRouteKind.none:
        return '未命中專案路由';
      case ProjectSemanticRouteKind.createProjectDoor:
        return '建立新專案門';
      case ProjectSemanticRouteKind.transferContext:
        return '移植到既有專案';
      case ProjectSemanticRouteKind.invokeDigitalAsset:
        return '引用數位資產';
    }
  }
}

// ── D11-4: Canvas Import Card ───────────────────────────────────────────────

/// Agent 建議把對話匯入畫布時的卡片資料。
///
/// Agent 在聊天中判斷時機後，回覆帶有 `canvasImportCardPrefix` 的系統訊息，
/// 攜帶此卡片資料。使用者在卡片上選擇新建或匯入既有畫布。
class CanvasImportCardData {
  /// Agent 建議的摘要（Agent 產生，非固定截取）
  final String summary;

  /// Agent 建議的畫布名稱（使用者可改）
  final String suggestedTitle;

  /// 可用既有畫布列表（JSON: [{id, title, status}]）
  final List<ExistingCanvasOption> existingCanvases;

  CanvasImportCardData({
    required this.summary,
    required this.suggestedTitle,
    this.existingCanvases = const [],
  });

  factory CanvasImportCardData.fromJson(Map<String, dynamic> json) =>
      CanvasImportCardData(
        summary: json['summary'] as String? ?? '',
        suggestedTitle: json['suggestedTitle'] as String? ?? '新畫布',
        existingCanvases: (json['existingCanvases'] as List?)
                ?.map((e) => ExistingCanvasOption.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'suggestedTitle': suggestedTitle,
        'existingCanvases': existingCanvases.map((e) => e.toJson()).toList(),
      };
}

/// 既有畫布選項
class ExistingCanvasOption {
  final String id;
  final String title;
  final String status;

  const ExistingCanvasOption({
    required this.id,
    required this.title,
    required this.status,
  });

  factory ExistingCanvasOption.fromJson(Map<String, dynamic> json) =>
      ExistingCanvasOption(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'planning',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status,
      };
}
