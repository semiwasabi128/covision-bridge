// [以利沙 Sprint 7 2026-06-24] 從 chat_screen.dart 抽出 CompanionPresenceLayer widget
// 原始位置：chat_screen.dart 行 4360-4524（_buildCompanionPresenceLayer 及其兩個子方法）
// 純 StatelessWidget，只搬移 UI，不改業務邏輯。

import 'package:flutter/material.dart';

import '../models/companion.dart';
import '../models/companion_runtime.dart';
import '../services/companion_runtime_store.dart';
import '../services/companion_store.dart';
import '../theme/app_theme.dart';
import 'bridge_cards/companion_status_helper.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../theme/bridge_design_system.dart';

/// [以利沙 Sprint 7 2026-06-24] 桌面夥伴浮層。
///
/// 原 chat_screen.dart `_ChatScreenState._buildCompanionPresenceLayer`，
/// 連同 `_buildPresenceToggleButton`、`_buildCompanionPresenceAvatar` 一起搬入。
class CompanionPresenceLayer extends StatelessWidget {
  final bool showCompanionPresence;
  final VoidCallback onTogglePresence;
  final bool showSidebar;
  final bool showStatusTestPanel;
  final Companion? activeCompanion;

  const CompanionPresenceLayer({
    super.key,
    required this.showCompanionPresence,
    required this.onTogglePresence,
    required this.showSidebar,
    this.showStatusTestPanel = false, // // [以利沙 手機精簡 Phase1 2026-06-27] 改為 optional
    required this.activeCompanion,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidePanelWidth = showStatusTestPanel
              ? MediaQuery.of(context).size.width >= 1100
                    ? 420.0
                    : 340.0
              : 0.0;
          final sidebarWidth = showSidebar ? 280.0 : 0.0;
          final usableWidth =
              constraints.maxWidth - sidePanelWidth - sidebarWidth;
          if (usableWidth < 420 || constraints.maxHeight < 420) {
            return const SizedBox.shrink();
          }

          final avatarSize = (usableWidth * 0.35)
              .clamp(180.0, 320.0)
              .toDouble();
          final rightInset =
              sidePanelWidth +
              (usableWidth * 0.035).clamp(14.0, 30.0).toDouble();
          final bottomInset = constraints.maxHeight < 700 ? 92.0 : 118.0;

          return Stack(
            children: [
              if (!showCompanionPresence)
                Positioned(
                  right: rightInset,
                  bottom: bottomInset,
                  child: _buildPresenceToggleButton(context, expanded: false),
                )
              else
                Positioned(
                  right: rightInset,
                  bottom: bottomInset,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildPresenceToggleButton(context, expanded: true),
                      const SizedBox(height: 6),
                      IgnorePointer(
                        child: _buildCompanionPresenceAvatar(size: avatarSize),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // [以利沙 Sprint 7 2026-06-24] 原行 4415-4440，setState 改為 onTogglePresence 回呼
  Widget _buildPresenceToggleButton(BuildContext context, {required bool expanded}) {
    return Tooltip(
      message: expanded ? '收起桌面夥伴' : '顯示桌面夥伴',
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: expanded
              ? AppTheme.surface.withValues(alpha: 0.82)
              : AppTheme.primary.withValues(alpha: 0.92),
          foregroundColor: expanded ? AppTheme.primaryDark : BridgeDSColors.of(context).textPrimary,
          side: BorderSide(
            color: expanded
                ? AppTheme.primary.withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.28),
          ),
          elevation: 2,
        ),
        icon: Icon(
          expanded ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18,
        ),
        onPressed: onTogglePresence,
      ),
    );
  }

  // [以利沙 Sprint 7 2026-06-24] 原行 4442-4524，_activeCompanion 改為 widget.activeCompanion
  Widget _buildCompanionPresenceAvatar({required double size}) {
    return ValueListenableBuilder<CompanionRuntimeState>(
      valueListenable: CompanionRuntimeStore.instance.state,
      builder: (context, runtime, _) {
        final companion = CompanionStore().activeCompanion ?? activeCompanion;
        final statusSpec = CompanionStatusHelper.statusSpecForRuntime(runtime);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0.04, 0.02),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: Column(
            key: ValueKey(
              'presence-${companion?.id ?? runtime.activeCompanionName}-${statusSpec.id}',
            ),
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                child: CompanionStatusHelper.buildStatusPreviewImage(
                  runtime: runtime,
                  companion: companion,
                  spec: statusSpec,
                  size: size,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                constraints: BoxConstraints(maxWidth: size + 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusSpec.icon, size: 14, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${runtime.activeCompanionName} · ${statusSpec.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
