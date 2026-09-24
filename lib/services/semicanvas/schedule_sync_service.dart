// schedule_sync_service.dart
// P3: App 端排程同步服務
// 把畫布上的 schedule 節點同步到 schedule_jobs.json，讓 daemon 讀取觸發
//
// 設計: 跟 Hermes cron/jobs.json 同模式 — App 寫入定義，daemon 讀取執行
// 同步時機: 節點增刪改時呼叫 sync()，或定時 30 秒同步一次

import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/widgets/canvas/v2/node_connection.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 排程同步服務 — 把畫布 schedule 節點寫入 schedule_jobs.json
class ScheduleSyncService {
  final EntityGraphService entityGraph;

  /// 排程定義檔路徑（跟 daemon 的 DaemonConfig.defaultConfig() 對齊）
  String? _jobsPath;
  String? _triggersPath;

  /// [教練 Agent 2026-07-27] 上次同步的 JSON 內容 — 避免重複寫入相同內容
  String? _lastSyncedJson;

  ScheduleSyncService({required this.entityGraph});

  /// 取得 schedule_jobs.json 路徑
  Future<String> get jobsPath async {
    if (_jobsPath != null) return _jobsPath!;
    final dir = await getApplicationSupportDirectory();
    _jobsPath = '${dir.path}/schedule_jobs.json';
    return _jobsPath!;
  }

  /// 取得 schedule_triggers.jsonl 路徑（daemon 寫入，App 讀取）
  Future<String> get triggersPath async {
    if (_triggersPath != null) return _triggersPath!;
    final dir = await getApplicationSupportDirectory();
    _triggersPath = '${dir.path}/schedule_triggers.jsonl';
    return _triggersPath!;
  }

  /// 同步所有畫布的 schedule 節點到 schedule_jobs.json
  ///
  /// [canvasNodes] 和 [canvasConnections] 來自 CanvasController，
  /// 用來打包 schedule 節點的下游 DAG 定義給 daemon 執行。
  Future<int> sync({
    Map<String, dynamic>? canvasNodes,
    List<NodeConnection>? canvasConnections,
  }) async {
    try {
      final entries = await entityGraph.getCanvasNodes();
      final jobs = <Map<String, dynamic>>[];

      for (final entry in entries) {
        if (entry.props.nodeType != WorkflowNodeType.schedule) continue;

        final job = <String, dynamic>{
          'id': entry.entity.id,
          'title': entry.entity.title,
          'canvasId': entry.props.canvasId ?? 'default',
          'params': entry.props.params,
        };

        // 打包下游 DAG 節點和邊
        if (canvasNodes != null && canvasConnections != null) {
          final dag = _extractDag(entry.entity.id, canvasNodes, canvasConnections);
          if (dag['nodes'].isNotEmpty) {
            job['dagNodes'] = dag['nodes'];
            job['dagEdges'] = dag['edges'];
          }
        }

        jobs.add(job);
      }

      final path = await jobsPath;
      final data = jsonEncode({'jobs': jobs});

      // [教練 Agent 2026-07-27] 避免重複寫入相同內容
      if (_lastSyncedJson == data) {
        return jobs.length; // 內容沒變，跳過寫入
      }
      _lastSyncedJson = data;

      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(data);

      debugPrint('[ScheduleSync] 同步 ${jobs.length} 個排程到 $path');
      return jobs.length;
    } catch (e, stack) {
      debugPrint('[ScheduleSync] 同步失敗: $e\n$stack');
      return -1;
    }
  }

  /// 從畫布節點中提取 schedule 節點的下游 DAG
  Map<String, dynamic> _extractDag(
    String scheduleNodeId,
    Map<String, dynamic> canvasNodes,
    List<NodeConnection> canvasConnections,
  ) {
    // BFS 從 schedule 節點出發，收集所有下游節點
    final visited = <String>{};
    final queue = <String>[scheduleNodeId];
    final dagNodes = <Map<String, dynamic>>[];
    final dagEdges = <Map<String, dynamic>>[];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      // 找到此節點的資料
      final node = canvasNodes[currentId];
      if (node == null) continue;

      // 收集節點定義（排除 schedule 節點本身，它只是觸發器）
      if (currentId != scheduleNodeId) {
        dagNodes.add(_nodeToJson(currentId, node));
      }

      // 找下游連線
      for (final conn in canvasConnections) {
        if (conn.fromNodeId == currentId && !visited.contains(conn.toNodeId)) {
          dagEdges.add({'from': conn.fromNodeId, 'to': conn.toNodeId});
          queue.add(conn.toNodeId);
        }
      }
    }

    return {'nodes': dagNodes, 'edges': dagEdges};
  }

  /// 把畫布節點轉成 daemon 可執行的 JSON 定義
  Map<String, dynamic> _nodeToJson(String nodeId, dynamic node) {
    // [小葵 2026-09-18 技術債修復] 病根：node 是 OpenCanvasNode，
    // 它沒有 props 成員（舊代碼 node.props 在 dynamic 下丟 NoSuchMethodError
    // 被靜默 catch 吞掉 → 永遠 fallback 成 input/{}，dagNodes 空殼兩個月）。
    // 正確路徑：OpenCanvasNode.entity.canvasProps（CanvasProps 內含 nodeType+params）。
    Map<String, dynamic> params = {};
    String type = 'input';

    try {
      final entity = node.entity as dynamic;
      final props = entity.canvasProps as CanvasProps?;
      if (props != null) {
        params = Map<String, dynamic>.from(props.params);
        final nt = props.nodeType;
        if (nt != null) {
          type = nt.name; // WorkflowNodeType enum name
        } else {
          debugPrint(
              '[ScheduleSync] ⚠️ 節點 $nodeId 無 nodeType（非工作流節點），序列化為 input');
        }
      } else {
        // [教訓] 模型不匹配必須大聲失敗，不能靜默空殼
        debugPrint(
            '[ScheduleSync] ❌ 節點 $nodeId 缺 canvasProps——無法序列化進 dagNodes！');
      }
    } catch (e) {
      debugPrint('[ScheduleSync] ❌ 節點 $nodeId 序列化失敗: $e');
    }

    return {
      'id': nodeId,
      'type': type,
      'params': params,
    };
  }

  /// 讀取 daemon 寫入的觸發紀錄（給 UI 顯示用）
  Future<List<Map<String, dynamic>>> readTriggers({int limit = 50}) async {
    try {
      final path = await triggersPath;
      final file = File(path);
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      final triggers = <Map<String, dynamic>>[];

      // 從最後面往前讀（最新的在檔案尾部）
      for (int i = lines.length - 1; i >= 0 && triggers.length < limit; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          triggers.add(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {
          // 跳過無效行
        }
      }

      return triggers;
    } catch (e) {
      debugPrint('[ScheduleSync] 讀取觸發紀錄失敗: $e');
      return [];
    }
  }

  /// 清除觸發紀錄
  Future<void> clearTriggers() async {
    try {
      final path = await triggersPath;
      final file = File(path);
      if (await file.exists()) {
        await file.writeAsString('');
      }
    } catch (e) {
      debugPrint('[ScheduleSync] 清除觸發紀錄失敗: $e');
    }
  }
}
