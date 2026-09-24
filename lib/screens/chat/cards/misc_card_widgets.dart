// [教練 Agent Sprint 17 Step 4 — 2026-07-07]
// 雜項卡片 widget：文件附件、Skill 快捷 Chip、回答回饋 Chip。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// Markdown 文件附件卡片。
class DocumentAttachmentCard extends StatelessWidget {
  final String path;
  final VoidCallback onPreview;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenPath;

  const DocumentAttachmentCard({
    super.key,
    required this.path,
    required this.onPreview,
    required this.onCopyPath,
    required this.onOpenPath,
  });

  @override
  Widget build(BuildContext context) {
    final isWebData = path.startsWith('data:text/markdown');
    final displayPath = isWebData ? 'Markdown 文件已保存在本次對話' : path;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: AppTheme.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Markdown 文件',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('預覽'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyPath,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('複製路徑'),
              ),
              if (!isWebData)
                OutlinedButton.icon(
                  onPressed: onOpenPath,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('開啟'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skill 快捷 Chip（純展示，onPressed 由外部 setState 處理）。
class SkillChip extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const SkillChip({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Text(label.substring(0, 2)),
      label: Text(
        label.substring(2),
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: theme.colorScheme.onSurfaceVariant,),
      ),
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      onPressed: onPressed,
    );
  }
}

/// 回答回饋 Chip（準確 / 不準確 / 先別採用）。
class AnswerFeedbackChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const AnswerFeedbackChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ActionChip(
        avatar: Icon(
          icon,
          size: 14,
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
        ),
        label: Text(label),
        tooltip: '標記這輪回答：$label',
        side: BorderSide(
          color: selected
              ? AppTheme.primary
              : AppTheme.border.withValues(alpha: 0.9),
        ),
        backgroundColor: selected
            ? AppTheme.primary.withValues(alpha: 0.12)
            : AppTheme.surface,
        labelStyle: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: selected ? AppTheme.primary : AppTheme.textSecondary,
          fontWeight: FontWeight.w900,),
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }
}
