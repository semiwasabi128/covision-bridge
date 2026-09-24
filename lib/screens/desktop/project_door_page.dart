// [Sprint 18b-5 + 18c-4 — 專案門桌面頁面]
// ProjectDoorPage：整合 Kanban + Detail + 資產閉環 + 關聯圖的完整頁面。
// 由桌面 screen 的 tab 4 呼叫。

import 'package:flutter/material.dart';

import '../../models/digital_asset.dart';
import '../../models/flow_step.dart';
import '../../models/project_door.dart';
import '../../services/asset_closure_service.dart';
import '../../services/project_door_store.dart';
import '../../theme/bridge_design_system.dart';
import '../../widgets/bridge_desktop_widgets.dart';
import 'project_door_kanban.dart';
import 'project_door_detail.dart';
import 'project_relation_graph.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class ProjectDoorPage extends StatefulWidget {
  const ProjectDoorPage({super.key});

  @override
  State<ProjectDoorPage> createState() => _ProjectDoorPageState();
}

class _ProjectDoorPageState extends State<ProjectDoorPage> {
  final _store = const ProjectDoorStore();
  final _closureService = const AssetClosureService();
  List<ProjectDoor> _doors = [];
  String? _selectedDoorId;
  bool _loading = true;

  // 資產閉環狀態
  List<DigitalAsset> _linkedAssets = [];
  List<AssetClosureSuggestion> _suggestions = [];
  bool _loadingAssets = false;

  @override
  void initState() {
    super.initState();
    _loadDoors();
  }

  Future<void> _loadDoors() async {
    final doors = await _store.loadAll();
    if (mounted) {
      setState(() {
        _doors = doors;
        _loading = false;
      });
      if (_selectedDoorId != null) {
        _loadAssets();
      }
    }
  }

  Future<void> _loadAssets() async {
    final door = _selectedDoor;
    if (door == null) return;

    setState(() => _loadingAssets = true);

    // 載入已連結的資產
    final assets = await _closureService.getLinkedAssets(door);

    // 查詢資產建議
    final suggestions = await _closureService.beforeTask(door);

    if (mounted) {
      setState(() {
        _linkedAssets = assets;
        _suggestions = suggestions;
        _loadingAssets = false;
      });
    }
  }

  void _onSelectDoor(ProjectDoor door) {
    setState(() => _selectedDoorId = door.id);
    _loadAssets();
  }

  ProjectDoor? get _selectedDoor =>
      _doors.where((d) => d.id == _selectedDoorId).firstOrNull;

  List<ProjectDoor> get _childDoors => _selectedDoor == null
      ? const []
      : _doors.where((d) => d.parentDoorId == _selectedDoor!.id).toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final selected = _selectedDoor;

    // ── 沒選中門 → 全寬看板 ──
    if (selected == null) {
      return Padding(
        padding: const EdgeInsets.all(BridgeDS.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsRow(),
            const SizedBox(height: BridgeDS.spaceMD),
            Expanded(
              child: ProjectDoorKanban(
                doors: _doors,
                selectedDoorId: _selectedDoorId,
                onSelect: _onSelectDoor,
                onMoveDoor: _onMoveDoor,
                onCreateDoor: _onCreateDoor,
                onDeleteDoor: _onDeleteDoor,
              ),
            ),
          ],
        ),
      );
    }

    // ── 選中門 → 看板(380px) + 詳情(flex) ──
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 左側看板 ──
        SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(BridgeDS.spaceLG),
                child: _buildStatsRow(),
              ),
              Expanded(
                child: ProjectDoorKanban(
                  doors: _doors,
                  selectedDoorId: _selectedDoorId,
                  onSelect: _onSelectDoor,
                  onMoveDoor: _onMoveDoor,
                  onCreateDoor: _onCreateDoor,
                  onDeleteDoor: _onDeleteDoor,
                ),
              ),
            ],
          ),
        ),
        BridgeGlowDivider(),
        // ── 右側詳情 ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BridgeDS.spaceLG),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProjectDoorDetail(
                  door: selected,
                  childDoors: _childDoors,
                  onAddStep: _onAddStep,
                  onUpdateStepStatus: _onUpdateStepStatus,
                  onRemoveStep: _onRemoveStep,
                  onForkDoor: _onForkDoor,
                  onBack: () => setState(() => _selectedDoorId = null),
                ),
                const SizedBox(height: BridgeDS.spaceMD),
                // ── 關聯圖 ──
                ProjectRelationGraph(
                  centerDoor: selected,
                  childDoors: _childDoors,
                  linkedAssets: _linkedAssets,
                  linkedMemoryIds: selected.linkedMemoryIds,
                ),
                const SizedBox(height: BridgeDS.spaceMD),
                // ── 資產閉環 ──
                _buildClosureSection(selected),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 統計列
  // ═══════════════════════════════════════════════════════

  Widget _buildStatsRow() {
    final active = _doors.where((d) => d.kanbanStatus == ProjectDoor.statusActive).length;
    final waiting = _doors.where((d) => d.kanbanStatus == ProjectDoor.statusWaiting).length;
    final completed = _doors.where((d) => d.kanbanStatus == ProjectDoor.statusCompleted).length;
    final totalSteps = _doors.fold(0, (sum, d) => sum + d.totalFlowCount);
    final doneSteps = _doors.fold(0, (sum, d) => sum + d.completedFlowCount);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatCard(label: '專案總數', value: '${_doors.length}', icon: Icons.door_sliding_outlined, color: BridgeDSColors.of(context).accentBlue),
        _StatCard(label: '進行中', value: '$active', icon: Icons.play_arrow_rounded, color: BridgeDSColors.of(context).accentBlue),
        _StatCard(label: '等待', value: '$waiting', icon: Icons.pause_rounded, color: BridgeDSColors.of(context).accentYellow),
        _StatCard(label: '完成', value: '$completed', icon: Icons.check_circle_outline, color: BridgeDSColors.of(context).accentGreen),
        _StatCard(label: '步驟', value: '$doneSteps/$totalSteps', icon: Icons.timeline_rounded, color: BridgeDSColors.of(context).accentPurple),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 資產閉環區
  // ═══════════════════════════════════════════════════════

  Widget _buildClosureSection(ProjectDoor door) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_alt, size: 18, color: BridgeDSColors.of(context).accentGreen),
              SizedBox(width: 8),
              Text('資產閉環', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontSize: 16)),
              Spacer(),
              if (_loadingAssets)
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          SizedBox(height: 12),
          // ── 已連結資產 ──
          Text('已連結資產 (${_linkedAssets.length})',
              style: BridgeDSColors.of(context).labelMono.copyWith(color: BridgeDSColors.of(context).tagInfoFg)),
          SizedBox(height: 6),
          if (_linkedAssets.isEmpty)
            Text('尚未連結資產', style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted))
          else
            ..._linkedAssets.map((asset) => _AssetRow(
                  asset: asset,
                  onUnlink: () => _onUnlinkAsset(door.id, asset.id),
                )),
          SizedBox(height: 16),
          // ── 資產建議 ──
          Text('任務前推薦資產 (${_suggestions.length})',
              style: BridgeDSColors.of(context).labelMono.copyWith(color: BridgeDSColors.of(context).tagSuccessFg)),
          SizedBox(height: 6),
          if (_suggestions.isEmpty)
            Text('暫無推薦資產', style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted))
          else
            ..._suggestions.take(5).map((s) => _SuggestionRow(
                  suggestion: s,
                  onLink: () => _onLinkAsset(door.id, s.suggestedForStepId, s.asset.id),
                )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════

  Future<void> _onMoveDoor(String doorId, String newStatus) async {
    await _store.updateDoorStatus(doorId, newStatus);
    await _loadDoors();
  }

  Future<void> _onCreateDoor() async {
    final now = DateTime.now();
    final door = ProjectDoor(
      id: 'project-door-${now.microsecondsSinceEpoch}',
      title: '新專案門',
      sourceIntent: '使用者手動建立',
      currentFlow: '目標定義',
      intakeQuestions: const [],
      requiredBridges: const [],
      createdAt: now,
      updatedAt: now,
      status: ProjectDoor.statusActive,
      secondBrainEntryId: 'second-brain-project-door-${now.microsecondsSinceEpoch}',
    );
    await _store.saveActive(door);
    await _loadDoors();
    _onSelectDoor(door);
  }

  Future<void> _onAddStep(FlowStep step) async {
    final door = _selectedDoor;
    if (door == null) return;
    await _store.addFlowStep(door.id, step);
    await _loadDoors();
  }

  Future<void> _onUpdateStepStatus(String stepId, String newStatus) async {
    final door = _selectedDoor;
    if (door == null) return;
    await _store.updateFlowStep(door.id, stepId, status: newStatus);
    await _loadDoors();
  }

  Future<void> _onRemoveStep(String stepId) async {
    final door = _selectedDoor;
    if (door == null) return;
    await _store.removeFlowStep(door.id, stepId);
    await _loadDoors();
  }

  Future<void> _onForkDoor(String parentDoorId) async {
    final parent = _doors.where((d) => d.id == parentDoorId).firstOrNull;
    if (parent == null) return;
    final forked = await _store.forkDoor(
      parentDoorId,
      title: '${parent.title} — 分岔',
      sourceIntent: parent.sourceIntent,
    );
    await _loadDoors();
    _onSelectDoor(forked);
  }

  /// P7: 刪除專案門
  Future<void> _onDeleteDoor(String doorId) async {
    await _store.deleteDoor(doorId);
    if (_selectedDoorId == doorId) {
      setState(() => _selectedDoorId = null);
    }
    await _loadDoors();
  }

  Future<void> _onLinkAsset(String doorId, String stepId, String assetId) async {
    if (stepId.isEmpty) {
      await _closureService.linkAssetToDoor(doorId, assetId);
    } else {
      await _closureService.linkAssetToStep(doorId, stepId, assetId);
    }
    await _loadDoors();
    _loadAssets();
  }

  Future<void> _onUnlinkAsset(String doorId, String assetId) async {
    await _closureService.unlinkAsset(doorId, assetId);
    await _loadDoors();
    _loadAssets();
  }
}

// ═══════════════════════════════════════════════════════
// Stat card
// ═══════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontSize: 14, color: color)),
              Text(label, style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Asset row — 已連結資產
// ═══════════════════════════════════════════════════════

class _AssetRow extends StatelessWidget {
  final DigitalAsset asset;
  final VoidCallback onUnlink;
  _AssetRow({required this.asset, required this.onUnlink});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(asset.kind == DigitalAssetKind.companionCharacter
              ? Icons.person_outline
              : Icons.category_outlined,
              size: 14, color: BridgeDSColors.of(context).accentGreen),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset.title,
                    style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(asset.kind.label,
                    style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onUnlink,
            child: Icon(Icons.link_off, size: 12, color: BridgeDSColors.of(context).textQuaternary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Suggestion row — 資產建議
// ═══════════════════════════════════════════════════════

class _SuggestionRow extends StatelessWidget {
  final AssetClosureSuggestion suggestion;
  final VoidCallback onLink;
  _SuggestionRow({required this.suggestion, required this.onLink});

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surfaceHover,
          borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
          border: Border.all(color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lightbulb_outline, size: 14, color: BridgeDSColors.of(context).accentGreen),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.asset.title,
                      style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textPrimary, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (s.reasons.isNotEmpty)
                    Text(s.reasons.take(2).join('、'),
                        style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: 6),
            GestureDetector(
              onTap: onLink,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                ),
                child: Text('引用',
                    style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).accentGreen)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
