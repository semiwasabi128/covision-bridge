// data_path_badge.dart
// [資料主權 P0-c 2026-09-14] 資料路徑徽章——讓使用者在選模型的當下
// 就看見「你的資料會去哪」（人機共視的資料路徑版）。
// 提案：docs/specs/2026-09-14-data-sovereignty-design.md §4.2
//
// 三級（與 DataPathGate 同源，不重複定義邏輯——只做呈現）：
//   🟢 本地封閉迴路：資料不出這台機器
//   🟡 BYOK 直連：你的金鑰直連該 provider，橋樑不經手
//   🔴 未知去路：不應出現（gate 會攔截）；出現即警示
//
// 文案鐵則：內部語法永不示人——只講「資料去哪」，不講 endpoint 內部細節。

import 'package:flutter/material.dart';

import '../../services/provider_registry.dart';
import '../../services/sovereignty/data_path_gate.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 判定 provider 的資料路徑分級（UI 側輕量判定，與 gate 同規則）。
DataPathGrade dataPathGradeForProvider(String providerId) {
  if (providerId == 'local' || providerId == 'ollama') {
    return DataPathGrade.green;
  }
  if (providerId == 'default') {
    // 「預設」= 動態路由，依當下選到的實際 provider；
    // 無法靜態判定時保守顯示黃（直連 provider）。
    return DataPathGrade.yellow;
  }
  return ProviderRegistry.cloudProviderIds.contains(providerId)
      ? DataPathGrade.yellow
      : DataPathGrade.red;
}

/// 小圓點徽章——放在模型選單每個選項的右側。
class DataPathBadge extends StatelessWidget {
  final DataPathGrade grade;
  final bool compact; // true=只有圓點（選單列內）；false=圓點+短語（按鈕/詳情）

  const DataPathBadge({super.key, required this.grade, this.compact = true});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final (dotColor, label) = switch (grade) {
      DataPathGrade.green => (colors.accentGreen, '本地'),
      DataPathGrade.yellow => (colors.accentYellow, '直連'),
      DataPathGrade.red => (colors.accentRed, '未知'),
    };
    if (compact) {
      return Tooltip(
        message: grade.label,
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
      );
    }
    return Tooltip(
      message: grade.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TierStyle.of(context, Tier.listItemMeta)
                .toTextStyle()
                .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
