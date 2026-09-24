// capability_maturity_badge.dart
// [刀 6 K6.5 2026-09-08] Buzz 式誠實分級三態標記——✅可用／🚧接線中／💭設計中
//
// 「UI 誠實鐵則」從錯誤顯示推廣到能力宣示（七刀報告 §4.6）。
// 使用者一眼看到：這個能力是完整能用的、還是半成品、還是計畫中。
//
// 分級由各能力卡片自評（不集中定義——能力狀態只有該能力的維護者知道）。

import 'package:flutter/material.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

enum CapabilityMaturity {
  ready('✅ 可用'),
  wiring('🚧 接線中'),
  planned('💭 設計中');

  final String label;
  const CapabilityMaturity(this.label);
}

class CapabilityMaturityBadge extends StatelessWidget {
  final CapabilityMaturity maturity;

  const CapabilityMaturityBadge({super.key, required this.maturity});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final (color, tip) = switch (maturity) {
      CapabilityMaturity.ready => (
          ds.accentGreen,
          '功能完整、體檢通過、記帳健全'
        ),
      CapabilityMaturity.wiring => (
          ds.accentYellow,
          '功能可跑，但部分路徑未完整接線（例如 Ledger 未全接）'
        ),
      CapabilityMaturity.planned => (
          ds.textMuted,
          '規劃中、尚未實作'
        ),
    };
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          maturity.label,
          style: TierStyle.of(context, Tier.cardCaptionBold)
              .toTextStyle()
              .copyWith(color: color),
        ),
      ),
    );
  }
}
