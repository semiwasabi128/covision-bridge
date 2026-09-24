// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 釘選的思維儀表狀態條：從 chat_screen.dart _buildPinnedBrainStatusStrip 提取。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/brain_reflection_panel.dart';
import 'brain_reflection_panel_data.dart';

/// 釘選狀態條：顯示 BrainInstrumentStatusStrip。
class PinnedBrainStatusStrip extends StatelessWidget {
  final BrainReflectionPanelData data;

  const PinnedBrainStatusStrip({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: BrainInstrumentStatusStrip(reflection: data.reflection),
    );
  }
}
