// [教練 Agent Sprint 17 Step 5 — 2026-07-07]
// 待恢復任務橫幅 widget。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../services/pending_bridge_task_store.dart';
import '../helpers/bridge_action_ui_helper.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 待恢復任務橫幅。
class PendingBridgeTaskBanner extends StatelessWidget {
  final PendingBridgeTask task;
  final bool autoResuming;
  final VoidCallback onDismiss;
  final VoidCallback onResume;

  const PendingBridgeTaskBanner({
    super.key,
    required this.task,
    required this.autoResuming,
    required this.onDismiss,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          Icon(BridgeActionUIHelper.capabilityIcon(task.iconName), color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  autoResuming
                      ? '正在回到卡點：${task.title}'
                      : '待恢復任務：${task.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
                const SizedBox(height: 2),
                Text(
                  task.request,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('dismiss-pending-bridge-task'),
            onPressed: autoResuming ? null : onDismiss,
            child: const Text('放下'),
          ),
          FilledButton.icon(
            key: const ValueKey('resume-pending-bridge-task'),
            onPressed: autoResuming ? null : onResume,
            icon: const Icon(Icons.play_arrow_rounded, size: 17),
            label: const Text('帶回輸入框'),
          ),
        ],
      ),
    );
  }
}
