// memory_recall_service.dart
// [教練 Agent 2026-07-25] 記憶回溯機制 — 方案 A（關鍵字回溯 + 迭代精進）
//
// 當使用者抱怨 Agent 失憶時，從完整對話歷史中搜尋相關內容，
// 注入 context 讓 Agent「找回記憶」。
// 搜尋不準時，使用者的追 complain 會成為下一輪搜尋的線索，越找越準。
//
// 設計文件：bridge_app/docs/design-memory-recall-2026-07-25.md

import '../models/conversation.dart';

/// 回溯關鍵字
class RecallKeyword {
  final String word;
  final double weight;
  final KeywordType type;

  const RecallKeyword({
    required this.word,
    required this.weight,
    required this.type,
  });
}

enum KeywordType {
  properNoun,   // 專有名詞（MiniMax、GraphRAG）— 權重 3
  number,       // 數字/日期（7/23、300萬）— 權重 2
  commonNoun,   // 一般名詞（設定、key）— 權重 1
  negatedNoun,  // 否定詞後的名詞（「不是 X」= X 是重要線索）— 權重 +1
}

/// 回溯片段（一則命中的訊息 + 上下文）
class RecallFragment {
  final String messageId;
  final DateTime timestamp;
  final String role;
  final String content;
  final List<String> hitKeywords;
  final double score;

  const RecallFragment({
    required this.messageId,
    required this.timestamp,
    required this.role,
    required this.content,
    required this.hitKeywords,
    required this.score,
  });
}

/// 回溯 session 狀態（跨輪迭代用）
class MemoryRecallSession {
  /// 累積的關鍵字（每輪迭代追加）
  final List<String> accumulatedKeywords;

  /// 已回覆過的訊息 ID（使用者說「不是這個」= 排除）
  final Set<String> excludedMessageIds;

  /// 迭代次數
  final int iterationCount;

  /// 是否處於回溯模式
  final bool isActive;

  /// 最後活躍時間
  final DateTime? lastActiveAt;

  const MemoryRecallSession({
    this.accumulatedKeywords = const [],
    this.excludedMessageIds = const {},
    this.iterationCount = 0,
    this.isActive = false,
    this.lastActiveAt,
  });

  MemoryRecallSession copyWith({
    List<String>? accumulatedKeywords,
    Set<String>? excludedMessageIds,
    int? iterationCount,
    bool? isActive,
    DateTime? lastActiveAt,
  }) {
    return MemoryRecallSession(
      accumulatedKeywords: accumulatedKeywords ?? this.accumulatedKeywords,
      excludedMessageIds: excludedMessageIds ?? this.excludedMessageIds,
      iterationCount: iterationCount ?? this.iterationCount,
      isActive: isActive ?? this.isActive,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}

/// 記憶回溯服務 — 無狀態工具方法
class MemoryRecallService {
  // ═══════════════════════════════════════════════════
  // ① 失憶抱怨偵測
  // ═══════════════════════════════════════════════════

  /// 判斷使用者是否在抱怨 Agent 失憶
  ///
  /// 寧可誤觸發也不要漏觸發 — 誤觸發只是多做一次本地搜尋（零成本），
  /// 漏觸發則讓使用者覺得「AI 真的失憶了」。
  static bool isMemoryComplaint(String userMessage) {
    final text = userMessage.toLowerCase();

    // 直接抱怨型
    const directPatterns = [
      '你忘記了', '你忘了', '你不是記得', '你之前說過', '我之前講過',
      '不是跟你說過', '我跟你說過', '之前明明就', '上次你還說',
      '怎麼跟上次不一樣', '你記得嗎', '你還記得嗎', '你不記得了',
      '失憶', '健忘', '記性差', '金魚腦', '你怎麼不記得',
      '我不是說了', '不是說好了', '之前討論的', '上次討論的',
      '你搞丟了', '不見了嗎', '你漏掉了',
    ];

    for (final pattern in directPatterns) {
      if (text.contains(pattern)) return true;
    }

    // 句型：「你之前不是 + (說/講/提)」
    if (RegExp(r'你之前.*不是.*(說|講|提|答應|講好)').hasMatch(text)) {
      return true;
    }

    // 句型：「我們不是 + (說|講|討論) 過」
    if (RegExp(r'我們不是.*(說|講|討論)過').hasMatch(text)) {
      return true;
    }

    return false;
  }

  /// 判斷是否為迭代抱怨（第一輪之後的追 complain）
  static bool isIterationComplaint(String userMessage) {
    final text = userMessage.toLowerCase();

    // 「不是這個」「不對」「不是」+ 通常是短句
    if (text.contains('不是這個') || text.contains('不是這些')) return true;
    if (text.contains('不對') && text.length < 50) return true;

    // 「還有」+ 名詞 = 補充搜尋
    if (RegExp(r'還有.*(的|一個|另外)').hasMatch(text)) return true;
    if (text.contains('另外一個') || text.contains('還有一個')) return true;

    // 「對就是這個」= 確認找到（不是抱怨，但需要繼續回溯 session）
    if (text.contains('就是這個') || text.contains('對就是')) return true;

    return false;
  }

  // ═══════════════════════════════════════════════════
  // ② 關鍵字萃取
  // ═══════════════════════════════════════════════════

  /// 從使用者的抱怨句中萃取搜尋關鍵字
  ///
  /// [previousKeywords] — 迭代時帶入上一輪的關鍵字
  static List<RecallKeyword> extractKeywords(
    String userMessage, {
    List<String>? previousKeywords,
  }) {
    final keywords = <RecallKeyword>[];
    final seen = <String>{};

    // 保留上一輪的關鍵字
    if (previousKeywords != null) {
      for (final kw in previousKeywords) {
        if (!seen.contains(kw)) {
          keywords.add(RecallKeyword(
            word: kw,
            weight: 2.0,
            type: KeywordType.commonNoun,
          ));
          seen.add(kw);
        }
      }
    }

    // 停用詞 — 不搜尋這些
    const stopWords = {
      '你', '我', '他', '它', '這個', '那個', '這些', '那些',
      '說', '講', '提', '討論', '忘記', '記得', '知道',
      '的', '了', '是', '就', '才', '還', '也', '都', '不',
      '嗎', '吧', '呢', '啊', '喔', '嘛', '捏',
      '之前', '上次', '之前講', '之前說', '不是', '不是這個',
      '怎麼', '為什麼', '明明', '過', '了嗎',
      'the', 'a', 'an', 'is', 'are', 'was', 'were',
    };

    // 萃取英文專有名詞（CamelCase 或全大寫或含數字的英文詞）
    final englishWords = RegExp(r'[A-Za-z][A-Za-z0-9\-]{2,}').allMatches(userMessage);
    for (final match in englishWords) {
      final word = match.group(0)!;
      if (stopWords.contains(word.toLowerCase())) continue;
      if (seen.contains(word)) continue;
      // 全大寫或含數字 = 可能是專有名詞
      final isProper = word == word.toUpperCase() || RegExp(r'\d').hasMatch(word);
      keywords.add(RecallKeyword(
        word: word,
        weight: isProper ? 3.0 : 2.0,
        type: isProper ? KeywordType.properNoun : KeywordType.commonNoun,
      ));
      seen.add(word);
    }

    // 萃取數字/日期
    final numbers = RegExp(r'\d+[/\-]\d+([/\-]\d+)?|\d+萬|\d+億|\d{2,}').allMatches(userMessage);
    for (final match in numbers) {
      final word = match.group(0)!;
      if (seen.contains(word)) continue;
      keywords.add(RecallKeyword(
        word: word,
        weight: 2.0,
        type: KeywordType.number,
      ));
      seen.add(word);
    }

    // 萃取中文名詞片語
    // 先抓連續中文字段，再用停用詞切割出有意義的片語
    final chineseRuns = RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(userMessage);
    for (final match in chineseRuns) {
      final run = match.group(0)!;
      // 用停用詞切割連續中文段（包含單字停用詞）
      var remaining = run;
      // 先切多字停用詞
      for (final sw in stopWords) {
        if (sw.length >= 2 && remaining.contains(sw)) {
          remaining = remaining.replaceAll(sw, ' ');
        }
      }
      // 再切單字停用詞（只切詞首和詞尾，避免破壞有意義的詞）
      const singleCharStop = {'了', '的', '是', '就', '才', '也', '都', '不', '嗎', '吧', '呢', '啊', '喔', '嘛'};
      final stopPattern = singleCharStop.join('');
      // 詞首和詞尾的單字停用詞移除
      remaining = remaining.replaceAll(RegExp(r'^[' + stopPattern + r']+'), '');
      remaining = remaining.replaceAll(RegExp(r'[' + stopPattern + r']+$'), '');
      // 中間的單字停用詞用空格切
      for (final sc in singleCharStop) {
        remaining = remaining.replaceAll(sc, ' ');
      }
      // 切割後取 2~6 字的片語
      final subPhrases = RegExp(r'[\u4e00-\u9fff]{2,6}').allMatches(remaining);
      for (final subMatch in subPhrases) {
        final word = subMatch.group(0)!;
        if (stopWords.contains(word)) continue;
        if (seen.contains(word)) continue;

        // 判斷是否為否定詞後的名詞
        final isNegated = _isAfterNegation(userMessage, word);

        keywords.add(RecallKeyword(
          word: word,
          weight: isNegated ? 2.5 : 1.5,
          type: isNegated ? KeywordType.negatedNoun : KeywordType.commonNoun,
        ));
        seen.add(word);
      }
    }

    // 如果沒萃取到任何關鍵字，從整句中取名詞片段
    if (keywords.isEmpty && userMessage.length > 5) {
      // fallback: 取抱怨句中引號或「」內的內容
      final quoted = RegExp(r'[「「"](.*?)[」"」"]').firstMatch(userMessage);
      if (quoted != null) {
        keywords.add(RecallKeyword(
          word: quoted.group(1)!,
          weight: 2.0,
          type: KeywordType.commonNoun,
        ));
      }
    }

    return keywords;
  }

  /// 判斷名詞是否出現在否定詞後面（「不是 X」「不要 X」）
  static bool _isAfterNegation(String text, String word) {
    final idx = text.indexOf(word);
    if (idx < 2) return false;
    final before = text.substring(idx.clamp(0, text.length - 1), idx);
    return before.contains('不') || before.contains('沒') || before.contains('非');
  }

  // ═══════════════════════════════════════════════════
  // ③ 全歷史搜尋
  // ═══════════════════════════════════════════════════

  /// 在完整對話歷史中搜尋包含關鍵字的訊息
  ///
  /// [allMessages] — 完整對話歷史（conversation.messages）
  /// [keywords] — 萃取出的關鍵字
  /// [excludedMessageIds] — 迭代排除的訊息 ID
  /// [recentMessageCount] — 最近 N 則不搜尋（LLM 已經看得到）
  /// [maxFragments] — 最多取回幾個片段
  static List<RecallFragment> search({
    required List<Message> allMessages,
    required List<RecallKeyword> keywords,
    Set<String>? excludedMessageIds,
    int recentMessageCount = 12,
    int maxFragments = 5,
  }) {
    if (keywords.isEmpty) return [];

    // 只搜尋「不在最近 N 則裡」的訊息
    final searchableMessages = allMessages.length > recentMessageCount
        ? allMessages.sublist(0, allMessages.length - recentMessageCount)
        : <Message>[];

    if (searchableMessages.isEmpty) return [];

    final fragments = <RecallFragment>[];

    for (final msg in searchableMessages) {
      // 排除已回覆過的
      if (excludedMessageIds != null && excludedMessageIds.contains(msg.id)) {
        continue;
      }

      // 只搜尋 user 和 assistant 訊息
      if (msg.role != 'user' && msg.role != 'assistant') continue;

      // 跳過空訊息
      final content = msg.content.trim();
      if (content.isEmpty) continue;

      // 跳過系統注入的靜默訊息
      if (msg.metadata?['silent'] == true) continue;

      // 計算命中
      final hitKeywords = <String>[];
      double score = 0;

      for (final kw in keywords) {
        if (content.toLowerCase().contains(kw.word.toLowerCase())) {
          hitKeywords.add(kw.word);
          score += kw.weight;
        }
      }

      if (hitKeywords.isEmpty) continue;

      // user 訊息加權（使用者記得的是自己說過的話）
      if (msg.role == 'user') score *= 1.5;

      // 截斷內容（保留前 500 字）
      final truncatedContent = content.length > 500
          ? '${content.substring(0, 500)}...'
          : content;

      fragments.add(RecallFragment(
        messageId: msg.id,
        timestamp: msg.timestamp,
        role: msg.role,
        content: truncatedContent,
        hitKeywords: hitKeywords,
        score: score,
      ));
    }

    // 排序：分數高的優先，同分時較新的優先
    fragments.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      return b.timestamp.compareTo(a.timestamp);
    });

    return fragments.take(maxFragments).toList();
  }

  // ═══════════════════════════════════════════════════
  // ④ 結果格式化
  // ═══════════════════════════════════════════════════

  /// 把搜尋結果格式化為 system note
  static String? buildRecallNote(List<RecallFragment> fragments) {
    if (fragments.isEmpty) {
      return '''【記憶回溯】
使用者似乎認為你忘記了某些內容。我從完整對話歷史中暫時沒有搜到直接相關的片段，但請放心——所有對話記錄都還在，只是一時沒搜到。

💡 回覆指引：
- 誠實但負責地說：「我暫時沒找到，但資料一定還在。請給我更多線索——大概是什麼時候討論的？或者提到什麼名詞？我一定會幫你找回來。」
- 不要說「資料不見了」或「我沒有存」——資料都在，只是搜尋還沒命中。
- 使用者給更多線索後，下一輪搜尋會更精準。''';
    }

    final buffer = StringBuffer();
    buffer.writeln('【記憶回溯】');
    buffer.writeln('使用者似乎認為你忘記了某些內容。以下是從完整對話歷史中找回的相關段落，');
    buffer.writeln('請參考這些內容回覆使用者。語氣要讓使用者安心——東西還在，你找回來了。');
    buffer.writeln();

    for (var i = 0; i < fragments.length; i++) {
      final f = fragments[i];
      final timeStr = '${f.timestamp.month}/${f.timestamp.day} ${f.timestamp.hour.toString().padLeft(2, '0')}:${f.timestamp.minute.toString().padLeft(2, '0')}';
      final roleLabel = f.role == 'user' ? '👤 使用者' : '🤖 助理';
      final hitStr = f.hitKeywords.join('、');

      buffer.writeln('---');
      buffer.writeln('📌 片段 ${i + 1}（$timeStr，命中關鍵字：$hitStr）');
      buffer.writeln('$roleLabel：${f.content}');
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.writeln('💡 回覆指引：');
    buffer.writeln('- 如果這些就是使用者指的內容，確認你找回來了：「我找回來了！你之前說的是...」');
    buffer.writeln('- 如果不完全對，誠實說：「我找到了這些，是你要找的嗎？如果不是，請給我更多線索」');
    buffer.writeln('- 如果沒找到，負責任地說：「我暫時沒找到，但資料一定還在。請問大概是什麼時候討論的？或者提到什麼關鍵詞？」');
    buffer.writeln('- 語氣要傳達：東西還在，我會負責找回來。使用者要的是「找回來找得到」的安全感。');

    return buffer.toString();
  }
}
