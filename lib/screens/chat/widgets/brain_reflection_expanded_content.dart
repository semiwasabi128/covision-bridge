// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 展開的判斷線索面板：從 chat_screen.dart _buildBrainReflectionExpandedContent 提取。
// 用 BrainReflectionPanelData 收參數，onCollapse callback 控制收合。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'brain_reflection_panel_data.dart';

/// 展開的判斷線索面板：收起按鈕 + BrainReflectionPanel。
class BrainReflectionExpandedContent extends StatelessWidget {
  final BrainReflectionPanelData data;
  final VoidCallback onCollapse;
  final double maxHeightFactor;

  const BrainReflectionExpandedContent({
    super.key,
    required this.data,
    required this.onCollapse,
    this.maxHeightFactor = 0.42,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: '收起判斷線索',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.surfaceHighlight,
                foregroundColor: AppTheme.primary,
                side: BorderSide(
                  color: AppTheme.primary.withValues(alpha: 0.20),
                ),
              ),
              onPressed: onCollapse,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * maxHeightFactor,
          ),
          child: SingleChildScrollView(
            child: data.toWidget(),
          ),
        ),
      ],
    );
  }
}
