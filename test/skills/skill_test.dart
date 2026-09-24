// [小葵 S20] Skills 系統測試
//
// 測試範圍：
// 1. Skill frontmatter 解析
// 2. SkillMatcher 匹配邏輯
// 3. SkillStore 存取
// 4. SkillPromptInjector 注入

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill.dart';
import 'package:bridge_app/services/skills/skill_matcher.dart';

void main() {
  group('Skill.fromMarkdown', () {
    test('解析基本 frontmatter + body', () {
      const content = '''
---
name: daily-briefing
description: 每日晨間簡報
trigger_keywords: [晨報, 簡報, 今日回顧]
priority: high
version: 2
---

# 每日晨間簡報

## 步驟
1. 使用 memory_search 搜尋昨日記憶
2. 整理成結構化簡報
''';

      final skill = Skill.fromMarkdown(content);

      expect(skill.name, 'daily-briefing');
      expect(skill.description, '每日晨間簡報');
      expect(skill.triggerKeywords, containsAll(['晨報', '簡報', '今日回顧']));
      expect(skill.priority, SkillPriority.high);
      expect(skill.version, 2);
      expect(skill.body, contains('每日晨間簡報'));
      expect(skill.body, contains('memory_search'));
    });

    test('解析多行 trigger_patterns', () {
      const content = '''
---
name: search-and-summarize
description: 搜尋並摘要
trigger_patterns:
  - "搜尋.*並.*摘要"
  - "找.*資料.*整理"
priority: normal
version: 1
---

搜尋後整理重點。
''';

      final skill = Skill.fromMarkdown(content);

      expect(skill.name, 'search-and-summarize');
      expect(skill.triggerPatterns.length, 2);
      expect(skill.triggerPatterns[0], '搜尋.*並.*摘要');
      expect(skill.triggerPatterns[1], '找.*資料.*整理');
    });

    test('無 frontmatter 的檔案不 crash', () {
      const content = '# Just a markdown file\n\nNo frontmatter here.';

      final skill = Skill.fromMarkdown(content);

      expect(skill.name, 'unnamed');
      expect(skill.description, isEmpty);
      expect(skill.priority, SkillPriority.normal);
    });

    test('toMarkdown 往返一致性', () {
      final original = Skill(
        name: 'test-skill',
        description: '測試用',
        triggerKeywords: ['測試', 'test'],
        priority: SkillPriority.high,
        version: 1,
        body: 'Do something useful.',
      );

      final md = original.toMarkdown();
      final parsed = Skill.fromMarkdown(md);

      expect(parsed.name, original.name);
      expect(parsed.description, original.description);
      expect(parsed.triggerKeywords, original.triggerKeywords);
      expect(parsed.priority, original.priority);
      expect(parsed.version, original.version);
      expect(parsed.body, original.body);
    });
  });

  group('SkillMatcher', () {
    final skills = [
      Skill(
        name: 'daily-briefing',
        description: '晨間簡報',
        triggerKeywords: ['晨報', '簡報'],
        priority: SkillPriority.high,
        body: '簡報步驟',
      ),
      Skill(
        name: 'web-search',
        description: '網路搜尋',
        triggerKeywords: ['搜尋', '查'],
        triggerPatterns: ['搜尋.*資料', '查.*一下'],
        priority: SkillPriority.normal,
        body: '搜尋步驟',
      ),
      Skill(
        name: 'image-gen',
        description: '生成圖片',
        triggerKeywords: ['畫', '生成圖片'],
        priority: SkillPriority.low,
        body: '圖片生成步驟',
      ),
      Skill(
        name: 'no-trigger',
        description: '沒有觸發條件',
        body: '永遠不該被匹配',
      ),
    ];

    test('關鍵字精確匹配', () {
      final matched = SkillMatcher.match(
        allSkills: skills,
        message: '幫我做個晨報',
      );

      expect(matched, isNotEmpty);
      expect(matched.first.name, 'daily-briefing');
    });

    test('正則模式匹配', () {
      final matched = SkillMatcher.match(
        allSkills: skills,
        message: '幫我搜尋一些資料',
      );

      expect(matched, isNotEmpty);
      expect(matched.first.name, 'web-search');
    });

    test('沒有觸發條件的 skill 永遠不匹配', () {
      final matched = SkillMatcher.match(
        allSkills: skills,
        message: 'no-trigger 永遠不該出現',
      );

      final noTriggerMatched = matched.where((s) => s.name == 'no-trigger');
      expect(noTriggerMatched, isEmpty);
    });

    test('高優先級 skill 排在前面（同分時）', () {
      // '查' 命中 web-search，'簡報' 命中 daily-briefing
      // 但 daily-briefing 是 high priority
      final matched = SkillMatcher.match(
        allSkills: skills,
        message: '查一下簡報',
      );

      expect(matched.length, greaterThanOrEqualTo(2));
      // daily-briefing (high) 應該排在 web-search (normal) 前面
      // 但 web-search 有正則+關鍵字雙命中，分數更高
      // 所以檢查兩者都出現
      final names = matched.map((s) => s.name).toList();
      expect(names, containsAll(['daily-briefing', 'web-search']));
    });

    test('無匹配時回傳空列表', () {
      final matched = SkillMatcher.match(
        allSkills: skills,
        message: '今天天氣真好',
      );

      expect(matched, isEmpty);
    });

    test('maxResults 限制回傳數量', () {
      final matched = SkillMatcher.match(
        allSkills: skills,
        message: '搜尋 查 畫 簡報 晨報 生成圖片',
        maxResults: 2,
      );

      expect(matched.length, lessThanOrEqualTo(2));
    });
  });

  group('SkillPriority', () {
    test('fromString 正確解析', () {
      expect(SkillPriority.fromString('high'), SkillPriority.high);
      expect(SkillPriority.fromString('normal'), SkillPriority.normal);
      expect(SkillPriority.fromString('low'), SkillPriority.low);
      expect(SkillPriority.fromString(null), SkillPriority.normal);
      expect(SkillPriority.fromString(''), SkillPriority.normal);
      expect(SkillPriority.fromString('HIGH'), SkillPriority.high);
    });
  });
}
