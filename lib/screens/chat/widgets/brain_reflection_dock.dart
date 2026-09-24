// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 思維面板 dock：從 chat_screen.dart _buildBrainReflectionDock 提取。
// 根據 reflection 是否存在 + _showBrainReflectionPanel 控制摘要/展開切換。
import 'package:flutter/material.dart';

import 'brain_reflection_expanded_content.dart';
import 'brain_reflection_panel_data.dart';
import 'brain_reflection_standby_dock.dart';

/// 思維面板 dock：控制判斷線索的摘要/展開/待命三態。
///
/// - reflection == null → 待命狀態
/// - !_showPanel → 摘要按鈕
/// - _showPanel → 展開內容
class BrainReflectionDock extends StatefulWidget {
  final BrainReflectionPanelData? data;
  final bool showPanel;
  final void Function(bool show) onTogglePanel;

  const BrainReflectionDock({
    super.key,
    required this.data,
    required this.showPanel,
    required this.onTogglePanel,
  });

  @override
  State<BrainReflectionDock> createState() => _BrainReflectionDockState();
}

class _BrainReflectionDockState extends State<BrainReflectionDock> {
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data == null) {
      return const BrainReflectionStandbyDock();
    }

    if (!widget.showPanel) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => widget.onTogglePanel(true),
          icon: const Icon(Icons.psychology_alt_outlined, size: 16),
          label: const Text('顯示判斷線索'),
        ),
      );
    }

    return BrainReflectionExpandedContent(
      data: data,
      onCollapse: () => widget.onTogglePanel(false),
    );
  }
}
