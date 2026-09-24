// canvas_snapshot.dart
// 人機共視的核心 — 讓原生 Agent（in-app agent）能看到使用者看到的畫布狀態。
// 建立日期: 2026-07-24
//
// 設計理念（參考 CollabBoard + Figma MCP + Honeycomb Canvas）：
// - 不靠截圖，靠結構化 state
// - AI 和人讀同一份 CanvasController.state
// - Perceive → Plan → Execute → Verify 循環
//
// 用法：
//   final snapshot = CanvasController.getSnapshot(canvasPixelSize);
//   // snapshot.overlaps → 哪些節點重疊
//   // snapshot.visibleNodes → 使用者現在看得到哪些節點
//   // snapshot.toReport() → 給原生 Agent的文字報告

import 'package:flutter/material.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'canvas_state.dart';
import 'node_connection.dart';

/// 單一節點在畫布上的完整狀態
class NodeBounds {
  final String id;
  final WorkflowNodeType? nodeType;
  final String title;
  final double x, y;      // 世界座標左上角
  final double width, height;  // 實際渲染尺寸（從 estimatedRenderSize）
  final double right, bottom;  // 右下角 = x+width, y+height
  final bool isVisible;        // 是否在 viewport 可見範圍內
  final bool isFullyVisible;   // 是否完全在可見範圍內

  const NodeBounds({
    required this.id,
    required this.nodeType,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.right,
    required this.bottom,
    required this.isVisible,
    required this.isFullyVisible,
  });

  /// 世界座標 Rect
  Rect get worldRect => Rect.fromLTWH(x, y, width, height);

  /// 螢幕座標 Rect（需傳入 viewport）
  Rect screenRect(CanvasViewport vp) {
    final screenPos = vp.worldToScreen(Offset(x, y));
    return Rect.fromLTWH(screenPos.dx, screenPos.dy, width * vp.scale, height * vp.scale);
  }

  /// 節點類型名稱（中文）
  String get typeName => nodeType != null ? _nodeTypeName(nodeType!) : '未知';

  @override
  String toString() => '$typeName($title) pos=($x,$y) size=(${width}x$height) '
      'visible=$isVisible fullyVisible=$isFullyVisible';
}

/// 一對重疊的節點
class OverlapPair {
  final NodeBounds a;
  final NodeBounds b;
  final double overlapWidth;
  final double overlapHeight;
  final double overlapArea;

  const OverlapPair({
    required this.a,
    required this.b,
    required this.overlapWidth,
    required this.overlapHeight,
    required this.overlapArea,
  });

  String get description =>
      '${a.typeName}(${a.title}) 與 ${b.typeName}(${b.title}) 重疊 '
      '${overlapWidth.toStringAsFixed(0)}x${overlapHeight.toStringAsFixed(0)}px';

  @override
  String toString() => 'OverlapPair: $description';
}

/// 一條連線的資訊
class ConnectionInfo {
  final String id;
  final String fromNodeId;
  final String fromNodeTitle;
  final String fromNodeType;
  final String fromPort;
  final String toNodeId;
  final String toNodeTitle;
  final String toNodeType;
  final String toPort;

  const ConnectionInfo({
    required this.id,
    required this.fromNodeId,
    required this.fromNodeTitle,
    required this.fromNodeType,
    required this.fromPort,
    required this.toNodeId,
    required this.toNodeTitle,
    required this.toNodeType,
    required this.toPort,
  });

  @override
  String toString() => '$fromNodeType($fromNodeTitle).$fromPort → $toNodeType($toNodeTitle).$toPort';
}

/// 畫布的完整快照 — 原生 Agent看到的就是這個
class CanvasSnapshot {
  /// 所有節點的 bounds
  final List<NodeBounds> nodes;

  /// 所有連線
  final List<ConnectionInfo> connections;

  /// 偵測到的重疊
  final List<OverlapPair> overlaps;

  /// Viewport 狀態
  final CanvasViewport viewport;

  /// 畫布像素大小（context.size）
  final Size canvasPixelSize;

  /// 可見範圍（世界座標）
  final Rect visibleRect;

  /// 統計
  final int totalNodes;
  final int visibleNodes;
  final int fullyVisibleNodes;
  final int hiddenNodes;
  final int totalConnections;
  final int overlapCount;

  const CanvasSnapshot({
    required this.nodes,
    required this.connections,
    required this.overlaps,
    required this.viewport,
    required this.canvasPixelSize,
    required this.visibleRect,
    required this.totalNodes,
    required this.visibleNodes,
    required this.fullyVisibleNodes,
    required this.hiddenNodes,
    required this.totalConnections,
    required this.overlapCount,
  });

  /// 生成給原生 Agent看的文字報告
  String toReport() {
    final lines = <String>[];

    // 概況
    lines.add('=== 畫布狀態報告 ===');
    lines.add('節點：$totalNodes 個（可見 $visibleNodes，完全可見 $fullyVisibleNodes，隱藏 $hiddenNodes）');
    lines.add('連線：$totalConnections 條');
    lines.add('Viewport：scale=${viewport.scale.toStringAsFixed(3)}, offset=${viewport.offset}');
    lines.add('可見範圍（世界座標）：${visibleRect.left.toStringAsFixed(0)},${visibleRect.top.toStringAsFixed(0)} → ${visibleRect.right.toStringAsFixed(0)},${visibleRect.bottom.toStringAsFixed(0)}');
    lines.add('畫布像素大小：${canvasPixelSize.width.toStringAsFixed(0)}x${canvasPixelSize.height.toStringAsFixed(0)}');

    // 重疊
    if (overlaps.isEmpty) {
      lines.add('\n重疊：✓ 無重疊');
    } else {
      lines.add('\n重疊：✗ 偵測到 $overlapCount 對重疊');
      for (final o in overlaps) {
        lines.add('  - ${o.description}');
      }
    }

    // 節點清單
    lines.add('\n節點清單：');
    for (final n in nodes) {
      final visIcon = n.isFullyVisible ? '✓' : (n.isVisible ? '~' : '✗');
      lines.add('  [$visIcon] $n');
    }

    // 連線清單
    lines.add('\n連線清單：');
    for (final c in connections) {
      lines.add('  $c');
    }

    // 診斷建議
    lines.add('\n=== 診斷 ===');
    if (overlapCount > 0) {
      lines.add('⚠️ 有節點重疊，建議調整間距或位置');
    }
    if (hiddenNodes > 0) {
      lines.add('⚠️ 有 $hiddenNodes 個節點在畫面外，使用者看不到');
    }
    if (overlapCount == 0 && hiddenNodes == 0) {
      lines.add('✅ 畫布狀態良好，所有節點可見且無重疊');
    }

    return lines.join('\n');
  }

  /// 生成 JSON 格式（給程式用）
  Map<String, dynamic> toJson() {
    return {
      'totalNodes': totalNodes,
      'visibleNodes': visibleNodes,
      'hiddenNodes': hiddenNodes,
      'totalConnections': totalConnections,
      'overlapCount': overlapCount,
      'viewport': {
        'scale': viewport.scale,
        'offset': {'x': viewport.offset.dx, 'y': viewport.offset.dy},
      },
      'visibleRect': {
        'left': visibleRect.left,
        'top': visibleRect.top,
        'right': visibleRect.right,
        'bottom': visibleRect.bottom,
      },
      'canvasPixelSize': {
        'width': canvasPixelSize.width,
        'height': canvasPixelSize.height,
      },
      'nodes': nodes.map((n) => {
        'id': n.id,
        'type': n.nodeType?.name,
        'title': n.title,
        'x': n.x,
        'y': n.y,
        'width': n.width,
        'height': n.height,
        'isVisible': n.isVisible,
        'isFullyVisible': n.isFullyVisible,
      }).toList(),
      'overlaps': overlaps.map((o) => {
        'a': {'type': o.a.nodeType?.name, 'title': o.a.title, 'x': o.a.x, 'y': o.a.y},
        'b': {'type': o.b.nodeType?.name, 'title': o.b.title, 'x': o.b.x, 'y': o.b.y},
        'overlapWidth': o.overlapWidth,
        'overlapHeight': o.overlapHeight,
      }).toList(),
      'connections': connections.map((c) => {
        'from': {'type': c.fromNodeType, 'title': c.fromNodeTitle, 'port': c.fromPort},
        'to': {'type': c.toNodeType, 'title': c.toNodeTitle, 'port': c.toPort},
      }).toList(),
    };
  }
}

// ── 工具函數 ──────────────────────────────────────────

String _nodeTypeName(WorkflowNodeType type) {
  return switch (type) {
    WorkflowNodeType.input => '輸入',
    WorkflowNodeType.llm => 'LLM推論',
    WorkflowNodeType.tool => '工具',
    WorkflowNodeType.imageGen => '圖片生成',
    WorkflowNodeType.vision => '視覺分析',
    WorkflowNodeType.characterLock => '角色鎖定',
    WorkflowNodeType.videoGen => '影片生成',
    WorkflowNodeType.musicGen => '音樂生成',
    WorkflowNodeType.tts => '語音合成',
    WorkflowNodeType.move => '招式', // [Blue 拍板]
    WorkflowNodeType.condition => '條件分支',
    WorkflowNodeType.merge => '合併',
    WorkflowNodeType.output => '輸出',
    WorkflowNodeType.subWorkflow => '子工作流',
    WorkflowNodeType.schedule => '排程',
    WorkflowNodeType.knowledge => 'Vault知識', // [教練 Agent 2026-08-16]
    WorkflowNodeType.materialPool => '素材池', // [教練 Agent 2026-08-25 F-1]
  };
}
