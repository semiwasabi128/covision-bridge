// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 桌面工作狀態面板：從 chat_screen.dart _buildInlineWorkStatusPanel 提取。
import 'package:flutter/material.dart';

import '../../../models/agent_activity.dart';
import '../../../models/companion.dart';
import '../../../models/companion_runtime.dart';
import '../../../services/companion_runtime_store.dart';
import '../../../services/companion_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/bridge_cards/companion_status_helper.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 桌面工作狀態面板：顯示夥伴運行狀態的即時面板。
class InlineWorkStatusPanel extends StatelessWidget {
  /// 傳入的 active companion（如果 CompanionStore 沒有就回退用這個）。
  final Companion? activeCompanion;

  /// 將 mood snapshot 轉成動作標籤的字串。
  final String Function(AgentActivitySnapshot snapshot) moodActionLabel;

  const InlineWorkStatusPanel({
    super.key,
    this.activeCompanion,
    required this.moodActionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CompanionRuntimeState>(
      valueListenable: CompanionRuntimeStore.instance.state,
      builder: (context, runtime, _) {
        final snapshot = runtime.activity;
        final companion = CompanionStore().activeCompanion ?? activeCompanion;
        final statusSpec = CompanionStatusHelper.statusSpecForRuntime(runtime);
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: AppTheme.primary.withValues(
                alpha: snapshot.active || snapshot.pulse ? 0.30 : 0.16,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(
                  alpha: snapshot.pulse ? 0.12 : 0.04,
                ),
                blurRadius: snapshot.pulse ? 18 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CompanionStatusHelper.buildStatusPreviewImage(
                  runtime: runtime,
                  companion: companion,
                  spec: statusSpec,
                  size: 52,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.monitor_heart_outlined,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '桌面工作狀態 · ${runtime.activeCompanionName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w900,),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${runtime.statusText}｜${snapshot.stage.shortLabel}｜${moodActionLabel(snapshot)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        height: 1.25,
                        fontWeight: FontWeight.w700,),
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
