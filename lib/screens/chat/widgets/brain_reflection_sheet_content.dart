// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// Bottom sheet 專用的判斷線索面板：從 chat_screen.dart _buildBrainReflectionSheetContent 提取。
// 用獨立的 _showSheetPanel 狀態（由外部 StatefulWidget 管理），不依賴 parent 的 _showBrainReflectionPanel。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'brain_reflection_panel_data.dart';
import 'pinned_brain_status_strip.dart';

/// Bottom sheet 判斷線索面板。
///
/// 摘要階段：顯示按鈕 + status strip。
/// 展開階段：完整面板 + 收起按鈕。
class BrainReflectionSheetContent extends StatefulWidget {
  final BrainReflectionPanelData data;

  const BrainReflectionSheetContent({super.key, required this.data});

  @override
  State<BrainReflectionSheetContent> createState() =>
      _BrainReflectionSheetContentState();
}

class _BrainReflectionSheetContentState
    extends State<BrainReflectionSheetContent> {
  bool _showSheetPanel = false;

  @override
  Widget build(BuildContext context) {
    if (!_showSheetPanel) {
      // 摘要階段
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showSheetPanel = true),
                icon: const Icon(Icons.psychology_alt_outlined, size: 16),
                label: const Text('顯示判斷線索'),
              ),
            ),
            const SizedBox(height: 8),
            PinnedBrainStatusStrip(data: widget.data),
          ],
        ),
      );
    }

    // 展開階段
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                onPressed: () => setState(() => _showSheetPanel = false),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: widget.data.toWidget(),
            ),
          ),
        ],
      ),
    );
  }
}
