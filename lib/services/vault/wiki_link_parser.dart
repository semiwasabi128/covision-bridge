// wiki_link_parser.dart
// [[wiki-link]] 解析器
// [教練 Agent 2026-07-22] Phase 1 ②
//
// 從條目內容中解析 [[條目名]] 語法，
// 自動在 wiki_links 表建立雙向連結關係。
//
// 解析規則：
// - [[文字]] → 建立一條 wiki_link，link_text = "文字"
// - target_memory 用「標題或內容匹配」找到目標條目
// - 找不到目標 → 不建立連結（不建立空條目，避免垃圾資料）

import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:flutter/foundation.dart';

/// Wiki-link 解析結果
class ParsedWikiLink {
  final String linkText;
  final int startIndex;
  final int endIndex;

  ParsedWikiLink({
    required this.linkText,
    required this.startIndex,
    required this.endIndex,
  });
}

class WikiLinkParser {
  /// [[link]] 語法的正則
  static final _wikiLinkRegex = RegExp(r'\[\[([^\]]+)\]\]');

  /// 從文字內容中提取所有 [[wiki-link]]。
  ///
  /// 回傳所有匹配的 linkText 和位置。
  static List<ParsedWikiLink> parse(String content) {
    final links = <ParsedWikiLink>[];
    for (final match in _wikiLinkRegex.allMatches(content)) {
      links.add(ParsedWikiLink(
        linkText: match.group(1)!.trim(),
        startIndex: match.start,
        endIndex: match.end,
      ));
    }
    return links;
  }

  /// 解析條目內容中的 [[wiki-link]] 並寫入 wiki_links 表。
  ///
  /// [sourceMemoryId] 包含 [[link]] 的條目 ID
  /// [content] 條目的完整內容
  ///
  /// 流程：
  /// 1. 解析所有 [[link]]
  /// 2. 對每個 link，搜尋 memories 表找標題/內容匹配的條目
  /// 3. 找到 → INSERT OR IGNORE 進 wiki_links
  /// 4. 找不到 → 跳過（不建立空條目）
  ///
  /// 回傳成功建立的連結數。
  static Future<int> parseAndSave({
    required String sourceMemoryId,
    required String content,
  }) async {
    final links = parse(content);
    if (links.isEmpty) return 0;

    int created = 0;
    final db = BrainDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final link in links) {
      // 搜尋目標條目：優先比對 content 開頭（作為標題），
      // 再比對完整 content 包含 linkText
      final targetRows = db.select(
        'SELECT id FROM memories '
        'WHERE (content LIKE ? OR content LIKE ?) '
        'AND id != ? '
        'AND archived = 0 '
        'LIMIT 1',
        [
          '${link.linkText}%',  // 開頭匹配（標題）
          '%${link.linkText}%', // 包含匹配
          sourceMemoryId,
        ],
      );

      final validTargets = targetRows
          .where((r) => r['id'] as String != sourceMemoryId)
          .toList();

      if (validTargets.isEmpty) continue;

      final targetId = validTargets.first['id'] as String;

      try {
        db.execute(
          'INSERT OR IGNORE INTO wiki_links (id, source_memory, target_memory, link_text, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            '${sourceMemoryId}_$targetId',
            sourceMemoryId,
            targetId,
            link.linkText,
            now,
          ],
        );
        created++;
      } catch (e) {
        debugPrint('[WikiLinkParser] insert 失敗: $e');
      }
    }

    return created;
  }

  /// 將內容中的 [[link]] 渲染為可點擊的 markdown 連結格式。
  ///
  /// 用於 UI 顯示——把 [[文字]] 轉成 [文字](memory://id) 格式。
  /// 如果目標條目存在，id 為實際 memory ID；不存在則保留原文字。
  static Future<String> renderForDisplay({
    required String content,
  }) async {
    final links = parse(content);
    if (links.isEmpty) return content;

    String result = content;
    // 從後往前替換，避免位移
    for (final link in links.reversed) {
      final targetRows = BrainDatabase.instance.db.select(
        'SELECT id FROM memories WHERE content LIKE ? AND archived = 0 LIMIT 1',
        ['${link.linkText}%'],
      );

      final replacement = targetRows.isNotEmpty
          ? '[${link.linkText}](memory://${targetRows.first['id']})'
          : link.linkText; // 找不到目標 → 顯示純文字

      result = result.substring(0, link.startIndex) +
          replacement +
          result.substring(link.endIndex);
    }

    return result;
  }
}
