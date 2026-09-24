// layer_source_chip.dart
// Sprint 6 — 層來源標籤 chip，點擊可切換 AI/規則版（單層 override）
// 建立日期: 2026-07-04 by 教練 Agent (CEO)

import 'package:flutter/material.dart';

import '../../services/brain_pipeline/layer_result.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 層來源標籤。
///
/// 顯示目前來源（AI / 規則 / 混合 / 快取），點擊可 toggle 強制模式。
/// [onToggle] 為 null 時不可互動（唯讀模式）。
class LayerSourceChip extends StatelessWidget {
  final LayerSource source;
  final LayerOverrideMode? overrideMode;

  /// 點擊時觸發，null 表示唯讀
  final VoidCallback? onToggle;

  const LayerSourceChip({
    super.key,
    required this.source,
    this.overrideMode,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isOverridden = overrideMode != null;
    final effectiveLabel = isOverridden
        ? (overrideMode == LayerOverrideMode.ai ? 'AI⚡' : '規則🔒')
        : _sourceLabel(source);
    final effectiveColor = isOverridden
        ? (overrideMode == LayerOverrideMode.ai
            ? AppTheme.secondary
            : BridgeDSColors.of(context).textMuted)
        : _sourceColor(source);

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: effectiveColor.withValues(alpha: 0.25),
            width: isOverridden ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          effectiveLabel,
          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
            color: effectiveColor,),
        ),
      ),
    );
  }

  String _sourceLabel(LayerSource s) {
    return switch (s) {
      LayerSource.ai => 'AI',
      LayerSource.rule => '規則',
      LayerSource.mixed => '混合',
      LayerSource.cached => '快取',
    };
  }

  Color _sourceColor(LayerSource s) {
    return switch (s) {
      LayerSource.ai => AppTheme.secondary,
      LayerSource.rule => BridgeDS.textMuted,
      LayerSource.mixed => BridgeDS.accentPurple,
      LayerSource.cached => BridgeDS.textSecondary,
    };
  }
}

/// 單層強制模式（使用者手動 override）
enum LayerOverrideMode { ai, rule }
