// vault_entry_card.dart
// [教練 Agent 2026-07-28] 從 vault_screen.dart 抽出 — 條目卡片 Widget
//
// 獨立的 StatelessWidget，顯示 VaultEntry 摘要卡片

import 'package:flutter/material.dart';
import '../../theme/bridge_design_system.dart';
import '../../services/vault/vault_service.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 向量資料庫條目卡片
class VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final bool isSelected;
  final bool isCardWall;
  final VoidCallback onTap;

  const VaultEntryCard({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    this.isCardWall = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        decoration: BoxDecoration(
          color: isSelected
              ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.08)
              : BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.3)
                : BridgeDSColors.of(context).borderSubtle,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // [教練 Agent 2026-07-28] 修復 unbounded height
          children: [
            // 標籤列
            if (entry.tags.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: entry.tags.take(3).map((tag) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context)
                          .accentPurple
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$tag',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 8),

            // 摘要
            // [教練 Agent 2026-07-28] 移除 Expanded — 在 ListView unbounded height 裡會 crash
            Text(
              entry.summary,
              maxLines: isCardWall ? 4 : 2,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.4,
                color: BridgeDSColors.of(context).textPrimary,),
            ),

            // 底部資訊列
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  entry.typeLabel,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.createdAt.month}/${entry.createdAt.day}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                ),
                const Spacer(),
                if (entry.linkCount > 0)
                  Row(
                    children: [
                      Icon(Icons.link,
                          size: 12,
                          color: BridgeDSColors.of(context).textMuted),
                      const SizedBox(width: 2),
                      Text(
                        '${entry.linkCount}',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                      ),
                    ],
                  ),
                if (entry.backlinkCount > 0) ...[
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      Icon(Icons.reply,
                          size: 12,
                          color: BridgeDSColors.of(context).textMuted),
                      const SizedBox(width: 2),
                      Text(
                        '${entry.backlinkCount}',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
