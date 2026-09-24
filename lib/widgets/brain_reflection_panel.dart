import 'package:flutter/material.dart';

import '../models/agent_activity.dart';
import '../models/capability_catalog.dart';
import '../models/intention_record.dart';
import '../models/second_brain_file_index.dart';
import '../models/second_brain_trace.dart';
import '../models/transurfing_brain.dart';
import '../services/agent_motivation_engine.dart';
import '../services/brain_pipeline/audit/audit_store.dart';
import '../services/brain_pipeline/heart_mind/heart_mind_dialogue.dart';
import '../services/brain_pipeline/layer_result.dart';
import '../state/brain_panel_state.dart';
import '../theme/app_theme.dart';
import 'brain_pipeline/attention_meter.dart';
import 'brain_pipeline/intention_timeline.dart';
import 'brain_pipeline/layer_card.dart';
import 'brain_pipeline/pendulum_radar_chart.dart';
import 'brain_pipeline/pendulum_audit_chart.dart';
import 'brain_pipeline/heart_mind_dialogue_card.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

enum BrainReflectionPanelDensity { full, compact }

class BrainReflectionPanel extends StatelessWidget {
  final BrainReflection reflection;
  final BrainReflectionPanelDensity density;
  final List<String> recalledInsights;
  final SecondBrainTrace? secondBrainTrace;
  final BrainSkillRegistrySnapshot? brainSkillRegistry;
  final AgentMotivationSnapshot? agentMotivation;
  final int turnCount;
  final int contextChars;
  final int bridgeActionCount;
  final int attachmentCount;
  final AgentActivityStage? activeStage;
  final AgentActivityTelemetry activeTelemetry;
  final String? activeBridgeActionLabel;
  final String? imageProgressLabel;
  final bool isWorking;
  final Map<String, SecondBrainMemoryFeedback> secondBrainMemoryFeedbacks;
  final Map<String, SecondBrainAssociationFeedback>
  secondBrainAssociationFeedbacks;
  final void Function(
    SecondBrainMemoryTrace memory,
    SecondBrainMemoryFeedback feedback,
  )?
  onSecondBrainMemoryFeedback;
  final void Function(
    String association,
    SecondBrainAssociationFeedback feedback,
  )?
  onSecondBrainAssociationFeedback;
  final Map<String, SecondBrainRoom> secondBrainMemoryRoomOverrides;
  final void Function(SecondBrainMemoryTrace memory, SecondBrainRoom room)?
  onSecondBrainMemoryRoomMove;
  final void Function(SecondBrainMemoryTrace memory)?
  onUndoSecondBrainMemoryCorrection;
  final void Function(SecondBrainMemoryTrace memory)?
  onOpenSecondBrainMemorySource;
  final void Function(SecondBrainMemoryTrace memory)?
  onCopySecondBrainMemorySource;
  final VoidCallback? onImportSecondBrainFolder;
  final DoorDecisionPendingReturn? pendingDoorReturn;
  final void Function(DoorDecision decision, DoorDecisionChoice choice)?
  onDoorChoice;
  final VoidCallback? onResumePendingDoor;
  final VoidCallback? onClearPendingDoor;
  // [教練 Agent Sprint 2 2026-07-04] 宣告/確認/行動閉環
  final List<IntentionRecord> intentions;
  // [教練 Agent Sprint 8 2026-07-04] 擺錘週報
  final PendulumAuditSummary? auditSummary;
  // [教練 Agent Sprint 9 2026-07-04] 心腦合一對話
  final HeartMindDialogue? heartMindDialogue;
  // [教練 Agent Sprint 1.2 2026-07-05] 門欄位改讀 activeDoorTitle（不讀 doorCandidates）
  final String? activeDoorTitle;

  const BrainReflectionPanel({
    super.key,
    required this.reflection,
    this.density = BrainReflectionPanelDensity.full,
    this.recalledInsights = const [],
    this.secondBrainTrace,
    this.brainSkillRegistry,
    this.agentMotivation,
    this.turnCount = 0,
    this.contextChars = 0,
    this.bridgeActionCount = 0,
    this.attachmentCount = 0,
    this.activeStage,
    this.activeTelemetry = const AgentActivityTelemetry(),
    this.activeBridgeActionLabel,
    this.imageProgressLabel,
    this.isWorking = false,
    this.activeDoorTitle,
    this.secondBrainMemoryFeedbacks = const {},
    this.secondBrainAssociationFeedbacks = const {},
    this.onSecondBrainMemoryFeedback,
    this.onSecondBrainAssociationFeedback,
    this.secondBrainMemoryRoomOverrides = const {},
    this.onSecondBrainMemoryRoomMove,
    this.onUndoSecondBrainMemoryCorrection,
    this.onOpenSecondBrainMemorySource,
    this.onCopySecondBrainMemorySource,
    this.onImportSecondBrainFolder,
    this.pendingDoorReturn,
    this.onDoorChoice,
    this.onResumePendingDoor,
    this.onClearPendingDoor,
    this.intentions = const [],
    this.auditSummary,
    this.heartMindDialogue,
  });

  @override
  Widget build(BuildContext context) {
    final compact = density == BrainReflectionPanelDensity.compact;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(
          compact ? AppTheme.radiusSmall : AppTheme.radiusMedium,
        ),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  size: compact ? 16 : 18,
                  color: BridgeDSColors.of(context).accentPurple,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '思維儀表',
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                      color: BridgeDSColors.of(context).textPrimary,),
                  ),
                ),
                if (!compact) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '行動卡',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                        fontWeight: FontWeight.w900,),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                _InfoButton(
                  title: '思維儀表',
                  body:
                      '這是橋樑大腦的方向判斷層。它會把使用者的意圖放進「思維儀表」裡觀察，再決定是回答、提問、降速、接橋，或把外部資訊轉成自己的輸出。',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!compact) ...[
              _InstrumentDisclosureSection(
                icon: Icons.dashboard_customize_outlined,
                title: '儀表摘要',
                summary: isWorking
                    ? '運行中'
                    : _moveLabel(reflection.recommendedMove),
                initiallyExpanded: false,
                child: _BrainActionCard(
                  reflection: reflection,
                  recalledInsights: recalledInsights,
                  bridgeActionCount: bridgeActionCount,
                  attachmentCount: attachmentCount,
                  activeStage: activeStage,
                  activeTelemetry: activeTelemetry,
                  activeBridgeActionLabel: activeBridgeActionLabel,
                  imageProgressLabel: imageProgressLabel,
                  isWorking: isWorking,
                ),
              ),
              // [教練 Agent Sprint 6 2026-07-04] 七層即時監控面板 v2
              if (reflection.layerResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                _InstrumentDisclosureSection(
                  icon: Icons.layers_outlined,
                  title: '七層判斷',
                  summary: _layerSummary(reflection),
                  initiallyExpanded: false,
                  child: _SevenLayerVisualization(
                    reflection: reflection,
                    intentions: intentions,
                  ),
                ),
                // [教練 Agent Sprint 8 2026-07-04] 擺錘週報
                if (auditSummary != null) ...[
                  const SizedBox(height: 8),
                  _InstrumentDisclosureSection(
                    icon: Icons.bar_chart_outlined,
                    title: '擺錘週報',
                    summary: _auditSummary(auditSummary!),
                    initiallyExpanded: false,
                    child: PendulumAuditChart(summary: auditSummary!),
                  ),
                ],
                // [教練 Agent Sprint 9 2026-07-04] 心腦合一對話
                if (heartMindDialogue != null) ...[
                  const SizedBox(height: 8),
                  HeartMindDialogueCard(
                    dialogue: heartMindDialogue!,
                    morningAffirmation:
                        heartMindDialogue!.getMorningAffirmation(),
                    onUserReply: (reply) {
                      heartMindDialogue!.handleUserReply(reply);
                    },
                    onDismiss: () {
                      heartMindDialogue!.reset();
                    },
                  ),
                ],
              ],
              if (secondBrainTrace != null) ...[
                const SizedBox(height: 8),
                _InstrumentDisclosureSection(
                  icon: Icons.account_tree_outlined,
                  title: '第二大腦工作台',
                  summary: _secondBrainSummary(secondBrainTrace),
                  initiallyExpanded: true,
                  child: _SecondBrainWorkbench(
                    trace: secondBrainTrace,
                    onImportFolder: onImportSecondBrainFolder,
                    feedbacks: secondBrainMemoryFeedbacks,
                    associationFeedbacks: secondBrainAssociationFeedbacks,
                    onMemoryFeedback: onSecondBrainMemoryFeedback,
                    onAssociationFeedback: onSecondBrainAssociationFeedback,
                    roomOverrides: secondBrainMemoryRoomOverrides,
                    onMemoryRoomMove: onSecondBrainMemoryRoomMove,
                    onUndoMemoryCorrection: onUndoSecondBrainMemoryCorrection,
                    onOpenMemorySource: onOpenSecondBrainMemorySource,
                    onCopyMemorySource: onCopySecondBrainMemorySource,
                  ),
                ),
              ],
              if (brainSkillRegistry?.hasVisibleSignal == true) ...[
                const SizedBox(height: 8),
                _InstrumentDisclosureSection(
                  icon: Icons.hub_outlined,
                  title: '能力判斷',
                  summary: _skillRegistrySummary(brainSkillRegistry!),
                  initiallyExpanded: false,
                  child: _BrainSkillRegistryCard(snapshot: brainSkillRegistry!),
                ),
              ],
              if (agentMotivation != null) ...[
                const SizedBox(height: 8),
                _InstrumentDisclosureSection(
                  icon: Icons.auto_awesome_outlined,
                  title: '內在驅動',
                  summary:
                      'Lv ${agentMotivation!.driveLevel} · 準確 ${agentMotivation!.accuracyScore}',
                  initiallyExpanded: false,
                  child: _AgentMotivationCard(snapshot: agentMotivation!),
                ),
              ],
              const SizedBox(height: 10),
            ],
            if (!compact &&
                (reflection.doorDecision != null ||
                    pendingDoorReturn != null)) ...[
              _DoorDecisionSection(
                decision: reflection.doorDecision,
                pendingReturn: pendingDoorReturn,
                onDoorChoice: onDoorChoice,
                onResumePendingDoor: onResumePendingDoor,
                onClearPendingDoor: onClearPendingDoor,
              ),
              const SizedBox(height: 10),
            ],
            // [教練 Agent Sprint 2 2026-07-04] 宣告/確認/行動三欄
            if (!compact && intentions.isNotEmpty) ...[
              _IntentionSection(intentions: intentions),
              const SizedBox(height: 10),
            ],
            if (compact) ...[
              const _BrainInstrumentHeader(),
              const SizedBox(height: 7),
              BrainInstrumentStatusStrip(
                reflection: reflection,
                activeDoorTitle: activeDoorTitle,
              ),
            ],
            if (!compact && reflection.guidance.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                reflection.guidance,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.35,
                  color: BridgeDSColors.of(context).textSecondary,),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BrainInstrumentStatusStrip extends StatelessWidget {
  final BrainReflection reflection;
  // [教練 Agent Sprint 1.2] 門欄位改讀 activeDoorTitle
  final String? activeDoorTitle;

  const BrainInstrumentStatusStrip({
    super.key,
    required this.reflection,
    this.activeDoorTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _BrainChip(
          label: '注意力',
          value: _attentionLabel(reflection.attentionState),
          icon: Icons.visibility_outlined,
          explanation:
              '注意力是使用者目前能不能清醒選擇的狀態。清醒代表能主動決定；被捕獲代表被新聞、平台、社群或新工具牽走；分散代表目標太多，能量被切碎。',
        ),
        _BrainChip(
          label: '重要性',
          value: _importanceLabel(reflection.importanceLevel),
          icon: Icons.speed_outlined,
          explanation:
              '重要性是使用者賦予事件的情緒重量。過高時容易焦慮、硬推、怕失敗。降低重要性不是放棄，而是先建立安全網，再穩定行動。',
        ),
        _BrainChip(
          label: '門',
          // [教練 Agent Sprint 1.2] 優先讀 activeDoorTitle，fallback 到 doorCandidates
          value: activeDoorTitle?.isNotEmpty == true
              ? activeDoorTitle!
              : _doorLabel(reflection.doorCandidates),
          icon: Icons.door_front_door_outlined,
          explanation:
              '門是通往目標的路徑。自己的門通常帶著自然、興趣、意義與可持續感；外部平台的門可能有用，但要確認它服務的是使用者自己的目標。',
        ),
        _BrainChip(
          label: '水流',
          value: _flowLabel(reflection.flowState),
          icon: Icons.water_outlined,
          explanation: '水流代表目前行動是否順著低阻力路徑。順流時適合推進下一環；逆流時先觀察是否過度控制、太急、或走進了別人的門。',
        ),
        _BrainChip(
          label: '建議',
          value: _moveLabel(reflection.recommendedMove),
          icon: Icons.assistant_direction_outlined,
          explanation: '建議是大腦此刻的下一步路由：直接回答、釐清、降重要性、轉成輸出、推進下一環，或接上橋樑能力。',
        ),
      ],
    );
  }
}

class _InstrumentDisclosureSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String summary;
  final Widget child;
  final bool initiallyExpanded;

  const _InstrumentDisclosureSection({
    required this.icon,
    required this.title,
    required this.summary,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.14)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            leading: Icon(icon, size: 17, color: BridgeDSColors.of(context).accentPurple),
            title: Text(
              title,
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            subtitle: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                fontWeight: FontWeight.w700,),
            ),
            children: [child],
          ),
        ),
      ),
    );
  }
}

String _secondBrainSummary(SecondBrainTrace? trace) {
  if (trace == null || !trace.hasActivity) return '尚未調用';
  final parts = <String>[
    if (trace.recalledMemories.isNotEmpty)
      '調閱 ${trace.recalledMemories.length}',
    if (trace.newInsights.isNotEmpty) '新增 ${trace.newInsights.length}',
    if (trace.associations.isNotEmpty) '關聯 ${trace.associations.length}',
  ];
  return parts.isEmpty ? '正在待命' : parts.join(' · ');
}

String _skillRegistrySummary(BrainSkillRegistrySnapshot snapshot) {
  final readyCount = snapshot.capabilities.where((item) => item.ready).length;
  final totalCount = snapshot.capabilities.length;
  if (snapshot.recommendations.isNotEmpty) {
    return '$readyCount/$totalCount 可用 · ${snapshot.recommendations.length} 建議';
  }
  return '$readyCount/$totalCount 可用';
}

// [教練 Agent Sprint 6 2026-07-04] 七層判斷摘要
String _layerSummary(BrainReflection reflection) {
  final layers = reflection.layerResults;
  if (layers.isEmpty) return '未啟用';
  final aiCount = layers.values.where((l) => l.source == LayerSource.ai || l.source == LayerSource.mixed).length;
  final ruleCount = layers.values.where((l) => l.source == LayerSource.rule).length;
  if (aiCount > 0) {
    return 'AI $aiCount 層 · 規則 $ruleCount 層';
  }
  return '全規則版';
}

// [教練 Agent Sprint 8 2026-07-04] 擺錘週報摘要
String _auditSummary(PendulumAuditSummary summary) {
  final total = summary.grandTotal;
  if (total == 0 && summary.clipConsumptionSecondsToday == 0) {
    return '無紀錄';
  }
  final parts = <String>[];
  if (total > 0) parts.add('7天 $total 次');
  if (summary.clipConsumptionSecondsToday > 0) {
    final mins = summary.clipConsumptionSecondsToday ~/ 60;
    parts.add('短影音 $mins 分');
  }
  return parts.join(' · ');
}

// [教練 Agent Sprint 6 2026-07-04] 七層即時監控面板 v2
class _SevenLayerVisualization extends StatefulWidget {
  final BrainReflection reflection;
  final List<IntentionRecord> intentions;

  const _SevenLayerVisualization({
    required this.reflection,
    this.intentions = const [],
  });

  @override
  State<_SevenLayerVisualization> createState() => _SevenLayerVisualizationState();
}

class _SevenLayerVisualizationState extends State<_SevenLayerVisualization> {
  late final BrainPanelState _panelState;

  @override
  void initState() {
    super.initState();
    _panelState = BrainPanelState();
    _panelState.startListening();
  }

  @override
  void dispose() {
    _panelState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reflection = _panelState.reflection ?? widget.reflection;
    final layers = reflection.layerResults;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        key: ValueKey(reflection.hashCode),
        children: [
          // Summary footer: 擺錘雷達 + attention meter
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 擺錘雷達圖
              if (reflection.pendulumSignals.isNotEmpty) ...[
                PendulumRadarChart(signals: reflection.pendulumSignals),
                const SizedBox(width: 10),
              ],
              // Attention meter + summary
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AttentionMeter(
                      state: reflection.attentionState,
                      source: layers['attention']?.source ?? LayerSource.rule,
                      confidence: layers['attention']?.confidence ?? 1.0,
                    ),
                    const SizedBox(height: 6),
                    _SummaryFooter(reflection: reflection),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Sprint 7：夥伴現在狀態
          _CompanionStatusSection(reflection: reflection),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => _panelState.toggleAllExpanded(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _panelState.allExpanded ? Icons.unfold_less : Icons.unfold_more,
                        size: 12,
                        color: BridgeDSColors.of(context).accentPurple,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _panelState.allExpanded ? '全部收合' : '全部展開',
                        style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                          color: BridgeDSColors.of(context).accentPurple,),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (_panelState.overrides.isNotEmpty)
                GestureDetector(
                  onTap: () => _panelState.clearOverrides(),
                  child: Text(
                    '清除 override',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 七層 LayerCard
          ...BrainLayerId.values.map((layerId) {
            final layerResult = layers[layerId.key];
            if (layerResult == null) return const SizedBox.shrink();
            final isExpanded = _panelState.isLayerExpanded(layerId.key);
            final override = _panelState.getOverride(layerId.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayerCard(
                    layerId: layerId,
                    layerResult: layerResult,
                    reflection: reflection,
                    overrideMode: override,
                    onSourceToggle: () => _panelState.toggleOverride(layerId.key),
                  ),
                  if (isExpanded && layerResult.evidence.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 10, top: 2),
                      child: Text(
                        layerResult.evidence,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                          height: 1.3,),
                      ),
                    ),
                ],
              ),
            );
          }),
          // 意圖時間軸
          if (widget.intentions.isNotEmpty) ...[
            const SizedBox(height: 8),
            IntentionTimeline(intentions: widget.intentions),
          ],
        ],
      ),
    );
  }
}

// [教練 Agent Sprint 7 2026-07-04] 夥伴現在狀態區塊
class _CompanionStatusSection extends StatelessWidget {
  final BrainReflection reflection;

  const _CompanionStatusSection({required this.reflection});

  @override
  Widget build(BuildContext context) {
    final expr = reflection.companionExpression;
    final gait = expr.gait;
    final voiceTone = expr.voiceTone;

    // 半透明小字——不搶視覺焦點
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.favorite_outline,
            size: 14,
            color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '夥伴現在狀態',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                    color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.7),),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildDescription(expr, gait, voiceTone),
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                    height: 1.35,),
                ),
              ],
            ),
          ),
          // gait / voiceTone 標籤
          if (gait != null || voiceTone != null) ...[
            const SizedBox(width: 4),
            Wrap(
              spacing: 3,
              runSpacing: 2,
              children: [
                if (gait != null)
                  _CompanionTag(
                    label: _gaitLabel(gait),
                    color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                  ),
                if (voiceTone != null)
                  _CompanionTag(
                    label: _voiceToneLabel(voiceTone),
                    color: AppTheme.secondary.withValues(alpha: 0.15),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _buildDescription(
    CompanionExpression expr,
    CompanionGait? gait,
    CompanionVoiceTone? voiceTone,
  ) {
    // 如果有 gait + voiceTone，組一句描述
    if (gait != null && voiceTone != null) {
      return '夥伴此時會${_gaitAction(gait)}，${_voiceToneAction(voiceTone)}';
    }
    // fallback：用 statusText
    return expr.statusText;
  }

  static String _gaitLabel(CompanionGait gait) {
    return switch (gait) {
      CompanionGait.still => '停',
      CompanionGait.stepping => '步',
      CompanionGait.running => '跑',
      CompanionGait.paused => '暫',
    };
  }

  static String _voiceToneLabel(CompanionVoiceTone tone) {
    return switch (tone) {
      CompanionVoiceTone.measured => '沉穩',
      CompanionVoiceTone.warm => '溫暖',
      CompanionVoiceTone.brisk => '輕快',
      CompanionVoiceTone.soft => '柔和',
    };
  }

  static String _gaitAction(CompanionGait gait) {
    return switch (gait) {
      CompanionGait.still => '停下來',
      CompanionGait.stepping => '緩步走',
      CompanionGait.running => '快步走',
      CompanionGait.paused => '暫停一下',
    };
  }

  static String _voiceToneAction(CompanionVoiceTone tone) {
    return switch (tone) {
      CompanionVoiceTone.measured => '沉穩地說一句',
      CompanionVoiceTone.warm => '溫暖地回應',
      CompanionVoiceTone.brisk => '輕快地說',
      CompanionVoiceTone.soft => '柔和地說',
    };
  }
}

class _CompanionTag extends StatelessWidget {
  final String label;
  final Color color;

  const _CompanionTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,),
      ),
    );
  }
}

class _SummaryFooter extends StatelessWidget {
  final BrainReflection reflection;

  const _SummaryFooter({required this.reflection});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _MiniStat(label: '擺錘', value: '${reflection.pendulumSignals.length}'),
        _MiniStat(label: '門', value: '${reflection.doorCandidates.length}'),
        _MiniStat(
          label: '建議',
          value: _moveLabel(reflection.recommendedMove),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
              color: BridgeDSColors.of(context).textPrimary,),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BrainActionCard extends StatelessWidget {
  final BrainReflection reflection;
  final List<String> recalledInsights;
  final int bridgeActionCount;
  final int attachmentCount;
  final AgentActivityStage? activeStage;
  final AgentActivityTelemetry activeTelemetry;
  final String? activeBridgeActionLabel;
  final String? imageProgressLabel;
  final bool isWorking;

  const _BrainActionCard({
    required this.reflection,
    required this.recalledInsights,
    required this.bridgeActionCount,
    required this.attachmentCount,
    required this.activeStage,
    required this.activeTelemetry,
    required this.activeBridgeActionLabel,
    this.imageProgressLabel,
    required this.isWorking,
  });

  @override
  Widget build(BuildContext context) {
    final stageTitle = activeStage == null
        ? '待命'
        : isWorking
        ? activeStage!.label
        : '剛完成';
    final stageBody = activeStage == null
        ? '等待新的任務。'
        : _stageSummary(activeStage!, activeTelemetry);
    final judgement = _judgementSummary(reflection);
    final memory = _memorySummary(
      recalledInsights,
      bridgeActionCount,
      attachmentCount,
      activeBridgeActionLabel,
    );
    final next = _nextStepSummary(reflection, activeBridgeActionLabel);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '儀表摘要',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _MiniPill(
                label: isWorking ? '運行中' : '已同步',
                color: isWorking ? BridgeDSColors.of(context).accentYellow : BridgeDSColors.of(context).accentPurple,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _BrainDashboardTile(
                icon: activeStage?.icon ?? Icons.radio_button_checked,
                title: stageTitle,
                value: stageBody,
              ),
              _BrainDashboardTile(
                icon: Icons.manage_search_outlined,
                title: '判斷',
                value: judgement,
              ),
              _BrainDashboardTile(
                icon: Icons.auto_stories_outlined,
                title: '記憶',
                value: memory,
              ),
              _BrainDashboardTile(
                icon: Icons.assistant_direction_outlined,
                title: '下一步',
                value: next,
              ),
            ],
          ),
          Material(
            color: Colors.transparent,
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                visualDensity: VisualDensity.compact,
              ),
              child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 2),
              dense: true,
              title: Text(
                '查看判斷細節',
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                  fontWeight: FontWeight.w900,),
              ),
              children: [
                if (activeStage != null) ...[
                  _BrainActionRow(
                    icon: activeStage!.icon,
                    title: isWorking ? activeStage!.label : '最近工作階段',
                    body: _stageText(activeStage!, activeTelemetry),
                  ),
                  const SizedBox(height: 8),
                ],
                _BrainActionRow(
                  icon: Icons.manage_search_outlined,
                  title: '正在判斷',
                  body: _judgementText(reflection),
                ),
                const SizedBox(height: 8),
                _BrainActionRow(
                  icon: Icons.auto_stories_outlined,
                  title: '記憶調閱',
                  body: _memoryText(
                    recalledInsights,
                    bridgeActionCount,
                    attachmentCount,
                    activeBridgeActionLabel,
                  ),
                ),
                const SizedBox(height: 8),
                _BrainActionRow(
                  icon: Icons.assistant_direction_outlined,
                  title: '下一步',
                  body: _nextStepText(reflection, activeBridgeActionLabel),
                ),
              ],
            ),
          ),
          ),
        ],
      ),
    );
  }

  String _stageText(
    AgentActivityStage stage,
    AgentActivityTelemetry telemetry,
  ) {
    final materials = <String>[
      if (telemetry.messages > 0) '${telemetry.messages} 則對話',
      if (telemetry.chars > 0) '${telemetry.chars} 字上下文',
      if (telemetry.memories > 0) '${telemetry.memories} 筆新記憶線索',
      if (telemetry.attachments > 0) '${telemetry.attachments} 份附件',
      if (telemetry.bridgeActions > 0) '${telemetry.bridgeActions} 個橋樑動作',
      if (telemetry.tokens > 0) '${telemetry.tokens} tokens',
    ];
    if (materials.isEmpty) return stage.detail;
    return '${stage.detail} 工作材料：${materials.join('、')}。';
  }

  String _stageSummary(
    AgentActivityStage stage,
    AgentActivityTelemetry telemetry,
  ) {
    final materials = <String>[
      if (telemetry.messages > 0) '${telemetry.messages}對話',
      if (telemetry.memories > 0) '${telemetry.memories}記憶',
      if (telemetry.attachments > 0) '${telemetry.attachments}附件',
      if (telemetry.bridgeActions > 0) '${telemetry.bridgeActions}橋',
    ];
    if (materials.isEmpty) return stage.detail;
    return materials.join(' · ');
  }

  String _judgementSummary(BrainReflection reflection) {
    final flow = _flowLabel(reflection.flowState);
    final move = _moveLabel(reflection.recommendedMove);
    return '$flow · $move';
  }

  String _judgementText(BrainReflection reflection) {
    // [教練 Agent P0.5b 2026-08-07] 圖片任務真實進度優先顯示。
    if (imageProgressLabel != null && imageProgressLabel!.trim().isNotEmpty) {
      return imageProgressLabel!;
    }
    if (activeBridgeActionLabel != null &&
        activeBridgeActionLabel!.trim().isNotEmpty) {
      return activeBridgeActionLabel!;
    }
    final attention = _attentionLabel(reflection.attentionState);
    final flow = _flowLabel(reflection.flowState);
    final importance = _importanceLabel(reflection.importanceLevel);
    final door = _doorLabel(reflection.doorCandidates);
    return '正在把「${reflection.userIntent}」放進判斷框：注意力 $attention，重要性 $importance，門是 $door，水流 $flow。';
  }

  String _memorySummary(
    List<String> insights,
    int bridgeActionCount,
    int attachmentCount,
    String? bridgeLabel,
  ) {
    final signals = <String>[
      if (insights.isNotEmpty) '${insights.length}洞察',
      if (bridgeActionCount > 0) '$bridgeActionCount橋',
      if (attachmentCount > 0) '$attachmentCount附件',
      if (bridgeLabel != null && bridgeLabel.trim().isNotEmpty) '橋樑命中',
    ];
    return signals.isEmpty ? '未召回' : signals.join(' · ');
  }

  String _memoryText(
    List<String> insights,
    int bridgeActionCount,
    int attachmentCount,
    String? bridgeLabel,
  ) {
    final signals = <String>[
      if (bridgeLabel != null && bridgeLabel.trim().isNotEmpty)
        bridgeLabel.trim(),
      if (bridgeActionCount > 0) '橋樑行動 $bridgeActionCount 次',
      if (attachmentCount > 0) '附件 $attachmentCount 份',
    ];
    if (insights.isEmpty) {
      final suffix = signals.isEmpty ? '' : '；同時看見${signals.join('、')}。';
      return '目前沒有召回既有洞察，會先把這一輪形成新的第二大腦線索$suffix';
    }
    final suffix = signals.isEmpty ? '' : '，並參照${signals.join('、')}';
    return '已調閱 ${insights.length} 筆可用洞察$suffix，會把它們放進這一輪判斷；細節可在下方標記準確或不相關。';
  }

  String _nextStepSummary(BrainReflection reflection, String? bridgeLabel) {
    if (bridgeLabel != null && bridgeLabel.trim().isNotEmpty) {
      return '執行橋樑';
    }
    return _moveLabel(reflection.recommendedMove);
  }

  String _nextStepText(BrainReflection reflection, String? bridgeLabel) {
    if (bridgeLabel != null && bridgeLabel.contains('新聞與網頁搜尋橋')) {
      return '先確認搜尋能力是否已開通；已開通就直接查詢、摘要重點並列出來源，未開通就引導到金鑰匙中心。';
    }
    if (bridgeLabel != null && bridgeLabel.contains('圖片辨識橋')) {
      return '先確認 Vision 能力是否已開通；已開通就讀圖，未開通就引導設定，不讓任務掉回空泛聊天。';
    }
    switch (reflection.recommendedMove) {
      case RecommendedMove.answerDirectly:
        return '直接回答，保持目前節奏，不額外增加設定負擔。';
      case RecommendedMove.askClarifyingQuestion:
        return '先問一個能降低分歧的問題，再繼續執行。';
      case RecommendedMove.reduceImportance:
        return '先降低壓力與急迫感，拆出安全、可做的一小步。';
      case RecommendedMove.convertToOutput:
        return '把外部資訊或混亂想法，轉成可保存、可使用的具體成果。';
      case RecommendedMove.takeNextAction:
        return '沿著目前主線推進下一步，避免開太多支線。';
      case RecommendedMove.routeBridge:
        return '準備接上缺少的橋樑能力，讓夥伴可以真正替你完成任務。';
      case RecommendedMove.declareIntention:
        return '把意圖寫進大腦容器，等待確認後再轉為行動。';
      case RecommendedMove.recordWaterAction:
        return '記錄已完成的行動，讓大腦容器追蹤你的水流趨勢。';
    }
  }
}

class _BrainDashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _BrainDashboardTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: BridgeDSColors.of(context).accentPurple),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                    fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrainSkillRegistryCard extends StatelessWidget {
  final BrainSkillRegistrySnapshot snapshot;

  const _BrainSkillRegistryCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final recommendations = snapshot.recommendations;
    final readyCount = snapshot.capabilities.where((item) => item.ready).length;
    final totalCount = snapshot.capabilities.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: BridgeDSColors.of(context).accentPurple,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '能力判斷',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _MiniPill(
                label: '$readyCount/$totalCount 可用',
                color: BridgeDSColors.of(context).accentPurple,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.summary.isEmpty ? '正在比對能力目錄與目前需求。' : snapshot.summary,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...recommendations.map(_BrainSkillRecommendationTile.new),
          ],
        ],
      ),
    );
  }
}

class _BrainSkillRecommendationTile extends StatelessWidget {
  final BrainSkillRecommendation recommendation;

  const _BrainSkillRecommendationTile(this.recommendation);

  @override
  Widget build(BuildContext context) {
    final status = recommendation.capability;
    final color = switch (status.availability) {
      CapabilityAvailability.ready => BridgeDSColors.of(context).accentGreen,
      CapabilityAvailability.needsSetup => BridgeDSColors.of(context).accentYellow,
      CapabilityAvailability.unsupported => AppTheme.error,
      CapabilityAvailability.planned => BridgeDSColors.of(context).accentPurple,
    };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_kindIcon(status.definition.kind), size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.definition.name,
                        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                          fontWeight: FontWeight.w900,),
                      ),
                    ),
                    _MiniPill(label: status.availability.label, color: color),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  recommendation.reason,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                    height: 1.3,
                    fontWeight: FontWeight.w700,),
                ),
                const SizedBox(height: 2),
                Text(
                  '下一步：${status.nextStep}',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                    height: 1.25,
                    fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _kindIcon(CapabilityKind kind) {
    switch (kind) {
      case CapabilityKind.search:
        return Icons.travel_explore_outlined;
      case CapabilityKind.vision:
        return Icons.image_search_outlined;
      case CapabilityKind.image:
        return Icons.auto_awesome_outlined;
      case CapabilityKind.music:
        return Icons.music_note_outlined;
      case CapabilityKind.video:
        return Icons.movie_creation_outlined;
      case CapabilityKind.document:
        return Icons.description_outlined;
      case CapabilityKind.desktop:
        return Icons.folder_copy_outlined;
      case CapabilityKind.animation:
        return Icons.animation_outlined;
      case CapabilityKind.custom:
        return Icons.extension_outlined;
    }
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
          fontWeight: FontWeight.w900,),
      ),
    );
  }
}

class _SecondBrainWorkbench extends StatelessWidget {
  final SecondBrainTrace? trace;
  final VoidCallback? onImportFolder;
  final Map<String, SecondBrainMemoryFeedback> feedbacks;
  final Map<String, SecondBrainAssociationFeedback> associationFeedbacks;
  final Map<String, SecondBrainRoom> roomOverrides;
  final void Function(
    SecondBrainMemoryTrace memory,
    SecondBrainMemoryFeedback feedback,
  )?
  onMemoryFeedback;
  final void Function(
    String association,
    SecondBrainAssociationFeedback feedback,
  )?
  onAssociationFeedback;
  final void Function(SecondBrainMemoryTrace memory, SecondBrainRoom room)?
  onMemoryRoomMove;
  final void Function(SecondBrainMemoryTrace memory)? onUndoMemoryCorrection;
  final void Function(SecondBrainMemoryTrace memory)? onOpenMemorySource;
  final void Function(SecondBrainMemoryTrace memory)? onCopyMemorySource;

  const _SecondBrainWorkbench({
    required this.trace,
    this.onImportFolder,
    this.feedbacks = const {},
    this.associationFeedbacks = const {},
    this.onMemoryFeedback,
    this.onAssociationFeedback,
    this.roomOverrides = const {},
    this.onMemoryRoomMove,
    this.onUndoMemoryCorrection,
    this.onOpenMemorySource,
    this.onCopyMemorySource,
  });

  @override
  Widget build(BuildContext context) {
    final currentTrace = trace;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: BridgeDSColors.of(context).accentPurple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTrace == null
                          ? '這輪尚未建立第二大腦追蹤。'
                          : '共用大腦：${currentTrace.brainName} · 夥伴：${currentTrace.agentName?.trim().isNotEmpty == true ? currentTrace.agentName : '目前夥伴'}',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                        fontWeight: FontWeight.w600,),
                    ),
                  ],
                ),
              ),
              if (onImportFolder != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: '匯入資料夾到第二大腦索引',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.08),
                      foregroundColor: BridgeDSColors.of(context).accentPurple,
                    ),
                    onPressed: onImportFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          if (currentTrace == null || !currentTrace.hasActivity)
            const _SecondBrainEmptyState()
          else ...[
            _SecondBrainRoomDashboard(trace: currentTrace),
            const SizedBox(height: 9),
            _SecondBrainPanelDensityGuide(trace: currentTrace),
            if (feedbacks.isNotEmpty || roomOverrides.isNotEmpty) ...[
              const SizedBox(height: 9),
              _SecondBrainCorrectionLoopDashboard(
                memories: currentTrace.recalledMemories,
                feedbacks: feedbacks,
                roomOverrides: roomOverrides,
              ),
              const SizedBox(height: 9),
              _SecondBrainCorrectionHistory(
                memories: currentTrace.recalledMemories,
                feedbacks: feedbacks,
                roomOverrides: roomOverrides,
              ),
              const SizedBox(height: 9),
              _SecondBrainMemoryConflictNotice(
                memories: currentTrace.recalledMemories,
                feedbacks: feedbacks,
              ),
            ],
            const SizedBox(height: 10),
            _SecondBrainSectionTitle(
              icon: Icons.manage_search_outlined,
              title: '調閱了什麼',
              trailing: '${currentTrace.recalledMemories.length} 筆',
            ),
            const SizedBox(height: 6),
            if (currentTrace.recalledMemories.isEmpty)
              const _SecondBrainMutedLine('這輪沒有召回既有記憶，會先形成新的洞察線索。')
            else
              ...currentTrace.recalledMemories
                  .take(2)
                  .map(
                    (memory) => _SecondBrainMemoryCard(
                      memory: memory,
                      feedback: feedbacks[_memoryFeedbackKey(memory)],
                      roomOverride: roomOverrides[_memoryFeedbackKey(memory)],
                      relatedMemories: currentTrace.recalledMemories
                          .where(
                            (candidate) =>
                                _memoryFeedbackKey(candidate) !=
                                _memoryFeedbackKey(memory),
                          )
                          .toList(),
                      associations: currentTrace.associations,
                      associationFeedbacks: associationFeedbacks,
                      onAssociationFeedback: onAssociationFeedback,
                      onFeedback: onMemoryFeedback == null
                          ? null
                          : (feedback) => onMemoryFeedback!(memory, feedback),
                      onRoomMove: onMemoryRoomMove == null
                          ? null
                          : (room) => onMemoryRoomMove!(memory, room),
                      onUndoCorrection: onUndoMemoryCorrection == null
                          ? null
                          : () => onUndoMemoryCorrection!(memory),
                      onOpenSource: onOpenMemorySource == null
                          ? null
                          : () => onOpenMemorySource!(memory),
                      onCopySource: onCopyMemorySource == null
                          ? null
                          : () => onCopyMemorySource!(memory),
                    ),
                  ),
            const SizedBox(height: 9),
            _SecondBrainSectionTitle(
              icon: Icons.add_link_outlined,
              title: '新增了什麼',
              trailing: '${currentTrace.newInsights.length} 筆',
            ),
            const SizedBox(height: 6),
            if (currentTrace.newInsights.isEmpty)
              const _SecondBrainMutedLine('這輪沒有新增可保存洞察。')
            else
              ...currentTrace.newInsights
                  .take(2)
                  .map((insight) => _SecondBrainNewInsightCard(insight)),
            if (currentTrace.associations.isNotEmpty) ...[
              const SizedBox(height: 9),
              _SecondBrainAssociationDashboard(
                associations: currentTrace.associations,
                feedbacks: associationFeedbacks,
              ),
            ],
            if (currentTrace.associations.isNotEmpty) ...[
              const SizedBox(height: 9),
              _SecondBrainSectionTitle(
                icon: Icons.hub_outlined,
                title: '新增關聯',
                trailing: '${currentTrace.associations.length} 條',
              ),
              const SizedBox(height: 6),
              ...currentTrace.associations
                  .take(2)
                  .map(
                    (association) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: _SecondBrainMutedLine(association),
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SecondBrainRoomDashboard extends StatelessWidget {
  final SecondBrainTrace trace;

  const _SecondBrainRoomDashboard({required this.trace});

  @override
  Widget build(BuildContext context) {
    final stats = _roomStatsFor(trace);
    final statsByRoom = {for (final stat in stats) stat.room: stat};
    final activeRooms = _dashboardRooms
        .where((room) => (statsByRoom[room]?.total ?? 0) > 0)
        .toList();
    final activeSources = _representativeSourcesFor(trace, statsByRoom);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.meeting_room_outlined,
                size: 15,
                color: BridgeDSColors.of(context).accentPurple,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '房間儀表',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _SecondBrainPill(label: '${activeRooms.length}/7 亮燈'),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '七個燈號代表第二大腦的主要房間；本輪有調用就亮綠燈，沒有用到就保持灰色。',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _dashboardRooms.map((room) {
              final stat = statsByRoom[room];
              return _SecondBrainRoomLamp(room: room, stat: stat);
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (activeSources.isEmpty)
            const _SecondBrainMutedLine(
              '本輪尚未調用房間來源。匯入資料、開啟專案或形成洞察後，亮燈房間會顯示代表來源。',
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: activeSources
                  .map(
                    (source) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SecondBrainRoomSourceLine(source: source),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  List<_SecondBrainRoomStat> _roomStatsFor(SecondBrainTrace trace) {
    final stats = <String, _SecondBrainRoomStat>{};
    for (final memory in trace.recalledMemories) {
      final room = memory.room.trim().isEmpty ? 'Files' : memory.room.trim();
      final current = stats[room] ?? _SecondBrainRoomStat(room: room);
      stats[room] = current.copyWith(recalledCount: current.recalledCount + 1);
    }
    for (final insight in trace.newInsights) {
      final room = insight.room.trim().isEmpty
          ? 'Insights'
          : insight.room.trim();
      final current = stats[room] ?? _SecondBrainRoomStat(room: room);
      stats[room] = current.copyWith(
        newInsightCount: current.newInsightCount + 1,
      );
    }
    final values = stats.values.toList()
      ..sort((a, b) {
        final scoreOrder = b.total.compareTo(a.total);
        if (scoreOrder != 0) return scoreOrder;
        return a.room.compareTo(b.room);
      });
    return values;
  }

  List<_SecondBrainRoomSource> _representativeSourcesFor(
    SecondBrainTrace trace,
    Map<String, _SecondBrainRoomStat> statsByRoom,
  ) {
    return _dashboardRooms
        .where((room) => (statsByRoom[room]?.total ?? 0) > 0)
        .map((room) {
          final stat = statsByRoom[room]!;
          final memory = trace.recalledMemories
              .where((memory) => memory.room == room)
              .cast<SecondBrainMemoryTrace?>()
              .firstWhere((memory) => memory != null, orElse: () => null);
          final label = memory == null
              ? '本輪新增洞察 ${stat.newInsightCount} 筆'
              : memory.sourceLabel;
          final path = memory?.sourcePath;
          return _SecondBrainRoomSource(
            room: room,
            sourceLabel: label,
            sourcePath: path,
          );
        })
        .toList();
  }
}

const _dashboardRooms = <String>[
  'Projects',
  'Files',
  'Insights',
  'Bridges',
  'Companions',
  'Doors',
  'Self',
];

class _SecondBrainRoomLamp extends StatelessWidget {
  final String room;
  final _SecondBrainRoomStat? stat;

  const _SecondBrainRoomLamp({required this.room, required this.stat});

  @override
  Widget build(BuildContext context) {
    final isActive = (stat?.total ?? 0) > 0;
    final color = isActive ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).textMuted;
    final background = isActive
        ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.13)
        : BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.72);
    final border = isActive
        ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.34)
        : BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.70);
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isActive
                  ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.18)
                  : BridgeDSColors.of(context).textMuted.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(_roomIcon(room), size: 18, color: color),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _roomDisplayName(room),
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: isActive ? BridgeDSColors.of(context).textPrimary : BridgeDSColors.of(context).textMuted,
                  height: 1.1,
                  fontWeight: FontWeight.w900,),
              ),
              const SizedBox(height: 2),
              Text(
                isActive ? '亮燈' : '未用',
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
                  height: 1,
                  fontWeight: FontWeight.w900,),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecondBrainRoomSource {
  final String room;
  final String sourceLabel;
  final String? sourcePath;

  const _SecondBrainRoomSource({
    required this.room,
    required this.sourceLabel,
    this.sourcePath,
  });
}

class _SecondBrainRoomSourceLine extends StatelessWidget {
  final _SecondBrainRoomSource source;

  const _SecondBrainRoomSourceLine({required this.source});

  @override
  Widget build(BuildContext context) {
    final text =
        '${_roomDisplayName(source.room)}：${source.sourceLabel}${source.sourcePath == null ? '' : ' · ${source.sourcePath}'}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_roomIcon(source.room), size: 13, color: BridgeDSColors.of(context).accentGreen),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              height: 1.3,
              fontWeight: FontWeight.w700,),
          ),
        ),
      ],
    );
  }
}

class _SecondBrainCorrectionLoopDashboard extends StatelessWidget {
  final List<SecondBrainMemoryTrace> memories;
  final Map<String, SecondBrainMemoryFeedback> feedbacks;
  final Map<String, SecondBrainRoom> roomOverrides;

  const _SecondBrainCorrectionLoopDashboard({
    required this.memories,
    required this.feedbacks,
    required this.roomOverrides,
  });

  @override
  Widget build(BuildContext context) {
    final currentKeys = memories.map(_memoryFeedbackKey).toSet();
    final currentFeedbacks = feedbacks.entries
        .where((entry) => currentKeys.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
    final boostCount = currentFeedbacks
        .where(
          (feedback) =>
              feedback == SecondBrainMemoryFeedback.useful ||
              feedback == SecondBrainMemoryFeedback.pin,
        )
        .length;
    final reduceCount = currentFeedbacks
        .where(
          (feedback) =>
              feedback == SecondBrainMemoryFeedback.irrelevant ||
              feedback == SecondBrainMemoryFeedback.mute,
        )
        .length;
    final movedCount = roomOverrides.keys
        .where((key) => currentKeys.contains(key))
        .length;
    final examples = memories
        .where((memory) {
          final key = _memoryFeedbackKey(memory);
          return feedbacks.containsKey(key) || roomOverrides.containsKey(key);
        })
        .take(2)
        .map((memory) {
          final key = _memoryFeedbackKey(memory);
          final feedback = feedbacks[key];
          final room = roomOverrides[key];
          final effect = _correctionEffectText(feedback, room);
          return '${memory.sourceLabel}：$effect';
        })
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_outlined,
                size: 15,
                color: BridgeDSColors.of(context).accentYellow,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '校正回路',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _SecondBrainPill(
                label: '${boostCount + reduceCount + movedCount} 筆校正',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SecondBrainCorrectionMetric(
                label: '提高召回',
                count: boostCount,
                color: BridgeDSColors.of(context).accentGreen,
              ),
              _SecondBrainCorrectionMetric(
                label: '降低召回',
                count: reduceCount,
                color: AppTheme.error,
              ),
              _SecondBrainCorrectionMetric(
                label: '移房間',
                count: movedCount,
                color: BridgeDSColors.of(context).accentPurple,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _correctionSummary(boostCount, reduceCount, movedCount),
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          if (examples.isNotEmpty) ...[
            const SizedBox(height: 7),
            ...examples.map(
              (example) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _SecondBrainMutedLine(example),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _correctionSummary(int boostCount, int reduceCount, int movedCount) {
    final parts = <String>[
      if (boostCount > 0) '$boostCount 筆會在相似問題中更容易被叫出來',
      if (reduceCount > 0) '$reduceCount 筆會降低召回或暫停引用',
      if (movedCount > 0) '$movedCount 筆會改用新房間作為檢索線索',
    ];
    if (parts.isEmpty) {
      return '還沒有校正效果。按「有用、不相關、常引用、不要引用」後，這裡會顯示下次召回會如何改變。';
    }
    return '${parts.join('；')}。';
  }
}

class _SecondBrainCorrectionMetric extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SecondBrainCorrectionMetric({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        '$label $count',
        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
          fontWeight: FontWeight.w900,),
      ),
    );
  }
}

class _SecondBrainPanelDensityGuide extends StatelessWidget {
  final SecondBrainTrace trace;

  const _SecondBrainPanelDensityGuide({required this.trace});

  @override
  Widget build(BuildContext context) {
    final memoryCount = trace.recalledMemories.length;
    final insightCount = trace.newInsights.length;
    final associationCount = trace.associations.length;
    final density = memoryCount + insightCount + associationCount >= 6
        ? '高密度'
        : memoryCount + insightCount + associationCount >= 3
        ? '標準'
        : '精簡';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 14,
            color: BridgeDSColors.of(context).accentPurple,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '面板密度：$density · 調閱 $memoryCount · 新增 $insightCount · 關聯 $associationCount',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                height: 1.25,
                fontWeight: FontWeight.w800,),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainCorrectionHistory extends StatelessWidget {
  final List<SecondBrainMemoryTrace> memories;
  final Map<String, SecondBrainMemoryFeedback> feedbacks;
  final Map<String, SecondBrainRoom> roomOverrides;

  const _SecondBrainCorrectionHistory({
    required this.memories,
    required this.feedbacks,
    required this.roomOverrides,
  });

  @override
  Widget build(BuildContext context) {
    final rows = memories
        .where((memory) {
          final key = _memoryFeedbackKey(memory);
          return feedbacks.containsKey(key) || roomOverrides.containsKey(key);
        })
        .map((memory) {
          final key = _memoryFeedbackKey(memory);
          final feedback = feedbacks[key];
          final room = roomOverrides[key];
          return '${memory.sourceLabel} · ${_correctionEffectText(feedback, room)}';
        })
        .take(3)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SecondBrainSectionTitle(
            icon: Icons.history_outlined,
            title: '校正歷史',
            trailing: '本輪',
          ),
          const SizedBox(height: 6),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SecondBrainMutedLine(row),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainMemoryConflictNotice extends StatelessWidget {
  final List<SecondBrainMemoryTrace> memories;
  final Map<String, SecondBrainMemoryFeedback> feedbacks;

  const _SecondBrainMemoryConflictNotice({
    required this.memories,
    required this.feedbacks,
  });

  @override
  Widget build(BuildContext context) {
    final lowered = memories.where((memory) {
      final feedback = feedbacks[_memoryFeedbackKey(memory)];
      return feedback == SecondBrainMemoryFeedback.irrelevant ||
          feedback == SecondBrainMemoryFeedback.mute;
    }).toList();
    if (lowered.isEmpty || memories.length < 2) return const SizedBox.shrink();
    final source = lowered.first;
    final alternatives = memories
        .where(
          (memory) => _memoryFeedbackKey(memory) != _memoryFeedbackKey(source),
        )
        .where(
          (memory) =>
              memory.room == source.room ||
              memory.tags.any((tag) => source.tags.contains(tag)),
        )
        .take(2)
        .toList();
    if (alternatives.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.report_problem_outlined,
            size: 15,
            color: AppTheme.error,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '可能記憶衝突：你降低了「${source.sourceLabel}」，同房間或同標籤仍有 ${alternatives.length} 筆可替代線索。下一次會優先避開被降低的資料。',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                height: 1.35,
                fontWeight: FontWeight.w800,),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainRoomStat {
  final String room;
  final int recalledCount;
  final int newInsightCount;

  const _SecondBrainRoomStat({
    required this.room,
    this.recalledCount = 0,
    this.newInsightCount = 0,
  });

  int get total => recalledCount + newInsightCount;

  _SecondBrainRoomStat copyWith({int? recalledCount, int? newInsightCount}) {
    return _SecondBrainRoomStat(
      room: room,
      recalledCount: recalledCount ?? this.recalledCount,
      newInsightCount: newInsightCount ?? this.newInsightCount,
    );
  }
}

class _SecondBrainAssociationDashboard extends StatelessWidget {
  final List<String> associations;
  final Map<String, SecondBrainAssociationFeedback> feedbacks;

  const _SecondBrainAssociationDashboard({
    required this.associations,
    required this.feedbacks,
  });

  @override
  Widget build(BuildContext context) {
    final useful = associations
        .where(
          (association) =>
              feedbacks[association] == SecondBrainAssociationFeedback.useful,
        )
        .toList();
    final wrong = associations
        .where(
          (association) =>
              feedbacks[association] == SecondBrainAssociationFeedback.wrong,
        )
        .toList();
    final neutral = associations.length - useful.length - wrong.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 15, color: BridgeDSColors.of(context).accentPurple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '關聯儀表板',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _SecondBrainPill(label: '${associations.length} 條關聯'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SecondBrainAssociationMetric(
                icon: Icons.trending_up_outlined,
                label: '強化召回',
                value: useful.length,
                color: BridgeDSColors.of(context).accentGreen,
              ),
              _SecondBrainAssociationMetric(
                icon: Icons.link_off_outlined,
                label: '降低誤連',
                value: wrong.length,
                color: AppTheme.error,
              ),
              _SecondBrainAssociationMetric(
                icon: Icons.tune_outlined,
                label: '待校準',
                value: neutral.clamp(0, associations.length),
                color: BridgeDSColors.of(context).textMuted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _associationDashboardSummary(useful.length, wrong.length, neutral),
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
          if (useful.isNotEmpty || wrong.isNotEmpty) ...[
            const SizedBox(height: 7),
            ...[
              ...useful
                  .take(1)
                  .map(
                    (association) => _SecondBrainAssociationBiasLine(
                      association: association,
                      feedback: SecondBrainAssociationFeedback.useful,
                    ),
                  ),
              ...wrong
                  .take(1)
                  .map(
                    (association) => _SecondBrainAssociationBiasLine(
                      association: association,
                      feedback: SecondBrainAssociationFeedback.wrong,
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }

  String _associationDashboardSummary(int useful, int wrong, int neutral) {
    if (useful == 0 && wrong == 0) {
      return '這些關聯尚未校準；標記「連得好」會提高相關記憶召回，標記「連錯了」會降低誤連。';
    }
    final parts = <String>[
      if (useful > 0) '$useful 條好關聯會提高相關記憶召回',
      if (wrong > 0) '$wrong 條錯關聯會降低誤連',
      if (neutral > 0) '$neutral 條仍等待校準',
    ];
    return '${parts.join('，')}。';
  }
}

class _SecondBrainAssociationMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _SecondBrainAssociationMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$label $value',
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
              fontWeight: FontWeight.w900,),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainAssociationBiasLine extends StatelessWidget {
  final String association;
  final SecondBrainAssociationFeedback feedback;

  const _SecondBrainAssociationBiasLine({
    required this.association,
    required this.feedback,
  });

  @override
  Widget build(BuildContext context) {
    final isUseful = feedback == SecondBrainAssociationFeedback.useful;
    final color = isUseful ? BridgeDSColors.of(context).accentGreen : AppTheme.error;
    final label = isUseful ? '提高召回' : '降低誤連';
    final icon = isUseful
        ? Icons.trending_up_outlined
        : Icons.link_off_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label：$association',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: color,
                height: 1.3,
                fontWeight: FontWeight.w800,),
            ),
          ),
        ],
      ),
    );
  }
}

String _roomDisplayName(String room) {
  switch (room) {
    case 'Self':
      return '自我房間';
    case 'Projects':
      return '計畫房間';
    case 'Files':
      return '檔案房間';
    case 'Doors':
      return '門房間';
    case 'Bridges':
      return '橋樑房間';
    case 'Companions':
      return '夥伴房間';
    case 'Pendulums':
      return '鐘擺線索';
    case 'Outputs':
      return '輸出房間';
    case 'Insights':
      return '洞察房間';
  }
  return room;
}

IconData _roomIcon(String room) {
  switch (room) {
    case 'Self':
      return Icons.person_outline;
    case 'Projects':
      return Icons.flag_outlined;
    case 'Files':
      return Icons.folder_open_outlined;
    case 'Doors':
      return Icons.meeting_room_outlined;
    case 'Bridges':
      return Icons.hub_outlined;
    case 'Companions':
      return Icons.auto_awesome_outlined;
    case 'Insights':
      return Icons.lightbulb_outline;
  }
  return Icons.grid_view_outlined;
}

String _memoryFeedbackKey(SecondBrainMemoryTrace memory) {
  final source = memory.sourcePath?.trim().isNotEmpty == true
      ? memory.sourcePath!.trim()
      : memory.sourceLabel.trim();
  return '$source|${memory.content.trim()}';
}

String _retrievalConfidenceFor(
  SecondBrainMemoryTrace memory,
  SecondBrainMemoryFeedback? feedback,
) {
  if (feedback == SecondBrainMemoryFeedback.irrelevant ||
      feedback == SecondBrainMemoryFeedback.mute) {
    return '需確認';
  }
  if (feedback == SecondBrainMemoryFeedback.pin ||
      memory.trustScore >= 78 ||
      memory.retrievalSignals.length >= 4) {
    return '高';
  }
  if (memory.trustScore < 45 || memory.retrievalSignals.length <= 1) {
    return '需確認';
  }
  return '中';
}

String _correctionEffectText(
  SecondBrainMemoryFeedback? feedback,
  SecondBrainRoom? roomOverride,
) {
  final roomText = roomOverride == null
      ? ''
      : '並改用「${roomOverride.zhLabel}」作為房間線索';
  final feedbackText = switch (feedback) {
    SecondBrainMemoryFeedback.useful => '相似問題會提高召回權重',
    SecondBrainMemoryFeedback.pin => '相似問題會優先召回這筆記憶',
    SecondBrainMemoryFeedback.irrelevant => '相似問題會降低召回，避免再次誤連',
    SecondBrainMemoryFeedback.mute => '預設不再引用這筆記憶',
    null => '依照新的房間位置重新檢索',
  };
  if (roomText.isEmpty) return feedbackText;
  return '$feedbackText，$roomText';
}

class _SecondBrainEmptyState extends StatelessWidget {
  const _SecondBrainEmptyState();

  @override
  Widget build(BuildContext context) {
    return Text(
      '這輪還沒有命中可用記憶或檔案索引。若對話形成穩定洞察，系統會存入本地洞察庫；若檔案已被索引，這裡會顯示房間與真實來源路徑。',
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
        height: 1.35,
        fontWeight: FontWeight.w600,),
    );
  }
}

class _SecondBrainSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String trailing;

  const _SecondBrainSectionTitle({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: BridgeDSColors.of(context).accentPurple),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              fontWeight: FontWeight.w900,),
          ),
        ),
        _SecondBrainPill(label: trailing),
      ],
    );
  }
}

class _SecondBrainMemoryCard extends StatelessWidget {
  final SecondBrainMemoryTrace memory;
  final SecondBrainMemoryFeedback? feedback;
  final SecondBrainRoom? roomOverride;
  final List<SecondBrainMemoryTrace> relatedMemories;
  final List<String> associations;
  final Map<String, SecondBrainAssociationFeedback> associationFeedbacks;
  final void Function(
    String association,
    SecondBrainAssociationFeedback feedback,
  )?
  onAssociationFeedback;
  final void Function(SecondBrainMemoryFeedback feedback)? onFeedback;
  final void Function(SecondBrainRoom room)? onRoomMove;
  final VoidCallback? onUndoCorrection;
  final VoidCallback? onOpenSource;
  final VoidCallback? onCopySource;

  const _SecondBrainMemoryCard({
    required this.memory,
    this.feedback,
    this.roomOverride,
    this.relatedMemories = const [],
    this.associations = const [],
    this.associationFeedbacks = const {},
    this.onAssociationFeedback,
    this.onFeedback,
    this.onRoomMove,
    this.onUndoCorrection,
    this.onOpenSource,
    this.onCopySource,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.78)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SecondBrainPill(
                label:
                    '房間：${roomOverride?.zhLabel ?? _roomDisplayName(memory.room)}',
              ),
              _SecondBrainPill(label: '信任 ${memory.trustScore}'),
              _SecondBrainConfidencePill(memory: memory, feedback: feedback),
              if (memory.freshnessLabel.trim().isNotEmpty)
                _SecondBrainPill(label: '鮮度：${memory.freshnessLabel}'),
              ...memory.tags.take(3).map((tag) => _SecondBrainPill(label: tag)),
            ],
          ),
          if (feedback == SecondBrainMemoryFeedback.pin ||
              feedback == SecondBrainMemoryFeedback.mute) ...[
            const SizedBox(height: 7),
            _SecondBrainVisibilityBanner(feedback: feedback!),
          ],
          if (onFeedback != null) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: SecondBrainMemoryFeedback.values
                  .map(
                    (item) => _SecondBrainFeedbackButton(
                      feedback: item,
                      selected: feedback == item,
                      onPressed: () => onFeedback!(item),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (onRoomMove != null) ...[
            const SizedBox(height: 7),
            _SecondBrainRoomMoveRow(
              selectedRoom: roomOverride,
              onRoomMove: onRoomMove!,
            ),
          ],
          if (feedback != null || roomOverride != null) ...[
            const SizedBox(height: 7),
            _SecondBrainCorrectionEffect(
              feedback: feedback,
              roomOverride: roomOverride,
              onUndo: onUndoCorrection,
            ),
          ],
          const SizedBox(height: 7),
          Text(
            memory.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          const SizedBox(height: 6),
          Text(
            '來源：${memory.sourceLabel}${memory.sourcePath == null ? '' : ' · ${memory.sourcePath}'}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              height: 1.3,
              fontWeight: FontWeight.w600,),
          ),
          if (memory.sourcePreview.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _SecondBrainSourcePreview(preview: memory.sourcePreview),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SecondBrainSourceActionButton(
                keyValue: 'second-brain-memory-detail',
                icon: Icons.article_outlined,
                label: '檢視細節',
                onPressed: () => _showDetailDrawer(context),
              ),
              if (_hasSourcePath(memory) && onOpenSource != null)
                _SecondBrainSourceActionButton(
                  keyValue: 'second-brain-open-source',
                  icon: Icons.open_in_new_outlined,
                  label: '開啟來源',
                  onPressed: onOpenSource!,
                ),
              if (_hasSourcePath(memory) && onCopySource != null)
                _SecondBrainSourceActionButton(
                  keyValue: 'second-brain-copy-source',
                  icon: Icons.copy_outlined,
                  label: '複製路徑',
                  onPressed: onCopySource!,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '為什麼調閱：${memory.reason}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
          if (memory.retrievalSignals.isNotEmpty) ...[
            const SizedBox(height: 7),
            _SecondBrainRetrievalSignals(signals: memory.retrievalSignals),
          ],
        ],
      ),
    );
  }

  bool _hasSourcePath(SecondBrainMemoryTrace memory) {
    return memory.sourcePath?.trim().isNotEmpty == true;
  }

  void _showDetailDrawer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SecondBrainMemoryDetailSheet(
        memory: memory,
        roomOverride: roomOverride,
        feedback: feedback,
        relatedMemories: relatedMemories,
        associations: associations,
        associationFeedbacks: associationFeedbacks,
        onAssociationFeedback: onAssociationFeedback,
        onOpenSource: onOpenSource,
        onCopySource: onCopySource,
      ),
    );
  }
}

class _SecondBrainConfidencePill extends StatelessWidget {
  final SecondBrainMemoryTrace memory;
  final SecondBrainMemoryFeedback? feedback;

  const _SecondBrainConfidencePill({required this.memory, this.feedback});

  @override
  Widget build(BuildContext context) {
    final label = _retrievalConfidenceFor(memory, feedback);
    final color = switch (label) {
      '高' => BridgeDSColors.of(context).accentGreen,
      '需確認' => BridgeDSColors.of(context).accentYellow,
      _ => BridgeDSColors.of(context).accentPurple,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        '召回信心：$label',
        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
          fontWeight: FontWeight.w900,),
      ),
    );
  }
}

class _SecondBrainVisibilityBanner extends StatelessWidget {
  final SecondBrainMemoryFeedback feedback;

  const _SecondBrainVisibilityBanner({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final muted = feedback == SecondBrainMemoryFeedback.mute;
    final color = muted ? AppTheme.error : BridgeDSColors.of(context).accentGreen;
    final text = muted ? '這筆記憶已標成「不要再引用」' : '這筆記憶已釘選為「之後常引用」';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            muted ? Icons.visibility_off_outlined : Icons.push_pin_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
                fontWeight: FontWeight.w900,),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainSourcePreview extends StatelessWidget {
  final String preview;

  const _SecondBrainSourcePreview({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.65)),
      ),
      child: Text(
        '來源預覽：$preview',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
          height: 1.35,
          fontWeight: FontWeight.w700,),
      ),
    );
  }
}

class _SecondBrainFeedbackButton extends StatelessWidget {
  final SecondBrainMemoryFeedback feedback;
  final bool selected;
  final VoidCallback? onPressed;

  const _SecondBrainFeedbackButton({
    required this.feedback,
    required this.selected,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (feedback) {
      SecondBrainMemoryFeedback.useful => BridgeDSColors.of(context).accentGreen,
      SecondBrainMemoryFeedback.irrelevant => AppTheme.error,
      SecondBrainMemoryFeedback.pin => BridgeDSColors.of(context).accentPurple,
      SecondBrainMemoryFeedback.mute => BridgeDSColors.of(context).accentYellow,
    };
    final icon = switch (feedback) {
      SecondBrainMemoryFeedback.useful => Icons.check_circle_outline,
      SecondBrainMemoryFeedback.irrelevant => Icons.block_outlined,
      SecondBrainMemoryFeedback.pin => Icons.push_pin_outlined,
      SecondBrainMemoryFeedback.mute => Icons.visibility_off_outlined,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: SelectionContainer.disabled(
        child: GestureDetector(
          key: ValueKey('second-brain-feedback-${feedback.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: color.withValues(alpha: selected ? 0.0 : 0.42),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: selected ? Colors.white : color),
                const SizedBox(width: 4),
                Text(
                  feedback.label,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w900,),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondBrainMemoryDetailSheet extends StatelessWidget {
  final SecondBrainMemoryTrace memory;
  final SecondBrainRoom? roomOverride;
  final SecondBrainMemoryFeedback? feedback;
  final List<SecondBrainMemoryTrace> relatedMemories;
  final List<String> associations;
  final Map<String, SecondBrainAssociationFeedback> associationFeedbacks;
  final void Function(
    String association,
    SecondBrainAssociationFeedback feedback,
  )?
  onAssociationFeedback;
  final VoidCallback? onOpenSource;
  final VoidCallback? onCopySource;

  const _SecondBrainMemoryDetailSheet({
    required this.memory,
    this.roomOverride,
    this.feedback,
    this.relatedMemories = const [],
    this.associations = const [],
    this.associationFeedbacks = const {},
    this.onAssociationFeedback,
    this.onOpenSource,
    this.onCopySource,
  });

  @override
  Widget build(BuildContext context) {
    final sourcePath = memory.sourcePath?.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.20)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.article_outlined,
                        color: BridgeDSColors.of(context).accentPurple,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '記憶細節',
                            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                              fontWeight: FontWeight.w900,),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '檢查 AI 這次調用了哪筆第二大腦資料。',
                            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                              fontWeight: FontWeight.w600,),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '關閉',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _SecondBrainPill(
                      label:
                          '房間：${roomOverride?.zhLabel ?? _roomDisplayName(memory.room)}',
                    ),
                    _SecondBrainPill(label: '信任 ${memory.trustScore}'),
                    _SecondBrainPill(
                      label: '信心：${_retrievalConfidenceFor(memory, feedback)}',
                    ),
                    if (memory.freshnessLabel.trim().isNotEmpty)
                      _SecondBrainPill(label: '鮮度：${memory.freshnessLabel}'),
                    if (feedback != null)
                      _SecondBrainPill(label: '回饋：${feedback!.label}'),
                  ],
                ),
                const SizedBox(height: 12),
                _SecondBrainDetailBlock(title: '記憶內容', body: memory.content),
                if (memory.sourcePreview.trim().isNotEmpty)
                  _SecondBrainDetailBlock(
                    title: '來源預覽',
                    body: memory.sourcePreview,
                  ),
                _SecondBrainDetailBlock(title: '為什麼調閱', body: memory.reason),
                if (memory.retrievalSignals.isNotEmpty)
                  _SecondBrainDetailBlock(
                    title: '召回線索',
                    body: memory.retrievalSignals.join('\n'),
                  ),
                _SecondBrainDetailBlock(
                  title: '來源名稱',
                  body: memory.sourceLabel,
                ),
                if (sourcePath != null && sourcePath.isNotEmpty)
                  _SecondBrainDetailBlock(title: '來源位置', body: sourcePath),
                if (memory.tags.isNotEmpty)
                  _SecondBrainDetailBlock(
                    title: '標籤',
                    body: memory.tags.join('、'),
                  ),
                _SecondBrainRelationGraph(
                  memory: memory,
                  roomOverride: roomOverride,
                  relatedMemories: relatedMemories,
                  associations: associations,
                  associationFeedbacks: associationFeedbacks,
                  onAssociationFeedback: onAssociationFeedback,
                ),
                if (sourcePath != null &&
                    sourcePath.isNotEmpty &&
                    (onOpenSource != null || onCopySource != null)) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onOpenSource != null)
                        _SecondBrainSourceActionButton(
                          keyValue: 'second-brain-detail-open-source',
                          icon: Icons.open_in_new_outlined,
                          label: '開啟來源',
                          onPressed: onOpenSource!,
                        ),
                      if (onCopySource != null)
                        _SecondBrainSourceActionButton(
                          keyValue: 'second-brain-detail-copy-source',
                          icon: Icons.copy_outlined,
                          label: '複製路徑',
                          onPressed: onCopySource!,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondBrainRelationGraph extends StatelessWidget {
  final SecondBrainMemoryTrace memory;
  final SecondBrainRoom? roomOverride;
  final List<SecondBrainMemoryTrace> relatedMemories;
  final List<String> associations;
  final Map<String, SecondBrainAssociationFeedback> associationFeedbacks;
  final void Function(
    String association,
    SecondBrainAssociationFeedback feedback,
  )?
  onAssociationFeedback;

  const _SecondBrainRelationGraph({
    required this.memory,
    this.roomOverride,
    this.relatedMemories = const [],
    this.associations = const [],
    this.associationFeedbacks = const {},
    this.onAssociationFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final sourcePath = memory.sourcePath?.trim();
    final sameRoom = relatedMemories
        .where((item) => item.room == memory.room)
        .take(2)
        .toList();
    final sharedTags = relatedMemories
        .where((item) => item.tags.any(memory.tags.contains))
        .take(2)
        .toList();
    final relationCount =
        sameRoom.length +
        sharedTags.length +
        associations.length +
        (sourcePath?.isNotEmpty == true ? 1 : 0);

    return Container(
      key: const ValueKey('second-brain-relation-graph'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 15, color: BridgeDSColors.of(context).accentPurple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '記憶關聯圖',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _SecondBrainPill(label: '$relationCount 條線索'),
            ],
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SecondBrainPill(label: '核心'),
              _SecondBrainPill(label: '房間'),
              _SecondBrainPill(label: '來源'),
              _SecondBrainPill(label: '標籤'),
              _SecondBrainPill(label: '使用者回饋'),
            ],
          ),
          const SizedBox(height: 8),
          _SecondBrainRelationNode(
            icon: Icons.radio_button_checked,
            title: '核心記憶',
            body: memory.content,
            emphasized: true,
          ),
          _SecondBrainRelationNode(
            icon: Icons.meeting_room_outlined,
            title: '連到房間',
            body: roomOverride?.zhLabel ?? _roomDisplayName(memory.room),
          ),
          if (sourcePath != null && sourcePath.isNotEmpty)
            _SecondBrainRelationNode(
              icon: Icons.description_outlined,
              title: '連到來源',
              body: '${memory.sourceLabel} · $sourcePath',
            ),
          if (memory.tags.isNotEmpty)
            _SecondBrainRelationNode(
              icon: Icons.sell_outlined,
              title: '連到標籤',
              body: memory.tags.join('、'),
            ),
          if (sameRoom.isNotEmpty)
            _SecondBrainRelationNode(
              icon: Icons.account_tree_outlined,
              title: '同房間記憶',
              body: sameRoom
                  .map((item) => '${item.sourceLabel}：${item.content}')
                  .join('\n'),
            ),
          if (sharedTags.isNotEmpty)
            _SecondBrainRelationNode(
              icon: Icons.join_inner_outlined,
              title: '共同標籤記憶',
              body: sharedTags
                  .map((item) => '${item.sourceLabel}：${item.tags.join('、')}')
                  .join('\n'),
            ),
          if (associations.isNotEmpty) ...[
            _SecondBrainRelationNode(
              icon: Icons.add_link_outlined,
              title: '本輪新增關聯',
              body: associations.take(3).join('\n'),
            ),
            if (onAssociationFeedback != null) ...[
              const SizedBox(height: 2),
              ...associations
                  .take(3)
                  .map(
                    (association) => _SecondBrainAssociationFeedbackRow(
                      association: association,
                      feedback: associationFeedbacks[association],
                      onFeedback: (feedback) =>
                          onAssociationFeedback!(association, feedback),
                    ),
                  ),
            ],
          ],
          if (relationCount == 0)
            const _SecondBrainMutedLine(
              '這筆記憶目前還沒有足夠關聯。之後被更多任務引用、移動房間或補上標籤後，圖譜會變密。',
            ),
        ],
      ),
    );
  }
}

class _SecondBrainRelationNode extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool emphasized;

  const _SecondBrainRelationNode({
    required this.icon,
    required this.title,
    required this.body,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: emphasized
            ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10)
            : BridgeDSColors.of(context).canvas.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: emphasized
              ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.24)
              : BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: BridgeDSColors.of(context).accentPurple),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                    fontWeight: FontWeight.w900,),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    height: 1.35,
                    fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainAssociationFeedbackRow extends StatelessWidget {
  final String association;
  final SecondBrainAssociationFeedback? feedback;
  final void Function(SecondBrainAssociationFeedback feedback) onFeedback;

  const _SecondBrainAssociationFeedbackRow({
    required this.association,
    required this.feedback,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            association,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: SecondBrainAssociationFeedback.values
                .map(
                  (item) => _SecondBrainAssociationFeedbackButton(
                    feedback: item,
                    selected: feedback == item,
                    onPressed: () => onFeedback(item),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainAssociationFeedbackButton extends StatelessWidget {
  final SecondBrainAssociationFeedback feedback;
  final bool selected;
  final VoidCallback onPressed;

  const _SecondBrainAssociationFeedbackButton({
    required this.feedback,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (feedback) {
      SecondBrainAssociationFeedback.useful => BridgeDSColors.of(context).accentGreen,
      SecondBrainAssociationFeedback.wrong => AppTheme.error,
    };
    final icon = switch (feedback) {
      SecondBrainAssociationFeedback.useful => Icons.check_circle_outline,
      SecondBrainAssociationFeedback.wrong => Icons.link_off_outlined,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: SelectionContainer.disabled(
        child: GestureDetector(
          key: ValueKey('second-brain-association-feedback-${feedback.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: color.withValues(alpha: selected ? 0.0 : 0.42),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: selected ? Colors.white : color),
                const SizedBox(width: 4),
                Text(
                  feedback.label,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w900,),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondBrainDetailBlock extends StatelessWidget {
  final String title;
  final String body;

  const _SecondBrainDetailBlock({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
              fontWeight: FontWeight.w900,),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              height: 1.42,
              fontWeight: FontWeight.w700,),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainSourceActionButton extends StatelessWidget {
  final String keyValue;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SecondBrainSourceActionButton({
    required this.keyValue,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey(keyValue),
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: BridgeDSColors.of(context).accentPurple),
            const SizedBox(width: 5),
            Text(
              label,
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                fontWeight: FontWeight.w900,),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondBrainRetrievalSignals extends StatelessWidget {
  final List<String> signals;

  const _SecondBrainRetrievalSignals({required this.signals});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.manage_search_outlined,
                size: 14,
                color: BridgeDSColors.of(context).accentPurple,
              ),
              SizedBox(width: 5),
              Text(
                '召回線索',
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                  fontWeight: FontWeight.w900,),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: signals
                .take(4)
                .map((signal) => _SecondBrainPill(label: signal))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainCorrectionEffect extends StatelessWidget {
  final SecondBrainMemoryFeedback? feedback;
  final SecondBrainRoom? roomOverride;
  final VoidCallback? onUndo;

  const _SecondBrainCorrectionEffect({
    this.feedback,
    this.roomOverride,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final text = _correctionEffectText(feedback, roomOverride);
    final color = switch (feedback) {
      SecondBrainMemoryFeedback.useful ||
      SecondBrainMemoryFeedback.pin => BridgeDSColors.of(context).accentGreen,
      SecondBrainMemoryFeedback.irrelevant ||
      SecondBrainMemoryFeedback.mute => AppTheme.error,
      null => BridgeDSColors.of(context).accentPurple,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync_alt_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '下次召回：$text',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: color,
                height: 1.35,
                fontWeight: FontWeight.w800,),
            ),
          ),
          if (onUndo != null) ...[
            const SizedBox(width: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: onUndo,
              icon: const Icon(Icons.undo_outlined, size: 14),
              label: Text(
                '撤回',
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SecondBrainRoomMoveRow extends StatelessWidget {
  final SecondBrainRoom? selectedRoom;
  final void Function(SecondBrainRoom room) onRoomMove;

  const _SecondBrainRoomMoveRow({this.selectedRoom, required this.onRoomMove});

  @override
  Widget build(BuildContext context) {
    final label = selectedRoom == null
        ? '移到房間'
        : '已移到 ${selectedRoom!.zhLabel}';
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SecondBrainPill(label: label),
        ...SecondBrainRoom.values.map(
          (room) => _SecondBrainRoomMoveButton(
            room: room,
            selected: selectedRoom == room,
            onPressed: () => onRoomMove(room),
          ),
        ),
      ],
    );
  }
}

class _SecondBrainRoomMoveButton extends StatelessWidget {
  final SecondBrainRoom room;
  final bool selected;
  final VoidCallback onPressed;

  const _SecondBrainRoomMoveButton({
    required this.room,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('second-brain-move-room-${room.label}'),
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? BridgeDSColors.of(context).accentPurple
              : BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: BridgeDSColors.of(context).accentPurple.withValues(alpha: selected ? 0.0 : 0.32),
          ),
        ),
        child: Text(
          room.zhLabel,
          style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: selected ? Colors.white : BridgeDSColors.of(context).accentPurple,
            fontWeight: FontWeight.w900,),
        ),
      ),
    );
  }
}

class _SecondBrainNewInsightCard extends StatelessWidget {
  final SecondBrainNewInsightTrace insight;

  const _SecondBrainNewInsightCard(this.insight);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SecondBrainPill(label: '存入：${insight.room}'),
              ...insight.tags
                  .take(3)
                  .map((tag) => _SecondBrainPill(label: tag)),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            insight.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
        ],
      ),
    );
  }
}

class _SecondBrainMutedLine extends StatelessWidget {
  final String text;

  const _SecondBrainMutedLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
        height: 1.35,
        fontWeight: FontWeight.w600,),
    );
  }
}

class _SecondBrainPill extends StatelessWidget {
  final String label;

  const _SecondBrainPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.78)),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
          fontWeight: FontWeight.w800,),
      ),
    );
  }
}

class _AgentMotivationCard extends StatelessWidget {
  final AgentMotivationSnapshot snapshot;

  const _AgentMotivationCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 16,
                  color: BridgeDSColors.of(context).accentYellow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '內在驅動',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${snapshot.agentName} · Drive Lv ${snapshot.driveLevel} · ${snapshot.driveXp} XP',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MotivationMetric(label: '準確度', value: snapshot.accuracyScore),
              _MotivationMetric(label: '貼近度', value: snapshot.resonanceScore),
              _MotivationMetric(label: '自主性', value: snapshot.autonomyScore),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '學習焦點：${snapshot.learningFocus}',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          if (snapshot.hasRecoveryRoute) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                '通關路線：${snapshot.activeRecoveryRoute}',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                  height: 1.35,
                  fontWeight: FontWeight.w800,),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '最新信號：${snapshot.lastSignal}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
        ],
      ),
    );
  }
}

class _MotivationMetric extends StatelessWidget {
  final String label;
  final int value;

  const _MotivationMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              fontWeight: FontWeight.w700,),
          ),
          Text(
            '$value',
            style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: _scoreColor(value),
              fontWeight: FontWeight.w900,),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(int value) {
    if (value >= 75) return BridgeDS.accentGreen;
    if (value >= 45) return BridgeDS.accentYellow;
    return AppTheme.error;
  }
}

class _BrainActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _BrainActionRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: BridgeDSColors.of(context).accentPurple),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                  fontWeight: FontWeight.w900,),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                  height: 1.35,
                  fontWeight: FontWeight.w600,),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DoorDecisionSection extends StatelessWidget {
  final DoorDecision? decision;
  final DoorDecisionPendingReturn? pendingReturn;
  final void Function(DoorDecision decision, DoorDecisionChoice choice)?
  onDoorChoice;
  final VoidCallback? onResumePendingDoor;
  final VoidCallback? onClearPendingDoor;

  const _DoorDecisionSection({
    required this.decision,
    required this.pendingReturn,
    required this.onDoorChoice,
    required this.onResumePendingDoor,
    required this.onClearPendingDoor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (decision != null) _DoorDecisionCard(decision!, onDoorChoice),
        if (decision != null && pendingReturn != null)
          const SizedBox(height: 8),
        if (pendingReturn != null)
          _PendingDoorReturnCard(
            pending: pendingReturn!,
            onResume: onResumePendingDoor,
            onClear: onClearPendingDoor,
          ),
      ],
    );
  }
}

class _DoorDecisionCard extends StatelessWidget {
  final DoorDecision decision;
  final void Function(DoorDecision decision, DoorDecisionChoice choice)?
  onDoorChoice;

  const _DoorDecisionCard(this.decision, this.onDoorChoice);

  @override
  Widget build(BuildContext context) {
    final isFlow = decision.navigationKind == NavigationDecisionKind.flow;
    final accent = isFlow ? BridgeDSColors.of(context).accentPurple : BridgeDSColors.of(context).accentYellow;
    return Container(
      key: const ValueKey('door-decision-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFlow
                      ? Icons.water_drop_outlined
                      : Icons.door_front_door_outlined,
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  decision.title,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _RecommendationPill(
                decision.recommendedChoice,
                navigationKind: decision.navigationKind,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            decision.summary,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
          const SizedBox(height: 8),
          _DoorOptionLine(
            label: decision.mainlineLabel,
            body: decision.mainlineReason,
            selected: decision.recommendedChoice == DoorDecisionChoice.mainline,
          ),
          const SizedBox(height: 6),
          _DoorOptionLine(
            label: decision.branchLabel,
            body: decision.branchReason,
            selected: decision.recommendedChoice == DoorDecisionChoice.branch,
          ),
          const SizedBox(height: 8),
          Text(
            '建議：${decision.recommendationReason}',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DoorChoiceButton(
                label: decision.mainlineLabel,
                icon: Icons.route_outlined,
                filled:
                    decision.recommendedChoice == DoorDecisionChoice.mainline,
                onTap: () =>
                    onDoorChoice?.call(decision, DoorDecisionChoice.mainline),
              ),
              _DoorChoiceButton(
                label: decision.branchLabel,
                icon: Icons.call_split_outlined,
                filled: decision.recommendedChoice == DoorDecisionChoice.branch,
                onTap: () =>
                    onDoorChoice?.call(decision, DoorDecisionChoice.branch),
              ),
              _DoorChoiceButton(
                label: isFlow ? '暫存這股水流' : '暫存這扇門',
                icon: isFlow
                    ? Icons.bookmark_border_outlined
                    : Icons.bookmark_add_outlined,
                filled: false,
                onTap: () =>
                    onDoorChoice?.call(decision, DoorDecisionChoice.pause),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoorOptionLine extends StatelessWidget {
  final String label;
  final String body;
  final bool selected;

  const _DoorOptionLine({
    required this.label,
    required this.body,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 15,
          color: selected ? BridgeDSColors.of(context).accentPurple : BridgeDSColors.of(context).textMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                height: 1.3,
                fontWeight: FontWeight.w600,),
              children: [
                TextSpan(
                  text: '$label：',
                  style: TextStyle(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecommendationPill extends StatelessWidget {
  final DoorDecisionChoice choice;
  final NavigationDecisionKind navigationKind;

  const _RecommendationPill(
    this.choice, {
    this.navigationKind = NavigationDecisionKind.door,
  });

  @override
  Widget build(BuildContext context) {
    final label = navigationKind == NavigationDecisionKind.flow
        ? switch (choice) {
            DoorDecisionChoice.mainline => '建議順流',
            DoorDecisionChoice.branch => '建議回主線',
            DoorDecisionChoice.pause => '建議暫存',
          }
        : switch (choice) {
            DoorDecisionChoice.mainline => '建議主線',
            DoorDecisionChoice.branch => '建議支線',
            DoorDecisionChoice.pause => '建議暫存',
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
          fontWeight: FontWeight.w900,),
      ),
    );
  }
}

class _DoorChoiceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _DoorChoiceButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label),
    );
  }
}

class _PendingDoorReturnCard extends StatelessWidget {
  final DoorDecisionPendingReturn pending;
  final VoidCallback? onResume;
  final VoidCallback? onClear;

  const _PendingDoorReturnCard({
    required this.pending,
    required this.onResume,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isFlow = pending.navigationKind == NavigationDecisionKind.flow;
    return Container(
      key: const ValueKey('pending-door-return-card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bookmark_added_outlined,
                size: 17,
                color: BridgeDSColors.of(context).accentPurple,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${isFlow ? '待回流水流' : '待回流門'}：${pending.deferredLabel}',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isFlow
                ? '剛才選擇了「${pending.chosenLabel}」，系統已記住這股未收完的水流。完成目前階段後，可以回來收尾：${pending.sourceSummary}'
                : '剛才選擇了「${pending.chosenLabel}」，系統已記住未走的門。完成目前階段後，可以回來處理：${pending.sourceSummary}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.keyboard_return_outlined, size: 15),
                label: Text(isFlow ? '回到這股水流' : '回到這扇門'),
              ),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.done_all_outlined, size: 15),
                label: const Text('已處理'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrainInstrumentHeader extends StatelessWidget {
  const _BrainInstrumentHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.tune_outlined, size: 15, color: BridgeDSColors.of(context).accentPurple),
        SizedBox(width: 6),
        Text(
          '思維儀表',
          style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
            fontWeight: FontWeight.w900,),
        ),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            '用來看見 AI 正在如何判斷這一輪對話。',
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              fontWeight: FontWeight.w600,),
          ),
        ),
      ],
    );
  }
}

class _BrainChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String explanation;

  const _BrainChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: BridgeDSColors.of(context).accentPurple),
          const SizedBox(width: 5),
          Text(
            '$label：',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
              color: BridgeDSColors.of(context).textMuted,),
          ),
          Text(
            value,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
              color: BridgeDSColors.of(context).textPrimary,),
          ),
          const SizedBox(width: 3),
          _InfoButton(title: label, body: explanation, mini: true),
        ],
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  final String title;
  final String body;
  final bool mini;

  const _InfoButton({
    required this.title,
    required this.body,
    this.mini = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = mini ? 20.0 : 26.0;
    return Tooltip(
      message: '$title 說明',
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: () => _showExplanation(context),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.help_outline,
            size: mini ? 14 : 17,
            color: BridgeDSColors.of(context).textMuted,
          ),
        ),
      ),
    );
  }

  void _showExplanation(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                    color: BridgeDSColors.of(context).textPrimary,),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.55,
                    color: BridgeDSColors.of(context).textSecondary,),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _attentionLabel(AttentionState state) {
  switch (state) {
    case AttentionState.clear:
      return '清醒';
    case AttentionState.captured:
      return '被捕獲';
    case AttentionState.scattered:
      return '分散';
  }
}

String _importanceLabel(ImportanceLevel level) {
  switch (level) {
    case ImportanceLevel.low:
      return '低';
    case ImportanceLevel.balanced:
      return '平衡';
    case ImportanceLevel.elevated:
      return '偏高';
    case ImportanceLevel.excessive:
      return '過高';
  }
}

String _doorLabel(List<DoorCandidate> doors) {
  if (doors.isEmpty) return '未明';
  final label = doors.first.label.trim();
  switch (doors.first.kind) {
    case DoorKind.ownDoor:
      return label.isEmpty ? '自己的門' : label;
    case DoorKind.foreignDoor:
      return label.isEmpty ? '外部門' : label;
    case DoorKind.falseDoor:
      return label.isEmpty ? '假門' : label;
    case DoorKind.currentLink:
      return label.isEmpty ? '下一環' : label;
  }
}

String _flowLabel(FlowState state) {
  switch (state) {
    case FlowState.withFlow:
      return '順流';
    case FlowState.againstFlow:
      return '逆流';
    case FlowState.stalled:
      return '停滯';
    case FlowState.unknown:
      return '觀察中';
  }
}

String _moveLabel(RecommendedMove move) {
  switch (move) {
    case RecommendedMove.answerDirectly:
      return '直接回應';
    case RecommendedMove.askClarifyingQuestion:
      return '先釐清';
    case RecommendedMove.reduceImportance:
      return '降重要性';
    case RecommendedMove.convertToOutput:
      return '轉成輸出';
    case RecommendedMove.takeNextAction:
      return '推進下一步';
    case RecommendedMove.routeBridge:
      return '接橋';
    case RecommendedMove.declareIntention:
      return '宣告意圖';
    case RecommendedMove.recordWaterAction:
      return '記錄行動';
  }
}

// [教練 Agent Sprint 2 2026-07-04] 宣告/確認/行動三欄
/// 顯示 open intentions、confirmed intentions、今日已行動。
class _IntentionSection extends StatelessWidget {
  final List<IntentionRecord> intentions;

  const _IntentionSection({required this.intentions});

  @override
  Widget build(BuildContext context) {
    final open = intentions.where((i) => i.isOpen).toList();
    final confirmed = intentions.where((i) => i.isConfirmed).toList();
    final acted = intentions.where((i) => i.isActed).toList();

    if (open.isEmpty && confirmed.isEmpty && acted.isEmpty) {
      return const SizedBox.shrink();
    }

    return _InstrumentDisclosureSection(
      icon: Icons.flag_outlined,
      title: '宣告與行動',
      summary: _summary(open, confirmed, acted),
      initiallyExpanded: open.isNotEmpty || confirmed.isNotEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (open.isNotEmpty) ...[
            _IntentionSubSection(
              title: '待確認',
              icon: Icons.hourglass_top_outlined,
              color: BridgeDSColors.of(context).accentYellow,
              records: open,
            ),
            if (confirmed.isNotEmpty || acted.isNotEmpty)
              const SizedBox(height: 8),
          ],
          if (confirmed.isNotEmpty) ...[
            _IntentionSubSection(
              title: '已確認',
              icon: Icons.check_circle_outline,
              color: BridgeDSColors.of(context).accentPurple,
              records: confirmed,
            ),
            if (acted.isNotEmpty) const SizedBox(height: 8),
          ],
          if (acted.isNotEmpty)
            _IntentionSubSection(
              title: '今日行動',
              icon: Icons.task_alt_outlined,
              color: BridgeDSColors.of(context).accentGreen,
              records: acted,
            ),
        ],
      ),
    );
  }

  String _summary(List<IntentionRecord> open, List<IntentionRecord> confirmed,
      List<IntentionRecord> acted) {
    final parts = <String>[];
    if (open.isNotEmpty) parts.add('待確認 ${open.length}');
    if (confirmed.isNotEmpty) parts.add('已確認 ${confirmed.length}');
    if (acted.isNotEmpty) parts.add('已行動 ${acted.length}');
    return parts.isEmpty ? '無' : parts.join(' · ');
  }
}

class _IntentionSubSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<IntentionRecord> records;

  const _IntentionSubSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              '$title (${records.length})',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                color: color,),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...records.map((r) => _IntentionTile(record: r, color: color)),
      ],
    );
  }
}

class _IntentionTile extends StatelessWidget {
  final IntentionRecord record;
  final Color color;

  const _IntentionTile({required this.record, required this.color});

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(record.createdAtMs);
    final timeStr = '${time.hour.toString().padLeft(2, '0')}'
        ':${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(left: 17, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              fontWeight: FontWeight.w600,),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              record.userMessage,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                height: 1.3,),
            ),
          ),
        ],
      ),
    );
  }
}
