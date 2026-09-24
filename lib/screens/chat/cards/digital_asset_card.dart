// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 數位資產相關卡片：從 chat_screen.dart 提取的純展示 widget。
import 'package:flutter/material.dart';

import '../../../models/chat_card_data.dart';
import '../../../theme/app_theme.dart';
import 'shared_card_widgets.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 任務前資產檢查卡片（找到可重用資產）。
class DigitalAssetInvocationCard extends StatelessWidget {
  final DigitalAssetInvocationCardData card;
  final VoidCallback onInvoke;
  final void Function(String message) onContinue;

  const DigitalAssetInvocationCard({
    super.key,
    required this.card,
    required this.onInvoke,
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
                  Icons.category_outlined,
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
                      '任務前資產檢查',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      '找到可重用資產：${card.assetTitle}',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              StatusPillLite(label: card.assetKind, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '目前專案',
            value: card.targetProjectTitle,
            icon: Icons.flag_circle_outlined,
          ),
          if (card.sourceLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            CapabilityCardLine(
              label: '資產來源',
              value: card.sourceLabel,
              icon: Icons.account_tree_outlined,
            ),
          ],
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '使用意圖',
            value: card.request,
            icon: Icons.track_changes_outlined,
          ),
          if (card.assetSummary.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              card.assetSummary,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                height: 1.4,
                fontWeight: FontWeight.w600,),
            ),
          ],
          if (card.reusableScenes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '適合帶入的場景',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.reusableScenes
                  .take(5)
                  .map(
                    (scene) => Chip(
                      avatar: const Icon(Icons.auto_awesome_rounded, size: 15),
                      label: Text(scene),
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
          if (card.matchReasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '命中線索',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.matchReasons
                  .take(5)
                  .map(
                    (reason) => Chip(
                      avatar: const Icon(Icons.radar_outlined, size: 15),
                      label: Text(reason),
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
          if (card.capabilities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '會一起帶入的能力',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.capabilities
                  .take(5)
                  .map(
                    (capability) => Chip(
                      avatar: const Icon(Icons.hub_outlined, size: 15),
                      label: Text(capability),
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
          SelectableText(
            '引入後，我會先用這包既有成果組裝任務，缺的部分再補。這也會寫回目前專案與第二大腦，後續同專案和其他 Agent 都能看到它已被採用。',
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
                onPressed: onInvoke,
                icon: const Icon(Icons.call_merge_rounded, size: 17),
                label: const Text('引入目前專案'),
              ),
              OutlinedButton.icon(
                onPressed: () => onContinue('好，我先不引入這包數位資產。'),
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: const Text('先不要'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 資產重用任務草案卡片。
class DigitalAssetReusePlanCard extends StatelessWidget {
  final DigitalAssetReusePlanCardData card;
  final VoidCallback onStart;
  final VoidCallback onStartOutline;
  final void Function(String message) onContinue;

  const DigitalAssetReusePlanCard({
    super.key,
    required this.card,
    required this.onStart,
    required this.onStartOutline,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.38)),
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
                  color: AppTheme.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.playlist_add_check_circle_outlined,
                  size: 23,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '資產重用任務草案',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      '已引用「${card.assetTitle}」，現在把它接成可執行下一步。',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              StatusPillLite(label: card.assetKind, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '目前專案',
            value: card.targetProjectTitle,
            icon: Icons.flag_circle_outlined,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '下一步任務',
            value: card.suggestedAction,
            icon: Icons.arrow_forward_rounded,
          ),
          if (card.planSummary.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              card.planSummary,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                height: 1.4,
                fontWeight: FontWeight.w600,),
            ),
          ],
          if (card.nextSteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '執行順序',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            ...card.nextSteps
                .take(5)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.primary,
                              fontWeight: FontWeight.w900,),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            entry.value,
                            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                              height: 1.35,
                              fontWeight: FontWeight.w700,),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (card.capabilities.isNotEmpty ||
              card.reusableScenes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...card.capabilities
                    .take(3)
                    .map(
                      (capability) => Chip(
                        avatar: const Icon(Icons.hub_outlined, size: 15),
                        label: Text(capability),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppTheme.surface,
                        side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                ...card.reusableScenes
                    .take(3)
                    .map(
                      (scene) => Chip(
                        avatar: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 15,
                        ),
                        label: Text(scene),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppTheme.surface,
                        side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded, size: 17),
                label: const Text('照這個開始'),
              ),
              OutlinedButton.icon(
                onPressed: onStartOutline,
                icon: const Icon(Icons.subject_rounded, size: 17),
                label: const Text('先整理大綱'),
              ),
              OutlinedButton.icon(
                onPressed: () => onContinue('好，這個資產先暫停使用。'),
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 17),
                label: const Text('暫停'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 數位資產成果卡片。
class DigitalAssetResultCard extends StatelessWidget {
  final DigitalAssetResultCardData card;
  final String activeProjectDoorId;
  final String activeProjectDoorTitle;
  final void Function(DigitalAssetInvocationCardData invocation) onInvoke;

  const DigitalAssetResultCard({
    super.key,
    required this.card,
    required this.activeProjectDoorId,
    required this.activeProjectDoorTitle,
    required this.onInvoke,
  });

  @override
  Widget build(BuildContext context) {
    final activeTitle = activeProjectDoorTitle.trim();
    final canInvoke = activeTitle.isNotEmpty &&
        activeTitle != card.sourceProjectTitle.trim();
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
                  Icons.inventory_2_outlined,
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
                      '數位資產成果',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      card.assetTitle,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
              StatusPillLite(label: card.assetKind, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          CapabilityCardLine(
            label: '這個專案產出',
            value: card.assetSummary.trim().isEmpty
                ? card.assetTitle
                : card.assetSummary,
            icon: Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: 8),
          CapabilityCardLine(
            label: '來源專案',
            value: card.sourceProjectTitle.trim().isEmpty
                ? '目前專案'
                : card.sourceProjectTitle,
            icon: Icons.flag_circle_outlined,
          ),
          if (card.capabilities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '包含的橋 / 能力',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.capabilities
                  .take(6)
                  .map(
                    (capability) => Chip(
                      avatar: const Icon(Icons.hub_outlined, size: 15),
                      label: Text(capability),
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
          if (card.reusableScenes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '可引用場景',
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.reusableScenes
                  .take(5)
                  .map(
                    (scene) => Chip(
                      avatar: const Icon(Icons.call_merge_rounded, size: 15),
                      label: Text(scene),
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
          CapabilityCardLine(
            label: '哪些專案可引用',
            value: card.availableProjects.isEmpty
                ? '其他專案建立後可引用'
                : card.availableProjects.join('、'),
            icon: Icons.account_tree_outlined,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canInvoke
                ? () => onInvoke(
                      DigitalAssetInvocationCardData(
                        assetId: card.assetId,
                        assetTitle: card.assetTitle,
                        assetKind: card.assetKind,
                        assetSummary: card.assetSummary,
                        sourceLabel: card.sourceProjectTitle,
                        capabilities: card.capabilities,
                        reusableScenes: card.reusableScenes,
                        matchReasons: [
                          if (card.assetKind.trim().isNotEmpty)
                            '資產類型：${card.assetKind}',
                          if (card.sourceProjectTitle.trim().isNotEmpty)
                            '來源專案：${card.sourceProjectTitle}',
                        ],
                        targetProjectId: activeProjectDoorId,
                        targetProjectTitle: activeProjectDoorTitle,
                        request: '把這包專案成果引用到目前專案。',
                      ),
                    )
                : null,
            icon: const Icon(Icons.call_merge_rounded, size: 17),
            label: Text(canInvoke ? '引用到目前專案' : '目前專案已是來源'),
          ),
        ],
      ),
    );
  }
}
