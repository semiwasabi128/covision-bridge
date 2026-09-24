// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 思考中指示器：從 chat_screen.dart _buildThinkingPanel 提取。
// 純展示 widget，零外部依賴。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 聊天思考中指示器：小圓圈 + 文字。
class ThinkingPanel extends StatelessWidget {
  const ThinkingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '思考中...',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,),
          ),
        ],
      ),
    );
  }
}
