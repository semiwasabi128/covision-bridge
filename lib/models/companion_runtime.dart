import 'agent_activity.dart';

class CompanionFirstAction {
  final String title;
  final String detail;
  final String prompt;
  final String ctaLabel;

  const CompanionFirstAction({
    required this.title,
    required this.detail,
    required this.prompt,
    this.ctaLabel = '交給夥伴開始',
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'detail': detail,
    'prompt': prompt,
    'ctaLabel': ctaLabel,
  };
}

class CompanionBridgeEvidence {
  final String summary;
  final String status;
  final String reply;
  final DateTime occurredAt;

  const CompanionBridgeEvidence({
    required this.summary,
    required this.status,
    required this.reply,
    required this.occurredAt,
  });

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'status': status,
    'reply': reply,
    'occurredAt': occurredAt.toIso8601String(),
  };
}

class CompanionLocalRuntimeSignal {
  final String phase;
  final String title;
  final String detail;
  final String label;
  final double? progress;
  final DateTime occurredAt;

  const CompanionLocalRuntimeSignal({
    required this.phase,
    required this.title,
    required this.detail,
    required this.label,
    this.progress,
    required this.occurredAt,
  });

  Map<String, dynamic> toJson() => {
    'phase': phase,
    'title': title,
    'detail': detail,
    'label': label,
    'progress': progress,
    'occurredAt': occurredAt.toIso8601String(),
  };
}

class CompanionRuntimeState {
  final String? activeCompanionId;
  final String activeCompanionName;
  final String activeCompanionRole;
  final AgentActivitySnapshot activity;
  final String statusText;
  final CompanionFirstAction? firstAction;
  final CompanionBridgeEvidence? latestBridgeEvidence;
  final CompanionLocalRuntimeSignal? latestLocalRuntimeSignal;
  final DateTime updatedAt;

  const CompanionRuntimeState({
    this.activeCompanionId,
    this.activeCompanionName = '你的 Agent',
    this.activeCompanionRole = '橋樑代理人',
    this.activity = const AgentActivitySnapshot(),
    this.statusText = '自由待機',
    this.firstAction,
    this.latestBridgeEvidence,
    this.latestLocalRuntimeSignal,
    required this.updatedAt,
  });

  factory CompanionRuntimeState.initial() {
    return CompanionRuntimeState(
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isActive => activity.active;

  CompanionRuntimeState copyWith({
    String? activeCompanionId,
    String? activeCompanionName,
    String? activeCompanionRole,
    AgentActivitySnapshot? activity,
    String? statusText,
    CompanionFirstAction? firstAction,
    CompanionBridgeEvidence? latestBridgeEvidence,
    CompanionLocalRuntimeSignal? latestLocalRuntimeSignal,
    DateTime? updatedAt,
    bool clearActiveCompanion = false,
    bool clearFirstAction = false,
    bool clearLatestBridgeEvidence = false,
    bool clearLatestLocalRuntimeSignal = false,
  }) {
    return CompanionRuntimeState(
      activeCompanionId: clearActiveCompanion
          ? null
          : activeCompanionId ?? this.activeCompanionId,
      activeCompanionName: activeCompanionName ?? this.activeCompanionName,
      activeCompanionRole: activeCompanionRole ?? this.activeCompanionRole,
      activity: activity ?? this.activity,
      statusText: statusText ?? this.statusText,
      firstAction: clearFirstAction ? null : firstAction ?? this.firstAction,
      latestBridgeEvidence: clearLatestBridgeEvidence
          ? null
          : latestBridgeEvidence ?? this.latestBridgeEvidence,
      latestLocalRuntimeSignal: clearLatestLocalRuntimeSignal
          ? null
          : latestLocalRuntimeSignal ?? this.latestLocalRuntimeSignal,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'activeCompanionId': activeCompanionId,
    'activeCompanionName': activeCompanionName,
    'activeCompanionRole': activeCompanionRole,
    'statusText': statusText,
    'firstAction': firstAction?.toJson(),
    'latestBridgeEvidence': latestBridgeEvidence?.toJson(),
    'latestLocalRuntimeSignal': latestLocalRuntimeSignal?.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
    'activity': {
      'stage': activity.stage.shortLabel,
      'stageLabel': activity.stage.label,
      'mood': activity.mood.name,
      'action': activity.action.name,
      'active': activity.active,
      'pulse': activity.pulse,
      'tick': activity.tick,
      'telemetry': {
        'messages': activity.telemetry.messages,
        'chars': activity.telemetry.chars,
        'memories': activity.telemetry.memories,
        'bridgeActions': activity.telemetry.bridgeActions,
        'attachments': activity.telemetry.attachments,
        'tokens': activity.telemetry.tokens,
      },
    },
  };
}
