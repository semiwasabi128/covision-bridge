// lib/services/companion_certification/companion_certification_guard.dart
//
// [教練 Agent 2026-08-05] 夥伴合規檢查統一入口
//
// 從 `SemiDaoReviewStore.certifyCompanion` / `certifyCompanionWithImages`
// 拆出，作為「建立夥伴 → 通過合規關卡」的純函式入口。
//
// **職責邊界**：
// - ✅ 純合規檢查（圖片 + 文字 + IP）
// - ✅ 回傳 CertificationResult（純資料，無副作用）
// - ❌ 不存進任何持久化（這是 `SemiDaoReviewStore.submitCompanion` 的職責）
// - ❌ 不寫進 companion.rightsPassport（wizard 自己用 CertificationResult 包 passport）
//
// **wizard 改用流程**（2026-08-05 修）：
//   final cert = await CompanionCertificationGuard.certify(companion);
//   final passport = _passportFromCertification(cert);
//   return companion.copyWith(rightsPassport: passport);
//
// **未來擴充**：
// - 新增 check：在這裡加 method，然後在 `certify()` 內組合
// - 改 signal 判定：在 `certify()` 內調整 blocked/warnings 邏輯
// - 不要把投票邏輯（社群評審）放進來，那屬於 `SemiDaoReviewStore.addVote`

import '../../models/companion.dart';
import '../semi_dao_review_signal.dart';
import '../semi_dao_visual_review_service.dart';
import 'certification_keywords.dart';

/// 合規檢查結果（純資料，可序列化）
///
/// 欄位命名刻意 100% 對應舊 `SemiDaoPlatformCertification`，
/// 這樣 wizard 從 `reviewCase.certification.xxx` 改成 `cert.xxx` 是 1:1 替換，
// 沒有認知負擔。
class CertificationResult {
  /// 圖片 + 文字 + IP 綜合判定結果
  final SemiDaoReviewSignal signal;

  /// 通過的檢查項目清單（給使用者看）
  final List<String> passedChecks;

  /// 警告項目清單（不擋建，但需注意）
  final List<String> warningChecks;

  /// 阻擋項目清單（擋建 / 擋分享）
  final List<String> blockedChecks;

  /// 檢查時間
  final DateTime certifiedAt;

  /// 圖片視覺檢查結果（可能為 null，若視覺檢查失敗或無圖）
  final SemiDaoVisualReviewResult? visualReview;

  /// 需要使用者額外聲明的項目（黃燈時顯示）
  final List<String> requiredClarifications;

  const CertificationResult({
    required this.signal,
    required this.passedChecks,
    required this.warningChecks,
    required this.blockedChecks,
    required this.certifiedAt,
    this.visualReview,
    this.requiredClarifications = const [],
  });

  /// 給 UI 顯示的標籤（綠 / 黃 / 紅燈說明）
  String get signalLabel {
    return switch (signal) {
      SemiDaoReviewSignal.approved => 'SemiDAO 預審綠燈：可進入社群展示',
      SemiDaoReviewSignal.watching => 'SemiDAO 預審黃燈：需補充聲明',
      SemiDaoReviewSignal.blocked => 'SemiDAO 預審紅燈：暫不接受分享',
    };
  }
}

/// 夥伴合規檢查統一入口
///
/// 純函式 — 同樣 companion 輸入永遠回傳同樣 CertificationResult（除時間戳）。
/// 無副作用、不寫任何持久化、不發任何網路（visualReview 由呼叫端注入或用預設 service）。
class CompanionCertificationGuard {
  /// 視覺檢查 service（預設使用 SemiDAO 內建；測試可注入 mock）
  final SemiDaoVisualReviewService visualReviewService;

  const CompanionCertificationGuard({
    this.visualReviewService = const SemiDaoVisualReviewService(),
  });

  /// 純文字合規檢查（不跑視覺檢查）
  ///
  /// 等價於舊 `SemiDaoReviewStore.certifyCompanion`。
  CertificationResult certifyTextOnly(Companion companion) {
    final passed = <String>[];
    final warnings = <String>[];
    final blocked = <String>[];
    final reviewText = [
      companion.name,
      companion.appearancePrompt,
      companion.appearanceDescription,
    ].join('\n').toLowerCase();

    if ((companion.avatarImagePath ?? '').trim().isEmpty) {
      warnings.add('缺少主形象圖，建議先完成角色主圖。');
    } else {
      passed.add('已包含主形象圖。');
    }

    if (companion.stateImagePaths.length < 6) {
      warnings.add('狀態圖組未完整，社群展示品質可能不足。');
    } else {
      passed.add('已包含完整狀態圖組。');
    }

    if (_containsAny(reviewText, adultKeywords)) {
      blocked.add('偵測到疑似 18 禁或成人內容描述。');
    } else {
      passed.add('未偵測到明顯 18 禁描述。');
    }

    if (_containsAny(reviewText, officialConfusionKeywords)) {
      blocked.add('偵測到疑似官方授權、官方合作或混淆字樣。');
    } else {
      passed.add('未偵測到官方混淆字樣。');
    }

    if (_containsAny(reviewText, disparagementKeywords)) {
      blocked.add('偵測到疑似醜化、貶損或攻擊原作/人物的字樣。');
    } else {
      passed.add('未偵測到醜化或貶損字樣。');
    }

    if (_containsAny(reviewText, knownIpKeywords)) {
      warnings.add('偵測到具名 IP / 工作室 / 創作者風格字樣，公開分享前需人工確認。');
    } else {
      passed.add('未偵測到常見具名 IP 風險字樣。');
    }

    final signal = blocked.isNotEmpty
        ? SemiDaoReviewSignal.blocked
        : warnings.isEmpty
            ? SemiDaoReviewSignal.approved
            : SemiDaoReviewSignal.watching;

    return CertificationResult(
      signal: signal,
      passedChecks: passed,
      warningChecks: warnings,
      blockedChecks: blocked,
      certifiedAt: DateTime.now(),
    );
  }

  /// 完整合規檢查（文字 + 圖片）
  ///
  /// 等價於舊 `SemiDaoReviewStore.certifyCompanionWithImages`。
  Future<CertificationResult> certify(Companion companion) async {
    final textCertification = certifyTextOnly(companion);
    final visualReview = await visualReviewService.reviewCompanionImages(
      companion,
    );
    final passed = [
      ...textCertification.passedChecks,
      ...visualReview.passedChecks,
    ];
    final warnings = [
      ...textCertification.warningChecks,
      ...visualReview.warningChecks,
    ];
    final blocked = [
      ...textCertification.blockedChecks,
      ...visualReview.blockedChecks,
    ];

    final signal = blocked.isNotEmpty
        ? SemiDaoReviewSignal.blocked
        : warnings.isEmpty
            ? SemiDaoReviewSignal.approved
            : SemiDaoReviewSignal.watching;

    return CertificationResult(
      signal: signal,
      passedChecks: passed,
      warningChecks: warnings,
      blockedChecks: blocked,
      certifiedAt: DateTime.now(),
      visualReview: visualReview,
      requiredClarifications: [
        ...textCertification.warningChecks,
        ...visualReview.warningChecks,
      ],
    );
  }

  /// 靜態工具：檢查文字內是否包含任一關鍵字
  static bool _containsAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }
}