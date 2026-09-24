// canvas_minimap.dart
// SemiCanvas 視覺 P4: 迷你地圖
// 右下角顯示整個畫布的節點分布 + 當前 viewport 框
// 可點擊跳轉 viewport

import 'package:flutter/material.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import '../../theme/bridge_design_system.dart';

/// 迷你地圖 widget。
///
/// 顯示所有節點的縮略位置 + 當前 viewport 框。
class CanvasMinimap extends StatelessWidget {
  final List<OpenCanvasNode> nodes;
  final Offset viewportOffset;
  final double viewportScale;
  final Size canvasSize;
  final void Function(Offset worldPos)? onTap;

  CanvasMinimap({
    super.key,
    required this.nodes,
    required this.viewportOffset,
    required this.viewportScale,
    required this.canvasSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const minimapWidth = 140.0;
    const minimapHeight = 90.0;

    return Container(
      width: minimapWidth,
      height: minimapHeight,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          onTapDown: (details) {
            if (onTap == null) return;
            // 將 minimap 座標轉為世界座標
            final localPos = details.localPosition;
            final worldX = (localPos.dx / minimapWidth) * canvasSize.width;
            final worldY = (localPos.dy / minimapHeight) * canvasSize.height;
            onTap!(Offset(worldX, worldY));
          },
          child: CustomPaint(
            painter: _MinimapPainter(
              nodes: nodes,
              viewportOffset: viewportOffset,
              viewportScale: viewportScale,
              canvasSize: canvasSize,
              minimapSize: Size(minimapWidth, minimapHeight),
            ),
            size: Size(minimapWidth, minimapHeight),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final List<OpenCanvasNode> nodes;
  final Offset viewportOffset;
  final double viewportScale;
  final Size canvasSize;
  final Size minimapSize;

  _MinimapPainter({
    required this.nodes,
    required this.viewportOffset,
    required this.viewportScale,
    required this.canvasSize,
    required this.minimapSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    // 計算世界座標範圍
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in nodes) {
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > node.position.dx + node.width
          ? maxX
          : node.position.dx + node.width;
      maxY = maxY > node.position.dy + node.height
          ? maxY
          : node.position.dy + node.height;
    }
    // 加邊距
    minX -= 100; minY -= 100;
    maxX += 100; maxY += 100;

    final worldW = maxX - minX;
    final worldH = maxY - minY;
    final scaleX = minimapSize.width / worldW;
    final scaleY = minimapSize.height / worldH;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // 畫節點
    for (final node in nodes) {
      final x = (node.position.dx - minX) * scale;
      final y = (node.position.dy - minY) * scale;
      final w = node.width * scale;
      final h = node.height * scale;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w.clamp(2.0, 20.0), h.clamp(2.0, 20.0)),
          Radius.circular(1),
        ),
        Paint()..color = node.color.withValues(alpha: 0.6),
      );
    }

    // 畫 viewport 框
    final vpWorldX = (-viewportOffset.dx / viewportScale - minX) * scale;
    final vpWorldY = (-viewportOffset.dy / viewportScale - minY) * scale;
    final vpW = (canvasSize.width / viewportScale) * scale;
    final vpH = (canvasSize.height / viewportScale) * scale;

    canvas.drawRect(
      Rect.fromLTWH(vpWorldX, vpWorldY, vpW, vpH),
      Paint()
        ..color = BridgeDS.accentBlue.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(vpWorldX, vpWorldY, vpW, vpH),
      Paint()
        ..color = BridgeDS.accentBlue.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) => true;
}
