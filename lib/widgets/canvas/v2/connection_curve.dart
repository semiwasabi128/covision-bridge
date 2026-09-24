// connection_curve.dart
// 連線曲線繪製 — 貝茲曲線 + 拖曳中預覽。
// 建立日期: 2026-07-15
// 參考: graph_edit ConnectionCurve + LiteGraph drawConnections

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../theme/bridge_design_system.dart';

/// 繪製連線的貝茲曲線。
class ConnectionCurve {
  final Offset start;
  final Offset end;

  /// 起點方向（output 通常朝右，input 朝左）
  final Offset startDirection;

  /// 終點方向
  final Offset endDirection;

  /// 顏色
  final Color color;

  /// 線寬
  final double strokeWidth;

  /// 是否流動動畫（執行中）
  final bool animated;

  /// 動畫進度（0.0 ~ 1.0，用於 dash offset）
  final double animationProgress;

  /// 是否為虛線（用於類型不匹配警告）
  final bool dashed;

  /// 虛線模式 [dash length, gap length]
  final List<double> dashPattern;

  const ConnectionCurve({
    required this.start,
    required this.end,
    this.startDirection = const Offset(1, 0),
    this.endDirection = const Offset(-1, 0),
    this.color = BridgeDS.brightCyan,
    this.strokeWidth = 2.0,
    this.animated = false,
    this.animationProgress = 0.0,
    this.dashed = false,
    this.dashPattern = const [5, 3],
  });

  /// 計算控制點距離（基於兩點距離）
  /// [教練 Agent 2026-08-15 使用者回饋] 取消最小 80px 限制——節點靠近時
  /// 控制點被強制外推，線折起來看起來很亂。改為彈性下限（12px 防退化成直線）。
  double _controlDistance() {
    final distance = (end - start).distance;
    return (distance * 0.4).clamp(12.0, 300.0);
  }

  /// 產生貝茲曲線路徑
  Path buildPath() {
    final cd = _controlDistance();
    final cp1 = start + startDirection * cd;
    final cp2 = end + endDirection * cd;

    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
  }

  /// 在 canvas 上繪製
  void paint(Canvas canvas) {
    final path = buildPath();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (animated) {
      // 動畫流動：dashed line + 動畫 offset
      paint.shader = SweepGradient(
        colors: [color.withValues(alpha: 0.1), color, color.withValues(alpha: 0.1)],
        stops: [0.0, animationProgress, 1.0],
      ).createShader(path.getBounds());
    } else if (dashed) {
      // 虛線模式（類型不匹配警告）
      final pathDashed = Path()..addPath(path, Offset.zero);
      final dashPath = _computeDashedPath(pathDashed, dashPattern);
      canvas.drawPath(dashPath, paint);
    }

    canvas.drawPath(path, paint);

    // 終點小圓點（input port 處）
    canvas.drawCircle(end, 3.0, Paint()..color = color);
  }

  /// [教練 Agent 2026-08-15 使用者 提案：hover 線變胖]
  /// 點擊測試：座標是否在曲線附近（容差=線寬+6px，涵蓋 hover 變胖後的範圍）。
  bool hitTest(Offset position) {
    final path = buildPath();
    final metric = path.computeMetrics().first;
    // 沿曲線取樣檢查最近距離
    const step = 8.0;
    double closest = double.infinity;
    for (double t = 0; t <= metric.length; t += step) {
      final tangent = metric.getTangentForOffset(t);
      if (tangent == null) continue;
      final d = (tangent.position - position).distance;
      if (d < closest) closest = d;
    }
    return closest <= strokeWidth + 6;
  }

  /// [教練 Agent 2026-08-15 使用者 提案] 計算座標在曲線上的參數位置 t（0=起點 1=終點），
  /// 用於判斷點在線的哪一端（前半=input 端遠，後半=output 端遠）。
  double positionT(Offset position) {
    final path = buildPath();
    final metric = path.computeMetrics().first;
    const step = 8.0;
    double bestT = 0;
    double closest = double.infinity;
    for (double t = 0; t <= metric.length; t += step) {
      final tangent = metric.getTangentForOffset(t);
      if (tangent == null) continue;
      final d = (tangent.position - position).distance;
      if (d < closest) {
        closest = d;
        bestT = t / metric.length;
      }
    }
    return bestT;
  }

  /// 計算虛線路徑
  Path _computeDashedPath(Path source, List<double> dashArray) {
    final dashPath = Path();
    final dashMetrics = source.computeMetrics();

    double distance = 0.0;
    for (final PathMetric metric in dashMetrics) {
      final pathLength = metric.length;
      while (distance < pathLength) {
        for (int i = 0; i < dashArray.length; i++) {
          final dashLength = dashArray[i];
          if (distance + dashLength > pathLength) {
            final subPath = metric.extractPath(distance, pathLength);
            dashPath.addPath(subPath, Offset.zero);
            distance = pathLength;
            break;
          }
          final subPath = metric.extractPath(distance, distance + dashLength);
          if (i % 2 == 0) {
            dashPath.addPath(subPath, Offset.zero);
          }
          distance += dashLength;
        }
      }
    }
    return dashPath;
  }
}
