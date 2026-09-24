// door_bar.dart
// F2 底部專案門條 — 當前門 + 進度 + 選節點歸入門
// B2 Phase 1.5 Open Canvas 統一設計
//
// 設計文件: open-canvas-unified-design.md §3.3

import 'package:bridge_app/models/flow_step.dart';
import 'package:bridge_app/models/project_door.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';

/// 底部專案門條。
///
/// 顯示當前專案門和進度，支援把選中的畫布節點歸入門成為 flowStep。
class DoorBar extends StatefulWidget {
  /// 當前選中的畫布節點 ID 列表（用於「歸入此門」按鈕）。
  final Set<String> selectedNodeIds;

  /// 當使用者把選中節點歸入門時呼叫。
  final void Function(String doorId, Set<String> nodeIds)? onAssignToDoor;

  /// 當使用者切換門時呼叫。
  final void Function(ProjectDoor? door)? onDoorChanged;

  const DoorBar({
    super.key,
    required this.selectedNodeIds,
    this.onAssignToDoor,
    this.onDoorChanged,
  });

  @override
  State<DoorBar> createState() => _DoorBarState();
}

class _DoorBarState extends State<DoorBar> {
  final _doorStore = ProjectDoorStore();
  List<ProjectDoor> _doors = [];
  ProjectDoor? _activeDoor;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDoors();
  }

  Future<void> _loadDoors() async {
    final doors = await _doorStore.loadAll();
    final active = await _doorStore.loadActive();
    if (mounted) {
      setState(() {
        _doors = doors;
        _activeDoor = active ?? (doors.isNotEmpty ? doors.first : null);
      });
      widget.onDoorChanged?.call(_activeDoor);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeDoor == null) {
      return _buildEmptyBar();
    }
    return _buildDoorBar();
  }

  Widget _buildEmptyBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        border: Border(
          top: BorderSide(color: BridgeDSColors.of(context).borderSubtle, width: 1),
        ),
      ),
      child: Center(
        child: Text(
          '🚩 尚無專案門 — 在專案 tab 建立門後可在此追蹤',
          style: BridgeDSColors.of(context).caption.copyWith(
            color: BridgeDSColors.of(context).textMuted,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildDoorBar() {
    final door = _activeDoor!;
    final hasSelection = widget.selectedNodeIds.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        border: Border(
          top: BorderSide(color: BridgeDSColors.of(context).borderSubtle, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 主條（永遠顯示）
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceLG),
              child: Row(
                children: [
                  // 門圖示
                  Icon(Icons.door_sliding,
                      color: BridgeDSColors.of(context).accentYellow, size: 18),
                  SizedBox(width: 8),
                  // 門名
                  Text(
                    door.title,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                      fontWeight: FontWeight.w500,),
                  ),
                  SizedBox(width: 10),
                  // 狀態標籤
                  _statusBadge(door.status),
                  SizedBox(width: 10),
                  // 進度
                  if (door.totalFlowCount > 0) ...[
                    SizedBox(
                      width: 100,
                      child: LinearProgressIndicator(
                        value: door.flowProgress,
                        backgroundColor: BridgeDSColors.of(context).surface,
                        valueColor: AlwaysStoppedAnimation(
                            BridgeDSColors.of(context).accentGreen),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '${door.completedFlowCount}/${door.totalFlowCount}',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                    ),
                  ],
                  Spacer(),
                  // 歸入此門按鈕（有選中節點時顯示）
                  if (hasSelection) ...[
                    _buildAssignButton(door),
                    SizedBox(width: 8),
                  ],
                  // 門切換下拉
                  if (_doors.length > 1)
                    Icon(
                      _isExpanded
                          ? Icons.expand_more
                          : Icons.chevron_left,
                      color: BridgeDSColors.of(context).textMuted,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
          // 展開的 flowSteps
          if (_isExpanded && door.flowSteps.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.symmetric(
                  horizontal: BridgeDS.spaceLG, vertical: 4),
              child: SingleChildScrollView(
                child: Row(
                  children: door.flowSteps.asMap().entries.map((entry) {
                    final i = entry.key;
                    final step = entry.value;
                    return _buildFlowStepChip(step, i);
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        _statusLabel(status),
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color,),
      ),
    );
  }

  Widget _buildAssignButton(ProjectDoor door) {
    return GestureDetector(
      onTap: () => widget.onAssignToDoor?.call(door.id, widget.selectedNodeIds),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BridgeDSColors.of(context).accentGreen, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_turned_in,
                color: BridgeDSColors.of(context).accentGreen, size: 14),
            SizedBox(width: 4),
            Text(
              '歸入此門 (${widget.selectedNodeIds.length})',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen,),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowStepChip(FlowStep step, int index) {
    final color = _stepColor(step.status);
    final isLast = index == _activeDoor!.flowSteps.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_stepIcon(step.status), color: color, size: 12),
              SizedBox(width: 4),
              Text(
                step.title,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color,),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right,
                color: BridgeDSColors.of(context).textMuted, size: 14),
          ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
      case 'in_progress':
        return BridgeDSColors.of(context).accentGreen;
      case 'paused':
        return BridgeDSColors.of(context).accentYellow;
      case 'completed':
        return BridgeDSColors.of(context).accentBlue;
      case 'blocked':
        return BridgeDSColors.of(context).accentRed;
      default:
        return BridgeDSColors.of(context).textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
      case 'in_progress':
        return '進行中';
      case 'paused':
        return '暫停';
      case 'completed':
        return '已完成';
      case 'blocked':
        return '受阻';
      default:
        return status;
    }
  }

  Color _stepColor(String status) {
    switch (status) {
      case 'done':
        return BridgeDSColors.of(context).accentGreen;
      case 'in_progress':
        return BridgeDSColors.of(context).accentBlue;
      case 'blocked':
        return BridgeDSColors.of(context).accentRed;
      default:
        return BridgeDSColors.of(context).textMuted;
    }
  }

  IconData _stepIcon(String status) {
    switch (status) {
      case 'done':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.autorenew;
      case 'blocked':
        return Icons.block;
      default:
        return Icons.radio_button_unchecked;
    }
  }
}
