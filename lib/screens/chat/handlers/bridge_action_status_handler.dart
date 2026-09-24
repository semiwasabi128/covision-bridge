// [教練 Agent Sprint 17 Step 8 2026-07-07]
// Bridge action status handler — 從 chat_screen.dart 提取。
// 處理橋樑動作狀態更新、取消、結果 SnackBar、自動執行。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/bridge_action.dart';
import '../../../models/conversation.dart';
import '../../../services/bridge_action_executor.dart';
import '../../../services/conversation_store.dart';
import '../helpers/bridge_action_ui_helper.dart';

class BridgeActionStatusHandlerConfig {
  final Conversation? Function() getCurrentConversation;
  final void Function(Conversation updated, List<Conversation> all)
      onConversationUpdated;
  final bool Function() mounted;
  final void Function(void Function() fn) setState;
  final BuildContext Function() context;
  final Future<void> Function(BridgeAction, {String? messageId, int? actionIndex, bool confirmed}) executeBridgeAction;
  final String Function(BridgeActionResult) bridgeResultStatusMessage;
  final void Function(BridgeActionResult) syncBridgeEvidenceToCompanion;
  final dynamic bridgeActionEvidence;

  const BridgeActionStatusHandlerConfig({
    required this.getCurrentConversation,
    required this.onConversationUpdated,
    required this.mounted,
    required this.setState,
    required this.context,
    required this.executeBridgeAction,
    required this.bridgeResultStatusMessage,
    required this.syncBridgeEvidenceToCompanion,
    required this.bridgeActionEvidence,
  });
}

class BridgeActionStatusHandler {
  final BridgeActionStatusHandlerConfig config;

  BridgeActionStatusHandler(this.config);

  Future<void> autoExecuteAssistantBridgeActions(Message message) async {
    final actions = message.bridgeActions;
    if (actions == null || actions.isEmpty) return;
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      if (!BridgeActionUIHelper.shouldAutoExecuteAssistantAction(action)) {
        continue;
      }
      await config.executeBridgeAction(
        action,
        messageId: message.id,
        actionIndex: index,
      );
      if (!config.mounted()) return;
    }
  }

  Future<void> updateBridgeActionStatus(
    String messageId,
    int actionIndex,
    BridgeActionRunStatus status, {
    String? statusMessage,
    bool? requiresConfirmation,
  }) async {
    final conv = config.getCurrentConversation();
    if (conv == null) return;

    final messages = [...conv.messages];
    final messagePosition = messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messagePosition < 0) return;

    final targetMessage = messages[messagePosition];
    final actions = targetMessage.bridgeActions;
    if (actions == null || actionIndex < 0 || actionIndex >= actions.length) {
      return;
    }

    final updatedActions = [...actions];
    updatedActions[actionIndex] = updatedActions[actionIndex].copyWith(
      runStatus: status,
      statusMessage: statusMessage,
      requiresConfirmation: requiresConfirmation,
    );
    messages[messagePosition] = targetMessage.copyWith(
      bridgeActions: updatedActions,
    );

    final updated = conv.copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );

    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    if (!config.mounted()) return;
    config.setState(() {
      config.onConversationUpdated(updated, all);
    });
  }

  Future<void> cancelBridgeAction(
    String messageId,
    int actionIndex, {
    required String message,
  }) async {
    await updateBridgeActionStatus(
      messageId,
      actionIndex,
      BridgeActionRunStatus.failed,
      statusMessage: message,
      requiresConfirmation: true,
    );
  }

  void showBridgeResultSnackBar(BridgeActionResult result) {
    if (result.status == BridgeActionStatus.completed) return;
    final route = BridgeActionUIHelper.setupRoute(result);
    ScaffoldMessenger.of(config.context()).showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: SnackBarAction(
          label: result.status == BridgeActionStatus.needsProvider
              ? '去開通'
              : '了解',
          onPressed: result.status == BridgeActionStatus.needsProvider
              ? () => config.context().go(route)
              : () {},
        ),
      ),
    );
  }
}
