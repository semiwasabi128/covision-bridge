// [教練 Agent Sprint 17 Step 7 2026-07-07]
// 橋樑結果 handler — 從 chat_screen.dart 提取。
// 處理 BridgeActionResult 的訊息追加與第二大腦索引。
import 'dart:convert';

import '../../../models/bridge_action.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/conversation.dart';
import '../../../models/digital_asset.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../services/bridge_action_executor.dart';
import '../../../services/conversation_store.dart';
import '../handlers/digital_asset_index_handler.dart';

class BridgeResultHandlerConfig {
  final Conversation? currentConversation;
  final dynamic bridgeActionEvidence;
  final dynamic secondBrainFileIndexStore;
  final dynamic digitalAssetRegistry;
  final dynamic activeProjectDoor;
  final String? Function(BridgeActionResult) documentAssetPrimaryPath;
  final SecondBrainRoom Function() documentAssetRoomForCurrentContext;
  final String? Function(String?) basename;
  final String Function(Map<String, dynamic>) desktopCategorySummary;
  final DigitalAssetResultCardData Function(DigitalAsset, {required String sourceProjectTitle}) digitalAssetResultCardFromAsset;
  final bool Function() mounted;
  final void Function(void Function() fn) setState;
  final void Function() scrollToBottom;
  final void Function(Conversation updated, List<Conversation> all) onConversationUpdated;

  const BridgeResultHandlerConfig({
    required this.currentConversation,
    required this.bridgeActionEvidence,
    required this.secondBrainFileIndexStore,
    required this.digitalAssetRegistry,
    required this.activeProjectDoor,
    required this.documentAssetPrimaryPath,
    required this.documentAssetRoomForCurrentContext,
    required this.basename,
    required this.desktopCategorySummary,
    required this.digitalAssetResultCardFromAsset,
    required this.mounted,
    required this.setState,
    required this.scrollToBottom,
    required this.onConversationUpdated,
  });
}

class BridgeResultHandler {
  final BridgeResultHandlerConfig config;

  BridgeResultHandler(this.config);

  Future<void> appendBridgeResultMessage(BridgeActionResult result) async {
    final conv = config.currentConversation;
    if (conv == null) return;
    final evidence = config.bridgeActionEvidence.describe(result);
    final resultMsg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: evidence == null
          ? result.message
          : '${result.message}\n\n$evidence',
      timestamp: DateTime.now(),
      imagePath: result.metadata?['kind'] == 'document'
          ? null
          : result.mediaUrl,
      attachmentKind: result.metadata?['kind'] == 'document'
          ? 'document'
          : null,
      attachmentPath: result.metadata?['kind'] == 'document'
          ? result.mediaUrl
          : null,
      metadata: result.metadata,
    );

    final indexHandler = DigitalAssetIndexHandler(
      config: DigitalAssetIndexHandlerConfig(
        secondBrainFileIndexStore: config.secondBrainFileIndexStore,
        digitalAssetRegistry: config.digitalAssetRegistry,
        activeProjectDoor: config.activeProjectDoor,
        currentConversation: conv,
        documentAssetPrimaryPath: config.documentAssetPrimaryPath,
        documentAssetRoomForCurrentContext: config.documentAssetRoomForCurrentContext,
        basename: config.basename,
        desktopCategorySummary: config.desktopCategorySummary,
      ),
    );
    final archivedAssets = [
      await indexHandler.indexDocumentAssetResult(result, resultMsg),
      await indexHandler.indexDesktopFilesResult(result, resultMsg),
      await indexHandler.indexBrowseResult(result, resultMsg),
      await indexHandler.indexVisionResult(result, resultMsg),
    ].whereType<DigitalAsset>().toList();
    final assetMessages = archivedAssets.map((asset) {
      final card = config.digitalAssetResultCardFromAsset(
        asset,
        sourceProjectTitle: config.activeProjectDoor?.title ?? asset.sourceLabel,
      );
      return Message(
        id: 'asset-result-${DateTime.now().microsecondsSinceEpoch}-${asset.id}',
        role: 'assistant',
        content: '$digitalAssetResultCardPrefix${jsonEncode(card.toJson())}',
        timestamp: DateTime.now(),
        metadata: {
          'kind': 'digital_asset_result',
          'assetId': asset.id,
          'sourceBridgeResultId': resultMsg.id,
        },
      );
    }).toList();

    final updated = conv.copyWith(
      messages: [
        ...conv.messages,
        resultMsg,
        ...assetMessages,
      ],
      updatedAt: DateTime.now(),
    );

    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    if (!config.mounted()) return;
    config.setState(() {
      config.onConversationUpdated(updated, all);
    });
    config.scrollToBottom();
  }

  Future<void> appendBridgeConfirmationMessage(
    BridgeAction action,
    BridgeActionResult result,
  ) async {
    final conv = config.currentConversation;
    if (conv == null) return;
    final confirmationMsg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: '這次橋樑動作需要你確認。',
      timestamp: DateTime.now(),
      bridgeActions: [
        action.copyWith(
          requiresConfirmation: true,
          runStatus: BridgeActionRunStatus.pending,
          statusMessage: result.message,
        ),
      ],
    );

    final updated = conv.copyWith(
      messages: [...conv.messages, confirmationMsg],
      updatedAt: DateTime.now(),
    );

    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    if (!config.mounted()) return;
    config.setState(() {
      config.onConversationUpdated(updated, all);
    });
    config.scrollToBottom();
  }
}
