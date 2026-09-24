/// Skill Prompt Injector — 把匹配到的 skill 注入 Agent Loop system prompt
///
/// S20: 負責把 SkillMatcher 匹配到的 skill 轉成 prompt 區塊。
/// 在 AgentLoopPromptBuilder.build() 裡呼叫。
///
/// 注入格式：
/// ```
/// ## 可用程序記憶（Skills）
/// 以下程序可能與使用者的請求相關，請參考但不強制遵循：
///
/// ### skill-name
/// <skill body>
/// ```

import 'skill_matcher.dart';
import 'skill_store.dart';
import 'skill.dart';

class SkillPromptInjector {
  /// 從使用者訊息匹配 skill 並產生 prompt 區塊
  ///
  /// 回傳 null = 沒有匹配到任何 skill（不注入）
  ///
  /// [localMode] — 本地 4B 模型精簡模式：
  ///   只取 priority >= high 的 skill，最多 1 個，body 截斷至 800 字。
  ///   4B 模型 prompt 太長會影響品質，所以只注入最關鍵的追問程序。
  static String? buildSkillSection({
    required String userMessage,
    int maxResults = 3,
    bool localMode = false,
  }) {
    final store = SkillStore.instance;
    if (!store.isLoaded || store.all.isEmpty) return null;

    var matched = SkillMatcher.match(
      allSkills: store.all,
      message: userMessage,
      maxResults: localMode ? 1 : maxResults,
    );

    if (matched.isEmpty) return null;

    // 本地模式：只保留高優先級 skill
    if (localMode) {
      matched = matched.where((s) => s.priority == SkillPriority.high).toList();
      if (matched.isEmpty) return null;
    }

    final buf = StringBuffer();
    if (localMode) {
      buf.writeln('## 追問程序');
      buf.writeln('使用者需求可能不夠明確，請參考以下程序自然地反問釐清：');
    } else {
      buf.writeln('## 可用程序記憶（Skills）');
      buf.writeln('以下程序可能與使用者的請求相關，請參考但不強制遵循：');
    }

    for (final skill in matched) {
      buf.writeln();
      buf.writeln('### ${skill.name}');
      var body = skill.body;
      if (localMode && body.length > 800) {
        body = '${body.substring(0, 800)}…';
      }
      buf.writeln(body);
    }

    return buf.toString();
  }
}
