// canvas_store.dart
// D11: 畫布元資料存取層 — 管理畫布的 CRUD + 專案同步
//
// 設計文件: d11-project-canvas-conversation-design.md §2, §4.3
//
// 職責：
// 1. CanvasMetadata 的 CRUD（JSON 檔案持久化）
// 2. 畫布存檔時同步更新 ProjectDoor 的 flowSteps
// 3. 查詢：by conversationId, by projectDoorId, list all

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/canvas/canvas_metadata.dart';
import '../models/flow_step.dart';
import '../models/project_door.dart';
import 'project_door_store.dart';

class CanvasStore {
  static const String _storageFolderName = 'bridge_state';
  static const String _storageFileName = 'canvases.json';

  static Directory? _debugStorageDirectory;

  @visibleForTesting
  static void debugSetStorageDirectory(Directory? directory) {
    _debugStorageDirectory = directory;
  }

  // ── CRUD ──

  static Future<List<CanvasMetadata>> getAll() async {
    final file = await _storageFile();
    if (!await file.exists()) return [];

    try {
      final jsonStr = await file.readAsString();
      if (jsonStr.isEmpty) return [];
      final List<dynamic> list = jsonDecode(jsonStr);
      return list
          .map((e) => CanvasMetadata.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('[CanvasStore] getAll error: $e');
      return [];
    }
  }

  static Future<CanvasMetadata?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<CanvasMetadata?> getByConversationId(String conversationId) async {
    final all = await getAll();
    try {
      return all.firstWhere((c) => c.conversationId == conversationId);
    } catch (_) {
      return null;
    }
  }

  static Future<CanvasMetadata?> getByProjectDoorId(String doorId) async {
    final all = await getAll();
    try {
      return all.firstWhere((c) => c.projectDoorId == doorId);
    } catch (_) {
      return null;
    }
  }

  static Future<CanvasMetadata> create({
    required String title,
    String? conversationId,
  }) async {
    final canvas = CanvasMetadata.create(
      title: title,
      conversationId: conversationId,
    );
    await save(canvas);
    return canvas;
  }

  static Future<void> save(CanvasMetadata canvas) async {
    final all = await getAll();
    final index = all.indexWhere((c) => c.id == canvas.id);
    if (index >= 0) {
      all[index] = canvas;
    } else {
      all.add(canvas);
    }
    await _writeAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((c) => c.id == id);
    await _writeAll(all);
  }

  // ── 存檔同步 ──

  /// 畫布存檔 — 建立或更新專案門，同步 flowSteps。
  ///
  /// 每次存檔都會：
  /// 1. 如果沒有 projectDoorId → 建立新的 ProjectDoor
  /// 2. 如果有 projectDoorId → 更新現有 ProjectDoor 的 flowSteps
  /// 3. 更新 CanvasMetadata 的 projectDoorId 和 updatedAt
  /// 4. 確保專案頁面永遠顯示最新結果
  static Future<CanvasMetadata> saveCanvasToProject({
    required CanvasMetadata canvas,
    required List<FlowStep> flowSteps,
  }) async {
    final doorStore = ProjectDoorStore();
    ProjectDoor? door;

    if (canvas.projectDoorId != null) {
      // 更新現有門
      final doors = await doorStore.loadAll();
      door = doors.where((d) => d.id == canvas.projectDoorId).firstOrNull;
    }

    if (door != null) {
      // 更新 flowSteps（保留已完成步驟的狀態）
      final existingSteps = {for (var s in door.flowSteps) s.id: s};
      final updatedSteps = flowSteps.map((s) {
        final existing = existingSteps[s.id];
        if (existing != null && existing.isDone) {
          // 保留已完成狀態
          return existing;
        }
        return s;
      }).toList();

      door = door.copyWith(
        flowSteps: updatedSteps,
        title: canvas.title,
        updatedAt: DateTime.now(),
      );
      await doorStore.save(door);
    } else {
      // 建立新門
      door = ProjectDoor.create(
        title: canvas.title,
        sourceIntent: 'canvas',
      ).copyWith(
        flowSteps: flowSteps,
        conversationId: canvas.conversationId,
        status: 'active',
      );
      await doorStore.save(door);

      // 更新畫布的 projectDoorId
      canvas = canvas.copyWith(
        projectDoorId: door.id,
        updatedAt: DateTime.now(),
      );
    }

    await save(canvas);
    return canvas;
  }

  // ── Storage ──

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

  static Future<void> _writeAll(List<CanvasMetadata> canvases) async {
    final file = await _storageFile();
    canvases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // [v200 原子寫令 2026-09-02] 舊 writeAsString 直接寫=被強殺（killall -9）
    // 打斷即截斷——今天 canvases.json 被砍成 [] 的真兇。
    // 改：先寫 .tmp 再 rename（rename 在同一檔案系統上是原子的，
    // 要麼舊檔完整要麼新檔完整，不存在半截狀態）。
    final tmp = File('${file.path}.tmp${DateTime.now().millisecondsSinceEpoch}');
    await tmp.writeAsString(
      jsonEncode(canvases.map((c) => c.toJson()).toList()),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
