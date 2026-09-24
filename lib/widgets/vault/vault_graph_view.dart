// vault_graph_view.dart
// 力導向圖譜 — Graph View
// [教練 Agent 2026-07-22] Phase 2 ⑥
//
// 使用簡化版 Fruchterman-Reingold 力導向佈局：
// - 斥力：所有節點互相排斥
// - 引力：有邊的節點互相吸引
// - 中心引力：將節點拉向畫布中心
// - 每幀迭代收斂，最終穩定
//
// 支援：拖曳節點、點擊選取、縮放、平移

import 'dart:math' as math;

import 'package:bridge_app/services/vault/vault_service.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';

class VaultGraphView extends StatefulWidget {
  final void Function(VaultGraphNode node)? onNodeTap;

  const VaultGraphView({super.key, this.onNodeTap});

  @override
  State<VaultGraphView> createState() => _VaultGraphViewState();
}

class _VaultGraphViewState extends State<VaultGraphView>
    with SingleTickerProviderStateMixin {
  VaultGraphData? _graphData;
  bool _isLoading = true;

  // 佈局
  final Map<String, Offset> _positions = {};
  final Map<String, Offset> _velocities = {};
  final Map<String, double> _nodeRadius = {};

  // 互動
  Offset _panOffset = Offset.zero;
  double _zoom = 1.0;
  String? _draggingNodeId;
  Offset? _lastPanPosition;
  String? _hoveredNodeId;

  // 動畫
  late final Ticker _ticker;
  int _iteration = 0;
  static const int _maxIterations = 300;
  double _temperature = 1.0;

  // 畫布尺寸
  Size _canvasSize = const Size(800, 600);

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _loadGraphData();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadGraphData() async {
    final data = await VaultService.instance.getGraphData(maxNodes: 150);

    if (!mounted) return;

    setState(() {
      _graphData = data;
      _isLoading = false;
    });

    if (!data.isEmpty) {
      _initLayout();
      _ticker.start();
    }
  }

  void _initLayout() {
    final data = _graphData!;
    final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    final rng = math.Random(42); // 固定種子，可重現

    for (final node in data.nodes) {
      // 初始位置：中心附近隨機分佈
      final angle = rng.nextDouble() * math.pi * 2;
      final dist = 50.0 + rng.nextDouble() * 100;
      _positions[node.id] = center + Offset(
        math.cos(angle) * dist,
        math.sin(angle) * dist,
      );
      _velocities[node.id] = Offset.zero;
      _nodeRadius[node.id] = node.radius;
    }

    _iteration = 0;
    _temperature = 1.0;
  }

  void _onTick(Duration elapsed) {
    if (_graphData == null || _graphData!.isEmpty) return;
    if (_iteration >= _maxIterations) {
      _ticker.stop();
      return;
    }

    _runForceIteration();
    _iteration++;
    _temperature *= 0.98; // 降溫

    if (mounted) setState(() {});
  }

  void _runForceIteration() {
    final data = _graphData!;
    final nodes = data.nodes;
    final k = math.sqrt(
        (_canvasSize.width * _canvasSize.height) / math.max(nodes.length, 1));
    final k2 = k * k;
    final temp = _temperature * 50;

    // 重置力
    final forces = <String, Offset>{};
    for (final node in nodes) {
      forces[node.id] = Offset.zero;
    }

    // 1. 斥力（所有節點對）
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final p1 = _positions[nodes[i].id]!;
        final p2 = _positions[nodes[j].id]!;
        var delta = p1 - p2;
        final dist = delta.distance;
        if (dist < 0.1) {
          // 太近，加隨機推力避免重疊
          delta = Offset(
            (math.Random().nextDouble() - 0.5) * 2,
            (math.Random().nextDouble() - 0.5) * 2,
          );
        }
        final force = k2 / dist;
        final unit = delta / dist;
        forces[nodes[i].id] = forces[nodes[i].id]! + unit * force;
        forces[nodes[j].id] = forces[nodes[j].id]! - unit * force;
      }
    }

    // 2. 引力（有邊的節點對）
    final adjacency = <String, Set<String>>{};
    for (final edge in data.edges) {
      adjacency.putIfAbsent(edge.source, () => {}).add(edge.target);
      adjacency.putIfAbsent(edge.target, () => {}).add(edge.source);
    }

    for (final entry in adjacency.entries) {
      final sourceId = entry.key;
      for (final targetId in entry.value) {
        if (sourceId.compareTo(targetId) >= 0) continue; // 避免重複
        final p1 = _positions[sourceId];
        final p2 = _positions[targetId];
        if (p1 == null || p2 == null) continue;

        var delta = p2 - p1;
        final dist = delta.distance;
        if (dist < 0.1) continue;
        final force = dist * dist / k;
        final unit = delta / dist;
        forces[sourceId] = forces[sourceId]! + unit * force;
        forces[targetId] = forces[targetId]! - unit * force;
      }
    }

    // 3. 中心引力（防止發散）
    final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    for (final node in nodes) {
      final pos = _positions[node.id]!;
      final toCenter = center - pos;
      final dist = toCenter.distance;
      if (dist > 1) {
        forces[node.id] = forces[node.id]! + (toCenter / dist) * (dist * 0.01);
      }
    }

    // 4. 更新位置
    for (final node in nodes) {
      if (_draggingNodeId == node.id) continue; // 拖曳中不更新

      var force = forces[node.id]!;
      final forceMag = force.distance;
      if (forceMag > 0.1) {
        force = (force / forceMag) * math.min(forceMag, temp);
        _positions[node.id] = _positions[node.id]! + force;

        // 邊界限制
        final pos = _positions[node.id]!;
        _positions[node.id] = Offset(
          pos.dx.clamp(30.0, _canvasSize.width - 30),
          pos.dy.clamp(30.0, _canvasSize.height - 30),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: BridgeDSColors.of(context).accentPurple,
        ),
      );
    }

    final data = _graphData;
    if (data == null || data.isEmpty) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: MouseRegion(
            onHover: _onHover,
            child: CustomPaint(
              painter: _GraphPainter(
                data: data,
                positions: _positions,
                nodeRadius: _nodeRadius,
                panOffset: _panOffset,
                zoom: _zoom,
                hoveredNodeId: _hoveredNodeId,
                draggingNodeId: _draggingNodeId,
                colors: _GraphColors.fromContext(context),
              ),
              child: Container(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_outlined,
              size: 64, color: BridgeDSColors.of(context).textMuted),
          const SizedBox(height: 16),
          Text(
            '圖譜是空的',
            style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
          ),
          const SizedBox(height: 8),
          Text(
            '當條目之間有 wiki-link 或共同標籤時\n會自動形成圖譜',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
        ],
      ),
    );
  }

  // ── 手勢處理 ──────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    final pos = _screenToWorld(details.localFocalPoint);
    final nodeId = _hitTest(pos);
    if (nodeId != null) {
      _draggingNodeId = nodeId;
      if (!_ticker.isActive) {
        _iteration = _maxIterations - 50;
        _temperature = 0.3;
        _ticker.start();
      }
    } else {
      _lastPanPosition = details.focalPoint;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      if (_draggingNodeId != null) {
        _positions[_draggingNodeId!] = _positions[_draggingNodeId]! + details.focalPointDelta;
      } else {
        _zoom = (_zoom * details.scale).clamp(0.3, 3.0);
        _panOffset += details.focalPointDelta;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_draggingNodeId != null) {
      _draggingNodeId = null;
      _iteration = _maxIterations - 30;
      _temperature = 0.2;
      if (!_ticker.isActive) _ticker.start();
    }
    _lastPanPosition = null;
  }

  void _onHover(PointerEvent event) {
    final pos = _screenToWorld(event.localPosition);
    final nodeId = _hitTest(pos);
    if (nodeId != _hoveredNodeId) {
      setState(() => _hoveredNodeId = nodeId);
    }
  }

  Offset _screenToWorld(Offset screenPos) {
    return (screenPos - _panOffset) / _zoom;
  }

  String? _hitTest(Offset worldPos) {
    if (_graphData == null) return null;
    for (final node in _graphData!.nodes) {
      final pos = _positions[node.id];
      if (pos == null) continue;
      final r = _nodeRadius[node.id] ?? 15;
      if ((worldPos - pos).distance <= r + 4) {
        return node.id;
      }
    }
    return null;
  }
}

// ── CustomPainter ────────────────────────────────────────────────

class _GraphColors {
  final Color edge;
  final Color edgeLabel;
  final Color textPrimary;
  final Color textOnNode;
  final Color background;

  _GraphColors({
    required this.edge,
    required this.edgeLabel,
    required this.textPrimary,
    required this.textOnNode,
    required this.background,
  });

  factory _GraphColors.fromContext(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return _GraphColors(
      edge: ds.borderSubtle,
      edgeLabel: ds.textMuted,
      textPrimary: ds.textPrimary,
      textOnNode: ds.surface,
      background: ds.canvas,
    );
  }
}

class _GraphPainter extends CustomPainter {
  final VaultGraphData data;
  final Map<String, Offset> positions;
  final Map<String, double> nodeRadius;
  final Offset panOffset;
  final double zoom;
  final String? hoveredNodeId;
  final String? draggingNodeId;
  final _GraphColors colors;

  _GraphPainter({
    required this.data,
    required this.positions,
    required this.nodeRadius,
    required this.panOffset,
    required this.zoom,
    required this.hoveredNodeId,
    required this.draggingNodeId,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(zoom);

    // 背景網格（淡）
    _drawGrid(canvas, size);

    // 畫邊
    for (final edge in data.edges) {
      final p1 = positions[edge.source];
      final p2 = positions[edge.target];
      if (p1 == null || p2 == null) continue;

      final paint = Paint()
        ..color = colors.edge.withValues(alpha: 0.4)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      // 貝茲曲線連線
      final midX = (p1.dx + p2.dx) / 2;
      final midY = (p1.dy + p2.dy) / 2;
      final cp = Offset(midX + (p2.dy - p1.dy) * 0.1, midY - (p2.dx - p1.dx) * 0.1);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);

      // 邊標籤（hover 時顯示）
      if (hoveredNodeId == edge.source || hoveredNodeId == edge.target) {
        final labelSpan = TextSpan(
          text: edge.label,
          style: TextStyle(color: colors.edgeLabel, fontSize: 14),
        );
        final labelPainter = TextPainter(
          text: labelSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(canvas, Offset(midX - labelPainter.width / 2, midY - 6));
      }
    }

    // 畫節點
    for (final node in data.nodes) {
      final pos = positions[node.id];
      if (pos == null) continue;
      final r = nodeRadius[node.id] ?? 15;
      final isHovered = hoveredNodeId == node.id;
      final isDragging = draggingNodeId == node.id;

      // 外光暈（hover / drag）
      if (isHovered || isDragging) {
        final glowPaint = Paint()
          ..color = node.color.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, r + 8, glowPaint);
      }

      // 節點圓
      final nodePaint = Paint()
        ..color = node.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, r, nodePaint);

      // 外圈
      final ringPaint = Paint()
        ..color = colors.textOnNode.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(pos, r, ringPaint);

      // 標籤
      final labelSpan = TextSpan(
        text: node.label,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: isHovered ? 12 : 10,
          fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 80);

      labelPainter.paint(
        canvas,
        Offset(
          pos.dx - labelPainter.width / 2,
          pos.dy + r + 4,
        ),
      );
    }

    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridSize = 40.0 * zoom;
    final paint = Paint()
      ..color = colors.edge.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    final startX = (panOffset.dx % gridSize);
    final startY = (panOffset.dy % gridSize);

    for (var x = startX; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = startY; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return true; // 動畫期間持續重繪
  }
}
