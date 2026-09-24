/// Skill Matcher — 根據使用者訊息匹配相關 skill
///
/// S20: 負責從 SkillStore 的所有 skill 中找出與使用者訊息相關的。
///
/// 匹配策略：
/// 1. 關鍵字精確匹配（trigger_keywords）
/// 2. 正則模式匹配（trigger_patterns）
/// 3. 按優先級排序
/// 4. 回傳前 N 個（避免 prompt 過長）
///
/// 設計原則：
/// - 匹配是純函數，無副作用
/// - 沒有觸發條件的 skill 永遠不匹配（必須明確設定）
/// - 多個 skill 匹配時，高優先級先注入

import 'skill.dart';

class SkillMatcher {
  /// 從所有 skill 中匹配與訊息相關的
  ///
  /// [allSkills] 所有可用 skill
  /// [message] 使用者訊息
  /// [maxResults] 最多回傳幾個（預設 3，避免 prompt 過長）
  static List<Skill> match({
    required List<Skill> allSkills,
    required String message,
    int maxResults = 3,
  }) {
    final lowerMessage = message.toLowerCase();
    final scored = <_ScoredSkill>[];

    for (final skill in allSkills) {
      final score = _scoreSkill(skill, message, lowerMessage);
      if (score > 0) {
        scored.add(_ScoredSkill(skill, score));
      }
    }

    // 排序：分數高→優先級高→名稱
    scored.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      final priorityCmp =
          b.skill.priority.index.compareTo(a.skill.priority.index);
      if (priorityCmp != 0) return priorityCmp;
      return a.skill.name.compareTo(b.skill.name);
    });

    return scored.take(maxResults).map((s) => s.skill).toList();
  }

  /// 計算單個 skill 的匹配分數
  static double _scoreSkill(
    Skill skill,
    String message,
    String lowerMessage,
  ) {
    double score = 0;

    // 關鍵字匹配（每命中一個 +1.0）
    for (final keyword in skill.triggerKeywords) {
      if (lowerMessage.contains(keyword.toLowerCase())) {
        score += 1.0;
      }
    }

    // 正則模式匹配（每命中一個 +2.0，正則更精確所以權重高）
    for (final pattern in skill.triggerPatterns) {
      try {
        final regex = RegExp(pattern, caseSensitive: false);
        if (regex.hasMatch(message)) {
          score += 2.0;
        }
      } catch (e) {
        // 無效正則 = 跳過
        continue;
      }
    }

    // 優先級加權
    switch (skill.priority) {
      case SkillPriority.high:
        score *= 1.2;
        break;
      case SkillPriority.normal:
        // 不加權
        break;
      case SkillPriority.low:
        score *= 0.8;
        break;
    }

    return score;
  }
}

class _ScoredSkill {
  final Skill skill;
  final double score;

  const _ScoredSkill(this.skill, this.score);
}
