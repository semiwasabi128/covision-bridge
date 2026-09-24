// [教練 Agent Sprint 17 Step 6 — 2026-07-07]
// 訊息泡泡：從 chat_screen.dart _buildMessageBubble 提取。
// 44 個依賴全透過 MessageBubbleConfig 傳入，行為不變。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/bridge_action.dart';
import '../../../models/capability_advisor.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/conversation.dart';
import '../../../models/project_door.dart';
import '../../../models/task_evidence.dart'; // P0.5 對話任務證據
import '../../../services/bridge_action_execution_decision_service.dart';
import '../../../services/asset_action_service.dart'; // P0.6a 資產操作
import '../../../services/causal/causal_ledger_service.dart'; // [因果引擎 L2] 證據等級
import '../../../services/managed_folder_rule_store.dart';
import '../../../services/memory_store.dart';
import '../../../services/local_model_runtime_service.dart'; // [教練 Agent 2026-08-14] resolveShortModelName
import '../../../theme/bridge_design_system.dart';
import '../../../widgets/bridge_cards/bridge_evidence_card.dart';
import '../cards/bridge_action_card.dart';
import '../cards/capability_card.dart';
import '../cards/digital_asset_card.dart';
import '../cards/managed_folder_card.dart';
import '../cards/misc_card_widgets.dart';
import '../cards/task_evidence_card.dart'; // P0.5
import '../cards/project_door_card.dart';
import 'message_extras.dart';
import '../../../widgets/chat/message_context_menu.dart';
import '../../../widgets/chat/tech_detail_collapsible.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 訊息泡泡需要的所有 callback 和資料。
class MessageBubbleConfig {
  // --- 解析器 ---
  final CapabilityGapCardData? Function(String content) tryParseCapabilityCard;
  final CapabilityAdvisorCardData? Function(String content)
      tryParseCapabilityAdvisorCard;
  final ProjectDoorCardData? Function(String content) tryParseProjectDoorCard;
  final ProjectContextTransferCardData? Function(String content)
      tryParseProjectContextTransferCard;
  final DigitalAssetInvocationCardData? Function(String content)
      tryParseDigitalAssetInvocationCard;
  final DigitalAssetReusePlanCardData? Function(String content)
      tryParseDigitalAssetReusePlanCard;
  final ProjectForkCompleteCardData? Function(String content)
      tryParseProjectForkCompleteCard;
  final ProjectForkIntroCardData? Function(String content)
      tryParseProjectForkIntroCard;
  final DigitalAssetResultCardData? Function(String content)
      tryParseDigitalAssetResultCard;
  final ManagedFolderRulePickerCardData? Function(String content)
      tryParseManagedFolderRulePickerCard;

  // --- 狀態 ---
  final ProjectDoor? activeProjectDoor;
  final String? selectedMessageId;
  final String? selectedMessageText;
  final Set<String> completedDocumentWorkflowActions;

  // --- Callbacks ---
  final VoidCallback onCopySelectedMessageText;
  final void Function(String text) onCopyMessage;
  final void Function(Message msg, String attachmentPath) onShowDocumentPreview;
  final void Function(String path) onOpenLocalBridgePath;
  final void Function(Message msg, TextSelection selection,
      SelectionChangedCause? cause) onMessageSelectionChanged;
  final bool Function(Map<String, dynamic>? metadata) shouldShowBridgeEvidence;
  final ManagedFolderRule? Function(Map<String, dynamic> metadata)
      managedFolderRuleForMetadata;
  final void Function(
      ManagedFolderRulePickerItem rule, {
      required ManagedFolderRulePickerCardData card,
  }) onStartManagedFolderRuleReuse;
  final void Function(DigitalAssetInvocationCardData invocation)
      onInvokeDigitalAsset;
  final void Function(DigitalAssetReusePlanCardData card,
      {required bool outlineOnly}) onStartDigitalAssetReusePlan;
  final void Function(ProjectContextTransferCardData card)
      onTransferContextToProject;
  final void Function(ProjectDoorCardData card) onCreateProjectDoorFromCard;
  final void Function(String msg) onAppendLocalSystemMessage;
  final void Function(String conversationId) onSwitchConversationById;
  final Future<bool> Function(CapabilityGapCardData card)
      isCapabilityGapResolved;
  final void Function(CapabilityGapCardData card) onResumeCapabilityRequest;
  final Future<void> Function(
    BridgeAction action, {
    String? messageId,
    int? actionIndex,
    bool confirmed,
    BridgeActionExecutionOverride executionOverride,
  }) onExecuteBridgeAction;
  final Future<void> Function(String messageId, int actionIndex,
      {required String message}) onCancelBridgeAction;
  final void Function(Message msg, TransurfingInsightFeedback feedback)
      onMarkAnswerFeedback;
  final void Function(String text) onSetMessageInputText;
  final VoidCallback onSendMessage;

  // --- Controller callbacks (Capability Advisor) ---
  final VoidCallback onAdvisorConfirmIntent;
  final VoidCallback onAdvisorStartBrowseSubFlow;
  final void Function(String intent) onAdvisorCorrectIntent;
  final void Function(String id) onAdvisorSelectSolution;
  final VoidCallback onAdvisorVerify;
  final VoidCallback onAdvisorRetry;
  final VoidCallback onAdvisorCancel;
  final void Function(void Function(bool) callback) onAdvisorReturnToTask;

  // --- Desktop organize callbacks ---
  final void Function(Map<String, dynamic> action) onExecuteDocumentWorkflowAction;
  final void Function(Map<String, dynamic> metadata, String applyPrompt)
      onRequestDesktopOrganizeConfirmation;
  final void Function(Map<String, dynamic> metadata) onExecuteDesktopPlanReport;
  final void Function(Map<String, dynamic> metadata) onExecuteDesktopPlanRules;
  final void Function(Map<String, dynamic> metadata) onImportDesktopOrganizeRules;

  // --- 排版 ---
  final String Function(DateTime timestamp) formatTime;
  final String Function(String speakerId) agentNameResolver;

  // --- 語音輸出 ---
  final Future<void> Function(String text)? onSpeakMessage;

  // [教練 Agent 2026-07-22] Phase H — 回覆指定訊息
  final void Function(Message msg)? onReplyMessage;

  // [教練 Agent 2026-08-02] 刪除訊息
  final void Function(Message msg)? onDeleteMessage;

  // [教練 Agent 2026-08-02] 延伸話題（帶上下文建立新對話）
  final void Function(Message msg)? onExtendTopic;

  const MessageBubbleConfig({
    required this.tryParseCapabilityCard,
    required this.tryParseCapabilityAdvisorCard,
    required this.tryParseProjectDoorCard,
    required this.tryParseProjectContextTransferCard,
    required this.tryParseDigitalAssetInvocationCard,
    required this.tryParseDigitalAssetReusePlanCard,
    required this.tryParseProjectForkCompleteCard,
    required this.tryParseProjectForkIntroCard,
    required this.tryParseDigitalAssetResultCard,
    required this.tryParseManagedFolderRulePickerCard,
    required this.activeProjectDoor,
    required this.selectedMessageId,
    required this.selectedMessageText,
    required this.completedDocumentWorkflowActions,
    required this.onCopySelectedMessageText,
    required this.onCopyMessage,
    required this.onShowDocumentPreview,
    required this.onOpenLocalBridgePath,
    required this.onMessageSelectionChanged,
    required this.shouldShowBridgeEvidence,
    required this.managedFolderRuleForMetadata,
    required this.onStartManagedFolderRuleReuse,
    required this.onInvokeDigitalAsset,
    required this.onStartDigitalAssetReusePlan,
    required this.onTransferContextToProject,
    required this.onCreateProjectDoorFromCard,
    required this.onAppendLocalSystemMessage,
    required this.onSwitchConversationById,
    required this.isCapabilityGapResolved,
    required this.onResumeCapabilityRequest,
    required this.onExecuteBridgeAction,
    required this.onCancelBridgeAction,
    required this.onMarkAnswerFeedback,
    required this.onSetMessageInputText,
    required this.onSendMessage,
    required this.onAdvisorConfirmIntent,
    required this.onAdvisorStartBrowseSubFlow,
    required this.onAdvisorCorrectIntent,
    required this.onAdvisorSelectSolution,
    required this.onAdvisorVerify,
    required this.onAdvisorRetry,
    required this.onAdvisorCancel,
    required this.onAdvisorReturnToTask,
    required this.onExecuteDocumentWorkflowAction,
    required this.onRequestDesktopOrganizeConfirmation,
    required this.onExecuteDesktopPlanReport,
    required this.onExecuteDesktopPlanRules,
    required this.onImportDesktopOrganizeRules,
    required this.formatTime,
    required this.agentNameResolver,
    this.onSpeakMessage,
    this.onReplyMessage,
    this.onDeleteMessage,
    this.onExtendTopic,
  });
}

/// 訊息泡泡 widget。
class MessageBubble extends StatelessWidget {
  final Message msg;
  final MessageBubbleConfig config;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final capabilityCard =
        isUser ? null : config.tryParseCapabilityCard(msg.content);
    final advisorCard = isUser
        ? null
        : config.tryParseCapabilityAdvisorCard(msg.content);
    final projectDoorCard =
        isUser ? null : config.tryParseProjectDoorCard(msg.content);
    final projectTransferCard = isUser
        ? null
        : config.tryParseProjectContextTransferCard(msg.content);
    final digitalAssetCard =
        isUser ? null : config.tryParseDigitalAssetInvocationCard(msg.content);
    final digitalAssetReusePlanCard = isUser
        ? null
        : config.tryParseDigitalAssetReusePlanCard(msg.content);
    final projectForkCompleteCard = isUser
        ? null
        : config.tryParseProjectForkCompleteCard(msg.content);
    final projectForkIntroCard =
        isUser ? null : config.tryParseProjectForkIntroCard(msg.content);
    final digitalAssetResultCard =
        isUser ? null : config.tryParseDigitalAssetResultCard(msg.content);
    final managedFolderRulePickerCard = isUser
        ? null
        : config.tryParseManagedFolderRulePickerCard(msg.content);

    // 建立訊息氣泡 widget
    Widget bubbleWidget = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // [教練 Agent 2026-07-22] Phase H — 回覆引用框
            if (msg.replyToSnippet != null && msg.replyToSnippet!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 2, left: 12, right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).textMuted.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                  border: Border(
                    left: BorderSide(
                      color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                ),
                constraints: BoxConstraints(maxWidth: 250),
                child: Text(
                  msg.replyToSnippet!.length > 80
                      ? '${msg.replyToSnippet!.substring(0, 80)}...'
                      : msg.replyToSnippet!,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,
                    fontStyle: FontStyle.italic,),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (!isUser && msg.speakerId?.isNotEmpty == true) ...[
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  config.agentNameResolver(msg.speakerId ?? ''),
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w700,),
                ),
              ),
            ],
            if (msg.imagePath != null) ...[
              GestureDetector(
                onTap: () => AssetActionService.instance.openWithDefaultApp(msg.imagePath!),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MessageImage(imagePath: msg.imagePath!),
                  ),
                ),
              ),
              _buildImageReceipt(context, msg),
            ],
            // [因果引擎 L2] 證據等級 chip——assistant 回覆必標價（推測/觀測/干預驗證）
            if (!isUser) _buildEvidenceGradeChip(context, msg),
            // [教練 Agent 2026-08-21] 死命令——所有生成的數位資產必須讓使用者看見。
            // 批量生成：第 2 張起全部攤開（第 1 張已由 imagePath 顯示）。
            if (msg.mediaAssets.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text(
                  '本輪共產出 ${msg.mediaAssets.length} 個資產（全部如下）：',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ...msg.mediaAssets
                  .asMap()
                  .entries
                  .where((e) => e.value != msg.imagePath)
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: GestureDetector(
                          onTap: () => AssetActionService.instance.openWithDefaultApp(e.value),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: MessageImage(imagePath: e.value),
                          ),
                        ),
                      )),
            ],
            if (advisorCard != null)
              CapabilityAdvisorCardBuilder(
                data: advisorCard,
                onConfirmIntent: config.onAdvisorConfirmIntent,
                onStartBrowseSubFlow: config.onAdvisorStartBrowseSubFlow,
                onCorrectIntent: config.onAdvisorCorrectIntent,
                onSelectSolution: config.onAdvisorSelectSolution,
                onVerify: config.onAdvisorVerify,
                onRetry: config.onAdvisorRetry,
                onCancel: config.onAdvisorCancel,
                onReturnToTask: () {
                  config.onAdvisorReturnToTask((executedTask) {
                    if (context.mounted) {
                      final snackBarMsg = executedTask
                          ? '✅ 已重新執行你的任務，請查看結果。'
                          : '✅ 設定完成，任務內容已填回輸入框，可直接送出。';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(snackBarMsg),
                          duration: const Duration(seconds: 3),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  });
                },
              )
            else if (projectDoorCard != null)
              ProjectDoorCard(
                card: projectDoorCard,
                alreadyActive:
                    config.activeProjectDoor?.title == projectDoorCard.title,
                onCreate: () =>
                    config.onCreateProjectDoorFromCard(projectDoorCard),
                onContinue: (msg) => config.onAppendLocalSystemMessage(msg),
              )
            else if (projectTransferCard != null)
              ProjectContextTransferCard(
                card: projectTransferCard,
                onTransfer: () =>
                    config.onTransferContextToProject(projectTransferCard),
                onContinue: (msg) => config.onAppendLocalSystemMessage(msg),
              )
            else if (digitalAssetCard != null)
              DigitalAssetInvocationCard(
                card: digitalAssetCard,
                onInvoke: () => config.onInvokeDigitalAsset(digitalAssetCard),
                onContinue: (msg) => config.onAppendLocalSystemMessage(msg),
              )
            else if (digitalAssetReusePlanCard != null)
              DigitalAssetReusePlanCard(
                card: digitalAssetReusePlanCard,
                onStart: () => config.onStartDigitalAssetReusePlan(
                    digitalAssetReusePlanCard,
                    outlineOnly: false),
                onStartOutline: () => config.onStartDigitalAssetReusePlan(
                    digitalAssetReusePlanCard,
                    outlineOnly: true),
                onContinue: (msg) => config.onAppendLocalSystemMessage(msg),
              )
            else if (projectForkCompleteCard != null)
              ProjectForkCompleteCard(
                card: projectForkCompleteCard,
                onSwitchToTarget: () => config
                    .onSwitchConversationById(
                        projectForkCompleteCard.targetProjectId),
                onContinue: (msg) => config.onAppendLocalSystemMessage(msg),
              )
            else if (projectForkIntroCard != null)
              ProjectForkIntroCard(card: projectForkIntroCard)
            else if (digitalAssetResultCard != null)
              DigitalAssetResultCard(
                card: digitalAssetResultCard,
                activeProjectDoorId: config.activeProjectDoor?.id ?? '',
                activeProjectDoorTitle: config.activeProjectDoor?.title ?? '',
                onInvoke: (invocation) =>
                    config.onInvokeDigitalAsset(invocation),
              )
            else if (managedFolderRulePickerCard != null)
              ManagedFolderRulePickerCard(
                card: managedFolderRulePickerCard,
                onApplyRule: (rule) => config.onStartManagedFolderRuleReuse(
                    rule, card: managedFolderRulePickerCard),
                onOpenRulePath: (rulePath) =>
                    config.onOpenLocalBridgePath(rulePath),
              )
            else if (capabilityCard != null)
              CapabilityGapCard(
                card: capabilityCard,
                checkResolved: config.isCapabilityGapResolved,
                onResume: () => config.onResumeCapabilityRequest(capabilityCard),
                onGoRoute: (route) => context.go(route),
              )
            else
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isUser ? BridgeDSColors.of(context).surface : BridgeDSColors.of(context).surfaceElevated,
                  borderRadius: BorderRadius.circular(18).copyWith(
                    bottomRight: isUser ? Radius.circular(BridgeDS.roundSubtle) : null,
                    bottomLeft: !isUser ? Radius.circular(BridgeDS.roundSubtle) : null,
                  ),
                  border: isUser
                      ? Border.all(color: BridgeDSColors.of(context).borderDefault)
                      : Border.all(
                          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.2),
                        ),
                ),
                // [小葵 2026-09-22 0.2 白話鐵則] 有【技術細節】標記 →
                // 白話正文在上，技術細節摺疊（工程師想看再點開）。
                // 沒有標記 → 原樣渲染（零影響）。
                child: isUser
                    ? SelectableText(
                        key: ValueKey('chat-message-text-${msg.id}'),
                        msg.content,
                        enableInteractiveSelection: true,
                        contextMenuBuilder: buildTextSelectionContextMenu,
                        onSelectionChanged: (selection, cause) =>
                            config.onMessageSelectionChanged(msg, selection, cause),
                        style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                          height: 1.5,),
                      )
                    : Builder(builder: (_) {
                        final split = PlainTechSplit.tryParse(msg.content);
                        if (split == null) {
                          return SelectableText(
                            key: ValueKey('chat-message-text-${msg.id}'),
                            msg.content,
                            enableInteractiveSelection: true,
                            contextMenuBuilder: buildTextSelectionContextMenu,
                            onSelectionChanged: (selection, cause) =>
                                config.onMessageSelectionChanged(msg, selection, cause),
                            style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                              height: 1.5,),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              key: ValueKey('chat-message-text-${msg.id}'),
                              split.plain,
                              enableInteractiveSelection: true,
                              contextMenuBuilder: buildTextSelectionContextMenu,
                              onSelectionChanged: (selection, cause) =>
                                  config.onMessageSelectionChanged(msg, selection, cause),
                              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                                height: 1.5,),
                            ),
                            TechDetailCollapsible(tech: split.tech!),
                          ],
                        );
                      }),
              ),
            if (!isUser && config.shouldShowBridgeEvidence(msg.metadata))
              BridgeEvidenceCard(
                metadata: msg.metadata!,
                onCopy: config.onCopyMessage,
                onOpenPath: config.onOpenLocalBridgePath,
                completedWorkflowActions: config.completedDocumentWorkflowActions,
                onExecuteWorkflowAction: config.onExecuteDocumentWorkflowAction,
                onRequestDesktopOrganizeConfirmation:
                    config.onRequestDesktopOrganizeConfirmation,
                onExecuteDesktopPlanReport: config.onExecuteDesktopPlanReport,
                onExecuteDesktopPlanRules: config.onExecuteDesktopPlanRules,
                onImportDesktopOrganizeRules: config.onImportDesktopOrganizeRules,
                managedFolderRule:
                    config.managedFolderRuleForMetadata(msg.metadata!),
                onExecuteGuardScan: (action) => config.onExecuteBridgeAction(
                  BridgeAction(
                    type: BridgeActionType.desktopFiles,
                    prompt: action.prompt,
                    provider: 'local_desktop_files',
                  ),
                  confirmed: true,
                ),
              ),
            if (capabilityCard != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  '能力缺口已保留，完成設定後可回到這段任務。',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary),
                ),
              ),
            if (msg.attachmentKind == 'document' &&
                msg.attachmentPath != null &&
                !config.shouldShowBridgeEvidence(msg.metadata))
              DocumentAttachmentCard(
                path: msg.attachmentPath!,
                onPreview: () =>
                    config.onShowDocumentPreview(msg, msg.attachmentPath!),
                onCopyPath: () => config.onCopyMessage(msg.attachmentPath!),
                onOpenPath: () =>
                    config.onOpenLocalBridgePath(msg.attachmentPath!),
              ),
            // P0.5 任務結果卡（取代原 ThinkingPanel / AgentLoopProgress 的自製狀態元件）。
            // 只在 assistant message 有安全版 task evidence 時渲染。
            if (!isUser) ...buildTaskEvidenceSection(msg),
            if (!isUser &&
                capabilityCard == null &&
                projectDoorCard == null &&
                projectTransferCard == null &&
                digitalAssetCard == null)
              AnswerFeedbackBar(
                msg: msg,
                onFeedback: (m, feedback) =>
                    config.onMarkAnswerFeedback(m, feedback),
              ),
            // 橋樑動作卡片（僅 AI 訊息）
            if (!isUser &&
                msg.bridgeActions != null &&
                msg.bridgeActions!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: msg.bridgeActions!.asMap().entries.map((entry) {
                    final actionIndex = entry.key;
                    final action = entry.value;
                    if (action.requiresConfirmation) {
                      return BridgeActionConfirmationCard(
                        action: action,
                        messageId: msg.id,
                        actionIndex: actionIndex,
                        onExecute: config.onExecuteBridgeAction,
                        onCancel: config.onCancelBridgeAction,
                      );
                    }
                    return BridgeActionStatusChip(
                      action: action,
                      messageId: msg.id,
                      actionIndex: actionIndex,
                      onExecute: config.onExecuteBridgeAction,
                    );
                  }).toList(),
                ),
              ),
            // 快速回覆選項
            if (!isUser && msg.quickReplies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: msg.quickReplies.map((reply) {
                    return ActionChip(
                      label: Text(
                        reply,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,
                          fontWeight: FontWeight.w600,),
                      ),
                      backgroundColor:
                          BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onPressed: () {
                        config.onSetMessageInputText(reply);
                        config.onSendMessage();
                      },
                    );
                  }).toList(),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  config.formatTime(msg.timestamp),
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary),
                ),
                // [教練 Agent 2026-07-29] Agent 回覆顯示模型名稱 — 主對話視窗
                if (!isUser &&
                    msg.model != null &&
                    msg.model!.isNotEmpty) ...[
                  Text(
                    ' · ${resolveShortModelName(msg.model) ?? msg.model}',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary),
                  ),
                ],
                if (msg.tokens != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '用量 ${msg.tokens}',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary),
                  ),
                ],
                if (config.selectedMessageId == msg.id &&
                    (config.selectedMessageText?.isNotEmpty ?? false))
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Tooltip(
                      message: '只複製目前反白的文字',
                      child: TextButton.icon(
                        key: ValueKey(
                            'chat-message-copy-selection-${msg.id}'),
                        style: messageCopyButtonStyle(context),
                        icon: const Icon(Icons.content_copy_rounded, size: 16),
                        label: const Text('複製選取'),
                        onPressed: config.onCopySelectedMessageText,
                      ),
                    ),
                  ),
                // [教練 Agent 2026-08-15 使用者 提案] 更多（三點）——統一選單入口
                _buildMoreMenuButton(config, msg),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Tooltip(
                    message: isUser ? '複製我的訊息' : '複製這輪回答',
                    child: TextButton.icon(
                      key: ValueKey('chat-message-copy-${msg.id}'),
                      style: messageCopyButtonStyle(context),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('複製整則'),
                      onPressed: () => config.onCopyMessage(msg.content),
                    ),
                  ),
                ),
                // [教練 Agent 2026-07-22] Phase H — 回覆指定訊息
                if (config.onReplyMessage != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Tooltip(
                      message: '回覆這則訊息',
                      child: TextButton.icon(
                        key: ValueKey('chat-message-reply-${msg.id}'),
                        style: messageCopyButtonStyle(context),
                        icon: const Icon(Icons.reply_rounded, size: 16),
                        label: const Text('回覆'),
                        onPressed: () => config.onReplyMessage!(msg),
                      ),
                    ),
                  ),
                if (!isUser && config.onSpeakMessage != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Tooltip(
                      message: '朗讀這輪回答',
                      child: TextButton.icon(
                        key: ValueKey('chat-message-speak-${msg.id}'),
                        style: messageCopyButtonStyle(context),
                        icon: const Icon(Icons.volume_up_rounded, size: 16),
                        label: const Text('朗讀'),
                        onPressed: () =>
                            config.onSpeakMessage!(msg.content),
                      ),
                    ),
                  ),
                // [教練 Agent 2026-08-15 使用者回饋] 刪除鈕上按鈕列——
                // 之前只在長按選單裡，使用者 找不到。長按選單保留。
                if (config.onDeleteMessage != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Tooltip(
                      message: '刪除這則訊息',
                      child: TextButton.icon(
                        key: ValueKey('chat-message-delete-${msg.id}'),
                        style: messageCopyButtonStyle(context),
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 16,
                            color: BridgeDSColors.of(context).accentRed),
                        label: Text('刪除',
                            style: TextStyle(
                                color: BridgeDSColors.of(context).accentRed)),
                        onPressed: () => config.onDeleteMessage!(msg),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    // 包上 GestureDetector 提供長按選單
    return GestureDetector(
      onLongPress: () {
        MessageContextMenu.show(
          context: context,
          message: msg,
          showExtendTopic: config.onExtendTopic != null,
          onReply: config.onReplyMessage != null ? () => config.onReplyMessage!(msg) : null,
          onDelete: config.onDeleteMessage != null ? () => config.onDeleteMessage!(msg) : null,
          onExtendTopic: config.onExtendTopic != null ? () => config.onExtendTopic!(msg) : null,
        );
      },
      child: bubbleWidget,
    );
  }

  /// [教練 Agent 2026-08-15 使用者 提案] 三點選單——與長按同內容，讓使用者看得到入口。
  /// 三個對話框（主/畫布/手機）統一：更多操作藏在時間旁的三個點。
  Builder _buildMoreMenuButton(MessageBubbleConfig config, Message msg) {
    return Builder(
      builder: (innerContext) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: '更多操作',
          child: TextButton.icon(
            key: ValueKey('chat-message-more-${msg.id}'),
            style: messageCopyButtonStyle(innerContext),
            icon: const Icon(Icons.more_horiz_rounded, size: 16),
            label: const Text('更多'),
            onPressed: () {
              MessageContextMenu.show(
                context: innerContext,
                message: msg,
                showExtendTopic: config.onExtendTopic != null,
                onReply: config.onReplyMessage != null ? () => config.onReplyMessage!(msg) : null,
                onDelete: config.onDeleteMessage != null ? () => config.onDeleteMessage!(msg) : null,
                onExtendTopic: config.onExtendTopic != null ? () => config.onExtendTopic!(msg) : null,
              );
            },
          ),
        ),
      ),
    );
  }

  /// P0.5: 從 assistant message.metadata 萃取已落地的安全版 TaskEvidence；
  /// 由 host 決定 action 對應到的 view。
  List<Widget> buildTaskEvidenceSection(Message msg) {
    final list = TaskEvidence.fromMetadata(msg.metadata);
    if (list.isEmpty) return const <Widget>[];
    return [
      for (final t in list)
        TaskEvidenceCard(
          evidence: t,
          onTapAction: (ctx) {
            final view = ctx.action.view;
            debugPrint(
                '[TaskEvidence] tap ${ctx.evidence.headline} action=${ctx.action.label} view=$view');
          },
        ),
    ];
  }

  // [因果引擎 P0.6a 2026-09-11] 證據等級 chip（因果誠實）——
  // assistant 回覆的因果宣稱強制標價：2 干預驗證/1 觀測/0 推測（警示色）。
  // 等級由 chat_controller 確定性計算（哪些工具真的執行成功），不是 LLM 自評。
  Widget _buildEvidenceGradeChip(BuildContext context, Message msg) {
    final level = msg.metadata?['evidenceGrade'] as int?;
    if (level == null) return const SizedBox.shrink();
    final label =
        msg.metadata?['evidenceGradeLabel']?.toString() ?? '未知';
    final grade = EvidenceGrade.fromLevel(level);
    final colors = BridgeDSColors.of(context);
    // 等級 0=推測 → 警示色（寧紅字不假成功）；1/2=語意色；3=反事實（紫語意）
    final color = grade == EvidenceGrade.speculated
        ? colors.accentRed
        : grade == EvidenceGrade.intervened
            ? colors.accentGreen
            : grade == EvidenceGrade.counterfactual
                ? colors.accentPurple
                : colors.accentBlue;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2, left: 12, right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            grade == EvidenceGrade.speculated
                ? Icons.help_outline
                : grade == EvidenceGrade.counterfactual
                    ? Icons.alt_route
                    : Icons.verified_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '證據：$label',
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  // [教練 Agent P0.6a 2026-08-07] 圖片 execution receipt（provider/model），
  // 與 Desktop Chat Panel 一致：從 msg.metadata['imageExecution'] 讀取。
  Widget _buildImageReceipt(BuildContext context, Message msg) {
    final imageExecution =
        msg.metadata?['imageExecution'] as Map<String, dynamic>?;
    final imageProvider = imageExecution?['provider']?.toString();
    final imageModel = imageExecution?['model']?.toString();
    if (imageProvider == null && imageModel == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '圖片：$imageProvider${imageModel != null ? ' · $imageModel' : ''}',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
              color: BridgeDSColors.of(context).textMuted,
            ),
      ),
    );
  }
}
