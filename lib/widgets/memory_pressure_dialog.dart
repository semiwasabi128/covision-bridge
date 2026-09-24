// memory_pressure_dialog.dart
// [教練 Agent 2026-07-22] #4 L2: 記憶體壓力對話框
//
// 紅燈（85-95% RAM）時彈出，讓使用者選擇要關閉什麼來釋放記憶體：
// 1. 關閉本地模型（llama-server）— 最顯眼選項，使用者 指示大部分關掉就夠了
// 2. 勾選其他背景程序（按 RAM 排序列出）
// 3. 稍後處理（不關任何東西，但 App 會在 L1 暫停狀態）

import 'package:flutter/material.dart';
import '../services/memory_guard_service.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class MemoryPressureDialog extends StatefulWidget {
  final MemoryGuardService guard;

  const MemoryPressureDialog({super.key, required this.guard});

  /// 顯示對話框的便捷方法
  static Future<void> show(BuildContext context, MemoryGuardService guard) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => MemoryPressureDialog(guard: guard),
    );
  }

  @override
  State<MemoryPressureDialog> createState() => _MemoryPressureDialogState();
}

class _MemoryPressureDialogState extends State<MemoryPressureDialog> {
  List<MemoryProcessInfo> _processes = [];
  final Set<int> _selectedPids = {};
  bool _killLocalModel = false;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadProcesses();
  }

  Future<void> _loadProcesses() async {
    final processes = await widget.guard.listTopMemoryProcesses();
    if (mounted) {
      setState(() {
        _processes = processes;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    setState(() => _processing = true);

    // 1. 關閉本地模型（如果選了）
    if (_killLocalModel) {
      await widget.guard.killLocalModelServer();
    }

    // 2. 殺掉選中的程序
    for (final pid in _selectedPids) {
      await widget.guard.killProcess(pid);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.memory, color: colors.accentRed, size: 24),
          const SizedBox(width: 8),
          Text('記憶體不足', style: colors.headingS),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 說明文字
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.accentRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.accentRed.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: colors.accentRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '系統記憶體使用率 ${widget.guard.usagePercent}%，'
                      '建議關閉部分程序以維持系統穩定。',
                      style: colors.body
                          .copyWith(color: colors.textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BridgeDS.spaceMD),

            // 本地模型選項 — 最顯眼
            _buildLocalModelOption(colors),
            const SizedBox(height: BridgeDS.spaceMD),

            // 其他程序列表
            Text('其他背景程序', style: colors.caption.copyWith(
              color: colors.textTertiary,
              fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_processes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('沒有偵測到其他高記憶體程序',
                    style: colors.caption.copyWith(color: colors.textMuted)),
              )
            else
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _processes.length,
                    itemBuilder: (ctx, i) => _buildProcessItem(
                      colors, _processes[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _processing
              ? null
              : () => Navigator.of(context).pop(),
          child: Text('稍後處理', style: colors.body.copyWith(
            color: colors.textTertiary,
          )),
        ),
        FilledButton.icon(
          onPressed: _processing ? null : _confirm,
          icon: _processing
              ? SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                    color: colors.textPrimary))
              : const Icon(Icons.check_circle_outline, size: 18),
          label: Text(_processing ? '處理中...' : '確認關閉'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.accentRed,
            foregroundColor: BridgeDSColors.of(context).textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  /// 本地模型關閉選項 — 最顯眼的大卡片
  Widget _buildLocalModelOption(BridgeDSColors colors) {
    return FutureBuilder<bool>(
      future: widget.guard.isLocalServerRunning(),
      builder: (ctx, snap) {
        final isRunning = snap.data ?? false;
        if (!isRunning) {
          // 本地模型沒在跑 — 不顯示這個選項
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: () => setState(() => _killLocalModel = !_killLocalModel),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _killLocalModel
                  ? colors.accentRed.withValues(alpha: 0.10)
                  : colors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _killLocalModel
                    ? colors.accentRed
                    : colors.borderDefault,
                width: _killLocalModel ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _killLocalModel
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _killLocalModel
                      ? colors.accentRed
                      : colors.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.psychology,
                              color: colors.accentPurple, size: 16),
                          const SizedBox(width: 6),
                          Text('關閉本地模型',
                              style: colors.body.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '關閉 llama-server 可立即釋放大量記憶體。\n'
                        '需要時可隨時重新啟動。',
                        style: colors.caption.copyWith(
                          color: colors.textTertiary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.local_fire_department,
                    color: colors.accentRed.withValues(alpha: 0.6), size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 單一程序列表項
  Widget _buildProcessItem(BridgeDSColors colors, MemoryProcessInfo proc) {
    final isSelected = _selectedPids.contains(proc.pid);
    return GestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedPids.remove(proc.pid);
        } else {
          _selectedPids.add(proc.pid);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accentRed.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: colors.borderSubtle.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: isSelected ? colors.accentRed : colors.textMuted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                proc.name,
                style: colors.body.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: proc.ramMB > 500
                    ? colors.accentRed.withValues(alpha: 0.12)
                    : proc.ramMB > 200
                        ? colors.accentYellow.withValues(alpha: 0.12)
                        : colors.surfaceHover,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${proc.ramMB} MB',
                style: colors.caption.copyWith(
                  fontSize: 14,
                  color: proc.ramMB > 500
                      ? colors.accentRed
                      : proc.ramMB > 200
                          ? colors.accentYellow
                          : colors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
