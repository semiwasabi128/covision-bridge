import 'dart:convert';
import 'dart:typed_data';

import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/services/openai_visual_review_adapter.dart';
import 'package:bridge_app/services/semi_dao_review_store.dart';
import 'package:bridge_app/services/semi_dao_visual_review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('platform certification approves complete low-risk companions', () {
    final companion = _companion(
      avatarImagePath: '/tmp/avatar.png',
      stateImagePaths: {
        for (final key in [
          'idle',
          'reading',
          'pointing',
          'bridging',
          'celebrating',
          'wandering',
        ])
          key: '/tmp/$key.png',
      },
    );

    final certification = const SemiDaoReviewStore().certifyCompanion(
      companion,
    );

    expect(certification.signal, SemiDaoReviewSignal.approved);
    expect(certification.blockedChecks, isEmpty);
    expect(certification.warningChecks, isEmpty);
  });

  test('platform certification warns when assets are incomplete', () {
    final companion = _companion();

    final certification = const SemiDaoReviewStore().certifyCompanion(
      companion,
    );

    expect(certification.signal, SemiDaoReviewSignal.watching);
    expect(certification.warningChecks, isNotEmpty);
    expect(certification.blockedChecks, isEmpty);
  });

  test(
    'platform certification blocks official confusion and adult content',
    () {
      final companion = _companion(
        appearanceDescription: '官方授權的 18禁 角色包。',
        avatarImagePath: '/tmp/avatar.png',
      );

      final certification = const SemiDaoReviewStore().certifyCompanion(
        companion,
      );

      expect(certification.signal, SemiDaoReviewSignal.blocked);
      expect(certification.blockedChecks.length, greaterThanOrEqualTo(2));
    },
  );

  test('platform certification ignores internal safety history prompts', () {
    final companion = _companion(
      appearanceDescription: '原創物流研究夥伴，形象美觀、可靠、沒有既有角色元素。',
      avatarImagePath: '/tmp/avatar.png',
      stateImagePaths: {
        for (final key in [
          'idle',
          'reading',
          'pointing',
          'bridging',
          'celebrating',
          'wandering',
        ])
          key: '/tmp/$key.png',
      },
      appearanceHistory: const ['生成時請避免 18 禁、成人內容、醜化、攻擊或貶損原作。'],
    );

    final certification = const SemiDaoReviewStore().certifyCompanion(
      companion,
    );

    expect(certification.signal, SemiDaoReviewSignal.approved);
    expect(certification.blockedChecks, isEmpty);
  });

  test('platform certification does not block broad neutral words', () {
    final companion = _companion(
      appearanceDescription: '適合成人使用者的協作夥伴，能支援合作任務與遊戲攻擊動作設計。',
      avatarImagePath: '/tmp/avatar.png',
      stateImagePaths: {
        for (final key in [
          'idle',
          'reading',
          'pointing',
          'bridging',
          'celebrating',
          'wandering',
        ])
          key: '/tmp/$key.png',
      },
    );

    final certification = const SemiDaoReviewStore().certifyCompanion(
      companion,
    );

    expect(certification.signal, SemiDaoReviewSignal.approved);
    expect(certification.blockedChecks, isEmpty);
  });

  test('submitted companion stores certification in review pool', () async {
    final store = const SemiDaoReviewStore();
    final companion = _companion(avatarImagePath: '/tmp/avatar.png');

    final reviewCase = await store.submitCompanion(
      companion: companion,
      packJson: '{"schema":"bridge.companion-pack.v0.1"}',
    );
    final cases = await store.loadCases();

    expect(reviewCase.certification.signal, SemiDaoReviewSignal.watching);
    expect(cases, hasLength(1));
    expect(cases.single.companionId, companion.id);
    expect(cases.single.certification.warningChecks, isNotEmpty);
  });

  test(
    'submitted companion includes visual safety and quality preflight',
    () async {
      final png = _pngDataUri(width: 512, height: 512);
      final store = const SemiDaoReviewStore();
      final companion = _companion(
        avatarImagePath: png,
        stateImagePaths: {
          for (final key in [
            'idle',
            'reading',
            'pointing',
            'bridging',
            'celebrating',
            'wandering',
          ])
            key: png,
        },
      );

      final reviewCase = await store.submitCompanion(
        companion: companion,
        packJson: '{"schema":"bridge.companion-pack.v0.1"}',
      );

      expect(reviewCase.certification.visualReview, isNotNull);
      // 沒有 API token 時，deep review 不會跑，但本地檢查通過
      expect(
        reviewCase.certification.visualReview!.deepContentReviewRan,
        isFalse,
      );
      expect(reviewCase.certification.visualReview!.inspectedImageCount, 7);
      expect(
        reviewCase.certification.passedChecks,
        contains('已完成 7 張圖片的可讀性與基本品質檢查。'),
      );
      // infoNotes 應包含引導訊息（告知使用者缺 API token 或審查未執行）
      expect(
        reviewCase.certification.visualReview!.infoNotes.isNotEmpty,
        isTrue,
      );
    },
  );

  test('visual review blocks unsafe model findings', () async {
    final png = _pngDataUri(width: 512, height: 512);
    final store = SemiDaoReviewStore(
      visualReviewService: SemiDaoVisualReviewService(
        openAiAdapter: _FakeUnsafeVisualAdapter(),
      ),
    );
    final companion = _companion(
      avatarImagePath: png,
      stateImagePaths: {
        for (final key in [
          'idle',
          'reading',
          'pointing',
          'bridging',
          'celebrating',
          'wandering',
        ])
          key: png,
      },
    );

    final reviewCase = await store.submitCompanion(
      companion: companion,
      packJson: '{"schema":"bridge.companion-pack.v0.1"}',
    );

    expect(reviewCase.certification.signal, SemiDaoReviewSignal.blocked);
    expect(
      reviewCase.certification.blockedChecks,
      contains('偵測到疑似成人、裸露或性暗示內容（無法分享至社群，仍可自用）。'),
    );
    expect(
      reviewCase.certification.blockedChecks,
      contains('偵測到疑似 Logo、商標或官方混淆風險（無法分享至社群，仍可自用）。'),
    );
  });

  test('clarification can resolve reviewable yellow warnings', () async {
    final png = _pngDataUri(width: 512, height: 512);
    final store = SemiDaoReviewStore(
      visualReviewService: SemiDaoVisualReviewService(
        openAiAdapter: _FakeIpWarningVisualAdapter(),
      ),
    );
    final companion = _companion(
      avatarImagePath: png,
      stateImagePaths: {
        for (final key in [
          'idle',
          'reading',
          'pointing',
          'bridging',
          'celebrating',
          'wandering',
        ])
          key: png,
      },
    );

    final yellow = await store.submitCompanion(
      companion: companion,
      packJson: '{"schema":"bridge.companion-pack.v0.1"}',
    );
    expect(yellow.certification.signal, SemiDaoReviewSignal.watching);
    expect(yellow.certification.requiredClarifications, isNotEmpty);

    final green = await store.submitCompanion(
      companion: companion,
      packJson: '{"schema":"bridge.companion-pack.v0.1"}',
      clarification: '此角色為本人原創，沒有引用既有角色、Logo、商標或官方素材。',
    );
    expect(green.certification.signal, SemiDaoReviewSignal.approved);
    expect(green.certification.requiredClarifications, isEmpty);
    expect(green.clarification, contains('本人原創'));
  });

  test(
    'quality observations do not create warnings for generated assets',
    () async {
      final png = _pngDataUri(width: 512, height: 512);
      final store = SemiDaoReviewStore(
        visualReviewService: SemiDaoVisualReviewService(
          openAiAdapter: _FakeQualityIssueVisualAdapter(),
        ),
      );
      final companion = _companion(
        avatarImagePath: png,
        stateImagePaths: {
          for (final key in [
            'idle',
            'reading',
            'pointing',
            'bridging',
            'celebrating',
            'wandering',
          ])
            key: png,
        },
      );

      final reviewCase = await store.submitCompanion(
        companion: companion,
        packJson: '{"schema":"bridge.companion-pack.v0.1"}',
      );

      expect(reviewCase.certification.signal, SemiDaoReviewSignal.approved);
      expect(reviewCase.certification.warningChecks, isEmpty);
      expect(reviewCase.certification.requiredClarifications, isEmpty);
      expect(
        reviewCase.certification.visualReview!.infoNotes,
        contains('觀察：small text details are soft'),
      );
    },
  );

  test(
    'severely broken image score creates one clarification prompt',
    () async {
      final png = _pngDataUri(width: 512, height: 512);
      final store = SemiDaoReviewStore(
        visualReviewService: SemiDaoVisualReviewService(
          openAiAdapter: _FakeLowQualityVisualAdapter(),
        ),
      );
      final companion = _companion(
        avatarImagePath: png,
        stateImagePaths: {
          for (final key in [
            'idle',
            'reading',
            'pointing',
            'bridging',
            'celebrating',
            'wandering',
          ])
            key: png,
        },
      );

      final reviewCase = await store.submitCompanion(
        companion: companion,
        packJson: '{"schema":"bridge.companion-pack.v0.1"}',
      );

      expect(reviewCase.certification.requiredClarifications, hasLength(1));
      expect(
        reviewCase.certification.requiredClarifications.single,
        contains('正常辨識與展示'),
      );
    },
  );
}

Companion _companion({
  String appearanceDescription = '原創森林研究夥伴，溫和、可靠、沒有既有角色元素。',
  String? avatarImagePath,
  Map<String, String> stateImagePaths = const {},
  List<String> appearanceHistory = const [],
}) {
  return Companion(
    id: 'cmp_test',
    name: '測試夥伴',
    mbtiCode: 'INTJ',
    role: CompanionRole.research,
    appearancePrompt: '原創森林研究夥伴',
    appearanceDescription: appearanceDescription,
    appearanceHistory: appearanceHistory,
    avatarImagePath: avatarImagePath,
    stateImagePaths: stateImagePaths,
  );
}

String _pngDataUri({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setAll(0, [137, 80, 78, 71, 13, 10, 26, 10]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(16, width);
  data.setUint32(20, height);
  return 'data:image/png;base64,${base64Encode(bytes)}';
}

class _FakeUnsafeVisualAdapter extends OpenAiVisualReviewAdapter {
  @override
  Future<VisionReviewOutcome> reviewCompanion(Companion companion) async {
    return const VisionReviewOutcome(
      status: VisionReviewStatus.success,
      result: OpenAiVisualReviewResult(
        adultContent: true,
        violenceOrHate: false,
        logoOrTrademark: true,
        officialConfusion: true,
        identifiableIpRisk: false,
        qualityScore: 4,
        qualityIssues: [],
        safeForCommunityPreview: false,
        notes: 'fixture unsafe image',
      ),
    );
  }
}

class _FakeIpWarningVisualAdapter extends OpenAiVisualReviewAdapter {
  @override
  Future<VisionReviewOutcome> reviewCompanion(Companion companion) async {
    return const VisionReviewOutcome(
      status: VisionReviewStatus.success,
      result: OpenAiVisualReviewResult(
        adultContent: false,
        violenceOrHate: false,
        logoOrTrademark: false,
        officialConfusion: false,
        identifiableIpRisk: true,
        qualityScore: 4,
        qualityIssues: [],
        safeForCommunityPreview: true,
        notes: 'fixture possible ip similarity',
      ),
    );
  }
}

class _FakeQualityIssueVisualAdapter extends OpenAiVisualReviewAdapter {
  @override
  Future<VisionReviewOutcome> reviewCompanion(Companion companion) async {
    return const VisionReviewOutcome(
      status: VisionReviewStatus.success,
      result: OpenAiVisualReviewResult(
        adultContent: false,
        violenceOrHate: false,
        logoOrTrademark: false,
        officialConfusion: false,
        identifiableIpRisk: false,
        qualityScore: 4,
        qualityIssues: ['small text details are soft', 'minor edge blur'],
        safeForCommunityPreview: true,
        notes: 'fixture quality warnings',
      ),
    );
  }
}

class _FakeLowQualityVisualAdapter extends OpenAiVisualReviewAdapter {
  @override
  Future<VisionReviewOutcome> reviewCompanion(Companion companion) async {
    return const VisionReviewOutcome(
      status: VisionReviewStatus.success,
      result: OpenAiVisualReviewResult(
        adultContent: false,
        violenceOrHate: false,
        logoOrTrademark: false,
        officialConfusion: false,
        identifiableIpRisk: false,
        qualityScore: 1,
        qualityIssues: ['image is unreadable'],
        safeForCommunityPreview: true,
        notes: 'fixture unreadable image',
      ),
    );
  }
}
