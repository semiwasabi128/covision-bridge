// swarm_legion_card.dart
// [TRIO M4 2026-09-22] L3 兵團卡——蜂群戰役的任務卡展開視圖
//
// AgentsRoom 卡片網格精神 × 房間四象限：每兵一格狀態燈。
// 讀取端：SwarmCommand（戰役）＋AgentStatusStore（狀態）——同一真相源。
// 顏色走 BridgeDSColors；字級走 Tier（AlertDialog 鐵則同規範）。
library;

import 'package:flutter/material.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

/// 兵團卡——嵌入任務卡展開態或獨立對話 widget
class SwarmLegionCard extends StatelessWidget {
  const SwarmLegionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SwarmCommand.instance,
        AgentStatusStore.instance,
      ]),
      builder: (context, _) {
        final c = SwarmCommand.instance.active;
        if (c == null || c.phase == SwarmPhase.aborted) {
          return const SizedBox.shrink();
        }
        final ds = BridgeDSColors.of(context);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ds.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: c.phase == SwarmPhase.running
                  ? ds.accentGreen
                  : ds.borderSubtle,
              width: c.phase == SwarmPhase.running ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 標題列
              Row(
                children: [
                  Text('⚔️ 蜂群作戰', style: _tier(context, Tier.cardTitle)),
                  const Spacer(),
                  _phaseChip(context, c.phase),
                ],
              ),
              const SizedBox(height: 6),
              Text(c.objective,
                  style: _tier(context, Tier.cardBody),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('終點：${c.endpoint}',
                  style: _tier(context, Tier.cardCaption),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),

              // 六關進度條（planning 期）
              if (c.phase == SwarmPhase.planning) ...[
                Row(
                  children: [
                    for (final g in SwarmGate.values)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 6,
                          decoration: BoxDecoration(
                            color: g.index < c.gatesPassed
                                ? ds.accentGreen
                                : ds.surface,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    '開戰閘門 ${c.gatesPassed}/6——'
                    '${SwarmGate.values[c.gatesPassed.clamp(0, 5)].label}進行中',
                    style: _tier(context, Tier.listItemMeta)),
              ],

              // 成本試算摘要（G5 過後）
              if (c.cost != null) ...[
                const Divider(height: 16),
                Text(
                    '試算：\$${c.cost!.moneyCost.toStringAsFixed(2)}／'
                    '${c.cost!.wallClock.inMinutes} 分'
                    '${c.cost!.budgetCap != null ? '（上限 \$${c.cost!.budgetCap}）' : ''}',
                    style: _tier(context, Tier.listItemMeta)),
              ],

              // 戰後對帳（done）
              if (c.actual != null) ...[
                const Divider(height: 16),
                Text(
                    '實際：\$${c.actual!.moneySpent.toStringAsFixed(2)}／'
                    '${c.actual!.wallClockActual.inMinutes} 分',
                    style: _tier(context, Tier.listItemMeta)),
              ],
            ],
          ),
        );
      },
    );
  }

  TextStyle _tier(BuildContext context, Tier tier) =>
      TierStyle.of(context, tier).toTextStyle();

  Widget _phaseChip(BuildContext context, SwarmPhase phase) {
    final ds = BridgeDSColors.of(context);
    final (label, color) = switch (phase) {
      SwarmPhase.planning => ('規劃中', ds.accentYellow),
      SwarmPhase.committed => ('已開戰', ds.accentRed),
      SwarmPhase.running => ('作戰中', ds.accentGreen),
      SwarmPhase.reviewing => ('驗收中', ds.accentBlue),
      SwarmPhase.done => ('完戰', ds.textMuted),
      SwarmPhase.aborted => ('已棄案', ds.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: _tier(context, Tier.listItemMeta)
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
