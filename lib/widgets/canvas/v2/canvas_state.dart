// canvas_state.dart
// 畫布不可變狀態 — 所有畫布狀態的單一真相來源。
// 建立日期: 2026-07-15
// 參考: fldraw CanvasState + graph_edit GraphCanvasController
//
// 設計: 不可變 state + CanvasController 發射 action → 產生新 state → UI 重渲染。

import 'package:flutter/material.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'node_connection.dart';

/// 畫布工具
enum CanvasTool2 { select, connect, doodle, pan, addNode }

/// 連線拖曳中的狀態
class ConnectionDragState {
  /// 拖曳起點的節點 ID
  final String fromNodeId;

  /// 拖曳起點的 port ID
  final String fromPortId;

  /// 是否從 output port 拖出（true = 從 output 拖向 input）
  final bool fromOutput;

  /// 拖曳起點的世界座標
  final Offset fromWorldPos;

  /// 目前游標的世界座標（用於繪製預覽曲線）
  final Offset currentWorldPos;

  /// [教練 Agent 2026-08-15 Phase 2.5-C] 抓住的現有連線 ID（從已連接 input port 拖出時）。
  /// 放開無目標 → 斷線；接到新目標 → 搬線。
  final String? detachedConnectionId;

  const ConnectionDragState({
    required this.fromNodeId,
    required this.fromPortId,
    required this.fromOutput,
    required this.fromWorldPos,
    required this.currentWorldPos,
    this.detachedConnectionId,
  });

  ConnectionDragState copyWith({Offset? currentWorldPos}) {
    return ConnectionDragState(
      fromNodeId: fromNodeId,
      fromPortId: fromPortId,
      fromOutput: fromOutput,
      fromWorldPos: fromWorldPos,
      currentWorldPos: currentWorldPos ?? this.currentWorldPos,
      detachedConnectionId: detachedConnectionId,
    );
  }
}

/// 畫布 viewport（平移 + 縮放）
class CanvasViewport {
  final Offset offset;
  final double scale;

  const CanvasViewport({
    this.offset = Offset.zero,
    this.scale = 1.0,
  });

  /// 縮放範圍
  static const double minScale = 0.2;
  static const double maxScale = 3.0;

  CanvasViewport copyWith({Offset? offset, double? scale}) {
    return CanvasViewport(
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
    );
  }

  /// 螢幕座標 → 世界座標
  Offset screenToWorld(Offset screen) {
    return (screen - offset) / scale;
  }

  /// 世界座標 → 螢幕座標
  Offset worldToScreen(Offset world) {
    return world * scale + offset;
  }

  @override
  String toString() => 'CanvasViewport(offset: $offset, scale: ${scale.toStringAsFixed(2)})';
}

/// 畫布不可變狀態
class CanvasState {
  /// 所有節點（id → OpenCanvasNode）
  final Map<String, OpenCanvasNode> nodes;

  /// 所有連線
  final List<NodeConnection> connections;

  /// Viewport（平移 + 縮放）
  final CanvasViewport viewport;

  /// 選中的節點 ID
  final Set<String> selectedNodeIds;

  /// 正在編輯參數的節點 ID（右側面板）
  final String? editingNodeId;

  /// 當前工具
  final CanvasTool2 activeTool;

  /// 連線拖曳狀態（null = 沒在拖連線）
  final ConnectionDragState? dragState;

  const CanvasState({
    this.nodes = const {},
    this.connections = const [],
    this.viewport = const CanvasViewport(),
    this.selectedNodeIds = const {},
    this.editingNodeId,
    this.activeTool = CanvasTool2.select,
    this.dragState,
  });

  CanvasState copyWith({
    Map<String, OpenCanvasNode>? nodes,
    List<NodeConnection>? connections,
    CanvasViewport? viewport,
    Set<String>? selectedNodeIds,
    String? editingNodeId,
    CanvasTool2? activeTool,
    ConnectionDragState? dragState,
    bool clearEditingNode = false,
    bool clearDragState = false,
  }) {
    return CanvasState(
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      viewport: viewport ?? this.viewport,
      selectedNodeIds: selectedNodeIds ?? this.selectedNodeIds,
      editingNodeId: clearEditingNode ? null : (editingNodeId ?? this.editingNodeId),
      activeTool: activeTool ?? this.activeTool,
      dragState: clearDragState ? null : (dragState ?? this.dragState),
    );
  }

  /// 是否只有一個節點被選中
  bool get isSingleSelection => selectedNodeIds.length == 1;

  /// 取得唯一選中的節點
  OpenCanvasNode? get singleSelectedNode {
    if (!isSingleSelection) return null;
    return nodes[selectedNodeIds.first];
  }

  /// 取得指定節點的所有連入連線
  List<NodeConnection> incomingConnections(String nodeId) {
    return connections.where((c) => c.toNodeId == nodeId).toList();
  }

  /// 取得指定節點的所有連出連線
  List<NodeConnection> outgoingConnections(String nodeId) {
    return connections.where((c) => c.fromNodeId == nodeId).toList();
  }

  /// 取得指定 port 的連線
  List<NodeConnection> connectionsForPort(String nodeId, String portId) {
    return connections
        .where((c) => c.involvesPort(nodeId, portId))
        .toList();
  }

  /// 檢查兩個 port 之間是否已有連線
  bool hasConnection(String fromNodeId, String fromPortId, String toNodeId, String toPortId) {
    return connections.any((c) =>
        c.fromNodeId == fromNodeId &&
        c.fromPortId == fromPortId &&
        c.toNodeId == toNodeId &&
        c.toPortId == toPortId);
  }

  /// 檢查 input port 是否已被佔用（input 只能有一條連線）
  bool isInputPortOccupied(String nodeId, String portId) {
    return connections.any((c) => c.toNodeId == nodeId && c.toPortId == portId);
  }

  @override
  String toString() =>
      'CanvasState(nodes: ${nodes.length}, connections: ${connections.length}, '
      'selected: ${selectedNodeIds.length}, tool: ${activeTool.name})';
}
