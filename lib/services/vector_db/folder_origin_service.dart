// folder_origin_service.dart
// [小葵 2026-09-09 Blue v2 檢索令] 資料夾身份——分類/主題/來源/任務血緣。
//
// 設計稿 §2.1：folder_origin 表三路合一填充：
//  1. 規則推斷（免 LLM，本檔核心）
//  2. 任務反查（task_asset_links）
//  3. LLM 蒸餾（後續增強，介面已留）
//
// 身份嵌入（identity_embed_text.dart）與分組檢索都讀這裡。

import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';

class FolderOriginService {
  FolderOriginService._();
  static final FolderOriginService instance = FolderOriginService._();

  /// 規則推斷：相對路徑 → 分類。
  /// 路徑模式對應人類既有的分類習慣（Blue 的資料夾結構實測歸納）。
  static String? ruleCategory(String relPath) {
    final p = relPath.toLowerCase();
    // 品種照：照片紀錄下的最深層資料夾（品種名）
    if (relPath.contains('照片紀錄')) {
      final segs = relPath.split('/');
      final last = segs.last;
      if (last.isNotEmpty && !RegExp(r'^\d{4}').hasMatch(last)) {
        return '植物品種照';
      }
      return '農場照片';
    }
    if (p.contains('巡查') || p.contains('inspection')) return '巡查紀錄';
    if (p.contains('_ig') || p.contains('ig_') || p.contains('發想')) {
      return 'IG 發想文';
    }
    if (p.contains('週報')) return '週報';
    if (p.contains('鹿角蕨')) return '鹿角蕨';
    if (p.contains('企劃') || p.contains('規劃')) return '企劃文件';
    if (p.contains('備份')) return '備份';
    if (p.contains('原始碼') || p.contains('source')) return '程式原始碼';
    if (p.contains('知識庫') || p.contains('研究')) return '知識庫';
    return null;
  }

  /// 既有資料回填：掃 asset_index 全部 file_path → 建每個資料夾一列。
  /// 冪等：已存在的 folder_path 跳過（不覆蓋人類/LLM 補過的）。
  Future<int> backfillFromAssetIndex() async {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT DISTINCT folder_root, '
        "  rtrim(file_path, replace(file_path, '/', '')) AS folder_rel "
        'FROM asset_index',
      );
      // SQLite 沒有直接的 dirname——改在 Dart 端算
      final all = db.select(
        'SELECT DISTINCT folder_root, file_path FROM asset_index',
      );
      final folders = <String, ({String root, String rel})>{};
      for (final r in all) {
        final fp = r['file_path'] as String;
        final root = r['folder_root'] as String;
        final rel = fp.contains('/')
            ? fp.substring(0, fp.lastIndexOf('/'))
            : '';
        if (rel.isEmpty) continue;
        final key = '$root/$rel';
        folders.putIfAbsent(key, () => (root: root, rel: rel));
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      var inserted = 0;
      for (final e in folders.entries) {
        final cat = ruleCategory(e.value.rel);
        db.execute(
          'INSERT OR IGNORE INTO folder_origin '
          '(folder_path, root, category, summary, origin_kind, task_id, updated_at) '
          "VALUES (?, ?, ?, NULL, 'user', NULL, ?)",
          [e.value.rel, e.value.root, cat, now],
        );
        inserted++;
      }
      // 任務反查：task_asset_links → origin_kind='task'
      try {
        db.execute(
          'UPDATE folder_origin SET origin_kind = \'task\' '
          'WHERE folder_path IN ('
          '  SELECT rtrim(a.file_path, replace(a.file_path, \'/\', \'\')) '
          '  FROM task_asset_links l JOIN asset_index a ON a.id = l.asset_id '
          "  WHERE a.file_path LIKE '%/%')",
        );
      } catch (_) {/* 表可能空，無妨 */}
      debugPrint('[FolderOrigin] 回填 $inserted 個資料夾身份');
      return inserted;
    } catch (e) {
      debugPrint('[FolderOrigin] 回填失敗: $e');
      return 0;
    }
  }

  /// 查某相對路徑的資料夾身份（category/summary/task）。
  /// 精確命中 → 回傳；找不到試父層（身份可繼承：千手皇冠 繼承 照片紀錄的分類）。
  Map<String, String?> lookup(String relPath, String root) {
    try {
      final db = BrainDatabase.instance.db;
      var path = relPath.contains('/')
          ? relPath.substring(0, relPath.lastIndexOf('/'))
          : relPath;
      while (path.isNotEmpty) {
        final rows = db.select(
          'SELECT category, summary, origin_kind, task_id FROM folder_origin '
          'WHERE folder_path = ? AND root = ?',
          [path, root],
        );
        if (rows.isNotEmpty) {
          final r = rows.first;
          return {
            'category': r['category'] as String?,
            'summary': r['summary'] as String?,
            'origin_kind': r['origin_kind'] as String?,
            'task_id': r['task_id'] as String?,
          };
        }
        // 上溯父層
        path = path.contains('/')
            ? path.substring(0, path.lastIndexOf('/'))
            : '';
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// 查任務名（給嵌入文字的 [任務: ...] 段）。
  String? taskName(String? taskId) {
    if (taskId == null || taskId.isEmpty) return null;
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT name FROM scheduled_tasks WHERE id = ?',
        [taskId],
      );
      return rows.isEmpty ? null : rows.first['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 主題詞表：term → related（屬性聯動查詢擴展用）。
  List<String> expandQuery(String term) {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT related FROM topic_terms WHERE term = ?',
        [term],
      );
      if (rows.isEmpty) return [];
      final raw = rows.first['related'] as String?;
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      return list is List ? list.map((e) => e.toString()).toList() : [];
    } catch (_) {
      return [];
    }
  }
}
