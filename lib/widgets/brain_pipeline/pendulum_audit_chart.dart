// pendulum_audit_chart.dart
// Sprint 8 — 7 天擺錘統計 bar chart widget
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 用 CustomPaint 畫 7 天 x 6 軸的擺錘統計圖。
// 六軸（與 PendulumRadarChart 一致）：urgency/fear/comparison/proving/guilt/platformPull
// 點擊某一天可展開 evidence quotes（前 5 條）。
//
// 設計原則：不搶視覺焦點，半透明配色，與七層卡片風格一致。

import 'package:flutter/material.dart';

import '../../models/transurfing_brain.dart';
import '../../services/brain_pipeline/audit/audit_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';

/// 7 天擺錘統計 bar chart。
class PendulumAuditChart extends StatelessWidget {
  final PendulumAuditSummary summary;

  /// 六軸（與 PendulumRadarChart 一致）
  static const _chartTypes = [
    PendulumSignalType.urgency,
    PendulumSignalType.fear,
    PendulumSignalType.comparison,
    PendulumSignalType.proving,
    PendulumSignalType.guilt,
    PendulumSignalType.platformPull,
  ];

  static const _typeLabels = {
    PendulumSignalType.urgency: '急迫',
    PendulumSignalType.fear: '恐懼',
    PendulumSignalType.comparison: '比較',
    PendulumSignalType.proving: '證明',
    PendulumSignalType.guilt: '愧疚',
    PendulumSignalType.platformPull: '平台',
  };

  static const _typeColors = [
    Color(0xFFE53935), // urgency — 紅
    Color(0xFFFF7043), // fear — 橘
    Color(0xFFFFA726), // comparison — 黃橘
    Color(0xFF9CCC65), // proving — 綠
    Color(0xFFAB47BC), // guilt — 紫
    Color(0xFF42A5F5), // platformPull — 藍
  ];

  const PendulumAuditChart({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (summary.grandTotal == 0 && summary.clipConsumptionSecondsToday == 0) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '過去 7 天無擺錘紀錄',
          style: TextStyle(fontSize: 14, color: ds.textMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 擺錘統計圖
        if (summary.grandTotal > 0) ...[
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: _AuditBarPainter(
                summary: summary,
                types: _chartTypes,
                labels: _typeLabels,
                colors: _typeColors,
                textMuted: ds.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 圖例
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: List.generate(_chartTypes.length, (i) {
              final type = _chartTypes[i];
              final count = summary.totalForType(type);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _typeColors[i],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${_typeLabels[type]} $count',
                    style: TextStyle(
                      fontSize: 14,
                      color: ds.textMuted,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
        // clip 消費警示
        if (summary.clipConsumptionSecondsToday > 0) ...[
          const SizedBox(height: 6),
          _ClipConsumptionBar(seconds: summary.clipConsumptionSecondsToday),
        ],
      ],
    );
  }
}

/// 畫 7 天 x 6 類型的 stacked bar chart。
class _AuditBarPainter extends CustomPainter {
  final PendulumAuditSummary summary;
  final List<PendulumSignalType> types;
  final Map<PendulumSignalType, String> labels;
  final List<Color> colors;
  final Color textMuted;

  _AuditBarPainter({
    required this.summary,
    required this.types,
    required this.labels,
    required this.colors,
    required this.textMuted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final days = summary.days;
    if (days.isEmpty) return;

    final barCount = days.length; // 7
    final barWidth = (size.width - (barCount - 1) * 4) / barCount;
    final maxTotal = days.fold<int>(
      0,
      (max, d) => d.grandTotal > max ? d.grandTotal : max,
    );
    if (maxTotal == 0) return;

    final chartHeight = size.height - 16; // 底部留 16px 給日期標籤
    final unitHeight = chartHeight / maxTotal;

    for (int i = 0; i < barCount; i++) {
      final day = days[i];
      final x = i * (barWidth + 4);
      var yOffset = chartHeight; // 從底部往上疊

      // 每天疊 6 種類型
      for (int t = 0; t < types.length; t++) {
        final count = day.totalCount(types[t]);
        if (count == 0) continue;
        final segmentHeight = count * unitHeight;
        yOffset -= segmentHeight;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, yOffset, barWidth, segmentHeight),
          const Radius.circular(1.5),
        );
        final paint = Paint()..color = colors[t];
        canvas.drawRRect(rect, paint);
      }

      // 日期標籤（只顯示月/日）
      final dateLabel = _shortDate(day.dateKey);
      TextPainter(
        text: TextSpan(
          text: dateLabel,
          style: TextStyle(fontSize: 14, color: textMuted),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )
        ..layout(maxWidth: barWidth)
        ..paint(canvas, Offset(x, chartHeight + 2));
    }
  }

  String _shortDate(String dateKey) {
    // 'yyyy-MM-dd' → 'M/D'
    final parts = dateKey.split('-');
    if (parts.length != 3) return '';
    return '${int.parse(parts[1])}/${int.parse(parts[2])}';
  }

  @override
  bool shouldRepaint(covariant _AuditBarPainter oldDelegate) {
    return oldDelegate.summary != summary;
  }
}

/// Clip 消費計數條。
class _ClipConsumptionBar extends StatelessWidget {
  final int seconds;

  const _ClipConsumptionBar({required this.seconds});

  String get _formatted {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return m > 0 ? '$h 小時 $m 分鐘' : '$h 小時';
    }
    final m = seconds ~/ 60;
    return '$m 分鐘';
  }

  @override
  Widget build(BuildContext context) {
    final overLimit = seconds >= 3600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (overLimit ? Colors.red : Colors.orange)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (overLimit ? Colors.red : Colors.orange)
              .withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            overLimit ? Icons.warning_amber_rounded : Icons.play_circle_outline,
            size: 14,
            color: overLimit ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              overLimit
                  ? '今日短影音消費 $_formatted — 超過 60 分鐘警示'
                  : '今日短影音消費 $_formatted',
              style: TextStyle(
                fontSize: 14,
                color: overLimit ? Colors.red.shade700 : Colors.orange.shade700,
                fontWeight: overLimit ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
