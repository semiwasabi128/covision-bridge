// dag_engine.dart
// SemiCanvas Phase 2a: DAG 執行引擎
// 拓撲排序 (Kahn's algorithm) + 並行批次 + 循環偵測
//
// 參考: https://arpitbhayani.me/blogs/ai-topological-sort
// 設計文件: semicanvas-design.md §2.4

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';

/// DAG 執行結果
class DagExecutionResult {
  /// 拓撲排序後的執行層級（同層級可並行）
  final List<List<String>> executionLevels;

  /// 所有節點 ID 的拓撲順序（扁平化）
  final List<String> topologicalOrder;

  /// 偵測到的循環節點（空 = 無循環）
  final List<String> cyclicNodes;

  /// 是否有循環
  bool get hasCycle => cyclicNodes.isNotEmpty;

  /// 節點 ID → 入度（依賴數）
  final Map<String, int> inDegrees;

  const DagExecutionResult({
    required this.executionLevels,
    required this.topologicalOrder,
    required this.cyclicNodes,
    required this.inDegrees,
  });

  @override
  String toString() =>
      'DagExecutionResult(levels: ${executionLevels.length}, '
      'nodes: ${topologicalOrder.length}, '
      'cycle: ${hasCycle ? cyclicNodes.length : 'none'})';
}

/// DAG 執行引擎 — 將畫布上的節點和 depends 關係轉為執行順序。
///
/// 演算法：Kahn's algorithm (BFS-based topological sort)
/// - O(V+E) 時間複雜度
/// - 同層級節點可並行執行
/// - 自動偵測循環依賴
class DagEngine {
  final EntityGraphService entityGraph;

  /// [教練 Agent 2026-08-26 跨畫布洩漏修復] 只分析這個畫布的節點。
  /// null = 不過濾（危險——所有畫布節點混成超級 DAG；
  /// 2026-08-26 28 張幽靈圖片事件根因）。
  final String? canvasId;

  /// [小葵 2026-09-24 修 bug·工作流空轉] 畫布即時連線（state.connections）。
  /// 舊路徑只讀 EntityRelationStore（SharedPreferences）——那是「存檔時」
  /// 才寫入的持久層；畫布上現拉的線只存在 controller state，沒存檔前
  /// relationStore 查不到 → DagEngine 看到 0 條邊 → 12 節點全孤立、
  /// imageGen 無上游順序全亂（Blue 實測：按執行，vision 直通了但
  /// imageGen 紋絲不動、零 API 呼叫）。
  /// 有注入就用即時連線（與 executor/體檢同真相源）；null 才 fallback
  /// 舊路徑（排程引擎等離線情境）。
  final List<(String fromId, String toId)>? liveEdges;

  DagEngine({required this.entityGraph, this.canvasId, this.liveEdges});

  /// 分析當前畫布的 DAG 結構。
  ///
  /// 只考慮 RelationType.depends 類型的連線。
  /// 其他類型（relates, references 等）不影響執行順序。
  Future<DagExecutionResult> analyze() async {
    final canvasEntries = await entityGraph.getCanvasNodes(canvasId: canvasId);
    final nodeIds = canvasEntries.map((e) => e.entity.id).toSet();

    if (nodeIds.isEmpty) {
      return const DagExecutionResult(
        executionLevels: [],
        topologicalOrder: [],
        cyclicNodes: [],
        inDegrees: {},
      );
    }

    // 建構鄰接表 + 計算入度
    final adjacency = <String, List<String>>{};
    final inDegrees = <String, int>{};

    for (final id in nodeIds) {
      adjacency[id] = [];
      inDegrees[id] = 0;
    }

    // [小葵 2026-09-24 修 bug·工作流空轉] 邊的來源二選一：
    // liveEdges（畫布即時連線，與 controller state 同真相源）優先；
    // 沒注入才走舊路徑（relationStore——只有存檔過的線）。
    if (liveEdges != null) {
      for (final (fromId, toId) in liveEdges!) {
        if (nodeIds.contains(fromId) && nodeIds.contains(toId)) {
          adjacency[fromId]!.add(toId);
          inDegrees[toId] = (inDegrees[toId] ?? 0) + 1;
        }
      }
    } else
    // 收所有 depends 關係
    for (final id in nodeIds) {
      final relations = await entityGraph.getRelations(id);
      for (final rel in relations) {
        if (rel.type == RelationType.depends &&
            nodeIds.contains(rel.targetId)) {
          // id → targetId (id 是 source, target 依賴 id)
          // 但 depends 的語意是 "target depends on source"
          // 所以 source 必須先完成, target 才能執行
          adjacency[id]!.add(rel.targetId);
          inDegrees[rel.targetId] = (inDegrees[rel.targetId] ?? 0) + 1;
        }
      }
    }

    // Kahn's algorithm
    final queue = <String>[];
    for (final id in nodeIds) {
      if (inDegrees[id] == 0) {
        queue.add(id);
      }
    }

    final topologicalOrder = <String>[];
    final executionLevels = <List<String>>[];

    while (queue.isNotEmpty) {
      // 當前層級的所有節點（入度 = 0）可並行
      final level = List<String>.from(queue);
      executionLevels.add(level);
      queue.clear();

      for (final node in level) {
        topologicalOrder.add(node);
        for (final neighbor in adjacency[node]!) {
          inDegrees[neighbor] = inDegrees[neighbor]! - 1;
          if (inDegrees[neighbor] == 0) {
            queue.add(neighbor);
          }
        }
      }
    }

    // 循環偵測：如果拓撲排序的節點數 < 總節點數，有循環
    final sortedSet = topologicalOrder.toSet();
    final cyclicNodes = nodeIds.where((id) => !sortedSet.contains(id)).toList();

    return DagExecutionResult(
      executionLevels: executionLevels,
      topologicalOrder: topologicalOrder,
      cyclicNodes: cyclicNodes,
      inDegrees: inDegrees,
    );
  }

  /// 驗證工作流是否合法（無循環、有 input、有 output）。
  ///
  /// 回傳 null = 合法，否則回傳錯誤訊息。
  Future<String?> validate() async {
    final result = await analyze();

    if (result.hasCycle) {
      return '工作流存在循環依賴，涉及節點: ${result.cyclicNodes.join(", ")}';
    }

    if (result.topologicalOrder.isEmpty) {
      return '工作流為空';
    }

    // 檢查是否有 input 節點（入度 = 0 的節點）
    final hasInput = result.executionLevels.isNotEmpty &&
        result.executionLevels.first.isNotEmpty;
    if (!hasInput) {
      return '工作流缺少起點（入度為 0 的節點）';
    }

    // 檢查是否有 output 節點（出度 = 0 的節點）
    final canvasEntries = await entityGraph.getCanvasNodes(canvasId: canvasId);
    final nodeIds = canvasEntries.map((e) => e.entity.id).toSet();
    final hasOutput = result.executionLevels.isNotEmpty &&
        result.executionLevels.last.isNotEmpty;
    if (!hasOutput && nodeIds.isNotEmpty) {
      // 單節點工作流也合法
      if (nodeIds.length == 1) {
        return null;
      }
      return '工作流缺少終點（出度為 0 的節點）';
    }

    return null;
  }

  /// 取得節點的直接上游（它依賴哪些節點）。
  Future<List<String>> getUpstream(String nodeId) async {
    final reverseRelations = await entityGraph.getReverseRelations(nodeId);
    return reverseRelations
        .where((r) => r.type == RelationType.depends)
        .map((r) => r.sourceId)
        .toList();
  }

  /// 取得節點的直接下游（哪些節點依賴它）。
  Future<List<String>> getDownstream(String nodeId) async {
    final relations = await entityGraph.getRelations(nodeId);
    return relations
        .where((r) => r.type == RelationType.depends)
        .map((r) => r.targetId)
        .toList();
  }

  /// 取得受影響的下游子圖（增量重執行用）。
  ///
  /// 從 [startNodeId] 開始，收集所有傳遞依賴的節點。
  Future<List<String>> getAffectedSubgraph(String startNodeId) async {
    final visited = <String>{};
    final queue = [startNodeId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);
      final downstream = await getDownstream(current);
      queue.addAll(downstream);
    }

    return visited.toList();
  }
}
