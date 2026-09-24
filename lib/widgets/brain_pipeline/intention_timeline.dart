// intention_timeline.dart
// Sprint 6 — 24h 意圖時間軸
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 從 BrainContainer 撈 open/confirmed/acted intentions，畫 24h 橫軸。
// open=黃、confirmed=藍、acted=綠。

import 'package:flutter/material.dart';

import '../../models/intention_record.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class IntentionTimeline extends StatelessWidget {
  final List<IntentionRecord> intentions;
  final int nowMs;

  const IntentionTimeline({
    super.key,
    required this.intentions,
    this.nowMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (intentions.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = nowMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(nowMs)
        : DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayStartMs = dayStart.millisecondsSinceEpoch;
    final dayEndMs = dayStart.add(const Duration(days: 1)).millisecondsSinceEpoch;
    final dayRange = dayEndMs - dayStartMs;

    // 過濾今日 intentions
    final today = intentions.where((r) {
      final t = r.createdAtMs;
      return t >= dayStartMs && t < dayEndMs;
    }).toList();

    if (today.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '意圖時間軸',
          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
            color: BridgeDSColors.of(context).textSecondary,),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: Stack(
            children: [
              // 橫軸底線
              Positioned(
                left: 0,
                right: 0,
                top: 18,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).borderDefault,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // 時間刻度
              Positioned(
                left: 0,
                top: 24,
                child: Text('00', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted)),
              ),
              Positioned(
                right: 0,
                top: 24,
                child: Text('24', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted)),
              ),
              // 意圖點
              ...today.map((r) {
                final ratio = ((r.createdAtMs - dayStartMs) / dayRange).clamp(0.0, 1.0);
                final color = _statusColor(r.status);
                return Positioned(
                  left: ratio * (MediaQuery.of(context).size.width - 32) - 6,
                  top: 10,
                  child: Tooltip(
                    message: '${r.status.name}: ${r.userMessage}',
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // 圖例
        const SizedBox(height: 2),
        Row(
          children: [
            _LegendDot(color: BridgeDSColors.of(context).accentYellow, label: '待確認'),
            const SizedBox(width: 8),
            _LegendDot(color: BridgeDSColors.of(context).accentPurple, label: '已確認'),
            const SizedBox(width: 8),
            _LegendDot(color: BridgeDSColors.of(context).accentGreen, label: '已行動'),
          ],
        ),
      ],
    );
  }

  Color _statusColor(IntentionStatus s) {
    return switch (s) {
      IntentionStatus.open => BridgeDS.accentYellow,
      IntentionStatus.confirmed => BridgeDS.accentPurple,
      IntentionStatus.acted => BridgeDS.accentGreen,
      IntentionStatus.cancelled => BridgeDS.textMuted,
    };
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
            fontWeight: FontWeight.w600,),
        ),
      ],
    );
  }
}
