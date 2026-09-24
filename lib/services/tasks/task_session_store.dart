// task_session_store.dart
// [隊友訊息流 第 1 刀 C1 2026-09-08]
// TaskSession 的 JSON 持久化——完全沿用 ConversationStore 慣例：
// bridge_state/ 目錄、rolling backup 保留 10 版、損壞時找最新備份還原、
// @visibleForTesting debugSetStorageDirectory。
// 刻意不用 SharedPreferences：任務紀錄會長大，且要與 conversations.json 同目录好備份。

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'task_session.dart';

class TaskSessionStore {
  static const String _storageFolderName = 'bridge_state';
  static const String _storageFileName = 'task_sessions.json';

  static Directory? _debugStorageDirectory;

  @visibleForTesting
  static void debugSetStorageDirectory(Directory? directory) {
    _debugStorageDirectory = directory;
  }

  static Future<List<TaskSession>> getAll() async {
    final file = await _storageFile();
    if (await file.exists()) {
      final jsonStr = await file.readAsString();
      // [C1 修正] 解碼失敗必須走還原路徑——_decodeSessions 吞錯回 [] 的話，
      // 主檔損壞會被當成「沒有任務」靜默通過（靜默吞錯型 bug）。
      List<TaskSession>? decoded;
      try {
        decoded = _decodeSessions(jsonStr);
      } catch (e) {
        debugPrint('[TaskSessionStore] 解碼失敗: $e');
      }
      if (decoded != null) return decoded;

      debugPrint('[TaskSessionStore] 讀取失敗，嘗試從備份還原');
      final dir = file.parent;
      try {
        final backups = await dir
            .list()
            .where((e) => e.path.contains('.${_storageFileName}.v'))
            .toList();
        backups.sort((a, b) => b.path.compareTo(a.path));
        for (final backup in backups) {
          try {
            final text = await File(backup.path).readAsString();
            final restored = _decodeSessions(text);
            await file.writeAsString(text, flush: true);
            debugPrint(
                '[TaskSessionStore] 從備份還原 ${restored.length} 個任務');
            return restored;
          } catch (_) {}
        }
      } catch (_) {}
      return [];
    }
    return [];
  }

  /// 嚴格解碼——損壞內容直接 throw（讓 getAll 走備份還原），空檔案回 []。
  /// （C1 教訓：吞錯回 [] 會把「主檔損壞」偽裝成「沒有任務」。）
  static List<TaskSession> _decodeSessions(String jsonStr) {
    if (jsonStr.isEmpty) return [];
    final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => TaskSession.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> save(TaskSession session) async {
    final all = await getAll();
    final index = all.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      all[index] = session;
    } else {
      all.add(session);
    }
    await _writeAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((s) => s.id == id);
    await _writeAll(all);
  }

  static Future<TaskSession?> getById(String id) async {
    final all = await getAll();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 進行中的任務（UI 的任務卡 / chip 列 / 關窗確認框依此判斷）
  static Future<List<TaskSession>> getActive() async {
    final all = await getAll();
    return all.where((s) => s.isActive).toList();
  }

  static Future<File> _storageFile() async {
    final directory = await _storageDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$_storageFileName');
  }

  static Future<Directory> _storageDirectory() async {
    if (_debugStorageDirectory != null) return _debugStorageDirectory!;
    try {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/$_storageFolderName');
    } catch (_) {
      return Directory(
        '${Directory.systemTemp.path}/bridge_app/$_storageFolderName',
      );
    }
  }

  static Future<void> _writeAll(List<TaskSession> sessions) async {
    final file = await _storageFile();
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _rotateBackup(file);
    await file.writeAsString(
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
      flush: true,
    );
  }

  /// 滾動備份保留 10 版（與 ConversationStore 同慣例）
  static Future<void> _rotateBackup(File currentFile) async {
    final dir = currentFile.parent;
    const maxBackups = 10;
    try {
      final existing = await dir
          .list()
          .where((e) => e.path.contains('.${_storageFileName}.v'))
          .map((e) => e.path)
          .toList();
      existing.sort();
      if (existing.length >= maxBackups) {
        await File(existing.first).delete();
      }
      if (await currentFile.exists()) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final backupPath = '${dir.path}/.${_storageFileName}.v$timestamp';
        await currentFile.copy(backupPath);
      }
    } catch (e) {
      debugPrint('[TaskSessionStore] 備份失敗（不阻擋主流程）: $e');
    }
  }
}
