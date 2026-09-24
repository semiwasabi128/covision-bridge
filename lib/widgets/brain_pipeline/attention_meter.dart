// attention_meter.dart
// Sprint 6 — 三段注意力狀態條
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 三段：clear / captured / scattered
// 每段有百分比信心，目前狀態高亮。

import 'package:flutter/material.dart';

import '../../models/transurfing_brain.dart';
import '../../services/brain_pipeline/layer_result.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class AttentionMeter extends StatelessWidget {
  final AttentionState state;
  final double confidence;
  final LayerSource source;

  const AttentionMeter({
    super.key,
    required this.state,
    this.confidence = 1.0,
    this.source = LayerSource.rule,
  });

  @override
  Widget build(BuildContext context) {
    final segments = [
      (AttentionState.clear, '清醒', BridgeDSColors.of(context).accentGreen),
      (AttentionState.captured, '被捕獲', BridgeDSColors.of(context).accentYellow),
      (AttentionState.scattered, '分散', AppTheme.error),
    ];

    return Row(
      children: segments.map((seg) {
        final isActive = state == seg.$1;
        return Expanded(
          child: Container(
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: isActive
                  ? seg.$3.withValues(alpha: 0.18)
                  : BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive ? seg.$3.withValues(alpha: 0.4) : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Center(
              child: Text(
                seg.$2,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  color: isActive ? seg.$3 : BridgeDSColors.of(context).textMuted,),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
