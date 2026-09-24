// lib/models/capability_advisor.dart
// [以利沙 Capability Advisor 2026-06-25]
// 能力顧問流程的資料模型：狀態機、方案候選、顧問卡完整資料。

import 'bridge_action.dart';

// ── 狀態機 ────────────────────────────────────────────────────────────────────

enum CapabilityAdvisorStep {
  idle,
  checkingBrowse,
  browseGapDetected,
  searching,
  analyzing,
  presentingComparison,
  awaitingSelection,
  solutionSelected,
  verifying,
  verified,
  returningToTask,
  failed,
  cancelled,
}

extension CapabilityAdvisorStepX on CapabilityAdvisorStep {
  String get name => toString().split('.').last;

  static CapabilityAdvisorStep fromName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return CapabilityAdvisorStep.idle;
    }
    return CapabilityAdvisorStep.values.firstWhere(
      (step) => step.name == value.trim(),
      orElse: () => CapabilityAdvisorStep.idle,
    );
  }
}

// ── 部署類型 ──────────────────────────────────────────────────────────────────

enum SolutionDeploymentType { cloud, local, hybrid }

extension SolutionDeploymentTypeX on SolutionDeploymentType {
  String get name => toString().split('.').last;

  static SolutionDeploymentType fromName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return SolutionDeploymentType.cloud;
    }
    return SolutionDeploymentType.values.firstWhere(
      (type) => type.name == value.trim(),
      orElse: () => SolutionDeploymentType.cloud,
    );
  }
}

// ── 方案候選 ──────────────────────────────────────────────────────────────────

class SolutionCandidate {
  final String id;
  final String name;
  final String provider;
  final String officialUrl;
  final SolutionDeploymentType deploymentType;

  // 四維度分析結果
  final String budgetSummary;
  final bool hasFreeTier;
  final String paidPricingNote;
  final String chineseSupportLevel;
  final int chineseSupportScore;
  final String usageFrequencyFit;
  final int usageFrequencyScore;
  final String intentFitNote;
  final int intentFitScore;

  // 行動資訊
  final List<String> setupSteps;
  final String aiNote;
  final int overallScore;
  final bool isRecommended;

  const SolutionCandidate({
    required this.id,
    required this.name,
    required this.provider,
    required this.officialUrl,
    required this.deploymentType,
    required this.budgetSummary,
    required this.hasFreeTier,
    required this.paidPricingNote,
    required this.chineseSupportLevel,
    required this.chineseSupportScore,
    required this.usageFrequencyFit,
    required this.usageFrequencyScore,
    required this.intentFitNote,
    required this.intentFitScore,
    required this.setupSteps,
    required this.aiNote,
    required this.overallScore,
    required this.isRecommended,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'provider': provider,
    'officialUrl': officialUrl,
    'deploymentType': deploymentType.name,
    'budgetSummary': budgetSummary,
    'hasFreeTier': hasFreeTier,
    'paidPricingNote': paidPricingNote,
    'chineseSupportLevel': chineseSupportLevel,
    'chineseSupportScore': chineseSupportScore,
    'usageFrequencyFit': usageFrequencyFit,
    'usageFrequencyScore': usageFrequencyScore,
    'intentFitNote': intentFitNote,
    'intentFitScore': intentFitScore,
    'setupSteps': setupSteps,
    'aiNote': aiNote,
    'overallScore': overallScore,
    'isRecommended': isRecommended,
  };

  static SolutionCandidate? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final name = json['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;

    int scoreValue(Object? value, [int fallback = 0]) {
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed == null) return fallback;
      return parsed.clamp(0, 100);
    }

    return SolutionCandidate(
      id: id,
      name: name,
      provider: json['provider']?.toString().trim() ?? '',
      officialUrl: json['officialUrl']?.toString().trim() ?? '',
      deploymentType: SolutionDeploymentTypeX.fromName(
        json['deploymentType']?.toString(),
      ),
      budgetSummary: json['budgetSummary']?.toString().trim() ?? '',
      hasFreeTier: json['hasFreeTier'] == true,
      paidPricingNote: json['paidPricingNote']?.toString().trim() ?? '',
      chineseSupportLevel:
          json['chineseSupportLevel']?.toString().trim() ?? '',
      chineseSupportScore: scoreValue(json['chineseSupportScore']),
      usageFrequencyFit: json['usageFrequencyFit']?.toString().trim() ?? '',
      usageFrequencyScore: scoreValue(json['usageFrequencyScore']),
      intentFitNote: json['intentFitNote']?.toString().trim() ?? '',
      intentFitScore: scoreValue(json['intentFitScore']),
      setupSteps:
          (json['setupSteps'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      aiNote: json['aiNote']?.toString().trim() ?? '',
      overallScore: scoreValue(json['overallScore']),
      isRecommended: json['isRecommended'] == true,
    );
  }
}

// ── 缺口堆疊上下文 ────────────────────────────────────────────────────────────

class AdvisorGapContext {
  final String gapType;
  final String gapLabel;
  final String userRequest;
  final String? originalActionJson;
  final CapabilityAdvisorStep suspendedAtStep;

  const AdvisorGapContext({
    required this.gapType,
    required this.gapLabel,
    required this.userRequest,
    this.originalActionJson,
    required this.suspendedAtStep,
  });

  Map<String, dynamic> toJson() => {
    'gapType': gapType,
    'gapLabel': gapLabel,
    'userRequest': userRequest,
    if (originalActionJson != null) 'originalActionJson': originalActionJson,
    'suspendedAtStep': suspendedAtStep.name,
  };

  static AdvisorGapContext? fromJson(Map<String, dynamic> json) {
    final gapType = json['gapType']?.toString().trim();
    final gapLabel = json['gapLabel']?.toString().trim();
    if (gapType == null || gapType.isEmpty) return null;
    return AdvisorGapContext(
      gapType: gapType,
      gapLabel: gapLabel ?? '',
      userRequest: json['userRequest']?.toString().trim() ?? '',
      originalActionJson: json['originalActionJson']?.toString(),
      suspendedAtStep: CapabilityAdvisorStepX.fromName(
        json['suspendedAtStep']?.toString(),
      ),
    );
  }
}

// ── 顧問卡完整資料模型 ────────────────────────────────────────────────────────

class CapabilityAdvisorCardData {
  final String id;

  // 缺口資訊
  final String gapType;
  final String gapLabel;
  final String userRequest;
  final BridgeAction? originalAction;

  // 流程狀態
  final CapabilityAdvisorStep currentStep;
  final String statusMessage;

  // AI 意圖推斷
  final String? inferredIntent;
  final String? confirmedIntent;

  // 方案候選
  final List<SolutionCandidate> candidates;
  final String? selectedCandidateId;

  // 驗證
  final String? verificationResult;
  final bool? verificationPassed;

  // 任務回流
  final String? pendingTaskId;

  // Browse 堆疊
  final AdvisorGapContext? suspendedGap;

  // 元資料
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;

  const CapabilityAdvisorCardData({
    required this.id,
    required this.gapType,
    required this.gapLabel,
    required this.userRequest,
    this.originalAction,
    required this.currentStep,
    required this.statusMessage,
    this.inferredIntent,
    this.confirmedIntent,
    this.candidates = const [],
    this.selectedCandidateId,
    this.verificationResult,
    this.verificationPassed,
    this.pendingTaskId,
    this.suspendedGap,
    required this.createdAt,
    this.updatedAt,
    this.metadata = const {},
  });

  // ── 序列化 ──

  Map<String, dynamic> toJson() => {
    'id': id,
    'gapType': gapType,
    'gapLabel': gapLabel,
    'userRequest': userRequest,
    if (originalAction != null) 'originalAction': originalAction!.toJson(),
    'currentStep': currentStep.name,
    'statusMessage': statusMessage,
    if (inferredIntent != null) 'inferredIntent': inferredIntent,
    if (confirmedIntent != null) 'confirmedIntent': confirmedIntent,
    'candidates': candidates.map((c) => c.toJson()).toList(),
    if (selectedCandidateId != null) 'selectedCandidateId': selectedCandidateId,
    if (verificationResult != null) 'verificationResult': verificationResult,
    if (verificationPassed != null) 'verificationPassed': verificationPassed,
    if (pendingTaskId != null) 'pendingTaskId': pendingTaskId,
    if (suspendedGap != null) 'suspendedGap': suspendedGap!.toJson(),
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'metadata': metadata,
  };

  static CapabilityAdvisorCardData? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final gapType = json['gapType']?.toString().trim();
    if (id == null || id.isEmpty || gapType == null || gapType.isEmpty) {
      return null;
    }

    BridgeAction? originalAction;
    final originalActionJson = json['originalAction'];
    if (originalActionJson is Map<String, dynamic>) {
      originalAction = BridgeAction.fromJson(originalActionJson);
    }

    AdvisorGapContext? suspendedGap;
    final suspendedGapJson = json['suspendedGap'];
    if (suspendedGapJson is Map<String, dynamic>) {
      suspendedGap = AdvisorGapContext.fromJson(suspendedGapJson);
    }

    return CapabilityAdvisorCardData(
      id: id,
      gapType: gapType,
      gapLabel: json['gapLabel']?.toString().trim() ?? '',
      userRequest: json['userRequest']?.toString().trim() ?? '',
      originalAction: originalAction,
      currentStep: CapabilityAdvisorStepX.fromName(
        json['currentStep']?.toString(),
      ),
      statusMessage: json['statusMessage']?.toString().trim() ?? '',
      inferredIntent: json['inferredIntent']?.toString(),
      confirmedIntent: json['confirmedIntent']?.toString(),
      candidates:
          (json['candidates'] as List<dynamic>?)
              ?.map((item) => item is Map<String, dynamic>
                  ? SolutionCandidate.fromJson(item)
                  : null)
              .whereType<SolutionCandidate>()
              .toList() ??
          const [],
      selectedCandidateId: json['selectedCandidateId']?.toString(),
      verificationResult: json['verificationResult']?.toString(),
      verificationPassed: json['verificationPassed'] as bool?,
      pendingTaskId: json['pendingTaskId']?.toString(),
      suspendedGap: suspendedGap,
      createdAt: DateTime.tryParse(
            json['createdAt']?.toString() ?? '',
          ) ??
          DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : const {},
    );
  }

  // ── copyWith ──

  CapabilityAdvisorCardData copyWith({
    String? id,
    String? gapType,
    String? gapLabel,
    String? userRequest,
    BridgeAction? originalAction,
    CapabilityAdvisorStep? currentStep,
    String? statusMessage,
    String? inferredIntent,
    String? confirmedIntent,
    List<SolutionCandidate>? candidates,
    String? selectedCandidateId,
    String? verificationResult,
    bool? verificationPassed,
    String? pendingTaskId,
    AdvisorGapContext? suspendedGap,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return CapabilityAdvisorCardData(
      id: id ?? this.id,
      gapType: gapType ?? this.gapType,
      gapLabel: gapLabel ?? this.gapLabel,
      userRequest: userRequest ?? this.userRequest,
      originalAction: originalAction ?? this.originalAction,
      currentStep: currentStep ?? this.currentStep,
      statusMessage: statusMessage ?? this.statusMessage,
      inferredIntent: inferredIntent ?? this.inferredIntent,
      confirmedIntent: confirmedIntent ?? this.confirmedIntent,
      candidates: candidates ?? this.candidates,
      selectedCandidateId: selectedCandidateId ?? this.selectedCandidateId,
      verificationResult: verificationResult ?? this.verificationResult,
      verificationPassed: verificationPassed ?? this.verificationPassed,
      pendingTaskId: pendingTaskId ?? this.pendingTaskId,
      suspendedGap: suspendedGap ?? this.suspendedGap,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      metadata: metadata ?? this.metadata,
    );
  }

  // ── 便利 getter ──

  SolutionCandidate? get selectedCandidate {
    if (selectedCandidateId == null) return null;
    for (final c in candidates) {
      if (c.id == selectedCandidateId) return c;
    }
    return null;
  }
}
