// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 受管理資料夾規則選擇卡片：從 chat_screen.dart 提取。
import 'package:flutter/material.dart';

import '../../../models/chat_card_data.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 選擇已存整理規則卡片。
class ManagedFolderRulePickerCard extends StatelessWidget {
  final ManagedFolderRulePickerCardData card;
  final void Function(ManagedFolderRulePickerItem rule) onApplyRule;
  final void Function(String rulePath) onOpenRulePath;

  const ManagedFolderRulePickerCard({
    super.key,
    required this.card,
    required this.onApplyRule,
    required this.onOpenRulePath,
  });

  @override
  Widget build(BuildContext context) {
    final hasTargetFolder =
        card.targetFolderPath != null && card.targetFolderPath!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.45)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.rule_folder_outlined,
                  color: AppTheme.warning,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '選擇已存整理規則',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      hasTargetFolder
                          ? '目前已知道要整理哪個資料夾；請先選一條已存規則，我會直接套用到目前資料夾。'
                          : '我理解你想先沿用既有規則；請先選規則，再選要套用的資料夾。',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        height: 1.35,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RulePickerInfoRow(label: '原本需求', value: card.request),
          if (hasTargetFolder) ...[
            const SizedBox(height: 6),
            _RulePickerInfoRow(
              label: '目標資料夾',
              value: [
                if ((card.targetFolderLabel ?? '').trim().isNotEmpty)
                  card.targetFolderLabel!.trim(),
                card.targetFolderPath!.trim(),
              ].join(' · '),
            ),
          ],
          const SizedBox(height: 10),
          if (card.rules.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.22),
                ),
              ),
              child: SelectableText(
                '目前還沒有找到你保存過的整理規則。你可以先掃描一個資料夾並按「保存整理規則」，之後我就能在這裡列出來讓你套用。',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                  height: 1.4,
                  fontWeight: FontWeight.w700,),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rule in card.rules)
                  SizedBox(
                    width: 280,
                    child: _ManagedFolderRuleChoice(
                      rule: rule,
                      hasTargetFolder: hasTargetFolder,
                      onApplyRule: onApplyRule,
                      onOpenRulePath: onOpenRulePath,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RulePickerInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _RulePickerInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textPrimary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
        ),
      ],
    );
  }
}

class _ManagedFolderRuleChoice extends StatelessWidget {
  final ManagedFolderRulePickerItem rule;
  final bool hasTargetFolder;
  final void Function(ManagedFolderRulePickerItem rule) onApplyRule;
  final void Function(String rulePath) onOpenRulePath;

  const _ManagedFolderRuleChoice({
    required this.rule,
    required this.hasTargetFolder,
    required this.onApplyRule,
    required this.onOpenRulePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rule.builtIn
                    ? Icons.auto_awesome_outlined
                    : Icons.check_circle_outline,
                color: rule.builtIn ? AppTheme.textMuted : AppTheme.success,
                size: 17,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rule.ruleTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '來源資料夾：${rule.folderLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,),
          ),
          if (rule.categorySummary.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              rule.categorySummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted,
                height: 1.25,),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => onApplyRule(rule),
            icon: const Icon(Icons.playlist_add_check_outlined, size: 16),
            label: Text(hasTargetFolder ? '套用到目前資料夾' : '套用這條規則'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => onOpenRulePath(rule.rulePath),
            icon: const Icon(Icons.article_outlined, size: 16),
            label: const Text('查看規則文件'),
          ),
        ],
      ),
    );
  }
}
