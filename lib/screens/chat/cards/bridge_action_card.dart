// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 橋樑動作狀態與確認卡片：從 chat_screen.dart 提取。
import 'package:flutter/material.dart';

import '../../../models/bridge_action.dart';
import '../../../services/bridge_action_execution_decision_service.dart';
import '../../../theme/app_theme.dart';
import '../helpers/bridge_action_ui_helper.dart';
import 'shared_card_widgets.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 橋樑動作狀態 Chip。
class BridgeActionStatusChip extends StatelessWidget {
  final BridgeAction action;
  final String messageId;
  final int actionIndex;
  final Future<void> Function(
    BridgeAction action, {
    String? messageId,
    int? actionIndex,
    bool confirmed,
  }) onExecute;

  const BridgeActionStatusChip({
    super.key,
    required this.action,
    required this.messageId,
    required this.actionIndex,
    required this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    final type = action.type.legacyType;
    final isRunning = action.runStatus == BridgeActionRunStatus.running;
    final isCompleted = action.runStatus == BridgeActionRunStatus.completed;
    final isFailed = action.runStatus == BridgeActionRunStatus.failed;
    final statusMessage = action.statusMessage;
    final label = BridgeActionUIHelper.chipLabel(action);
    final showStatus =
        statusMessage != null &&
        statusMessage.isNotEmpty &&
        action.runStatus != BridgeActionRunStatus.pending &&
        !isRunning;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionChip(
            avatar: isRunning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isCompleted
                        ? Icons.check_circle
                        : isFailed
                        ? Icons.refresh
                        : BridgeActionUIHelper.icon(type),
                    size: 16,
                    color: isFailed
                        ? Theme.of(context).colorScheme.error
                        : BridgeDS.successGreen,
                  ),
            label: Text(
              '$label · ${action.runStatus.displayLabel}',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
            ),
            tooltip: action.statusMessage,
            backgroundColor: isFailed
                ? BridgeDS.bgLightRed
                : BridgeDS.bgLightGreen,
            side: BorderSide(
              color: isFailed
                  ? Theme.of(context).colorScheme.error
                  : BridgeDS.successGreen,
            ),
            onPressed: action.canExecute
                ? () => onExecute(
                      action,
                      messageId: messageId,
                      actionIndex: actionIndex,
                      confirmed: false,
                    )
                : null,
          ),
          if (showStatus)
            Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isFailed
                    ? BridgeDS.bgVeryLightRed
                    : AppTheme.surfaceHighlight,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: isFailed
                      ? Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.22)
                      : AppTheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: SelectableText(
                statusMessage,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                  height: 1.35,),
              ),
            ),
        ],
      ),
    );
  }
}

/// 橋樑動作確認卡片。
class BridgeActionConfirmationCard extends StatelessWidget {
  final BridgeAction action;
  final String messageId;
  final int actionIndex;
  final Future<void> Function(
    BridgeAction action, {
    String? messageId,
    int? actionIndex,
    bool confirmed,
    BridgeActionExecutionOverride executionOverride,
  }) onExecute;
  final Future<void> Function(String messageId, int actionIndex,
      {required String message}) onCancel;

  const BridgeActionConfirmationCard({
    super.key,
    required this.action,
    required this.messageId,
    required this.actionIndex,
    required this.onExecute,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final type = action.type.legacyType;
    final isDesktopOrganize = action.type == BridgeActionType.desktopFiles;
    final isRunning = action.runStatus == BridgeActionRunStatus.running;
    final isCancelled = action.runStatus == BridgeActionRunStatus.failed;
    return Container(
      width: 360,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.28)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(
                  BridgeActionUIHelper.icon(type),
                  size: 18,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDesktopOrganize
                      ? '桌面整理計畫需要確認'
                      : '${BridgeActionUIHelper.label(type)}需要確認',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              StatusPillLite(
                label: isCancelled ? '已取消' : action.runStatus.displayLabel,
                color: isCancelled ? AppTheme.error : AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            action.statusMessage ?? '這次任務設定為每次詢問，請確認後再執行。',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
              height: 1.35,),
          ),
          const SizedBox(height: 8),
          SelectableText(
            action.prompt,
            maxLines: 3,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted,
              height: 1.35,),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 96,
                child: OutlinedButton.icon(
                  onPressed: isRunning || isCancelled
                      ? null
                      : () => onCancel(
                            messageId,
                            actionIndex,
                            message: '已取消這次橋樑動作',
                          ),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('取消'),
                ),
              ),
              if (isDesktopOrganize)
                FilledButton.icon(
                  onPressed: isRunning || isCancelled
                      ? null
                      : () => onExecute(
                          action.copyWith(requiresConfirmation: false),
                          messageId: messageId,
                          actionIndex: actionIndex,
                          confirmed: true,
                          executionOverride:
                              BridgeActionExecutionOverride.localFirst,
                        ),
                  icon: const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('確認執行'),
                )
              else ...[
                OneShotRouteButton(
                  label: '自動',
                  icon: Icons.auto_mode,
                  filled: true,
                  disabled: isRunning || isCancelled,
                  onPressed: () => onExecute(
                    action.copyWith(requiresConfirmation: false),
                    messageId: messageId,
                    actionIndex: actionIndex,
                    confirmed: true,
                    executionOverride: BridgeActionExecutionOverride.automatic,
                  ),
                ),
                OneShotRouteButton(
                  label: '雲端',
                  icon: Icons.cloud_outlined,
                  disabled: isRunning || isCancelled,
                  onPressed: () => onExecute(
                    action.copyWith(requiresConfirmation: false),
                    messageId: messageId,
                    actionIndex: actionIndex,
                    confirmed: true,
                    executionOverride: BridgeActionExecutionOverride.cloudFirst,
                  ),
                ),
                OneShotRouteButton(
                  label: '本地',
                  icon: Icons.memory_outlined,
                  disabled: isRunning || isCancelled,
                  onPressed: () => onExecute(
                    action.copyWith(requiresConfirmation: false),
                    messageId: messageId,
                    actionIndex: actionIndex,
                    confirmed: true,
                    executionOverride: BridgeActionExecutionOverride.localFirst,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
