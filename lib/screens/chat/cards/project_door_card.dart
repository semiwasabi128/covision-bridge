// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 專案門相關卡片：從 chat_screen.dart 提取的純展示 widget。
// 行為不變，callback 透過建構函數傳入。
import 'package:flutter/material.dart';

import '../../../models/chat_card_data.dart';
import '../../../theme/app_theme.dart';
import 'shared_card_widgets.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 建立專案門卡片（含分岔專案門變體）。
class ProjectDoorCard extends StatelessWidget {
  final ProjectDoorCardData card;
  final bool alreadyActive;
  final VoidCallback onCreate;
  final void Function(String message) onContinue;

  const ProjectDoorCard({
    super.key,
    required this.card,
    required this.alreadyActive,
    required this.onCreate,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final cardTitle = card.forkFromConversation ? '建立分岔專案門' : '建立專案門';
    final primaryActionLabel = card.forkFromConversation ? '建立新專案門' : '建立專案門';
    final confidencePercent = (card.confidence * 100).round();
    return Container(
      width: 520,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.36)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_circle_outlined,
                  size: 22,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      cardTitle,
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      card.title,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              StatusPillLite(
                label: alreadyActive ? '已建立' : '信心 $confidencePercent%',
                color: alreadyActive ? AppTheme.success : AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.psychology_alt_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: SelectableText(
                    card.confidenceSignals.isEmpty
                        ? '我判斷這像是一扇可以成立的專案門；後續會從你的自然回應自動校正信心。'
                        : '判斷依據：${card.confidenceSignals.take(3).join('、')}。後續會從你的自然回應自動校正信心。',
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                      height: 1.35,
                      fontWeight: FontWeight.w700,),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          CapabilityCardLine(
            label: card.forkFromConversation ? '分岔意圖' : '原始意圖',
            value: card.sourceIntent,
            icon: Icons.track_changes_outlined,
          ),
          if (card.forkFromConversation &&
              card.sourceConversationTitle?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            CapabilityCardLine(
              label: '來源專案',
              value: card.sourceConversationTitle!,
              icon: Icons.account_tree_outlined,
            ),
          ],
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '第一水流',
            value: card.firstFlow,
            icon: Icons.water_drop_outlined,
          ),
          const SizedBox(height: 12),
          Text(
            '接下來要先釐清',
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,),
          ),
          const SizedBox(height: 6),
          for (final entry
              in card.intakeQuestions.take(5).toList().asMap().entries)
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
          if (card.requiredBridges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '可能需要的橋',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.requiredBridges
                  .map(
                    (bridge) => Chip(
                      avatar: const Icon(Icons.hub_outlined, size: 15),
                      label: Text(bridge),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppTheme.surfaceHighlight,
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: alreadyActive ? null : onCreate,
                icon: const Icon(Icons.add_task_rounded, size: 17),
                label: Text(alreadyActive ? '專案門已建立' : primaryActionLabel),
              ),
              OutlinedButton.icon(
                onPressed: () => onContinue(
                  '好，我先不建立專案門。這段仍會保留在對話裡，之後你說「開始做」時我會再提醒。',
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: const Text('先繼續聊天'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 移植到專案門卡片。
class ProjectContextTransferCard extends StatelessWidget {
  final ProjectContextTransferCardData card;
  final VoidCallback onTransfer;
  final void Function(String message) onContinue;

  const ProjectContextTransferCard({
    super.key,
    required this.card,
    required this.onTransfer,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.34)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.drive_file_move_outlined,
                  size: 22,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '移植到專案門',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      card.targetProjectTitle,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              const StatusPillLite(label: '待確認', color: AppTheme.warning),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '來源對話',
            value: card.sourceConversationTitle,
            icon: Icons.chat_bubble_outline_rounded,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '移植摘要',
            value: card.ideaSummary,
            icon: Icons.lightbulb_outline_rounded,
          ),
          const SizedBox(height: 12),
          Text(
            '準備帶入專案的上下文',
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHighlight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in card.contextLines.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(
                      '• $line',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        height: 1.35,
                        fontWeight: FontWeight.w600,),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            '確認後，我會把這段素材寫進目標專案對話與第二大腦 Projects 房間；原對話會留下移植紀錄。',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onTransfer,
                icon: const Icon(Icons.move_to_inbox_rounded, size: 17),
                label: const Text('移植到專案'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    onContinue('好，我先不移植。這段點子仍留在目前對話裡。'),
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: const Text('先留在這裡'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 專案分岔完成卡片。
class ProjectForkCompleteCard extends StatelessWidget {
  final ProjectForkCompleteCardData card;
  final VoidCallback onSwitchToTarget;
  final void Function(String message) onContinue;

  const ProjectForkCompleteCard({
    super.key,
    required this.card,
    required this.onSwitchToTarget,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.34)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_split_rounded,
                  size: 22,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '專案已分岔',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      '已分岔到：${card.targetProjectTitle}',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              const StatusPillLite(label: '原專案保留', color: AppTheme.success),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '帶入上下文',
            value: '${card.contextCount} 則',
            icon: Icons.format_list_bulleted_rounded,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '原專案',
            value: '${card.sourceProjectTitle} 仍保留',
            icon: Icons.flag_circle_outlined,
          ),
          if (card.assetTitle.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            CapabilityCardLine(
              label: '同步資產',
              value: card.assetTitle,
              icon: Icons.category_outlined,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: card.targetProjectId.trim().isEmpty
                    ? null
                    : onSwitchToTarget,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('前往新專案'),
              ),
              OutlinedButton.icon(
                onPressed: () => onContinue(
                  '好，我們先留在「${card.sourceProjectTitle}」。需要時可以從左側專案門打開「${card.targetProjectTitle}」。',
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: const Text('留在原專案'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 專案分岔介紹卡片。
class ProjectForkIntroCard extends StatelessWidget {
  final ProjectForkIntroCardData card;

  const ProjectForkIntroCard({
    super.key,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 560,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.34)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_circle_outlined,
                  size: 22,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      card.projectTitle,
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      '新專案門啟動卡',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              StatusPillLite(label: card.currentFlow, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '來源專案',
            value: card.sourceProjectTitle,
            icon: Icons.account_tree_outlined,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '分岔原因',
            value: card.forkReason,
            icon: Icons.track_changes_outlined,
          ),
          if (card.contextLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '帶入內容摘要',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHighlight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in card.contextLines.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        '• $line',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                          height: 1.35,
                          fontWeight: FontWeight.w600,),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '下一步提問',
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,),
          ),
          const SizedBox(height: 6),
          for (final entry
              in card.intakeQuestions.take(5).toList().asMap().entries)
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
          if (card.requiredBridges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.requiredBridges
                  .take(6)
                  .map(
                    (bridge) => Chip(
                      avatar: const Icon(Icons.hub_outlined, size: 15),
                      label: Text(bridge),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppTheme.surfaceHighlight,
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
