// [教練 Agent Sprint 17 Step 8 2026-07-07]
// Chat message appender — 從 chat_screen.dart 提取。
// 負責追加各種系統訊息與卡片訊息到對話中。
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/bridge_action.dart';
import '../../../models/capability_advisor.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/conversation.dart';
import '../../../models/intent_spine.dart';
import '../../../services/conversation_store.dart';
import '../../../services/managed_folder_rule_store.dart';
import '../../../services/pending_bridge_task_store.dart';
import '../../../services/chat_intent_router.dart';
import '../widgets/pending_task_banner.dart';

const _imageReceivedPrompt =
    '我收到圖片了。你想讓我怎麼處理這張圖？可以請我描述內容、找細節、判斷問題、整理文字，或用它當接下來任務的參考。';

class ChatMessageAppenderConfig {
  final Conversation? Function() getCurrentConversation;
  final void Function(Conversation updated, List<Conversation> all)
      onConversationUpdated;
  final bool Function() mounted;
  final void Function(void Function() fn) setState;
  final void Function() scrollToBottom;
  final PendingBridgeTaskStore pendingBridgeTaskStore;
  final PendingBridgeTask? Function() getPendingBridgeTask;
  final void Function(PendingBridgeTask?) setPendingBridgeTask;
  final bool Function() getAutoResumingPendingTask;
  final BuildContext Function() context;
  final Future<void> Function(String taskId, {bool silent}) dismissPendingBridgeTask;
  final Future<void> Function(PendingBridgeTask task) resumePendingBridgeTask;
  final Future<void> Function() loadManagedFolderRules;
  final List<ManagedFolderRule> Function() getManagedFolderRules;

  const ChatMessageAppenderConfig({
    required this.getCurrentConversation,
    required this.onConversationUpdated,
    required this.mounted,
    required this.setState,
    required this.scrollToBottom,
    required this.pendingBridgeTaskStore,
    required this.getPendingBridgeTask,
    required this.setPendingBridgeTask,
    required this.getAutoResumingPendingTask,
    required this.context,
    required this.dismissPendingBridgeTask,
    required this.resumePendingBridgeTask,
    required this.loadManagedFolderRules,
    required this.getManagedFolderRules,
  });
}

class ChatMessageAppender {
  final ChatMessageAppenderConfig config;

  ChatMessageAppender(this.config);

  Future<void> appendLocalSystemMessage(String content) async {
    final conv = config.getCurrentConversation();
    if (conv == null) return;
    final message = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
    );
    final updated = conv.copyWith(
      messages: [...conv.messages, message],
      updatedAt: DateTime.now(),
    );
    await _saveAndNotify(updated);
  }

  Future<void> appendImageIntentMessage(String imagePath) async {
    final conv = config.getCurrentConversation();
    if (conv == null) return;
    final trimmedPath = imagePath.trim();
    final message = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: _imageReceivedPrompt,
      timestamp: DateTime.now(),
      bridgeActions: [
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請描述這張圖片的內容，並指出畫面中重要的細節。',
          referenceImagePaths: [trimmedPath],
        ),
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請辨識這張圖片中可以讀到的文字，整理成清楚段落；不確定的字請標註。',
          referenceImagePaths: [trimmedPath],
        ),
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請檢查這張圖片是否有畫面、介面、排版、錯誤訊息或可疑問題，並列出優先處理事項。',
          referenceImagePaths: [trimmedPath],
        ),
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請把這張圖片作為接下來任務的視覺參考，先摘要可用線索，等我下一步指令。',
          referenceImagePaths: [trimmedPath],
        ),
      ],
    );
    final updated = conv.copyWith(
      messages: [...conv.messages, message],
      updatedAt: DateTime.now(),
    );
    await _saveAndNotify(updated);
  }

  Future<void> appendIntentClarificationMessage(IntentSpine intentSpine) async {
    final options = intentSpine.clarificationOptions
        .where((option) => option.trim().isNotEmpty)
        .take(3)
        .toList();
    final optionText = options.isEmpty
        ? ''
        : '\n\n你可以直接回我其中一種：\n${options.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value}').join('\n')}';
    await appendLocalSystemMessage(
      '我先確認一下你的意思，避免我直接走錯下一步。\n\n'
      '我理解到的是：${intentSpine.normalizedGoal}\n'
      '你想先把方向聊清楚，還是要我開始執行？'
      '$optionText',
    );
  }

  Future<void> appendCapabilityGapCard(
    CapabilityGapCardData card, {
    BridgeAction? bridgeAction,
  }) async {
    if (!shouldShowCapabilityGapForRequest(card.request)) {
      return appendLocalSystemMessage(
        '我先不急著開通能力，避免偏離你的原始意圖。\n\n'
        '我理解你這一輪比較像是在釐清、討論或詢問原則；如果你要我真的開始執行或開通能力，可以直接說「照這個開始」或「幫我開通這個能力」。',
      );
    }
    final task = await config.pendingBridgeTaskStore.save(
      PendingBridgeTask.create(
        title: card.title,
        request: card.request,
        missing: card.missing,
        route: card.route,
        routeLabel: card.routeLabel,
        iconName: card.iconName,
        conversationId: config.getCurrentConversation()?.id,
        bridgeAction: bridgeAction,
      ),
    );
    if (config.mounted()) {
      config.setState(() {
        config.setPendingBridgeTask(task);
      });
    }
    if (config.mounted()) {
      _showPendingTaskSnackBar();
    }
    final cardWithTask = card.copyWith(pendingTaskId: task.id);
    return appendLocalSystemMessage(
      '$capabilityCardPrefix${jsonEncode(cardWithTask.toJson())}',
    );
  }

  Future<void> appendCapabilityAdvisorCard(
    CapabilityAdvisorCardData card,
  ) async {
    return appendLocalSystemMessage(
      '$capabilityAdvisorCardPrefix${jsonEncode(card.toJson())}',
    );
  }

  Future<void> appendDigitalAssetInvocationCard(
    DigitalAssetInvocationCardData card,
  ) async {
    return appendLocalSystemMessage(
      '$digitalAssetInvocationCardPrefix${jsonEncode(card.toJson())}',
    );
  }

  Future<void> appendManagedFolderRulePickerCard(
    String request, {
    String? targetFolderPath,
    String? targetFolderLabel,
  }) async {
    await config.loadManagedFolderRules();
    final userRules = config.getManagedFolderRules()
        .where((rule) => !rule.isBuiltIn)
        .toList();
    final candidateRules = userRules.isNotEmpty
        ? userRules
        : config.getManagedFolderRules();
    final rules = candidateRules
        .take(8)
        .map(
          (rule) => ManagedFolderRulePickerItem(
            id: rule.id,
            ruleTitle: rule.ruleTitle,
            folderLabel: rule.folderLabel,
            folderPath: rule.folderPath,
            rulePath: rule.rulePath,
            modeLabel: rule.modeLabel,
            categorySummary: rule.categorySummary,
            builtIn: rule.isBuiltIn,
          ),
        )
        .toList();
    return appendLocalSystemMessage(
      '$managedFolderRulePickerCardPrefix${jsonEncode(ManagedFolderRulePickerCardData(request: request, rules: rules, targetFolderPath: targetFolderPath, targetFolderLabel: targetFolderLabel).toJson())}',
    );
  }

  void _showPendingTaskSnackBar() {
    ScaffoldMessenger.of(config.context()).showSnackBar(
      SnackBar(
        content: const Text('有待恢復的橋樑任務'),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            final task = config.getPendingBridgeTask();
            if (task == null) return;
            showModalBottomSheet(
              context: config.context(),
              builder: (context) => Padding(
                padding: const EdgeInsets.all(16),
                child: PendingBridgeTaskBanner(
                  task: task,
                  autoResuming: config.getAutoResumingPendingTask(),
                  onDismiss: () =>
                      config.dismissPendingBridgeTask(task.id),
                  onResume: () => config.resumePendingBridgeTask(task),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _saveAndNotify(Conversation updated) async {
    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    if (!config.mounted()) return;
    config.setState(() {
      config.onConversationUpdated(updated, all);
    });
    config.scrollToBottom();
  }
}
