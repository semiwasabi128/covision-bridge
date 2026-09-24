// [教練 Agent Sprint 17 Step 10 2026-07-07]
// Skill 快捷面板 widget — 從 chat_screen.dart build() 提取。
import 'package:flutter/material.dart';

import '../../../services/intent_classifier.dart';
import '../cards/misc_card_widgets.dart';

class SkillChipPanel extends StatelessWidget {
  final void Function(UserIntent intent, String skillCommand) onSelect;

  const SkillChipPanel({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SkillChip(
            label: '🔍 釐清需求',
            onPressed: () => onSelect(UserIntent.chat, '/grill-me'),
          ),
          SkillChip(
            label: '📝 產出規格',
            onPressed: () => onSelect(UserIntent.document, '/to-prd'),
          ),
          SkillChip(
            label: '📋 拆解任務',
            onPressed: () => onSelect(UserIntent.document, '/to-issues'),
          ),
          SkillChip(
            label: '🧪 測試驅動',
            onPressed: () => onSelect(UserIntent.review, '/tdd'),
          ),
          SkillChip(
            label: '🐛 系統除錯',
            onPressed: () => onSelect(UserIntent.review, '/diagnose'),
          ),
          SkillChip(
            label: '🚀 快速驗證',
            onPressed: () => onSelect(UserIntent.creative, '/prototype'),
          ),
          SkillChip(
            label: '🌍 全局視角',
            onPressed: () => onSelect(UserIntent.chat, '/zoom-out'),
          ),
        ],
      ),
    );
  }
}
