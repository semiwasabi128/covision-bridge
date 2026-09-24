// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 待命狀態的思維儀表 dock：從 chat_screen.dart _buildBrainReflectionStandbyDock 提取。
// 純展示 widget，零外部依賴。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 思維儀表待命狀態：顯示圖示 + 提示文字。
class BrainReflectionStandbyDock extends StatelessWidget {
  const BrainReflectionStandbyDock({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.psychology_alt_outlined,
              size: 17,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '思維儀表待命',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,),
                ),
                SizedBox(height: 2),
                Text(
                  '送出訊息後，這裡會顯示判斷、調閱記憶與下一步。',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
