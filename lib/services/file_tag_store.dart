// file_tag_store.dart
// AD-05 檔案標籤系統 — TagStore（持久化 + CRUD）
// Sprint 13-5
//
// 標籤索引存在 SharedPreferences（快取層），不修改原始檔案。
// 標籤對應的檔案路徑指向檔案層的真實檔案。

import 'dart:convert';

import 'package:bridge_app/models/master_folder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 檔案標籤 Store。
///
/// 管理 FileTag 的持久化（SharedPreferences key `bridge_file_tags_v1`）。
/// 支援：新增標籤、為檔案加/移標籤、依標籤查檔案、依檔案查標籤。
class FileTagStore {
  static const String _key = 'bridge_file_tags_v1';

  const FileTagStore();

  // ──────────────────────────────────────────────
  // 讀取
  // ──────────────────────────────────────────────

  /// 載入所有標籤
  Future<List<FileTag>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => FileTag.fromJson(Map<String, dynamic>.from(item)))
          .where((tag) => tag.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
    } catch (_) {
      return const [];
    }
  }

  /// 依標籤名稱查找
  Future<FileTag?> findByName(String name) async {
    final normalized = FileTag.normalizeName(name);
    final all = await loadAll();
    for (final tag in all) {
      if (tag.name == normalized) return tag;
    }
    return null;
  }

  /// 查詢某個檔案的所有標籤
  Future<List<FileTag>> tagsForFile(String filePath) async {
    final all = await loadAll();
    return all.where((tag) => tag.filePaths.contains(filePath)).toList();
  }

  // ──────────────────────────────────────────────
  // 寫入
  // ──────────────────────────────────────────────

  /// 建立新標籤（如已存在則回傳現有的）
  Future<FileTag> createTag(
    String label, {
    String? color,
  }) async {
    final normalized = FileTag.normalizeName(label);
    final all = List<FileTag>.of(await loadAll());

    // 已存在
    final existing = all.where((t) => t.name == normalized);
    if (existing.isNotEmpty) return existing.first;

    final tag = FileTag(
      name: normalized,
      label: label.trim(),
      color: color,
      createdAt: DateTime.now(),
    );
    all.add(tag);
    await _save(all);
    return tag;
  }

  /// 為檔案添加標籤（標籤不存在則自動建立）
  Future<void> tagFile(String filePath, String label) async {
    final normalized = FileTag.normalizeName(label);
    final all = List<FileTag>.of(await loadAll());

    final index = all.indexWhere((t) => t.name == normalized);
    if (index >= 0) {
      // 標籤已存在，加檔案路徑
      final paths = List<String>.of(all[index].filePaths);
      if (!paths.contains(filePath)) {
        paths.add(filePath);
        all[index] = all[index].copyWith(filePaths: paths);
      }
    } else {
      // 建立新標籤
      all.add(FileTag(
        name: normalized,
        label: label.trim(),
        filePaths: [filePath],
        createdAt: DateTime.now(),
      ));
    }

    await _save(all);
  }

  /// 為檔案移除標籤
  Future<void> untagFile(String filePath, String label) async {
    final normalized = FileTag.normalizeName(label);
    final all = List<FileTag>.of(await loadAll());

    final index = all.indexWhere((t) => t.name == normalized);
    if (index < 0) return;

    final paths = List<String>.of(all[index].filePaths)
      ..remove(filePath);

    if (paths.isEmpty) {
      // 標籤下沒有檔案了，移除標籤
      all.removeAt(index);
    } else {
      all[index] = all[index].copyWith(filePaths: paths);
    }

    await _save(all);
  }

  /// 刪除標籤
  Future<void> deleteTag(String name) async {
    final normalized = FileTag.normalizeName(name);
    final all = List<FileTag>.of(await loadAll());
    all.removeWhere((t) => t.name == normalized);
    await _save(all);
  }

  /// 更新標籤
  Future<FileTag?> updateTag(
    String name, {
    String? label,
    String? color,
  }) async {
    final normalized = FileTag.normalizeName(name);
    final all = List<FileTag>.of(await loadAll());
    final index = all.indexWhere((t) => t.name == normalized);
    if (index < 0) return null;

    all[index] = all[index].copyWith(
      label: label?.trim(),
      color: color,
    );
    await _save(all);
    return all[index];
  }

  // ──────────────────────────────────────────────
  // 測試用
  // ──────────────────────────────────────────────

  Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ──────────────────────────────────────────────
  // 內部
  // ──────────────────────────────────────────────

  Future<void> _save(List<FileTag> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(tags.map((t) => t.toJson()).toList()),
    );
  }
}
