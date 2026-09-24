// project_trash_store.dart
// [小葵 2026-09-21 Blue 令] 專案回收桶——畫布（專案檔）的後悔藥。
//
// 緣起：刪整個畫布＝五件套級聯刪除（CanvasMetadata + CanvasProps 節點 +
// 綁定對話 + ProjectDoor + 關聯 Entity）。之前刪了就是刪了；
// Blue 令：專案回收桶做為保護傘——刪錯專案要撈得回來。
//
// 設計（比照 ConversationStore 的 trash/ 制度）：
// - bridge_state/project_trash/{canvasId}.json 一畫布一檔，永不清理
// - 快照內容：canvas metadata + 全部節點（CanvasProps + entity id）
//   + 綁定對話 id + project door
// - restore：把五件套逐一還原；衝突（id 已存在）以現行為準、跳過還原項
// - purge：永久刪除（UI 需先警示「刪除後無法恢復」）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/entity_graph/canvas_props.dart';
import '../models/project_door.dart';
import 'project_door_store.dart';

/// 專案回收桶的一筆完整快照
class ProjectTrashSnapshot {
  final String canvasId;
  final Map<String, dynamic> canvas; // CanvasMetadata.toJson()
  final List<Map<String, dynamic>> nodes; // CanvasProps.toJson()（含 entityId 為 key 的資訊）
  final Map<String, dynamic>? door; // ProjectDoor.toJson()（若刪除時有關聯門）
  final String? conversationId; // 綁定的對話 id（對話本身另有 trash/ 備份）
  final DateTime deletedAt;

  const ProjectTrashSnapshot({
    required this.canvasId,
    required this.canvas,
    required this.nodes,
    this.door,
    this.conversationId,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'canvasId': canvasId,
        'canvas': canvas,
        'nodes': nodes,
        'door': door,
        'conversationId': conversationId,
        'deletedAt': deletedAt.toIso8601String(),
      };

  factory ProjectTrashSnapshot.fromJson(Map<String, dynamic> j) =>
      ProjectTrashSnapshot(
        canvasId: j['canvasId'] as String,
        canvas: Map<String, dynamic>.from(j['canvas'] as Map),
        nodes: (j['nodes'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        door: j['door'] == null
            ? null
            : Map<String, dynamic>.from(j['door'] as Map),
        conversationId: j['conversationId'] as String?,
        deletedAt: DateTime.tryParse(j['deletedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class ProjectTrashStore {
  static const _folderName = 'project_trash';

  /// 測試用——注入儲存目錄（避開 path_provider）
  static Directory? _debugDir;
  static void debugSetStorageDirectory(Directory? d) => _debugDir = d;

  static Future<Directory> _trashDir() async {
    if (_debugDir != null) {
      final dir = Directory('${_debugDir!.path}/bridge_state/$_folderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/bridge_state/$_folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 備份整個畫布進專案回收桶（刪除前呼叫）
  static Future<void> backup({
    required Map<String, dynamic> canvasJson,
    required List<CanvasEntry> nodes,
    ProjectDoor? door,
    String? conversationId,
  }) async {
    final dir = await _trashDir();
    final canvasId = canvasJson['id'] as String;
    final snapshot = ProjectTrashSnapshot(
      canvasId: canvasId,
      canvas: canvasJson,
      nodes: nodes.map((n) {
        final m = Map<String, dynamic>.from(n.props.toJson());
        m['_entityId'] = n.entity.id;
        // Entity 是投影視圖（underlying 才是持久物件）——只存 id + type，
        // 還原時靠 CanvasProps + 底層物件（門/對話）帶回。
        m['_entityType'] = n.entity.type.name;
        return m;
      }).toList(),
      door: door?.toJson(),
      conversationId: conversationId,
      deletedAt: DateTime.now(),
    );
    final f = File(
        '${dir.path}/$canvasId.json'); // 同 id 覆寫——重複刪不堆疊
    await f.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    debugPrint('[ProjectTrashStore] 畫布 $canvasId（${nodes.length} 節點）已進專案回收桶');
  }

  /// 專案回收桶清單（新的在前）
  static Future<List<ProjectTrashSnapshot>> listAll() async {
    final dir = await _trashDir();
    final out = <ProjectTrashSnapshot>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        out.add(ProjectTrashSnapshot.fromJson(
            jsonDecode(await e.readAsString()) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return out;
  }

  /// 還原畫布。回傳還原的節點數（-1 = 找不到快照）。
  /// 交談與門的還原由呼叫端負責（ConversationStore.restore / doorStore.save）。
  static Future<int> restoreNodes(String canvasId,
      {required Future<void> Function(String entityId, Map<String, dynamic> propsJson)
          writeNode}) async {
    final dir = await _trashDir();
    final f = File('${dir.path}/$canvasId.json');
    if (!await f.exists()) return -1;
    final snap = ProjectTrashSnapshot.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    for (final node in snap.nodes) {
      final entityId = node.remove('_entityId') as String;
      node.remove('_entityType'); // Entity 是投影視圖——底層物件還原由門/對話帶回
      await writeNode(entityId, node);
    }
    return snap.nodes.length;
  }

  /// 取得快照（還原 metadata 用）
  static Future<ProjectTrashSnapshot?> getSnapshot(String canvasId) async {
    final dir = await _trashDir();
    final f = File('${dir.path}/$canvasId.json');
    if (!await f.exists()) return null;
    try {
      return ProjectTrashSnapshot.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 永久刪除（UI 需先警示「刪除後無法恢復」）
  static Future<bool> purge(String canvasId) async {
    final dir = await _trashDir();
    final f = File('${dir.path}/$canvasId.json');
    if (!await f.exists()) return false;
    await f.delete();
    debugPrint('[ProjectTrashStore] 畫布 $canvasId 已從專案回收桶永久刪除');
    return true;
  }
}
