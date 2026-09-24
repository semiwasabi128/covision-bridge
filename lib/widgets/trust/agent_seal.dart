// agent_seal.dart
// [Blue 令 2026-09-12] Agent 蓋章制度——「橋樑的城牆每一塊磚都有 Agent 的簽名」。
//
// 羅盤規則、決策紀錄、工作真相（Ledger）……凡是 Agent 留下的紀錄，
// 旁邊都要有他的指紋縮圖——蓋章的感覺。
//
// 作者字串格式（現存資料）：
//   'agent:小葵（S4 統一令落地）'  → 夥伴章（AgentGlyph 指紋）
//   'auto:harvest'               → 系統章（齒輪）
//   'user:Blue' / 'Blue'         → Blue 章（👑）
// 解析後反查 CompanionStore：找到 → 該夥伴的指紋；
// 找不到（如未建卡的 agent）→ 用名字本身的 hash 生成指紋（同 ID 必同臉）。

import 'package:flutter/material.dart';
import 'package:bridge_app/services/companion_store.dart';
import 'package:bridge_app/widgets/trust/agent_glyph.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';

/// 蓋章——誰在這塊磚上簽了名
class AgentSeal extends StatelessWidget {
  /// 作者字串（CompassRule.updatedBy / Ledger 作者欄）
  final String author;

  /// 章的大小（配合所在行高）
  final double size;

  const AgentSeal({super.key, required this.author, this.size = 18});

  /// 解析作者字串 → (kind, 名字)
  static (String kind, String name) parse(String author) {
    final a = author.trim();
    if (a.startsWith('agent:')) {
      final rest = a.substring(6);
      // '小葵（S4 統一令落地）' → 取括號前名字
      final paren = rest.indexOf('（');
      final paren2 = rest.indexOf('(');
      final cut = paren >= 0 && (paren2 < 0 || paren < paren2) ? paren : paren2;
      return ('agent', cut > 0 ? rest.substring(0, cut).trim() : rest);
    }
    if (a.startsWith('auto:')) return ('auto', a.substring(5));
    if (a.startsWith('user:')) return ('user', a.substring(5));
    if (a == 'Blue' || a.contains('Blue')) return ('user', 'Blue');
    return ('agent', a);
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final (kind, name) = parse(author);

    switch (kind) {
      case 'auto':
        return Tooltip(
          message: '系統自動（$name）',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: ds.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: ds.borderDefault),
            ),
            child: Icon(Icons.settings_suggest_outlined,
                size: size * 0.6, color: ds.textMuted),
          ),
        );
      case 'user':
        return Tooltip(
          message: 'Blue（拍板）',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: ds.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: ds.accentYellow.withOpacity(0.5)),
            ),
            child:
                Text('👑', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: size * 0.55, height: 1.5)),
          ),
        );
      default: // agent——指紋章
        final companionId = _safeLookupId(name) ?? 'agent:$name';
        return Tooltip(
          message: name,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: ds.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: ds.borderDefault),
            ),
            child: OverflowBox(
              maxWidth: size,
              maxHeight: size,
              child: AgentGlyph(
                companionId: companionId,
                name: name,
                size: size,
                showInitial: false, // 章只要圖騰不要字——更像印章
              ),
            ),
          ),
        );
    }
  }

  String? _safeLookupId(String name) {
    try {
      return CompanionStore()
          .all
          .firstWhere((c) => c.name == name)
          .id;
    } catch (_) {
      return null;
    }
  }
}
