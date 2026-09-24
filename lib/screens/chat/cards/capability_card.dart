// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 能力缺口卡片：從 chat_screen.dart 提取。
// _isCapabilityGapResolved / _capabilityCardActionType 搬成同檔 static methods。
import 'package:flutter/material.dart';

import '../../../models/chat_card_data.dart';
import '../../../theme/app_theme.dart';
import '../helpers/bridge_action_ui_helper.dart';
import 'shared_card_widgets.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 能力缺口卡片。checkResolved 為外部傳入的解析函式（原 _isCapabilityGapResolved）。
class CapabilityGapCard extends StatelessWidget {
  final CapabilityGapCardData card;
  final Future<bool> Function(CapabilityGapCardData card) checkResolved;
  final VoidCallback onResume;
  final void Function(String route) onGoRoute;

  const CapabilityGapCard({
    super.key,
    required this.card,
    required this.checkResolved,
    required this.onResume,
    required this.onGoRoute,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: checkResolved(card),
      builder: (context, snapshot) {
        final isReady = snapshot.data == true;
        return _buildBody(context, isReady: isReady);
      },
    );
  }

  Widget _buildBody(BuildContext context, {required bool isReady}) {
    return Container(
      width: 430,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.42)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  BridgeActionUIHelper.capabilityIcon(card.iconName),
                  size: 20,
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      card.title,
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      isReady ? '這座橋現在已經可用，可以回到原任務。' : '我知道你想做什麼，但還差一座橋。',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              StatusPillLite(
                label: isReady ? '已開通' : '待開通',
                color: isReady ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '原本任務',
            value: card.request,
            icon: Icons.flag_outlined,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '缺少能力',
            value: card.missing,
            icon: Icons.vpn_key_outlined,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '目前狀態',
            value: isReady ? '目前能力已開通。你可以直接繼續原本任務，或進設定管理這座橋。' : card.status,
            icon: Icons.info_outline,
          ),
          if (card.steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '接下來',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            for (final entry in card.steps.asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${entry.key + 1}',
                        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.primary,
                          fontWeight: FontWeight.w900,),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: SelectableText(
                        entry.value,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                          height: 1.35,
                          fontWeight: FontWeight.w600,),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (card.providerHints.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '可選入口',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.providerHints
                  .map(
                    (hint) => Chip(
                      avatar: const Icon(Icons.verified_outlined, size: 15),
                      label: Text(hint),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.16),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isReady
                      ? onResume
                      : () => onGoRoute(card.route),
                  icon: Icon(
                    isReady
                        ? Icons.play_arrow_rounded
                        : Icons.arrow_forward_rounded,
                    size: 17,
                  ),
                  label: Text(isReady ? '繼續原任務' : card.routeLabel),
                ),
                OutlinedButton.icon(
                  onPressed: isReady
                      ? () => onGoRoute(card.route)
                      : onResume,
                  icon: Icon(
                    isReady ? Icons.settings_outlined : Icons.replay_rounded,
                    size: 17,
                  ),
                  label: Text(isReady ? '管理設定' : '繼續原任務'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
