// AD-05 主資料夾 — Store（持久化管理資料夾清單）
//
// 持久化在 SharedPreferences：使用者納入的主資料夾清單。
// 支援多資料夾（使用者增補 #2）、新增/移除/啟停。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/master_folder.dart';

class MasterFolderStore {
  static const String _key = 'bridge_master_folders_v1';

  const MasterFolderStore();

  // ──────────────────────────────────────────────
  // 讀取
  // ──────────────────────────────────────────────

  Future<List<MasterFolder>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) =>
              MasterFolder.fromJson(Map<String, dynamic>.from(item)))
          .where((folder) => folder.path.isNotEmpty)
          .toList()
        ..sort((a, b) {
          // 預設資料夾排前面
          if (a.isDefault && !b.isDefault) return -1;
          if (!a.isDefault && b.isDefault) return 1;
          return a.addedAt.compareTo(b.addedAt);
        });
    } catch (_) {
      return const [];
    }
  }

  /// 只取啟用的資料夾
  Future<List<MasterFolder>> loadEnabled() async {
    final all = await loadAll();
    return all.where((f) => f.enabled).toList();
  }

  // ──────────────────────────────────────────────
  // 寫入
  // ──────────────────────────────────────────────

  /// 新增主資料夾。若路徑已存在則更新。
  Future<MasterFolder> add(String path, {String? label}) async {
    final normalized = _normalizePath(path);
    final id = MasterFolder.idForPath(normalized);
    final all = List<MasterFolder>.of(await loadAll());

    // 檢查是否已存在
    final existingIndex = all.indexWhere(
      (f) => f.id == id || _normalizePath(f.path) == normalized,
    );

    final now = DateTime.now();
    final folder = MasterFolder(
      id: id,
      path: normalized,
      label: label?.trim().isNotEmpty == true
          ? label!.trim()
          : _basename(normalized),
      isDefault: false,
      addedAt: existingIndex >= 0 ? all[existingIndex].addedAt : now,
      lastScannedAt: existingIndex >= 0
          ? all[existingIndex].lastScannedAt
          : null,
      enabled: true,
    );

    if (existingIndex >= 0) {
      all[existingIndex] = folder;
    } else {
      all.add(folder);
    }

    await _save(all);

    // 確保目錄結構存在
    await folder.ensureStructure();

    return folder;
  }

  /// 移除主資料夾（只從清單移除，不刪實際檔案）
  Future<void> remove(String folderId) async {
    final all = List<MasterFolder>.of(await loadAll());
    all.removeWhere((f) => f.id == folderId);
    await _save(all);
  }

  /// 更新主資料夾
  Future<MasterFolder?> update(MasterFolder folder) async {
    final all = List<MasterFolder>.of(await loadAll());
    final index = all.indexWhere((f) => f.id == folder.id);
    if (index < 0) return null;
    all[index] = folder;
    await _save(all);
    return folder;
  }

  /// 切換啟用狀態
  Future<void> toggleEnabled(String folderId) async {
    final all = List<MasterFolder>.of(await loadAll());
    final index = all.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    all[index] = all[index].copyWith(enabled: !all[index].enabled);
    await _save(all);
  }

  /// 更新最後掃描時間
  Future<void> markScanned(String folderId) async {
    final all = List<MasterFolder>.of(await loadAll());
    final index = all.indexWhere((f) => f.id == folderId);
    if (index < 0) return;
    all[index] =
        all[index].copyWith(lastScannedAt: DateTime.now());
    await _save(all);
  }

  // ──────────────────────────────────────────────
  // 預設資料夾
  // ──────────────────────────────────────────────

  /// 確保預設資料夾（App Documents Directory）存在於清單中。
  /// App 首次啟動或未設定任何資料夾時呼叫。
  Future<MasterFolder?> ensureDefaultFolder() async {
    if (kIsWeb) return null;

    final docs = await getApplicationDocumentsDirectory();
    final defaultPath = '${docs.path}/BridgeHome';

    final all = await loadAll();
    final existing = all.where((f) => f.isDefault).toList();

    if (existing.isNotEmpty) {
      // 預設資料夾已存在，確保結構完整
      await existing.first.ensureStructure();
      return existing.first;
    }

    // 建立預設資料夾
    final id = MasterFolder.idForPath(defaultPath);
    final now = DateTime.now();
    final folder = MasterFolder(
      id: id,
      path: defaultPath,
      label: '預設資料夾',
      isDefault: true,
      addedAt: now,
      enabled: true,
    );

    await folder.ensureStructure();

    final newAll = List<MasterFolder>.of(all)..add(folder);
    await _save(newAll);

    return folder;
  }

  /// 是否已設定過主資料夾（用於判斷是否需要顯示首次設定引導）
  Future<bool> hasAnyFolder() async {
    final all = await loadAll();
    return all.isNotEmpty;
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

  Future<void> _save(List<MasterFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(folders.map((f) => f.toJson()).toList()),
    );
  }

  static String _normalizePath(String path) {
    var value = path.trim();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _basename(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return '資料夾';
    return normalized.split('/').where((part) => part.isNotEmpty).last;
  }
}
