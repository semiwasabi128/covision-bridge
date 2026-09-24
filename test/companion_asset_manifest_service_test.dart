import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/services/companion_asset_manifest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds reproducible companion asset manifest', () {
    final manifest = const CompanionAssetManifestService().buildManifest(
      companionId: 'cmp_test',
      name: '霧橋',
      mbtiCode: 'INFJ',
      seed: 77,
      appearancePrompt: '霧光研究員',
      appearanceDescription: '柔和霧光與燈塔感的研究夥伴',
      characterSheetPrompts: [
        for (final stage in agentActivityStages) '${stage.shortLabel} prompt',
      ],
      primaryImagePath: 'data:image/png;base64,avatar',
      primaryAnimationPath: 'data:image/gif;base64,avatar-animation',
    );

    expect(manifest['schema'], CompanionAssetManifestService.schema);
    expect(
      manifest['renderEngine'],
      CompanionAssetManifestService.renderEngine,
    );
    expect(manifest['primaryAvatar'], 'asset.cmp_test.avatar');
    expect(manifest['primaryAvatarImagePath'], 'data:image/png;base64,avatar');
    expect(
      manifest['primaryAvatarAnimation']['path'],
      'data:image/gif;base64,avatar-animation',
    );
    expect(manifest['exportTargets'], contains('png_sequence'));

    final states = manifest['states'] as List<dynamic>;
    // [小葵 2026-07-03] idle 狀態已移除（主形象圖即為待機圖），現有 8 個核心狀態。
    expect(states, hasLength(8));
    expect(states.first['id'], 'asset.cmp_test.state_reading');
    expect(states.first['stateId'], 'reading');
    expect(states.first['kind'], 'core');
    expect(states.first['recommendedSize']['width'], 256);
    expect(states.first['trigger']['fallbackStateId'], 'idle');
    expect(states.first['still']['format'], 'png');
    expect(states.first['animation']['status'], 'planned');
    expect(
      states.first['animation']['formatPreference'],
      contains('bridge_motion'),
    );
    expect(states.first['animation']['formatPreference'], contains('gif'));
    expect(
      states.any(
        (state) => state['action'] == AgentCompanionAction.spinning.name,
      ),
      isTrue,
    );

    final includedAssets = manifest['includedAssets'] as List<dynamic>;
    expect(includedAssets, contains('asset.cmp_test.avatar'));
    expect(includedAssets, contains('asset.cmp_test.avatar_animation'));
    expect(includedAssets, contains('asset.cmp_test.state_bridging'));
  });

  test('builds custom companion asset states with trigger rules', () {
    final manifest = const CompanionAssetManifestService().buildManifest(
      companionId: 'cmp_custom',
      name: '星火',
      mbtiCode: 'ENFP',
      seed: 9,
      appearancePrompt: '星火夥伴',
      appearanceDescription: '發光的創造型夥伴',
      assetStates: const [
        CompanionAssetStateSpec(
          stateId: 'custom_cheer',
          label: '超興奮',
          kind: 'custom',
          behavior: '原地跳三下。',
          expression: '眼睛發亮。',
          mood: AgentCompanionMood.proud,
          action: AgentCompanionAction.bouncing,
          imagePath: '/tmp/cheer.png',
          animationPath: '/tmp/cheer.webp',
          animationPrompt: '跳起來揮手的短循環動圖',
          trigger: CompanionAssetTriggerRule(
            keywords: ['太棒了'],
            stages: ['completed'],
            intentTags: ['celebration'],
            scene: '使用者稱讚或任務完成時。',
            priority: 88,
            cooldownSeconds: 20,
            fallbackStateId: 'celebrating',
          ),
        ),
      ],
    );

    final states = manifest['states'] as List<dynamic>;
    expect(states, hasLength(1));
    expect(states.first['stateId'], 'custom_cheer');
    expect(states.first['kind'], 'custom');
    expect(states.first['imagePath'], '/tmp/cheer.png');
    expect(states.first['animation']['status'], 'ready');
    expect(states.first['animation']['path'], '/tmp/cheer.webp');
    expect(states.first['animation']['prompt'], '跳起來揮手的短循環動圖');
    expect(states.first['trigger']['keywords'], contains('太棒了'));
    expect(states.first['trigger']['priority'], 88);
    expect(states.first['trigger']['fallbackStateId'], 'celebrating');
    expect(
      manifest['includedAssets'],
      contains('asset.cmp_custom.state_custom_cheer_animation'),
    );
  });

  test(
    'builds asset manifest from companion without leaking provider config',
    () {
      final companion = Companion(
        id: 'cmp_private',
        name: '珀光',
        mbtiCode: 'INFP',
        role: CompanionRole.writing,
        appearancePrompt: '柔和 2D 動畫風',
        appearanceDescription: '像會發光的文字精靈',
        appearanceSeed: 123,
        appearanceHistory: ['待機 prompt', '漫遊 prompt'],
        modelEndpoint: 'https://private.example',
      );

      final manifest = const CompanionAssetManifestService().buildForCompanion(
        companion,
      );
      final manifestText = manifest.toString();

      expect(manifest['companionId'], 'cmp_private');
      expect(manifestText, isNot(contains('secret-key-id')));
      expect(manifestText, isNot(contains('private.example')));
    },
  );
}
