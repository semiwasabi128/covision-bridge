import 'dart:convert';

import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/services/companion_asset_manifest_service.dart';
import 'package:bridge_app/services/companion_pack_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports companion as safe companion pack json', () {
    final companion = Companion(
      id: 'cmp_test',
      name: '霧橋',
      mbtiCode: 'INFJ',
      role: CompanionRole.research,
      personalityTags: [PersonalityTag.warm, PersonalityTag.precise],
      appearancePrompt: '霧光研究員',
      appearanceDescription: '柔和霧光與燈塔感的研究夥伴',
      appearanceSeed: 77,
      modelEndpoint: 'https://private.example',
      rightsPassport: CompanionRightsPassport(
        signal: CompanionRightsSignal.approved,
        label: 'SemiDAO 預審綠燈：可進入社群展示',
        reviewCaseId: 'semi_case_1',
        reviewedAt: DateTime(2026, 6, 10, 10, 30),
        passedCount: 13,
        warningCount: 0,
        blockedCount: 0,
        inspectedImageCount: 7,
      ),
    );

    final jsonString = const CompanionPackService().exportToJson(
      companion,
      primaryImagePath: 'data:image/png;base64,avatar',
      primaryAnimationPath: 'data:image/gif;base64,avatar-animation',
      assetStates: const [
        CompanionAssetStateSpec(
          stateId: 'idle',
          label: '待機',
          kind: 'core',
          behavior: '等待使用者。',
          expression: '穩定。',
          mood: AgentCompanionMood.idle,
          action: AgentCompanionAction.standing,
          imagePath: 'data:image/png;base64,idle',
          animationPath: 'data:image/gif;base64,idle-animation',
          trigger: CompanionAssetTriggerRule(stages: ['idle']),
        ),
      ],
    );
    final pack = jsonDecode(jsonString) as Map<String, dynamic>;

    expect(pack['schema'], CompanionPackService.schema);
    expect(pack['name'], '霧橋');
    expect(pack['identity']['role'], 'research');
    expect(pack['identity']['personalityTags'], contains('warm'));
    expect(pack['appearance']['appearancePrompt'], '霧光研究員');
    expect(pack['appearance']['avatar'], 'asset.cmp_test.avatar');
    expect(
      pack['appearance']['avatarImagePath'],
      'data:image/png;base64,avatar',
    );
    expect(
      pack['appearance']['avatarAnimationPath'],
      'data:image/gif;base64,avatar-animation',
    );
    expect(pack['activitySet']['actions']['idle'], 'standing');
    expect(pack['activitySet']['labels']['idle'], '待機');
    expect(pack['activitySet']['triggers']['idle']['stages'], contains('idle'));
    expect(pack['assets']['included'], contains('asset.cmp_test.state_idle'));
    expect(
      pack['assets']['manifest']['renderEngine'],
      'bridge.flutter-procedural.v0.1',
    );
    expect(
      pack['assets']['manifest']['primaryAvatarImagePath'],
      'data:image/png;base64,avatar',
    );
    expect(
      pack['assets']['manifest']['primaryAvatarAnimation']['path'],
      'data:image/gif;base64,avatar-animation',
    );
    expect(
      pack['assets']['manifest']['states'].first['still']['path'],
      'data:image/png;base64,idle',
    );
    expect(
      pack['assets']['manifest']['states'].first['animation']['path'],
      'data:image/gif;base64,idle-animation',
    );
    expect(pack['safety']['containsApiKeys'], isFalse);
    expect(pack['safety']['rightsPassport']['signal'], 'approved');
    expect(pack['safety']['rightsPassport']['inspectedImageCount'], 7);
    expect(jsonString, isNot(contains('secret-key-id')));
    expect(jsonString, isNot(contains('private.example')));
  });

  test('imports companion pack with a new local id and safe boundaries', () {
    final pack = {
      'schema': CompanionPackService.schema,
      'name': '珀光',
      'identity': {
        'role': 'writing',
        'mbtiCode': 'INFP',
        'personalityTags': ['warm', 'detailed'],
      },
      'appearance': {
        'appearancePrompt': '柔和 2D 動畫風',
        'generatedDescription': '像會發光的文字精靈',
        'appearanceSeed': 123,
        'avatarImagePath': 'data:image/png;base64,avatar',
        'avatarAnimationPath': 'data:image/gif;base64,avatar-animation',
      },
      'assets': {
        'manifest': {
          'states': [
            {
              'stateId': 'idle',
              'still': {'path': 'data:image/png;base64,idle'},
              'animation': {'path': 'data:image/gif;base64,idle-animation'},
            },
            {
              'stateId': 'wandering',
              'imagePath': 'data:image/png;base64,wander',
            },
          ],
        },
      },
      'safety': {
        'containsUserMemory': false,
        'containsApiKeys': false,
        'containsExecutableCode': false,
        'rightsPassport': {
          'signal': 'watching',
          'label': 'SemiDAO 預審黃燈：需補充聲明',
          'reviewCaseId': 'semi_case_imported',
          'reviewedAt': '2026-06-10T10:40:00.000',
          'passedCount': 10,
          'warningCount': 1,
          'blockedCount': 0,
          'inspectedImageCount': 7,
          'requiredClarifications': ['請補充原創聲明'],
        },
      },
    };

    final companion = const CompanionPackService(
      idFactory: _fixedId,
    ).importFromPackJson(pack);

    expect(companion.id, 'cmp_imported');
    expect(companion.name, '珀光');
    expect(companion.role, CompanionRole.writing);
    expect(companion.mbtiCode, 'INFP');
    expect(companion.personalityTags, contains(PersonalityTag.detailed));
    // [教練 Agent 2026-08-04] appearanceSeed 已從 pack 往返中刪除，匯入固定為 0
    expect(companion.appearanceSeed, 0);
    expect(companion.avatarImagePath, 'data:image/png;base64,avatar');
    expect(
      companion.avatarAnimationPath,
      'data:image/gif;base64,avatar-animation',
    );
    expect(companion.stateImagePaths['idle'], 'data:image/png;base64,idle');
    expect(
      companion.stateAnimationPaths['idle'],
      'data:image/gif;base64,idle-animation',
    );
    expect(
      companion.stateImagePaths['wandering'],
      'data:image/png;base64,wander',
    );
    // [教練 Agent 2026-08-04] modelEndpoint 有 non-null 預設值 'default'（隱私隔離靠不寫入 pack）
    expect(companion.modelEndpoint, 'default');
    expect(companion.trustBoundary.autoExecute, isFalse);
    expect(companion.trustBoundary.confirmBeforeSend, isTrue);
    expect(companion.trustBoundary.allowFileAccess, isFalse);
    expect(companion.rightsPassport?.signal, CompanionRightsSignal.watching);
    expect(companion.rightsPassport?.reviewCaseId, 'semi_case_imported');
    expect(companion.rightsPassport?.requiredClarifications, ['請補充原創聲明']);
  });

  test('yellow and red passports export as local-only', () {
    for (final entry in [
      (
        signal: CompanionRightsSignal.watching,
        label: 'SemiDAO 預審黃燈：需要補充說明',
        blockedCount: 0,
      ),
      (
        signal: CompanionRightsSignal.blocked,
        label: 'SemiDAO 預審紅燈：暫不接受分享',
        blockedCount: 1,
      ),
    ]) {
      final companion = Companion(
        id: 'cmp_${entry.signal.name}',
        name: '本機角色${entry.signal.name}',
        mbtiCode: 'ENFJ',
        role: CompanionRole.general,
        rightsPassport: CompanionRightsPassport(
          signal: entry.signal,
          label: entry.label,
          reviewCaseId: 'semi_${entry.signal.name}',
          reviewedAt: DateTime(2026, 6, 10, 12),
          blockedCount: entry.blockedCount,
        ),
      );

      final jsonString = const CompanionPackService(
        localInstallId: 'local_a',
      ).exportToJson(companion);
      final pack = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(pack['safety']['localOnly'], isTrue);
      expect(pack['safety']['localOnlyOwnerId'], 'local_a');
      expect(
        const CompanionPackService(
          localInstallId: 'local_a',
          idFactory: _fixedId,
        ).importFromJson(jsonString).name,
        companion.name,
      );
      expect(
        () => const CompanionPackService(
          localInstallId: 'local_b',
        ).importFromJson(jsonString),
        throwsA(isA<CompanionPackException>()),
      );
    }
  });

  test('previews companion pack metadata before import', () {
    final pack = {
      'schema': CompanionPackService.schema,
      'id': 'community.blue.mist-bridge',
      'version': '0.1.0',
      'name': '霧橋',
      'summary': '溫柔但精準的研究與導流夥伴。',
      'author': {'name': 'Blue'},
      'license': 'CC-BY-SA-4.0',
      'tags': ['research', 'warm'],
      'identity': {
        'role': 'research',
        'mbtiCode': 'INFJ',
        'personalityTags': ['warm', 'precise'],
      },
      'voice': {
        'speakingStyle': '溫柔、精準、會先整理方向再提出下一步。',
        'toneRules': ['先確認使用者意圖', '遇到焦慮語氣時先降低重要性'],
      },
      'capabilities': {
        'specialFunction': '研究摘要、資料整理',
        'expertise': ['research', 'writing'],
      },
      'appearance': {
        'appearancePrompt': '霧光生物，像圖書館守護者與燈塔的結合。',
        'generatedDescription': '柔和霧光與燈塔感的研究夥伴',
        'palette': ['#2A9D8F', '#E9C46A'],
      },
      'permissions': {
        'riskLevel': 'L0',
        'requires': [],
        'optional': ['desktop.notification'],
      },
      'safety': {
        'containsUserMemory': false,
        'containsApiKeys': false,
        'containsExecutableCode': false,
        'reviewStatus': 'community-reviewed',
        'contentWarnings': [],
      },
    };

    final preview = const CompanionPackService().previewFromJson(
      jsonEncode(pack),
    );

    expect(preview.id, 'community.blue.mist-bridge');
    expect(preview.name, '霧橋');
    expect(preview.authorName, 'Blue');
    expect(preview.license, 'CC-BY-SA-4.0');
    expect(preview.tags, contains('research'));
    expect(preview.role, 'research');
    expect(preview.mbtiCode, 'INFJ');
    expect(preview.personalityTags, contains('precise'));
    expect(preview.expertise, contains('writing'));
    expect(preview.palette, ['#2A9D8F', '#E9C46A']);
    expect(preview.optionalPermissions, ['desktop.notification']);
    expect(preview.reviewStatus, 'community-reviewed');
    expect(preview.isSafe, isTrue);
    expect(preview.unsafeReasons, isEmpty);
  });

  test('rejects unsupported or unsafe companion packs', () {
    expect(
      () => const CompanionPackService().importFromPackJson({
        'schema': 'bridge.companion-pack.v9',
        'name': '錯誤包',
      }),
      throwsA(isA<CompanionPackException>()),
    );

    expect(
      () => const CompanionPackService().importFromPackJson({
        'schema': CompanionPackService.schema,
        'name': '危險包',
        'identity': {'role': 'general'},
        'safety': {
          'containsUserMemory': false,
          'containsApiKeys': true,
          'containsExecutableCode': false,
        },
      }),
      throwsA(isA<CompanionPackException>()),
    );
  });

  test('preview exposes unsafe reasons without importing', () {
    final preview = const CompanionPackService().previewFromPackJson({
      'schema': CompanionPackService.schema,
      'name': '危險包',
      'identity': {'role': 'general'},
      'safety': {
        'containsUserMemory': true,
        'containsApiKeys': true,
        'containsExecutableCode': false,
      },
    });

    expect(preview.isSafe, isFalse);
    expect(preview.unsafeReasons, ['含有使用者記憶', '含有 API Key']);
  });
}

String _fixedId() => 'cmp_imported';
