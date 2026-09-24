// P0.5 任務證據卡——僅顯示 ConversationStore 已落地的安全 metadata。
//
// 設計合約見 docs/CHAT_TASK_EVIDENCE_DESIGN.md：
//   - 沒有可用 callback 的動作按鈕不會被渲染
//   - 不會自行 fetch / 不會自行跳轉 / 不會讀 raw map
//   - 媒體縮圖若 mediaUrl 為本機路徑或可顯示 HTTP，皆使用 MessageImage 既有 helper

import 'package:flutter/material.dart';

import '../../../models/task_evidence.dart';
import '../widgets/message_extras.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// Callback contract: kind 對應的 view 由 host 解析；沒給就只 call onAction。
class TaskEvidenceCardClickContext {
  final TaskEvidence evidence;
  final TaskEvidenceAction action;
  const TaskEvidenceCardClickContext(this.evidence, this.action);
}

class TaskEvidenceCard extends StatelessWidget {
  final TaskEvidence evidence;
  final void Function(TaskEvidenceCardClickContext ctx) onTapAction;

  const TaskEvidenceCard({
    super.key,
    required this.evidence,
    required this.onTapAction,
  });

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final accent = _outcomeColor(evidence.outcome, ds);
    final icon = _kindIcon(evidence.kind);

    return Container(
      margin: const EdgeInsets.only(bottom: 6, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ds.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  evidence.headline,
                  style: TierStyle.of(context, Tier.cardCaptionBold)
                      .toTextStyle()
                      .copyWith(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (evidence.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              evidence.summary,
              style: TierStyle.of(
                context,
                Tier.cardBody,
              ).toTextStyle().copyWith(color: ds.textSecondary),
            ),
          ],
          if (evidence.mediaUrl != null &&
              evidence.kind == TaskEvidenceKind.image) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MessageImage(imagePath: evidence.mediaUrl!),
            ),
          ],
          if (evidence.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final a in evidence.actions)
                  OutlinedButton(
                    onPressed: () =>
                        onTapAction(TaskEvidenceCardClickContext(evidence, a)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 28),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      a.label,
                      style: TierStyle.of(
                        context,
                        Tier.cardCaptionBold,
                      ).toTextStyle().copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _outcomeColor(TaskEvidenceOutcome outcome, BridgeDSColors ds) {
    switch (outcome) {
      case TaskEvidenceOutcome.completed:
        return ds.accentGreen;
      case TaskEvidenceOutcome.partial:
        return ds.accentYellow;
      case TaskEvidenceOutcome.failed:
        return ds.accentRed;
    }
  }

  IconData _kindIcon(TaskEvidenceKind kind) {
    switch (kind) {
      case TaskEvidenceKind.image:
        return Icons.image_outlined;
      case TaskEvidenceKind.document:
        return Icons.description_outlined;
      case TaskEvidenceKind.search:
        return Icons.travel_explore_outlined;
      case TaskEvidenceKind.canvas:
        return Icons.account_tree_outlined;
      case TaskEvidenceKind.file:
        return Icons.folder_outlined;
      case TaskEvidenceKind.delegation:
        return Icons.call_split_outlined;
      case TaskEvidenceKind.capability:
        return Icons.extension_outlined;
      case TaskEvidenceKind.other:
        return Icons.check_circle_outline;
    }
  }
}
