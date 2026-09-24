// pendulum_radar_chart.dart
// Sprint 6 — 六軸擺錘雷達圖
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 六軸：urgency / fear / comparison / proving / guilt / platformPull
// 每軸的值 = 命中次數（0~N），用 CustomPaint 畫六角形雷達。

import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/transurfing_brain.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';

class PendulumRadarChart extends StatelessWidget {
  final List<PendulumSignal> signals;

  const PendulumRadarChart({super.key, required this.signals});

  @override
  Widget build(BuildContext context) {
    // 六軸定義
    const axes = [
      (PendulumSignalType.urgency, '急迫'),
      (PendulumSignalType.fear, '恐懼'),
      (PendulumSignalType.comparison, '比較'),
      (PendulumSignalType.proving, '證明'),
      (PendulumSignalType.guilt, '愧疚'),
      (PendulumSignalType.platformPull, '平台'),
    ];

    // 計算每軸命中數
    final counts = <int>[];
    for (final (type, _) in axes) {
      counts.add(signals.where((s) => s.type == type).length);
    }
    final maxCount = counts.reduce((a, b) => a > b ? a : b).clamp(1, 99);

    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _RadarPainter(
          counts: counts,
          maxCount: maxCount,
          axisLabels: axes.map((e) => e.$2).toList(),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<int> counts;
  final int maxCount;
  final List<String> axisLabels;

  _RadarPainter({
    required this.counts,
    required this.maxCount,
    required this.axisLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width * 0.38;
    final n = counts.length; // 6

    // 背景網格（3 層）
    for (var ring = 1; ring <= 3; ring++) {
      final r = radius * ring / 3;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -pi / 2 + 2 * pi * i / n;
        final x = cx + r * cos(angle);
        final y = cy + r * sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = BridgeDS.borderDefault.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // 軸線
    for (var i = 0; i < n; i++) {
      final angle = -pi / 2 + 2 * pi * i / n;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + radius * cos(angle), cy + radius * sin(angle)),
        Paint()
          ..color = BridgeDS.borderDefault.withValues(alpha: 0.4)
          ..strokeWidth = 0.5,
      );
    }

    // 資料多邊形
    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final angle = -pi / 2 + 2 * pi * i / n;
      final r = counts[i] == 0 ? 0.0 : radius * counts[i] / maxCount;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        dataPath.moveTo(x, y);
      } else {
        dataPath.lineTo(x, y);
      }
    }
    dataPath.close();

    canvas.drawPath(
      dataPath,
      Paint()
        ..color = BridgeDS.accentPurple.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = BridgeDS.accentPurple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 頂點圓點
    for (var i = 0; i < n; i++) {
      final angle = -pi / 2 + 2 * pi * i / n;
      final r = counts[i] == 0 ? 0.0 : radius * counts[i] / maxCount;
      if (r > 0) {
        canvas.drawCircle(
          Offset(cx + r * cos(angle), cy + r * sin(angle)),
          2,
          Paint()..color = BridgeDS.accentPurple,
        );
      }
    }

    // 軸標籤
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final angle = -pi / 2 + 2 * pi * i / n;
      final lx = cx + (radius + 10) * cos(angle);
      final ly = cy + (radius + 10) * sin(angle);
      labelPainter.text = TextSpan(
        text: '${axisLabels[i]}${counts[i] > 0 ? counts[i] : ''}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: counts[i] > 0 ? FontWeight.w700 : FontWeight.w500,
          color: counts[i] > 0 ? BridgeDS.textPrimary : BridgeDS.textMuted,
        ),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(lx - labelPainter.width / 2, ly - labelPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.counts != counts;
  }
}
