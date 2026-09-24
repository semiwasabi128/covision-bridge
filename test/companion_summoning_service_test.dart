import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/services/companion_summoning_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summoning uses clues to create deterministic companion candidate', () {
    final service = CompanionSummoningService();
    const clues = CompanionSummoningClues(
      name: '霧橋',
      specialFunction: '替我研究資料與比較方案',
      speakingStyle: '精準、直接、不繞路',
      personality: '冷靜、專注、策略性',
      expertise: '研究分析',
      artStyle: '明亮的遊戲角色設定圖',
      species: '光靈',
    );

    final first = service.summon(clues, salt: 7);
    final second = service.summon(clues, salt: 7);

    expect(first.name, '霧橋');
    expect(first.seed, second.seed);
    expect(first.mbtiCode, second.mbtiCode);
    expect(first.role, CompanionRole.research);
    expect(first.personalityTags, contains(PersonalityTag.precise));
    expect(first.appearancePrompt, contains('特殊功能'));
    expect(first.appearanceDescription, isNotEmpty);
  });

  test('summoning creates character sheet prompts for activity stages', () {
    final candidate = CompanionSummoningService().summon(
      const CompanionSummoningClues(
        name: '珀光',
        specialFunction: '幫我串接新的 AI 服務',
        personality: '溫暖、守護、細心',
        artStyle: '柔和 2D 動畫風',
      ),
      salt: 3,
    );

    expect(
      candidate.characterSheetPrompts.length,
      agentActivityStages.length + 2,
    );
    expect(candidate.characterSheetPrompts.first, contains('正面、側面、背面'));
    expect(
      candidate.characterSheetPrompts.any(
        (prompt) => prompt.contains(AgentActivityStage.bridge.shortLabel),
      ),
      isTrue,
    );
    expect(candidate.characterSheetPrompts.last, contains('自由走動'));
  });

  test('reference images count as summoning clues', () {
    const clues = CompanionSummoningClues(
      referenceImagePaths: ['/tmp/reference.png'],
    );

    final candidate = CompanionSummoningService().summon(clues, salt: 2);

    expect(clues.hasAnySignal, isTrue);
    expect(candidate.appearancePrompt, contains('使用者已上傳 1 張視覺參考圖'));
  });

  test('candidate can keep generated portrait and state sheet images', () {
    final candidate = CompanionSummoningService().summon(
      const CompanionSummoningClues(name: '尼希米', artStyle: '柔和水墨'),
      salt: 11,
    );

    final updated = candidate.copyWith(
      generatedImagePath: '/tmp/portrait.png',
      visualGenerationMessage: 'ok',
      generatedSheetImagePaths: const {'reading': '/tmp/reading.png'},
      sheetGenerationMessages: const {'reading': 'done'},
    );

    expect(updated.generatedImagePath, '/tmp/portrait.png');
    expect(updated.visualGenerationMessage, 'ok');
    expect(updated.generatedSheetImagePaths['reading'], '/tmp/reading.png');
    expect(updated.sheetGenerationMessages['reading'], 'done');
    expect(updated.characterSheetPrompts, candidate.characterSheetPrompts);
  });
}
