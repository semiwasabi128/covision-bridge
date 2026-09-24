import 'dart:io';

import '../models/second_brain_file_index.dart';

class SecondBrainContentDigest {
  final SecondBrainRoom room;
  final String summary;
  final String excerpt;
  final List<String> keywords;

  const SecondBrainContentDigest({
    required this.room,
    required this.summary,
    required this.excerpt,
    required this.keywords,
  });
}

class SecondBrainContentDigestService {
  static const int maxReadableBytes = 1024 * 1024;
  static const int maxSummaryLength = 160;
  static const int maxExcerptLength = 520;

  const SecondBrainContentDigestService();

  Future<SecondBrainContentDigest?> digestFile(
    File file, {
    required String title,
    required String extension,
    SecondBrainRoom fallbackRoom = SecondBrainRoom.files,
  }) async {
    if (!_isTextDigestSupported(extension)) return null;

    final stat = await file.stat();
    if (stat.size <= 0 || stat.size > maxReadableBytes) return null;

    String raw;
    try {
      raw = await file.readAsString();
    } catch (_) {
      return null;
    }

    final clean = _cleanText(raw);
    if (clean.length < 8) return null;

    final keywords = _keywordsFor('$title $clean');
    final room = _roomFor('$title $clean', fallbackRoom: fallbackRoom);
    final excerpt = _truncate(clean, maxExcerptLength);
    final summary = _summaryFor(
      title: title,
      room: room,
      clean: clean,
      keywords: keywords,
    );

    return SecondBrainContentDigest(
      room: room,
      summary: summary,
      excerpt: excerpt,
      keywords: keywords,
    );
  }

  bool _isTextDigestSupported(String extension) {
    const supported = {
      'txt',
      'md',
      'markdown',
      'csv',
      'tsv',
      'json',
      'yaml',
      'yml',
      'rtf',
    };
    return supported.contains(extension.toLowerCase());
  }

  SecondBrainRoom _roomFor(
    String text, {
    required SecondBrainRoom fallbackRoom,
  }) {
    final value = text.toLowerCase();
    final scores = <SecondBrainRoom, int>{
      SecondBrainRoom.self: _scoreFor(value, const [
        '自我',
        '偏好',
        '習慣',
        '人格',
        'identity',
        'profile',
        'preference',
      ]),
      SecondBrainRoom.projects: _scoreFor(value, const [
        '專案',
        '計畫',
        '任務',
        'roadmap',
        'milestone',
        'todo',
        'prd',
      ]),
      SecondBrainRoom.files: _scoreFor(value, const [
        '資料夾',
        '檔案',
        '文件',
        '索引',
        'archive',
        'document',
        'file',
      ]),
      SecondBrainRoom.doors: _scoreFor(value, const [
        '門',
        '主線',
        '支線',
        '回流',
        '分支',
        'decision',
        'branch',
      ]),
      SecondBrainRoom.bridges: _scoreFor(value, const [
        '橋樑',
        'adapter',
        'gateway',
        'api',
        'provider',
        '能力',
        'bridge',
      ]),
      SecondBrainRoom.companions: _scoreFor(value, const [
        '夥伴',
        '角色',
        'agent',
        'companion',
        '人格設定',
        '狀態圖',
      ]),
    };

    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value <= 0) return fallbackRoom;
    return best.key;
  }

  int _scoreFor(String value, List<String> needles) {
    var score = 0;
    for (final needle in needles) {
      if (value.contains(needle.toLowerCase())) {
        score += needle.length >= 4 ? 3 : 2;
      }
    }
    return score;
  }

  String _summaryFor({
    required String title,
    required SecondBrainRoom room,
    required String clean,
    required List<String> keywords,
  }) {
    final firstSentence = clean
        .split(RegExp(r'[。！？!?]\s*|\n+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.length >= 8, orElse: () => clean);
    final keywordText = keywords.isEmpty
        ? '尚未抽出關鍵詞'
        : keywords.take(4).join('、');
    return _truncate(
      '已讀取「$title」並歸入${room.zhLabel}。重點：$firstSentence。關鍵詞：$keywordText。',
      maxSummaryLength,
    );
  }

  List<String> _keywordsFor(String text) {
    final normalized = text
        .replaceAll(RegExp(r"""[#*_`>"':;,.!?，。！？、（）()\[\]{}<>「」『』]"""), ' ')
        .toLowerCase();
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2)
        .where((token) => !_stopWords.contains(token))
        .toList();

    final counts = <String, int>{};
    for (final token in tokens) {
      counts[token] = (counts[token] ?? 0) + 1;
    }

    final scored = counts.entries.toList()
      ..sort((a, b) {
        final countOrder = b.value.compareTo(a.value);
        if (countOrder != 0) return countOrder;
        return b.key.length.compareTo(a.key.length);
      });
    return scored.take(8).map((entry) => entry.key).toList();
  }

  String _cleanText(String raw) {
    return raw
        .replaceAll(RegExp(r'\\[a-z]+\d* ?|[{}]'), ' ')
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 1)}…';
  }

  static const _stopWords = {
    'the',
    'and',
    'for',
    'with',
    'this',
    'that',
    'from',
    'into',
    '我們',
    '以及',
    '可以',
    '這個',
    '那個',
    '目前',
    '使用者',
  };
}
