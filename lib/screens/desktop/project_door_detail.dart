// [Sprint 18b-4 — 專案門詳情面板]
// ProjectDoorDetail：選中門的右側/全螢幕詳情
// 包含：門資訊 + 水流時間線 + 資產/記憶連結 + 分岔門列表

import 'package:flutter/material.dart';

import '../../models/flow_step.dart';
import '../../models/project_door.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class ProjectDoorDetail extends StatelessWidget {
  final ProjectDoor door;
  final List<ProjectDoor> childDoors; // 從此門分岔的子門
  final void Function(FlowStep step) onAddStep;
  final void Function(String stepId, String newStatus) onUpdateStepStatus;
  final void Function(String stepId) onRemoveStep;
  final void Function(String doorId) onForkDoor;
  final VoidCallback onBack;

  const ProjectDoorDetail({
    super.key,
    required this.door,
    this.childDoors = const [],
    required this.onAddStep,
    required this.onUpdateStepStatus,
    required this.onRemoveStep,
    required this.onForkDoor,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 返回 + 標題 ──
            _buildHeader(),
            const SizedBox(height: BridgeDS.spaceMD),
            // ── 門資訊卡 ──
            _buildInfoCard(),
            const SizedBox(height: BridgeDS.spaceMD),
            // ── 水流時間線 ──
            _buildFlowTimeline(),
            const SizedBox(height: BridgeDS.spaceMD),
            // ── 資產/記憶連結 ──
            _buildLinksSection(),
            const SizedBox(height: BridgeDS.spaceMD),
            // ── 分岔門 ──
            if (childDoors.isNotEmpty) ...[
              _buildChildDoors(),
              SizedBox(height: BridgeDS.spaceMD),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Header
  // ═══════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BridgeDS.surface,
              borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
              border: Border.all(color: BridgeDS.borderSubtle),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: BridgeDS.textSecondary,
              size: 18,
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(door.title, style: BridgeDS.headingL.copyWith(fontSize: 24)),
              SizedBox(height: 2),
              Text(
                door.parentDoorId != null ? '分岔自上層專案' : '獨立專案',
                style: BridgeDS.small.copyWith(color: BridgeDS.textMuted),
              ),
            ],
          ),
        ),
        // 分岔按鈕
        GestureDetector(
          onTap: () => onForkDoor(door.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: BridgeDS.accentPurple.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
              border: Border.all(
                color: BridgeDS.accentPurple.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_split_rounded,
                    size: 14, color: BridgeDS.accentPurple),
                SizedBox(width: 6),
                Text('分岔',
                    style: BridgeDS.small
                        .copyWith(color: BridgeDS.accentPurple)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 門資訊卡
  // ═══════════════════════════════════════════════════════

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDS.surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDS.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 狀態 + 進度 ──
          Row(
            children: [
              _StatusChip(status: door.kanbanStatus),
              Spacer(),
              if (door.totalFlowCount > 0)
                Text(
                  '${door.completedFlowCount}/${door.totalFlowCount} 完成',
                  style: BridgeDS.small.copyWith(
                    color: BridgeDS.accentBlue,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 意圖 ──
          _InfoLine(
            label: '原始意圖',
            value: door.sourceIntent,
            icon: Icons.track_changes_outlined,
          ),
          SizedBox(height: 8),
          _InfoLine(
            label: '當前水流',
            value: door.currentFlow,
            icon: Icons.water_drop_outlined,
          ),
          SizedBox(height: 8),
          _InfoLine(
            label: '建立時間',
            value: _formatDate(door.createdAt),
            icon: Icons.schedule_outlined,
          ),
          // ── intake questions ──
          if (door.intakeQuestions.isNotEmpty) ...[
            SizedBox(height: 16),
            Text('待釐清', style: BridgeDS.headingS.copyWith(fontSize: 14)),
            SizedBox(height: 8),
            ...door.intakeQuestions.take(3).map((q) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle,
                          size: 4, color: BridgeDS.textMuted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(q,
                            style: BridgeDS.small
                                .copyWith(color: BridgeDS.textTertiary)),
                      ),
                    ],
                  ),
                )),
          ],
          // ── 橋 ──
          if (door.requiredBridges.isNotEmpty) ...[
            SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: door.requiredBridges
                  .map((bridge) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: BridgeDS.surfaceElevated,
                          borderRadius:
                              BorderRadius.circular(BridgeDS.roundSubtle),
                        ),
                        child: Text(bridge,
                            style: BridgeDS.small.copyWith(
                                fontSize: 14,
                                color: BridgeDS.textTertiary)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 水流時間線
  // ═══════════════════════════════════════════════════════

  Widget _buildFlowTimeline() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDS.surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDS.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded,
                  size: 18, color: BridgeDS.accentBlue),
              SizedBox(width: 8),
              Text('水流追蹤', style: BridgeDS.headingS.copyWith(fontSize: 16)),
              Spacer(),
              GestureDetector(
                onTap: () => onAddStep(FlowStep.create(
                  doorId: door.id,
                  title: '新步驟',
                )),
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BridgeDS.accentBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 14, color: BridgeDS.accentBlue),
                      SizedBox(width: 4),
                      Text('新增步驟',
                          style: BridgeDS.small
                              .copyWith(color: BridgeDS.accentBlue)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          if (door.flowSteps.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(BridgeDS.spaceLG),
                child: Text(
                  '尚無水流步驟\n點「新增步驟」開始追蹤推進',
                  textAlign: TextAlign.center,
                  style: BridgeDS.small.copyWith(
                    color: BridgeDS.textMuted,
                    height: 1.6,
                  ),
                ),
              ),
            )
          else
            ...door.flowSteps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              final isLast = index == door.flowSteps.length - 1;
              return _FlowStepTile(
                step: step,
                index: index,
                isLast: isLast,
                onUpdateStatus: (newStatus) =>
                    onUpdateStepStatus(step.id, newStatus),
                onRemove: () => onRemoveStep(step.id),
              );
            }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 資產/記憶連結
  // ═══════════════════════════════════════════════════════

  Widget _buildLinksSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDS.surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDS.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: BridgeDS.accentGreen),
              SizedBox(width: 8),
              Text('資產與記憶',
                  style: BridgeDS.headingS.copyWith(fontSize: 16)),
            ],
          ),
          SizedBox(height: 12),
          if (door.linkedAssetIds.isEmpty && door.linkedMemoryIds.isEmpty)
            Text(
              '尚未連結資產或記憶',
              style: BridgeDS.small.copyWith(color: BridgeDS.textMuted),
            )
          else ...[
            if (door.linkedAssetIds.isNotEmpty) ...[
              Text('資產 (${door.linkedAssetIds.length})',
                  style: BridgeDS.labelMono.copyWith(
                      color: BridgeDS.tagInfoFg)),
              SizedBox(height: 4),
              ...door.linkedAssetIds.map((id) => _LinkItem(
                    id: id,
                    icon: Icons.category_outlined,
                    color: BridgeDS.accentBlue,
                  )),
              SizedBox(height: 8),
            ],
            if (door.linkedMemoryIds.isNotEmpty) ...[
              Text('記憶 (${door.linkedMemoryIds.length})',
                  style: BridgeDS.labelMono.copyWith(
                      color: BridgeDS.tagBrainFg)),
              SizedBox(height: 4),
              ...door.linkedMemoryIds.map((id) => _LinkItem(
                    id: id,
                    icon: Icons.psychology_outlined,
                    color: BridgeDS.accentPurple,
                  )),
            ],
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 分岔門
  // ═══════════════════════════════════════════════════════

  Widget _buildChildDoors() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDS.surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDS.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 18, color: BridgeDS.accentPurple),
              SizedBox(width: 8),
              Text('分岔專案',
                  style: BridgeDS.headingS.copyWith(fontSize: 16)),
              Spacer(),
              Text('${childDoors.length}',
                  style: BridgeDS.labelMono.copyWith(
                      color: BridgeDS.accentPurple)),
            ],
          ),
          SizedBox(height: 12),
          ...childDoors.map((child) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.call_split_rounded,
                        size: 12, color: BridgeDS.accentPurple),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(child.title,
                          style: BridgeDS.small
                              .copyWith(color: BridgeDS.textSecondary)),
                    ),
                    _StatusChip(status: child.kanbanStatus, compact: true),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  _InfoLine({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: BridgeDSColors.of(context).textMuted),
        SizedBox(width: 8),
        Text(label,
            style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted)),
        SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textSecondary)),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool compact;
  _StatusChip({required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ProjectDoor.statusActive => ('進行中', BridgeDSColors.of(context).accentBlue),
      ProjectDoor.statusWaiting => ('等待', BridgeDSColors.of(context).accentYellow),
      ProjectDoor.statusCompleted => ('完成', BridgeDSColors.of(context).accentGreen),
      _ => (status, BridgeDSColors.of(context).textTertiary),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BridgeDS.roundPill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: BridgeDSColors.of(context).small.copyWith(color: color, fontSize: compact ? 9 : 10),
      ),
    );
  }
}

class _FlowStepTile extends StatelessWidget {
  final FlowStep step;
  final int index;
  final bool isLast;
  final void Function(String newStatus) onUpdateStatus;
  final VoidCallback onRemove;

  const _FlowStepTile({
    required this.step,
    required this.index,
    required this.isLast,
    required this.onUpdateStatus,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusIcon) = _statusVisual(step.status);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 時間線軸 ──
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Icon(statusIcon, size: 10, color: statusColor),
              ),
              if (!isLast)
                Container(
                  width: 1.5,
                  height: 36,
                  color: BridgeDSColors.of(context).borderDefault,
                ),
            ],
          ),
        ),
        SizedBox(width: 8),
        // ── 步驟內容 ──
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).surfaceHover,
              borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
              border: Border.all(
                color: step.isDone
                    ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.20)
                    : BridgeDSColors.of(context).borderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: BridgeDSColors.of(context).body.copyWith(
                          fontSize: 14,
                          decoration:
                              step.isDone ? TextDecoration.lineThrough : null,
                          color: step.isDone
                              ? BridgeDSColors.of(context).textMuted
                              : BridgeDSColors.of(context).textPrimary,
                        ),
                      ),
                    ),
                    // ── 狀態切換 ──
                    _StepStatusMenu(
                      currentStatus: step.status,
                      onChanged: onUpdateStatus,
                    ),
                    SizedBox(width: 4),
                    // ── 刪除 ──
                    GestureDetector(
                      onTap: onRemove,
                      child: Icon(Icons.close_rounded,
                          size: 14, color: BridgeDSColors.of(context).textQuaternary),
                    ),
                  ],
                ),
                if (step.description != null &&
                    step.description!.trim().isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    step.description!,
                    style: BridgeDSColors.of(context).small.copyWith(
                      color: BridgeDSColors.of(context).textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
                // ── 資產/記憶連結指示 ──
                if (step.linkedAssetIds.isNotEmpty ||
                    step.linkedMemoryIds.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      if (step.linkedAssetIds.isNotEmpty) ...[
                        Icon(Icons.category_outlined,
                            size: 10, color: BridgeDSColors.of(context).accentBlue),
                        SizedBox(width: 2),
                        Text('${step.linkedAssetIds.length}',
                            style: BridgeDSColors.of(context).small.copyWith(
                                fontSize: 14, color: BridgeDSColors.of(context).accentBlue)),
                        SizedBox(width: 6),
                      ],
                      if (step.linkedMemoryIds.isNotEmpty) ...[
                        Icon(Icons.psychology_outlined,
                            size: 10, color: BridgeDSColors.of(context).accentPurple),
                        SizedBox(width: 2),
                        Text('${step.linkedMemoryIds.length}',
                            style: BridgeDSColors.of(context).small.copyWith(
                                fontSize: 14, color: BridgeDSColors.of(context).accentPurple)),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  (Color, IconData) _statusVisual(String status) {
    return switch (status) {
      FlowStep.statusDone =>
        (BridgeDS.accentGreen, Icons.check_rounded),
      FlowStep.statusInProgress =>
        (BridgeDS.accentBlue, Icons.play_arrow_rounded),
      FlowStep.statusBlocked =>
        (BridgeDS.accentRed, Icons.block_rounded),
      _ => (BridgeDS.textMuted, Icons.circle_outlined),
    };
  }
}

class _StepStatusMenu extends StatelessWidget {
  final String currentStatus;
  final void Function(String newStatus) onChanged;
  _StepStatusMenu({
    required this.currentStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (context) => [
        _menuItem('pending', '待開始'),
        _menuItem('in_progress', '進行中'),
        _menuItem('done', '完成'),
        _menuItem('blocked', '阻塞'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surfaceElevated,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _statusLabel(currentStatus),
              style: BridgeDSColors.of(context).small.copyWith(fontSize: 14),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 12),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label, style: BridgeDS.small.copyWith(fontSize: 14)),
    );
  }

  String _statusLabel(String status) => switch (status) {
        FlowStep.statusPending => '待開始',
        FlowStep.statusInProgress => '進行中',
        FlowStep.statusDone => '完成',
        FlowStep.statusBlocked => '阻塞',
        _ => status,
      };
}

class _LinkItem extends StatelessWidget {
  final String id;
  final IconData icon;
  final Color color;
  const _LinkItem({
    required this.id,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              id,
              style: BridgeDSColors.of(context).code.copyWith(fontSize: 14, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
