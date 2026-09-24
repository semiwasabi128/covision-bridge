// [教練 Agent Sprint 17 Step 7 2026-07-07]
// 數位資產調用 handler — 從 chat_screen.dart 提取。
// 採用與 DesktopOrganizeHandler 相同的 config 模式。
import 'dart:convert';

import '../../../models/bridge_action.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/conversation.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../services/conversation_store.dart';
import 'digital_asset_detection_handler.dart';

/// 數位資產調用 handler 的依賴配置。
class DigitalAssetInvocationHandlerConfig {
  final dynamic digitalAssetRegistry;
  final dynamic activeProjectDoor;
  final Conversation? currentConversation;
  final bool Function(String, List<String>) containsAny;
  final dynamic secondBrainFileIndexStore;
  final String? activeCompanionName;
  final bool Function() mounted;
  final void Function(void Function() fn) setState;
  final void Function() scrollToBottom;
  final Future<void> Function(Conversation) onConversationSaved;

  const DigitalAssetInvocationHandlerConfig({
    required this.digitalAssetRegistry,
    required this.activeProjectDoor,
    required this.currentConversation,
    required this.containsAny,
    required this.secondBrainFileIndexStore,
    required this.activeCompanionName,
    required this.mounted,
    required this.setState,
    required this.scrollToBottom,
    required this.onConversationSaved,
  });
}

/// 數位資產調用 handler — 處理 _invokeDigitalAsset 邏輯。
class DigitalAssetInvocationHandler {
  final DigitalAssetInvocationHandlerConfig config;

  DigitalAssetInvocationHandler(this.config);

  /// 調用數位資產，寫入對話與第二大腦索引。
  Future<void> invokeDigitalAsset(DigitalAssetInvocationCardData card) async {
    final now = DateTime.now();
    final plan = DigitalAssetDetectionHandler(
      DigitalAssetDetectionHandlerConfig(
        digitalAssetRegistry: config.digitalAssetRegistry,
        activeProjectDoor: config.activeProjectDoor,
        currentConversation: config.currentConversation,
        containsAny: config.containsAny,
      ),
    ).reusePlanFromDigitalAsset(card);
    final content = _buildInvocationContent(card);

    final conv = config.currentConversation;
    if (conv != null) {
      final updated = conv.copyWith(
        updatedAt: now,
        messages: [
          ...conv.messages,
          Message(
            id: 'digital-asset-invoked-${now.microsecondsSinceEpoch}',
            role: 'assistant',
            content: content,
            timestamp: now,
            metadata: {
              'kind': 'digital_asset_invoked',
              'assetId': card.assetId,
              'targetProjectId': card.targetProjectId,
            },
          ),
          Message(
            id: 'digital-asset-reuse-plan-${now.microsecondsSinceEpoch}',
            role: 'assistant',
            content:
                '$digitalAssetReusePlanCardPrefix${jsonEncode(plan.toJson())}',
            timestamp: now.add(const Duration(milliseconds: 1)),
            metadata: {
              'kind': 'digital_asset_reuse_plan',
              'assetId': card.assetId,
              'targetProjectId': card.targetProjectId,
            },
          ),
        ],
      );
      await ConversationStore.save(updated);
      await config.onConversationSaved(updated);
      if (config.mounted()) {
        config.setState(() {});
      }
    }

    await _upsertSecondBrainEntries(card, plan, content, now);

    if (!config.mounted()) return;
    config.setState(() {
      _buildSecondBrainTrace(card, plan);
    });

    if (!config.mounted()) return;
    config.setState(() {});
    config.scrollToBottom();
  }

  String _buildInvocationContent(DigitalAssetInvocationCardData card) {
    return [
      '已引入數位資產：${card.assetTitle}',
      '',
      '資產類型：${card.assetKind}',
      if (card.sourceLabel.trim().isNotEmpty) '來源：${card.sourceLabel}',
      '目前專案：${card.targetProjectTitle}',
      '',
      '這次使用意圖：${card.request}',
      if (card.reusableScenes.isNotEmpty) '',
      if (card.reusableScenes.isNotEmpty)
        '可用場景：${card.reusableScenes.take(5).join('、')}',
      if (card.capabilities.isNotEmpty)
        '帶入能力：${card.capabilities.take(5).join('、')}',
      '',
      '下一步：我會把這包資產視為目前專案可調用的玩法/能力，後續規劃會優先嘗試使用它。',
    ].join('\n');
  }

  Future<void> _upsertSecondBrainEntries(
    DigitalAssetInvocationCardData card,
    DigitalAssetReusePlanCardData plan,
    String content,
    DateTime now,
  ) async {
    await config.secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'project-digital-asset-${card.targetProjectId}-${card.assetId}',
        title: '已引入資產：${card.assetTitle}',
        path:
            'local://project-doors/${card.targetProjectId}/digital-assets/${card.assetId}',
        room: SecondBrainRoom.projects,
        summary: '「${card.targetProjectTitle}」已調用「${card.assetTitle}」。',
        contentDigest: content,
        contentExcerpt: [
          card.assetSummary,
          ...card.reusableScenes.take(3),
        ].where((item) => item.trim().isNotEmpty).join(' / '),
        tags: ['專案門', '數位資產調用', card.assetKind, card.targetProjectTitle],
        keywords: [
          card.targetProjectTitle,
          card.assetTitle,
          card.assetKind,
          card.request,
          ...card.capabilities,
          ...card.reusableScenes,
        ],
        indexedAt: now,
        trustScore: 82,
        pinned: true,
      ),
    );

    await config.secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'project-digital-asset-plan-${card.targetProjectId}-${card.assetId}',
        title: '資產重用任務草案：${card.assetTitle}',
        path:
            'local://project-doors/${card.targetProjectId}/digital-assets/${card.assetId}/reuse-plan',
        room: SecondBrainRoom.projects,
        summary:
            '「${card.targetProjectTitle}」已根據「${card.assetTitle}」產生下一步任務草案。',
        contentDigest: plan.readableSummary,
        contentExcerpt: plan.suggestedAction,
        tags: ['專案門', '資產重用任務草案', card.assetKind, card.targetProjectTitle],
        keywords: [
          card.targetProjectTitle,
          card.assetTitle,
          card.assetKind,
          card.request,
          plan.suggestedAction,
          ...plan.nextSteps,
          ...card.capabilities,
          ...card.reusableScenes,
        ],
        indexedAt: now,
        trustScore: 84,
        pinned: true,
      ),
    );
  }

  void _buildSecondBrainTrace(
    DigitalAssetInvocationCardData card,
    DigitalAssetReusePlanCardData plan,
  ) {
    // Trace 由呼叫端 setState 處理
  }
}

/// 從重用計畫卡片組建 BridgeAction — 純函數。
BridgeAction bridgeActionForReusePlan(
  DigitalAssetReusePlanCardData card, {
  required bool outlineOnly,
  required bool Function(String, List<String>) containsAny,
}) {
  final normalized =
      '${card.assetTitle} ${card.assetKind} ${card.request} ${card.suggestedAction} ${card.capabilities.join(' ')} ${card.reusableScenes.join(' ')}'
          .toLowerCase();
  if (!outlineOnly &&
      containsAny(normalized, const ['整理', '歸檔', '資料夾', '桌面整理', '規則'])) {
    return BridgeAction(
      type: BridgeActionType.desktopFiles,
      provider: 'local_desktop_files',
      prompt: [
        '依照「${card.assetTitle}」先只讀掃描資料夾，產生整理計畫。',
        '原始需求：${card.request}',
        '下一步任務：${card.suggestedAction}',
        if (card.reusableScenes.isNotEmpty)
          '可用場景：${card.reusableScenes.take(4).join('、')}',
      ].join('\n'),
    );
  }

  final title = outlineOnly
      ? '資產重用大綱：${card.assetTitle}'
      : '資產重用第一步：${card.assetTitle}';
  return BridgeAction(
    type: BridgeActionType.document,
    prompt: [
      '$title|',
      '請根據以下已引用的數位資產，產出目前專案可以立刻檢查與接續執行的文件草案。',
      '',
      '目前專案：${card.targetProjectTitle}',
      '使用者原始需求：${card.request}',
      '已引用資產：${card.assetTitle}',
      '資產類型：${card.assetKind}',
      '下一步任務：${card.suggestedAction}',
      if (card.reusableScenes.isNotEmpty)
        '可用場景：${card.reusableScenes.take(6).join('、')}',
      if (card.capabilities.isNotEmpty)
        '可帶入能力：${card.capabilities.take(6).join('、')}',
      '',
      outlineOnly
          ? '請只產出大綱：包含目標、可重用資產如何接入、缺口、下一步提問。'
          : '請產出第一版可執行草案：包含明確任務步驟、輸入資料、產出物、驗收標準與下一個可按的行動。',
      '最後請標註：本文件由數位資產重用閉環產生，完成後要寫回第二大腦與 Digital Asset Registry。',
    ].join('\n'),
  );
}
