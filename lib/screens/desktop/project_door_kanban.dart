// [Sprint 18b-3 — 專案門看板]
// ProjectDoorKanban：3-column 看板（進行中 / 等待 / 完成）
// 使用 BridgeDS 設計系統，每張卡片可點擊展開詳情。
// 支援拖曳移動狀態（透過 callback）。

import 'package:flutter/material.dart';

import '../../models/project_door.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class ProjectDoorKanban extends StatelessWidget {
  final List<ProjectDoor> doors;
  final String? selectedDoorId;
  final void Function(ProjectDoor door) onSelect;
  final void Function(String doorId, String newStatus) onMoveDoor;
  final VoidCallback onCreateDoor;
  final void Function(String doorId)? onDeleteDoor;

  const ProjectDoorKanban({
    super.key,
    required this.doors,
    this.selectedDoorId,
    required this.onSelect,
    required this.onMoveDoor,
    required this.onCreateDoor,
    this.onDeleteDoor,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ProjectDoor.kanbanStatuses;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 新增門按鈕（左側浮動） ──
        Padding(
          padding: const EdgeInsets.only(right: BridgeDS.spaceMD),
          child: _NewDoorButton(onTap: onCreateDoor),
        ),
        // ── 三列看板 ──
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: columns.map((status) {
              final columnDoors = doors
                  .where((d) => d.kanbanStatus == status)
                  .toList();
              return Expanded(
                child: _KanbanColumn(
                  status: status,
                  doors: columnDoors,
                  selectedDoorId: selectedDoorId,
                  onSelect: onSelect,
                  onMoveDoor: onMoveDoor,
                  onDeleteDoor: onDeleteDoor,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// 新增門按鈕
// ═══════════════════════════════════════════════════════

class _NewDoorButton extends StatelessWidget {
  final VoidCallback onTap;
  _NewDoorButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          border: Border.all(
            color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.30),
          ),
        ),
        child: Icon(
          Icons.add_rounded,
          color: BridgeDSColors.of(context).accentBlue,
          size: 28,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 看板列
// ═══════════════════════════════════════════════════════

class _KanbanColumn extends StatelessWidget {
  final String status;
  final List<ProjectDoor> doors;
  final String? selectedDoorId;
  final void Function(ProjectDoor door) onSelect;
  final void Function(String doorId, String newStatus) onMoveDoor;
  final void Function(String doorId)? onDeleteDoor;

  _KanbanColumn({
    required this.status,
    required this.doors,
    this.selectedDoorId,
    required this.onSelect,
    required this.onMoveDoor,
    this.onDeleteDoor,
  });

  String get _title => switch (status) {
        ProjectDoor.statusActive => '進行中',
        ProjectDoor.statusWaiting => '等待',
        ProjectDoor.statusCompleted => '完成',
        _ => status,
      };

  Color get _accentColor => switch (status) {
        ProjectDoor.statusActive => BridgeDS.accentBlue,
        ProjectDoor.statusWaiting => BridgeDS.accentYellow,
        ProjectDoor.statusCompleted => BridgeDS.accentGreen,
        _ => BridgeDS.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onMoveDoor(details.data, status),
      builder: (context, candidateItems, rejectedItems) {
        final isHovering = candidateItems.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(right: BridgeDS.spaceMD),
          padding: const EdgeInsets.all(BridgeDS.spaceSM),
          decoration: BoxDecoration(
            color: isHovering
                ? _accentColor.withValues(alpha: 0.05)
                : BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            border: Border.all(
              color: isHovering
                  ? _accentColor.withValues(alpha: 0.30)
                  : BridgeDSColors.of(context).borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 列頭 ──
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BridgeDS.spaceSM,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _title,
                      style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontSize: 16),
                    ),
                    const Spacer(),
                    Text(
                      '${doors.length}',
                      style: BridgeDSColors.of(context).labelMono.copyWith(
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              // ── 卡片列表 ──
              ...doors.map((door) => _DoorCard(
                    door: door,
                    isSelected: door.id == selectedDoorId,
                    accentColor: _accentColor,
                    onSelect: () => onSelect(door),
                    onDelete: onDeleteDoor != null
                        ? () => onDeleteDoor!(door.id)
                        : null,
                  )),
              if (doors.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(BridgeDS.spaceMD),
                  child: Center(
                    child: Text(
                      '—',
                      style: BridgeDSColors.of(context).small.copyWith(
                        color: BridgeDSColors.of(context).textQuaternary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// 門卡片
// ═══════════════════════════════════════════════════════

class _DoorCard extends StatelessWidget {
  final ProjectDoor door;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  const _DoorCard({
    required this.door,
    required this.isSelected,
    required this.accentColor,
    required this.onSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progress = door.flowProgress;
    final progressPercent = (progress * 100).round();

    return LongPressDraggable<String>(
      data: door.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 220,
          child: _DoorCardBody(
            door: door,
            isSelected: true,
            accentColor: accentColor,
            progressPercent: progressPercent,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.30,
        child: _DoorCardBody(
          door: door,
          isSelected: false,
          accentColor: accentColor,
          progressPercent: progressPercent,
        ),
      ),
      child: GestureDetector(
        onTap: onSelect,
        child: _DoorCardBody(
          door: door,
          isSelected: isSelected,
          accentColor: accentColor,
          progressPercent: progressPercent,
          onDelete: onDelete,
        ),
      ),
    );
  }
}

class _DoorCardBody extends StatelessWidget {
  final ProjectDoor door;
  final bool isSelected;
  final Color accentColor;
  final int progressPercent;
  final VoidCallback? onDelete;

  _DoorCardBody({
    required this.door,
    required this.isSelected,
    required this.accentColor,
    required this.progressPercent,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? BridgeDSColors.of(context).surfaceElevated
            : BridgeDSColors.of(context).surfaceHover,
        borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
        border: Border.all(
          color: isSelected
              ? accentColor.withValues(alpha: 0.50)
              : BridgeDSColors.of(context).borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題行 ──
          Row(
            children: [
              if (door.parentDoorId != null) ...[
                Icon(
                  Icons.call_split_rounded,
                  size: 12,
                  color: BridgeDSColors.of(context).accentPurple,
                ),
                SizedBox(width: 4),
              ],
              Expanded(
                child: SelectableText(
                  door.title,
                  style: BridgeDSColors.of(context).body.copyWith(fontSize: 14),
                ),
              ),
              // P7: 刪除按鈕
              if (onDelete != null)
                GestureDetector(
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 14,
                        color: BridgeDSColors.of(context).textQuaternary),
                  ),
                ),
            ],
          ),
          SizedBox(height: 6),
          // ── 意圖摘要 ──
          Text(
            door.sourceIntent,
            style: BridgeDSColors.of(context).small.copyWith(
              color: BridgeDSColors.of(context).textMuted,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          // ── 進度條 ──
          if (door.totalFlowCount > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: door.flowProgress,
                      backgroundColor: BridgeDSColors.of(context).borderDefault,
                      valueColor: AlwaysStoppedAnimation(accentColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '$progressPercent%',
                  style: BridgeDSColors.of(context).small.copyWith(
                    color: accentColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            // ── 步驟統計 ──
            Text(
              '${door.completedFlowCount}/${door.totalFlowCount} 步驟',
              style: BridgeDSColors.of(context).small.copyWith(
                color: BridgeDSColors.of(context).textMuted,
                fontSize: 14,
              ),
            ),
          ] else
            Text(
              door.currentFlow,
              style: BridgeDSColors.of(context).small.copyWith(
                color: BridgeDSColors.of(context).textMuted,
                fontSize: 14,
              ),
            ),
          // ── 橋標籤 ──
          if (door.requiredBridges.isNotEmpty) ...[
            SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: door.requiredBridges
                  .take(2)
                  .map((bridge) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).surfaceElevated,
                          borderRadius:
                              BorderRadius.circular(BridgeDS.roundSubtle),
                        ),
                        child: Text(
                          bridge,
                          style: BridgeDSColors.of(context).small.copyWith(
                            fontSize: 14,
                            color: BridgeDSColors.of(context).textTertiary,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
