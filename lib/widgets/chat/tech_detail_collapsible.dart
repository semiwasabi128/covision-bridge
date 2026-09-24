import 'package:flutter/material.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// [小葵 2026-09-22 0.2] 白話鐵則 UI 配套——訊息氣泡的技術細節摺疊區。
/// prompt 端（agent_loop / agent_loop_prompt_builder 白話鐵則）要求 LLM
/// 把技術細節放在「【技術細節】」獨立標記之後。本 widget 負責：
/// - 標記之前的白話正文 → 直接顯示
/// - 標記之後的技術內容 → 摺疊成「技術細節」可展開區塊（工程師/開發者
///   使用者想看再點開），預設收合。
///
/// 沒有標記的訊息完全不受影響（原樣渲染）。
class PlainTechSplit {
  PlainTechSplit(this.plain, this.tech);

  final String plain;
  final String? tech;

  static const marker = '【技術細節】';

  /// 把訊息切成白話/技術兩段；沒有標記回傳 null（呼叫端原樣渲染）。
  static PlainTechSplit? tryParse(String content) {
    final idx = content.indexOf(marker);
    if (idx < 0) return null;
    final plain = content.substring(0, idx).trimRight();
    final tech = content.substring(idx + marker.length).trim();
    if (tech.isEmpty) return null;
    return PlainTechSplit(plain, tech);
  }
}

class TechDetailCollapsible extends StatefulWidget {
  const TechDetailCollapsible({super.key, required this.tech});

  final String tech;

  @override
  State<TechDetailCollapsible> createState() => _TechDetailCollapsibleState();
}

class _TechDetailCollapsibleState extends State<TechDetailCollapsible> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terminal_outlined,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _expanded ? '收起技術細節' : '技術細節',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceElevated.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: SelectableText(
                widget.tech,
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                      // 等寬親和：技術細節含 ID/參數，對齊易讀
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
