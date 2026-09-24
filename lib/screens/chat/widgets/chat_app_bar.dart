// [教練 Agent Sprint 17 Step 7 2026-07-07]
// ChatAppBar — 從 chat_screen.dart build() 提取的 AppBar widget。
// 純 UI，所有行為透過 callbacks 注入。
import 'package:flutter/material.dart';

import '../../../models/companion.dart';
import '../../../models/transurfing_brain.dart';
import '../../../theme/app_theme.dart';
import 'app_bar_widgets.dart';
import 'brain_reflection_panel_data.dart';
import 'brain_reflection_sheet_content.dart';
import 'stream_badge.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? conversationTitle;
  final Companion? activeCompanion;
  final String currentMode;
  final bool isUsingLocalModel;
  final int totalTokens;
  final BrainReflection? brainReflection;
  final VoidCallback onOpenDrawer;
  final VoidCallback onTapCompanion;
  final VoidCallback onModelSwitchChanged;
  final VoidCallback onMemory;
  final VoidCallback onNewProjectDoor;
  final VoidCallback onSettings;
  final BrainReflectionPanelData Function() buildBrainReflectionPanelData;

  const ChatAppBar({
    super.key,
    required this.conversationTitle,
    required this.activeCompanion,
    required this.currentMode,
    required this.isUsingLocalModel,
    required this.totalTokens,
    required this.brainReflection,
    required this.onOpenDrawer,
    required this.onTapCompanion,
    required this.onModelSwitchChanged,
    required this.onMemory,
    required this.onNewProjectDoor,
    required this.onSettings,
    required this.buildBrainReflectionPanelData,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: Builder(
        builder: (scaffoldContext) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: onOpenDrawer,
        ),
      ),
      title: buildAppBarTitle(
        context,
        conversationTitle: conversationTitle,
        activeCompanion: activeCompanion,
        currentMode: currentMode,
        onTapCompanion: onTapCompanion,
      ),
      backgroundColor: AppTheme.background,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      actions: [
        // [教練 Agent 2026-08-08] Transurfing：水流狀態徽章
        const Center(child: StreamBadge()),
        const SizedBox(width: 4),
        buildModelSwitchButton(context, onChanged: onModelSwitchChanged),
        if (isUsingLocalModel)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: BridgeDS.successDark.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: BridgeDS.successDark.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '🖥️ 本地模型',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                    color: BridgeDS.successDark,),
                ),
              ),
            ),
          ),
        if (totalTokens > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('用量 $totalTokens'),
                labelStyle: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                backgroundColor: AppTheme.surface,
              ),
            ),
          ),
        Semantics(
          label: '更多選單',
          button: true,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
            onSelected: (value) {
              switch (value) {
                case 'memory':
                  onMemory();
                  break;
                case 'project_door':
                  onNewProjectDoor();
                  break;
                case 'settings':
                  onSettings();
                  break;
                case 'insights':
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (sheetContext) => SafeArea(
                      child: BrainReflectionSheetContent(
                        data: buildBrainReflectionPanelData(),
                      ),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'memory',
                child: Row(
                  children: [
                    Icon(Icons.psychology_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('長期記憶'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'project_door',
                child: Row(
                  children: [
                    Icon(Icons.flag_circle, size: 20),
                    SizedBox(width: 8),
                    Text('新增專案門'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'insights',
                child: Row(
                  children: [
                    Icon(
                      brainReflection != null
                          ? Icons.insights
                          : Icons.insights_outlined,
                      size: 20,
                      color: brainReflection != null
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    const Text('判斷線索與大腦狀態'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 8),
                    Text('設定'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
