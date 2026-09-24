// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// BrainReflectionPanel 參數束：把 ~28 個參數收成一個 data class，
// 讓 dock / sheet / expanded content 共用同一份配置。
// 行為不變，純搬移。
import 'package:flutter/material.dart';

import '../../../models/agent_activity.dart';
import '../../../models/capability_catalog.dart';
import '../../../models/intention_record.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../models/second_brain_trace.dart';
import '../../../models/transurfing_brain.dart';
import '../../../services/agent_motivation_engine.dart';
import '../../../services/brain_pipeline/audit/audit_store.dart';
import '../../../services/brain_pipeline/heart_mind/heart_mind_dialogue.dart';
import '../../../widgets/brain_reflection_panel.dart';

/// 把 [BrainReflectionPanel] 需要的所有資料和 callback 收成一束。
class BrainReflectionPanelData {
  final BrainReflection reflection;
  final String? activeDoorTitle;
  final int turnCount;
  final int contextChars;
  final AgentActivityTelemetry effectiveTelemetry;
  final AgentActivityStage? activeStage;
  final String? activeBridgeActionLabel;
  final String? imageProgressLabel;
  final bool isWorking;
  final List<String> recalledInsights;
  final SecondBrainTrace? secondBrainTrace;
  final BrainSkillRegistrySnapshot? brainSkillRegistry;
  final AgentMotivationSnapshot? agentMotivation;
  final Map<String, SecondBrainMemoryFeedback> secondBrainMemoryFeedbacks;
  final Map<String, SecondBrainAssociationFeedback>
      secondBrainAssociationFeedbacks;
  final void Function(
    SecondBrainMemoryTrace memory,
    SecondBrainMemoryFeedback feedback,
  )? onSecondBrainMemoryFeedback;
  final void Function(
    String association,
    SecondBrainAssociationFeedback feedback,
  )? onSecondBrainAssociationFeedback;
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
  final List<IntentionRecord> intentions;
  final PendulumAuditSummary? auditSummary;
  final HeartMindDialogue? heartMindDialogue;

  const BrainReflectionPanelData({
    required this.reflection,
    required this.activeDoorTitle,
    required this.turnCount,
    required this.contextChars,
    required this.effectiveTelemetry,
    required this.activeStage,
    required this.activeBridgeActionLabel,
    this.imageProgressLabel,
    required this.isWorking,
    required this.recalledInsights,
    required this.secondBrainTrace,
    required this.brainSkillRegistry,
    required this.agentMotivation,
    required this.secondBrainMemoryFeedbacks,
    required this.secondBrainAssociationFeedbacks,
    required this.onSecondBrainMemoryFeedback,
    required this.onSecondBrainAssociationFeedback,
    required this.secondBrainMemoryRoomOverrides,
    required this.onSecondBrainMemoryRoomMove,
    required this.onUndoSecondBrainMemoryCorrection,
    required this.onOpenSecondBrainMemorySource,
    required this.onCopySecondBrainMemorySource,
    required this.onImportSecondBrainFolder,
    required this.pendingDoorReturn,
    required this.onDoorChoice,
    required this.onResumePendingDoor,
    required this.onClearPendingDoor,
    required this.intentions,
    required this.auditSummary,
    required this.heartMindDialogue,
  });

  /// 把 data 展開成 BrainReflectionPanel 的具名參數。
  /// 用 spread + 直接傳入，避免漏參數。
  BrainReflectionPanel toWidget() {
    return BrainReflectionPanel(
      reflection: reflection,
      activeDoorTitle: activeDoorTitle,
      turnCount: turnCount,
      contextChars: contextChars,
      bridgeActionCount: effectiveTelemetry.bridgeActions,
      attachmentCount: effectiveTelemetry.attachments,
      activeStage: activeStage,
      activeTelemetry: effectiveTelemetry,
      activeBridgeActionLabel: activeBridgeActionLabel,
      imageProgressLabel: imageProgressLabel,
      isWorking: isWorking,
      recalledInsights: recalledInsights,
      secondBrainTrace: secondBrainTrace,
      brainSkillRegistry: brainSkillRegistry,
      agentMotivation: agentMotivation,
      secondBrainMemoryFeedbacks: secondBrainMemoryFeedbacks,
      secondBrainAssociationFeedbacks: secondBrainAssociationFeedbacks,
      onSecondBrainMemoryFeedback: onSecondBrainMemoryFeedback,
      onSecondBrainAssociationFeedback: onSecondBrainAssociationFeedback,
      secondBrainMemoryRoomOverrides: secondBrainMemoryRoomOverrides,
      onSecondBrainMemoryRoomMove: onSecondBrainMemoryRoomMove,
      onUndoSecondBrainMemoryCorrection: onUndoSecondBrainMemoryCorrection,
      onOpenSecondBrainMemorySource: onOpenSecondBrainMemorySource,
      onCopySecondBrainMemorySource: onCopySecondBrainMemorySource,
      onImportSecondBrainFolder: onImportSecondBrainFolder,
      pendingDoorReturn: pendingDoorReturn,
      onDoorChoice: onDoorChoice,
      onResumePendingDoor: onResumePendingDoor,
      onClearPendingDoor: onClearPendingDoor,
      intentions: intentions,
      auditSummary: auditSummary,
      heartMindDialogue: heartMindDialogue,
    );
  }
}
