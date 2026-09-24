// [Sprint 18c-2 — 專案關聯圖]
// ProjectRelationGraph：門與門、門與資產、門與記憶的關聯視覺化。
// 使用 CustomPainter 自繪，輕量級，不依賴 Canvas 系統的 Memory 綁定。
//
// 節點類型：門(藍) / 資產(綠) / 記憶(紫) / 分岔門(洋紅)
// 邊類型：分岔(實線紫) / 資產引用(實線綠) / 記憶連結(虛線藍)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/digital_asset.dart';
import '../../models/project_door.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 關聯圖節點
class RelationNode {
  final String id;
  final String label;
  final RelationNodeType type;
  final Offset position;

  const RelationNode({
    required this.id,
    required this.label,
    required this.type,
    required this.position,
  });
}

enum RelationNodeType {
  door, // 門 — 藍
  childDoor, // 分岔門 — 洋紅
  asset, // 資產 — 綠
  memory, // 記憶 — 紫
}

/// 關聯圖邊
class RelationEdge {
  final String id;
  final String fromId;
  final String toId;
  final RelationEdgeType type;

  const RelationEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.type,
  });
}

enum RelationEdgeType {
  fork, // 分岔
  assetLink, // 資產引用
  memoryLink, // 記憶連結
}

class ProjectRelationGraph extends StatefulWidget {
  final ProjectDoor centerDoor;
  final List<ProjectDoor> childDoors;
  final List<DigitalAsset> linkedAssets;
  final List<String> linkedMemoryIds;
  final double height;

  const ProjectRelationGraph({
    super.key,
    required this.centerDoor,
    this.childDoors = const [],
    this.linkedAssets = const [],
    this.linkedMemoryIds = const [],
    this.height = 320,
  });

  @override
  State<ProjectRelationGraph> createState() => _ProjectRelationGraphState();
}

class _ProjectRelationGraphState extends State<ProjectRelationGraph>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late List<RelationNode> _nodes;
  late List<RelationEdge> _edges;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: BridgeDS.durationCanvas,
    )..forward();
    _buildGraph();
  }

  @override
  void didUpdateWidget(ProjectRelationGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerDoor.id != widget.centerDoor.id ||
        oldWidget.childDoors.length != widget.childDoors.length ||
        oldWidget.linkedAssets.length != widget.linkedAssets.length) {
      _buildGraph();
    }
  }

  void _buildGraph() {
    _nodes = [];
    _edges = [];

    // 中心節點 — 當前門
    _nodes.add(RelationNode(
      id: widget.centerDoor.id,
      label: widget.centerDoor.title,
      type: RelationNodeType.door,
      position: Offset.zero,
    ));

    // 分岔子門 — 右側弧線排列
    for (var i = 0; i < widget.childDoors.length; i++) {
      final angle = -0.6 + (i * 0.4); // 從右上往右下散開
      final radius = 120.0;
      final pos = Offset(
        radius * 1.5,
        radius * angle,
      );
      final child = widget.childDoors[i];
      _nodes.add(RelationNode(
        id: child.id,
        label: child.title,
        type: RelationNodeType.childDoor,
        position: pos,
      ));
      _edges.add(RelationEdge(
        id: 'fork-${child.id}',
        fromId: widget.centerDoor.id,
        toId: child.id,
        type: RelationEdgeType.fork,
      ));
    }

    // 資產 — 左側排列
    for (var i = 0; i < widget.linkedAssets.length; i++) {
      final angle = -0.5 + (i * 0.35);
      final radius = 110.0;
      final pos = Offset(
        -radius * 1.4,
        radius * angle,
      );
      final asset = widget.linkedAssets[i];
      _nodes.add(RelationNode(
        id: asset.id,
        label: asset.title,
        type: RelationNodeType.asset,
        position: pos,
      ));
      _edges.add(RelationEdge(
        id: 'asset-${asset.id}',
        fromId: widget.centerDoor.id,
        toId: asset.id,
        type: RelationEdgeType.assetLink,
      ));
    }

    // 記憶 — 上方排列
    for (var i = 0; i < widget.linkedMemoryIds.length; i++) {
      final offset = (i - widget.linkedMemoryIds.length / 2) * 80;
      final pos = Offset(offset, -130);
      final memId = widget.linkedMemoryIds[i];
      _nodes.add(RelationNode(
        id: memId,
        label: memId.length > 20 ? '${memId.substring(0, 18)}...' : memId,
        type: RelationNodeType.memory,
        position: pos,
      ));
      _edges.add(RelationEdge(
        id: 'mem-$memId',
        fromId: widget.centerDoor.id,
        toId: memId,
        type: RelationEdgeType.memoryLink,
      ));
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: widget.height,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題 + 圖例 ──
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 18, color: BridgeDSColors.of(context).accentMiro),
              SizedBox(width: 8),
              Text('專案關聯圖',
                  style: BridgeDSColors.of(context).headingS.copyWith(fontSize: 16)),
              Spacer(),
              _LegendItem(
                  color: BridgeDSColors.of(context).accentBlue, label: '門', icon: Icons.door_sliding_outlined),
              SizedBox(width: 8),
              _LegendItem(
                  color: BridgeDSColors.of(context).accentMagenta, label: '分岔', icon: Icons.call_split_rounded),
              SizedBox(width: 8),
              _LegendItem(
                  color: BridgeDSColors.of(context).accentGreen, label: '資產', icon: Icons.category_outlined),
              SizedBox(width: 8),
              _LegendItem(
                  color: BridgeDSColors.of(context).accentPurple, label: '記憶', icon: Icons.psychology_outlined),
            ],
          ),
          const SizedBox(height: 8),
          // ── 圖形區 ──
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _GraphPainter(
                      nodes: _nodes,
                      edges: _edges,
                      progress: _anim.value,
                      colors: BridgeDSColors.of(context),
                    ),
                    child: Container(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CustomPainter
// ═══════════════════════════════════════════════════════

class _GraphPainter extends CustomPainter {
  final List<RelationNode> nodes;
  final List<RelationEdge> edges;
  final double progress;
  final BridgeDSColors colors;

  const _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.progress,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 先畫邊
    for (final edge in edges) {
      final from = _nodePosition(edge.fromId, center);
      final to = _nodePosition(edge.toId, center);
      if (from == null || to == null) continue;

      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _edgeColor(edge.type).withValues(alpha: 0.5 * progress);

      if (edge.type == RelationEdgeType.memoryLink) {
        // 虛線
        edgePaint.strokeCap = StrokeCap.round;
        _drawDashedLine(canvas, from, to, edgePaint);
      } else {
        // 貝茲曲線
        final midX = (from.dx + to.dx) / 2;
        final control = Offset(midX, from.dy);
        canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy),
          edgePaint,
        );
      }
    }

    // 再畫節點
    for (final node in nodes) {
      final pos = _nodePosition(node.id, center);
      if (pos == null) continue;

      final nodeColor = _nodeColor(node.type);
      final nodeRadius = node.type == RelationNodeType.door ? 22.0 : 16.0;
      final animRadius = nodeRadius * progress;

      // 光暈
      canvas.drawCircle(
        pos,
        animRadius + 6,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.10 * progress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // 節點圓
      canvas.drawCircle(
        pos,
        animRadius,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.20)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pos,
        animRadius,
        Paint()
          ..color = nodeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // 標籤
      final labelPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            color: BridgeDSColors.dark.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      labelPainter.layout(maxWidth: 100);
      labelPainter.paint(
        canvas,
        pos + Offset(-labelPainter.width / 2, animRadius + 4),
      );

      // 節點圖示 (用文字代替)
      final iconPainter = TextPainter(
        text: TextSpan(
          text: _nodeIcon(node.type),
          style: const TextStyle(fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        pos + Offset(-iconPainter.width / 2, -iconPainter.height / 2),
      );
    }
  }

  Offset? _nodePosition(String id, Offset center) {
    final node = nodes.where((n) => n.id == id).firstOrNull;
    if (node == null) return null;
    return center + node.position * progress;
  }

  Color _nodeColor(RelationNodeType type) {
    return switch (type) {
      RelationNodeType.door => colors.accentBlue,
      RelationNodeType.childDoor => colors.accentMagenta,
      RelationNodeType.asset => colors.accentGreen,
      RelationNodeType.memory => colors.accentPurple,
    };
  }

  Color _edgeColor(RelationEdgeType type) {
    return switch (type) {
      RelationEdgeType.fork => colors.accentMagenta,
      RelationEdgeType.assetLink => colors.accentGreen,
      RelationEdgeType.memoryLink => colors.accentPurple,
    };
  }

  String _nodeIcon(RelationNodeType type) {
    return switch (type) {
      RelationNodeType.door => '🚪',
      RelationNodeType.childDoor => '🌿',
      RelationNodeType.asset => '📦',
      RelationNodeType.memory => '🧠',
    };
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashWidth = 4.0;
    const dashGap = 3.0;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final distance = (dx * dx + dy * dy);
    if (distance == 0) return;
    final dist = distance.toDouble();
    final sqrtDist = math.sqrt(dist);
    final dashCount = (sqrtDist / (dashWidth + dashGap)).floor();
    final unitDx = dx / sqrtDist;
    final unitDy = dy / sqrtDist;

    for (var i = 0; i < dashCount; i++) {
      final start = Offset(
        from.dx + unitDx * (dashWidth + dashGap) * i,
        from.dy + unitDy * (dashWidth + dashGap) * i,
      );
      final end = Offset(
        start.dx + unitDx * dashWidth,
        start.dy + unitDy * dashWidth,
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.nodes.length != nodes.length;
}

// ═══════════════════════════════════════════════════════
// Legend item
// ═══════════════════════════════════════════════════════

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;
  const _LegendItem({
    required this.color,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: color)),
      ],
    );
  }
}
