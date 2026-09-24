import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/companion.dart';
import 'companion_certification/companion_certification_guard.dart';
import 'semi_dao_review_signal.dart';
import 'semi_dao_visual_review_service.dart';

// [教練 Agent 2026-08-05] SemiDaoReviewSignal 已搬到獨立檔案，這裡 re-export
// 讓既有 import 路徑（semi_dao_review_store.dart）仍可使用，向後相容。
export 'semi_dao_review_signal.dart' show SemiDaoReviewSignal;

enum SemiDaoRiskVote { low, medium, high }

class SemiDaoPlatformCertification {
  final SemiDaoReviewSignal signal;
  final List<String> passedChecks;
  final List<String> warningChecks;
  final List<String> blockedChecks;
  final DateTime certifiedAt;
  final SemiDaoVisualReviewResult? visualReview;
  final List<String> requiredClarifications;

  const SemiDaoPlatformCertification({
    required this.signal,
    required this.passedChecks,
    required this.warningChecks,
    required this.blockedChecks,
    required this.certifiedAt,
    this.visualReview,
    this.requiredClarifications = const [],
  });

  String get signalLabel {
    return switch (signal) {
      SemiDaoReviewSignal.approved => 'SemiDAO 預審綠燈：可進入社群展示',
      SemiDaoReviewSignal.watching => 'SemiDAO 預審黃燈：需補充聲明',
      SemiDaoReviewSignal.blocked => 'SemiDAO 預審紅燈：暫不接受分享',
    };
  }

  Map<String, dynamic> toJson() => {
    'signal': signal.name,
    'signalLabel': signalLabel,
    'passedChecks': passedChecks,
    'warningChecks': warningChecks,
    'blockedChecks': blockedChecks,
    'certifiedAt': certifiedAt.toIso8601String(),
    if (visualReview != null) 'visualReview': visualReview!.toJson(),
    'requiredClarifications': requiredClarifications,
  };

  factory SemiDaoPlatformCertification.fromJson(Map<String, dynamic> json) {
    return SemiDaoPlatformCertification(
      signal: SemiDaoReviewSignal.values.firstWhere(
        (value) => value.name == json['signal'],
        orElse: () => SemiDaoReviewSignal.watching,
      ),
      passedChecks: _stringList(json['passedChecks']),
      warningChecks: _stringList(json['warningChecks']),
      blockedChecks: _stringList(json['blockedChecks']),
      certifiedAt:
          DateTime.tryParse('${json['certifiedAt'] ?? ''}') ?? DateTime.now(),
      visualReview: json['visualReview'] is Map
          ? SemiDaoVisualReviewResult.fromJson(
              Map<String, dynamic>.from(json['visualReview'] as Map),
            )
          : SemiDaoVisualReviewResult.empty(),
      requiredClarifications: _stringList(json['requiredClarifications']),
    );
  }
}

class SemiDaoReviewVote {
  final String voterId;
  final SemiDaoRiskVote risk;
  final int qualityScore;
  final bool hasIdentifiableIp;
  final bool hasOfficialConfusion;
  final bool hasAdultContent;
  final bool hasDisparagement;
  final DateTime votedAt;

  const SemiDaoReviewVote({
    required this.voterId,
    required this.risk,
    required this.qualityScore,
    required this.hasIdentifiableIp,
    required this.hasOfficialConfusion,
    required this.hasAdultContent,
    required this.hasDisparagement,
    required this.votedAt,
  });

  Map<String, dynamic> toJson() => {
    'voterId': voterId,
    'risk': risk.name,
    'qualityScore': qualityScore,
    'hasIdentifiableIp': hasIdentifiableIp,
    'hasOfficialConfusion': hasOfficialConfusion,
    'hasAdultContent': hasAdultContent,
    'hasDisparagement': hasDisparagement,
    'votedAt': votedAt.toIso8601String(),
  };

  factory SemiDaoReviewVote.fromJson(Map<String, dynamic> json) {
    return SemiDaoReviewVote(
      voterId: '${json['voterId'] ?? 'anonymous'}',
      risk: SemiDaoRiskVote.values.firstWhere(
        (value) => value.name == json['risk'],
        orElse: () => SemiDaoRiskVote.medium,
      ),
      qualityScore: (json['qualityScore'] as num?)?.round().clamp(1, 5) ?? 3,
      hasIdentifiableIp: json['hasIdentifiableIp'] == true,
      hasOfficialConfusion: json['hasOfficialConfusion'] == true,
      hasAdultContent: json['hasAdultContent'] == true,
      hasDisparagement: json['hasDisparagement'] == true,
      votedAt: DateTime.tryParse('${json['votedAt'] ?? ''}') ?? DateTime.now(),
    );
  }
}

class SemiDaoReviewCase {
  final String id;
  final String companionId;
  final String companionName;
  final String companionRole;
  final String mbtiCode;
  final String summary;
  final String avatarImagePath;
  final String packJson;
  final DateTime submittedAt;
  final SemiDaoPlatformCertification certification;
  final List<SemiDaoReviewVote> votes;
  final String clarification;

  const SemiDaoReviewCase({
    required this.id,
    required this.companionId,
    required this.companionName,
    required this.companionRole,
    required this.mbtiCode,
    required this.summary,
    required this.avatarImagePath,
    required this.packJson,
    required this.submittedAt,
    required this.certification,
    this.votes = const [],
    this.clarification = '',
  });

  SemiDaoReviewSignal get signal {
    if (votes.isEmpty) return certification.signal;
    final highRiskVotes = votes.where((vote) {
      return vote.risk == SemiDaoRiskVote.high ||
          vote.hasIdentifiableIp ||
          vote.hasOfficialConfusion ||
          vote.hasAdultContent ||
          vote.hasDisparagement;
    }).length;
    final lowRiskVotes = votes
        .where((vote) => vote.risk == SemiDaoRiskVote.low)
        .length;
    if (highRiskVotes >= 2 || highRiskVotes / votes.length >= 0.34) {
      return SemiDaoReviewSignal.blocked;
    }
    if (votes.length >= 3 && lowRiskVotes / votes.length >= 0.67) {
      return SemiDaoReviewSignal.approved;
    }
    return SemiDaoReviewSignal.watching;
  }

  String get signalLabel {
    if (votes.isEmpty) return certification.signalLabel;
    return switch (signal) {
      SemiDaoReviewSignal.approved => 'SemiDAO 社群綠燈：可上架',
      SemiDaoReviewSignal.watching => 'SemiDAO 社群黃燈：審核中',
      SemiDaoReviewSignal.blocked => 'SemiDAO 社群紅燈：暫停散布',
    };
  }

  double get averageQuality {
    if (votes.isEmpty) return 0;
    final total = votes.fold<int>(0, (sum, vote) => sum + vote.qualityScore);
    return total / votes.length;
  }

  int get highRiskCount {
    return votes.where((vote) {
      return vote.risk == SemiDaoRiskVote.high ||
          vote.hasIdentifiableIp ||
          vote.hasOfficialConfusion ||
          vote.hasAdultContent ||
          vote.hasDisparagement;
    }).length;
  }

  SemiDaoReviewCase copyWith({
    SemiDaoPlatformCertification? certification,
    List<SemiDaoReviewVote>? votes,
    String? clarification,
  }) {
    return SemiDaoReviewCase(
      id: id,
      companionId: companionId,
      companionName: companionName,
      companionRole: companionRole,
      mbtiCode: mbtiCode,
      summary: summary,
      avatarImagePath: avatarImagePath,
      packJson: packJson,
      submittedAt: submittedAt,
      certification: certification ?? this.certification,
      votes: votes ?? this.votes,
      clarification: clarification ?? this.clarification,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'companionId': companionId,
    'companionName': companionName,
    'companionRole': companionRole,
    'mbtiCode': mbtiCode,
    'summary': summary,
    'avatarImagePath': avatarImagePath,
    'packJson': packJson,
    'submittedAt': submittedAt.toIso8601String(),
    'certification': certification.toJson(),
    'votes': [for (final vote in votes) vote.toJson()],
    'clarification': clarification,
  };

  factory SemiDaoReviewCase.fromJson(Map<String, dynamic> json) {
    return SemiDaoReviewCase(
      id: '${json['id'] ?? ''}',
      companionId: '${json['companionId'] ?? ''}',
      companionName: '${json['companionName'] ?? '未命名角色'}',
      companionRole: '${json['companionRole'] ?? '夥伴'}',
      mbtiCode: '${json['mbtiCode'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      avatarImagePath: '${json['avatarImagePath'] ?? ''}',
      packJson: '${json['packJson'] ?? ''}',
      submittedAt:
          DateTime.tryParse('${json['submittedAt'] ?? ''}') ?? DateTime.now(),
      certification: json['certification'] is Map
          ? SemiDaoPlatformCertification.fromJson(
              Map<String, dynamic>.from(json['certification'] as Map),
            )
          : SemiDaoPlatformCertification(
              signal: SemiDaoReviewSignal.watching,
              passedChecks: const [],
              warningChecks: const ['舊版送審資料尚未產生平台預審認證。'],
              blockedChecks: const [],
              certifiedAt: DateTime.now(),
            ),
      votes: [
        if (json['votes'] is List)
          for (final vote in json['votes'] as List)
            if (vote is Map)
              SemiDaoReviewVote.fromJson(Map<String, dynamic>.from(vote)),
      ],
      clarification: '${json['clarification'] ?? ''}',
    );
  }
}

class SemiDaoReviewStore {
  static const _storageKey = 'semi_dao_review_cases_v1';
  final SemiDaoVisualReviewService visualReviewService;

  const SemiDaoReviewStore({
    this.visualReviewService = const SemiDaoVisualReviewService(),
  });

  Future<List<SemiDaoReviewCase>> loadCases() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            SemiDaoReviewCase.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<SemiDaoReviewCase> submitCompanion({
    required Companion companion,
    required String packJson,
    String clarification = '',
  }) async {
    final cases = await loadCases();
    final existing = cases.where((item) => item.companionId == companion.id);
    final existingClarification = existing.isEmpty
        ? ''
        : existing.first.clarification;
    final effectiveClarification = clarification.trim().isEmpty
        ? existingClarification
        : clarification.trim();
    final certification = await certifyCompanionWithImages(
      companion,
      clarification: effectiveClarification,
    );
    if (existing.isNotEmpty) {
      final current = existing.first;
      final index = cases.indexWhere((item) => item.id == current.id);
      final updated = current.copyWith(
        certification: certification,
        clarification: effectiveClarification,
      );
      final nextCases = [...cases]..[index] = updated;
      await _saveCases(nextCases);
      return updated;
    }
    final reviewCase = SemiDaoReviewCase(
      id: 'semi_${DateTime.now().millisecondsSinceEpoch}_${companion.id}',
      companionId: companion.id,
      companionName: companion.name,
      companionRole: companion.roleName,
      mbtiCode: companion.mbtiCode,
      summary: companion.appearanceDescription,
      avatarImagePath: companion.avatarImagePath ?? '',
      packJson: packJson,
      submittedAt: DateTime.now(),
      certification: certification,
      clarification: effectiveClarification,
    );
    await _saveCases([...cases, reviewCase]);
    return reviewCase;
  }

  /// [教練 Agent 2026-08-05] 純文字合規檢查（已搬到 CompanionCertificationGuard）
  /// 此處保留為 thin wrapper，向後相容既有呼叫端。
  SemiDaoPlatformCertification certifyCompanion(Companion companion) {
    final cert = CompanionCertificationGuard().certifyTextOnly(companion);
    return _certToPlatform(cert);
  }

  /// [教練 Agent 2026-08-05] 完整合規檢查（含圖片）— 內部呼叫 guard，再加上 wizard 專屬
  /// 的「使用者補充聲明」邏輯（clarification 過濾）。
  Future<SemiDaoPlatformCertification> certifyCompanionWithImages(
    Companion companion, {
    String clarification = '',
  }) async {
    // [hang/測試修復 2026-09-22] 原本這裡建了全新預設 guard，導致
    // SemiDaoReviewStore.visualReviewService 注入欄位形同虛設——
    // 測試注入的 fake adapter 永遠不會被用到（DI 管線斷線）。
    final cert = await CompanionCertificationGuard(
      visualReviewService: visualReviewService,
    ).certify(companion);
    final warnings = cert.warningChecks;
    final requiredClarifications = _requiredClarifications(
      warnings,
      clarification: clarification,
    );
    final effectiveWarnings = clarification.trim().isEmpty
        ? warnings
        : [
            for (final warning in warnings)
              if (!_canBeClarifiedByUser(warning)) warning,
          ];
    final passed = [
      ...cert.passedChecks,
      if (clarification.trim().isNotEmpty)
        '已收到使用者補充聲明：${_shortClarification(clarification)}',
    ];
    final signal = cert.blockedChecks.isNotEmpty
        ? SemiDaoReviewSignal.blocked
        : effectiveWarnings.isEmpty
            ? SemiDaoReviewSignal.approved
            : SemiDaoReviewSignal.watching;
    return SemiDaoPlatformCertification(
      signal: signal,
      passedChecks: passed,
      warningChecks: effectiveWarnings,
      blockedChecks: cert.blockedChecks,
      certifiedAt: DateTime.now(),
      visualReview: cert.visualReview,
      requiredClarifications: requiredClarifications,
    );
  }

  /// 把 `CertificationResult` 轉成 `SemiDaoPlatformCertification`（向後相容）
  SemiDaoPlatformCertification _certToPlatform(CertificationResult cert) {
    return SemiDaoPlatformCertification(
      signal: cert.signal,
      passedChecks: cert.passedChecks,
      warningChecks: cert.warningChecks,
      blockedChecks: cert.blockedChecks,
      certifiedAt: cert.certifiedAt,
      visualReview: cert.visualReview,
      requiredClarifications: cert.requiredClarifications,
    );
  }

  List<String> _requiredClarifications(
    List<String> warnings, {
    required String clarification,
  }) {
    if (clarification.trim().isNotEmpty) return const [];
    return <String>{
      for (final warning in warnings)
        if (_canBeClarifiedByUser(warning)) _clarificationForWarning(warning),
    }.toList();
  }

  bool _canBeClarifiedByUser(String warning) {
    return warning.contains('具名 IP') ||
        warning.contains('既有 IP') ||
        warning.contains('知名角色') ||
        warning.contains('嚴重破圖') ||
        warning.contains('動圖首幀');
  }

  String _clarificationForWarning(String warning) {
    if (warning.contains('具名 IP') ||
        warning.contains('既有 IP') ||
        warning.contains('知名角色')) {
      return '請補充：這個角色是否為原創？是否引用任何既有角色、品牌、Logo、商標或具名創作者風格？';
    }
    if (warning.contains('動圖首幀')) {
      return '請補充：動圖內容是否與主圖同樣安全，沒有成人、暴力、Logo 或官方混淆？';
    }
    if (warning.contains('嚴重破圖')) {
      return '請補充：圖片是否可以正常辨識與展示？如果已重新生成或你確認可接受，請在此說明。';
    }
    return '請補充說明：$warning';
  }

  String _shortClarification(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= 60) return trimmed;
    return '${trimmed.substring(0, 60)}...';
  }

  Future<SemiDaoReviewCase?> caseForCompanion(String companionId) async {
    final cases = await loadCases();
    for (final reviewCase in cases) {
      if (reviewCase.companionId == companionId) return reviewCase;
    }
    return null;
  }

  Future<SemiDaoReviewCase> addVote(
    String reviewCaseId,
    SemiDaoReviewVote vote,
  ) async {
    final cases = await loadCases();
    final index = cases.indexWhere((item) => item.id == reviewCaseId);
    if (index == -1) {
      throw StateError('SemiDAO review case not found: $reviewCaseId');
    }
    final reviewCase = cases[index];
    final votes = [
      for (final existing in reviewCase.votes)
        if (existing.voterId != vote.voterId) existing,
      vote,
    ];
    final updated = reviewCase.copyWith(votes: votes);
    final nextCases = [...cases]..[index] = updated;
    await _saveCases(nextCases);
    return updated;
  }

  Future<void> _saveCases(List<SemiDaoReviewCase> cases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final reviewCase in cases) reviewCase.toJson()]),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [for (final item in value) '$item'];
}
