// identity_embed_text.dart
// [小葵 2026-09-09 Blue v2 檢索令] 身份嵌入文字組裝器——嵌入內容的單一真相。
//
// 設計稿 §2：五因素織進向量——
//   [資料夾: 路徑] [分類: folder_origin.category] [主題: folder_origin.summary]
//   [任務: task.name] [屬性: topic_terms] {檔名} {內容}
//
// 寫入管線三路（vision/文字/檔名 fallback）與全量重嵌都呼叫這裡。
// 每段可選（無則跳過）——流水編號照片也有資料夾身份，任務產出有任務血緣。

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';
import 'asset_sandbox.dart';
import 'folder_origin_service.dart';

class IdentityEmbedText {
  IdentityEmbedText._();
  static final IdentityEmbedText instance = IdentityEmbedText._();

  /// 組裝身份嵌入文字。
  ///
  /// [relPath] 相對路徑（含檔名）
  /// [folderRoot] 授權根絕對路徑
  /// [content] 內容主體（視覺描述 / 檔案文字 / 檔名）
  /// [originKind] 來源（farm/agent/media…，任務或 agent 產出的線索）
  Future<String> build({
    required String relPath,
    required String folderRoot,
    required String content,
    String? originKind,
  }) async {
    final parts = <String>[];

    // 因素2：資料夾路徑（身份骨幹）
    final folderCtx = AssetSandbox.folderContextPrefix(relPath).trim();
    if (folderCtx.isNotEmpty) parts.add(folderCtx);

    // 因素3：資料夾分類/主題（folder_origin，父層繼承）
    try {
      final origin = FolderOriginService.instance.lookup(relPath, folderRoot);
      final cat = origin['category'];
      final sum = origin['summary'];
      if (cat != null && cat.isNotEmpty) parts.add('[分類: $cat]');
      if (sum != null && sum.isNotEmpty) parts.add('[主題: $sum]');

      // 因素4：任務血緣
      final taskId = origin['task_id'];
      final tName = FolderOriginService.instance.taskName(taskId);
      if (tName != null) parts.add('[任務: $tName]');
    } catch (e) {
      debugPrint('[IdentityEmbed] folder_origin 查詢失敗（跳過身份段）: $e');
    }

    // 因素5：屬性聯動（topic_terms——檔名/資料夾段的詞擴展）
    try {
      final terms = await attributeTerms(relPath);
      if (terms.isNotEmpty) parts.add('[屬性: ${terms.join('/')}]');
    } catch (_) {/* 詞表空即跳過 */}

    // 來源身份（agent/task 產出線索）
    if (originKind != null && originKind.isNotEmpty) {
      parts.add('[來源: $originKind]');
    }

    // 因素1：檔名 + 內容主體
    final fileName = relPath.split('/').last;
    parts.add(fileName);
    if (content.isNotEmpty && content != fileName) parts.add(content);

    return parts.join(' ');
  }

  /// 屬性詞——從 topic_terms 反查：檔名與資料夾段出現在詞表的
  /// related 清單裡，就把該 term 附上（例：千手皇冠 → 鹿角蕨）。
  Future<List<String>> attributeTerms(String relPath) async {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select('SELECT term, related FROM topic_terms');
      if (rows.isEmpty) return [];
      final segments = relPath.split('/');
      final hits = <String>[];
      for (final r in rows) {
        final term = r['term'] as String;
        final raw = r['related'] as String?;
        if (raw == null || raw.isEmpty) continue;
        final list = jsonDecode(raw);
        if (list is! List) continue;
        // 路徑段或檔名出現在 related 裡 → 這個 term 是它的屬性
        for (final seg in segments) {
          if (seg.isEmpty) continue;
          if (list.any((e) => e.toString() == seg)) {
            hits.add(term);
            break;
          }
        }
      }
      return hits;
    } catch (_) {
      return [];
    }
  }

  /// 截斷（嵌入模型輸入上限）。
  String clamp(String text, {int max = 2000}) =>
      text.length > max ? text.substring(0, max) : text;
}
