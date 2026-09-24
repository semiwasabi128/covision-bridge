// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 共用卡片元件：從 chat_screen.dart 提取的純展示 widget。
// 這些 widget 被多張卡片共用，獨立出來避免循環依賴。

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 卡片右上角的狀態小藥丸。
class StatusPillLite extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPillLite({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
          fontWeight: FontWeight.w900,),
      ),
    );
  }
}

/// 卡片內部的「標籤：值」行（icon + label + value）。
class CapabilityCardLine extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const CapabilityCardLine({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.primary),
        const SizedBox(width: 7),
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textMuted,
              fontWeight: FontWeight.w800,),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
        ),
      ],
    );
  }
}

/// 卡片底部的單次操作按鈕（filled 或 outlined）。
class OneShotRouteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool disabled;
  final VoidCallback onPressed;

  const OneShotRouteButton({
    super.key,
    required this.label,
    required this.icon,
    this.filled = false,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 15), const SizedBox(width: 4), Text(label)],
    );
    return SizedBox(
      width: 76,
      child: filled
          ? FilledButton(onPressed: disabled ? null : onPressed, child: child)
          : OutlinedButton(
              onPressed: disabled ? null : onPressed,
              child: child,
            ),
    );
  }
}
