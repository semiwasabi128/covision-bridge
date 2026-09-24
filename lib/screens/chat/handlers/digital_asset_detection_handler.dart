// [教練 Agent Sprint 17 Step 7 — 2026-07-07]
// DigitalAssetDetectionHandler — 數位資產偵測方法群，從 chat_screen.dart _ChatScreenState 拆出。
//
// 職責：
//   1. 偵測使用者訊息是否意圖重用既有數位資產，並產出 DigitalAssetInvocationCardData。
//   2. 判斷訊息是否像可重用資產任務（_looksLikeReusableAssetTask）。
//   3. 近期訊息是否已出現同一資產的 invocation card，避免重複推薦。
//   4. fallback 比對理由 / 語意比對 / 關鍵詞比對等輔助判斷。
//   5. 從 DigitalAssetInvocationCardData 推導重用計畫（DigitalAssetReusePlanCardData）
//      以及建議的第一步動作。
//
// 設計：
// - 依賴全部透過 DigitalAssetDetectionHandlerConfig 構造函數傳入，handler 不持有
//   ChatScreenState，方便測試與單獨復用。
// - 純搬移，不改邏輯：方法內容與 chat_screen.dart 原始版本一致，只把
//   _currentConversation / _activeProjectDoor / _digitalAssetRegistry 等欄位存取
//   改為 config.xxx，方法去掉 `_` 前綴變成 instance methods。
// - _containsAny 原為 thin wrapper 委派至 ChatController.containsAny；此處改成
//   config.containsAny callback，由呼叫端注入，handler 不直接依賴 ChatController。
// - _meaningfulDigitalAssetTerms / _suggestedActionForReusedAsset /
//   _looksLikeReusableAssetTask 為純函數，改為 static 方法。

import '../../../models/conversation.dart';
import '../../../models/digital_asset.dart';
import '../../../models/project_door.dart';
import '../../../models/chat_card_data.dart';
import '../../../services/digital_asset_registry_store.dart';

/// 數位資產偵測 handler 的依賴封裝。
///
/// 把原本散在 _ChatScreenState 的欄位集中成一個 config，構造時一次傳入，
/// handler 內部不再回頭存取 ChatScreen。
class DigitalAssetDetectionHandlerConfig {
  const DigitalAssetDetectionHandlerConfig({
    required this.digitalAssetRegistry,
    required this.activeProjectDoor,
    required this.currentConversation,
    required this.containsAny,
  });

  /// 數位資產 registry，用於查詢可重用資產。
  final DigitalAssetRegistryStore digitalAssetRegistry;

  /// 目前作用中的專案門（可能為 null）。
  final ProjectDoor? activeProjectDoor;

  /// 目前對話（可能為 null）。
  final Conversation? currentConversation;

  /// 文本比對 callback，對應原 ChatController.containsAny。
  final bool Function(String text, List<String> needles) containsAny;
}

/// 數位資產偵測 handler。
///
/// 從 chat_screen.dart 拆出的偵測方法群，純搬移不改邏輯。
class DigitalAssetDetectionHandler {
  DigitalAssetDetectionHandler(this.config);

  final DigitalAssetDetectionHandlerConfig config;

  Future<DigitalAssetInvocationCardData?> detectDigitalAssetInvocation(
    String text,
  ) async {
    final activeDoor = config.activeProjectDoor;
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final asksToReuse = config.containsAny(normalized, const [
      '使用',
      '引用',
      '調用',
      '套用',
      '導入',
      '引入',
      '拿來用',
      '用在',
      '接上',
      '移植',
      '共享',
      '共用',
      '套進',
      '帶進',
    ]);
    final mentionsAssetLikeThing = config.containsAny(normalized, const [
      '數位資產',
      '資產',
      '玩法',
      '引擎',
      '插件',
      '能力',
      '角色',
      '創建角色',
      '創造角色',
      'semidao',
      'semi dao',
      '橋',
      'adapter',
    ]);
    final looksLikeReusableTask = looksLikeReusableAssetTask(normalized);
    if ((!asksToReuse || !mentionsAssetLikeThing) && !looksLikeReusableTask) {
      return null;
    }

    final targetProjectId =
        activeDoor?.id ?? config.currentConversation?.id ?? 'current-conversation';
    final targetProjectTitle =
        activeDoor?.title ?? config.currentConversation?.title ?? '目前對話';
    final targetCapabilities = activeDoor?.requiredBridges ?? const <String>[];
    var suggestions = await config.digitalAssetRegistry.suggestForTask(
      request: text,
      projectTitle: targetProjectTitle,
      projectCapabilities: targetCapabilities,
      excludeProjectDoorId: activeDoor?.id ?? '',
      limit: 6,
    );
    if (suggestions.isEmpty) {
      final fallbackHits = await config.digitalAssetRegistry.search(
        '$text $targetProjectTitle ${targetCapabilities.join(' ')}',
        limit: 6,
      );
      suggestions = fallbackHits
          .where(
            (asset) =>
                activeDoor == null ||
                asset.sourceProjectDoorId != activeDoor.id,
          )
          .where((asset) => digitalAssetMatchesRequest(asset, normalized))
          .map(
            (asset) => DigitalAssetSuggestion(
              asset: asset,
              score: 8,
              reasons: fallbackDigitalAssetMatchReasons(asset, normalized),
            ),
          )
          .toList();
    }
    final suggestion = suggestions
        .where(
          (item) =>
              item.asset.reusableByProjects || item.asset.reusableByAgents,
        )
        .where((item) => digitalAssetMatchesRequest(item.asset, normalized))
        .firstOrNull;
    final asset = suggestion?.asset;
    if (asset == null) return null;
    if (hasRecentDigitalAssetInvocationCard(asset.id, targetProjectId)) {
      return null;
    }
    return DigitalAssetInvocationCardData(
      assetId: asset.id,
      assetTitle: asset.title,
      assetKind: asset.kind.label,
      assetSummary: asset.summary,
      sourceLabel: asset.sourceLabel,
      capabilities: asset.capabilities,
      reusableScenes: asset.reusableScenes,
      matchReasons: suggestion?.reasons ?? const [],
      targetProjectId: targetProjectId,
      targetProjectTitle: targetProjectTitle,
      request: text,
    );
  }

  /// 判斷輸入文字是否像一個可重用資產任務。純函數，改為 static。
  static bool looksLikeReusableAssetTask(String normalizedText) {
    if (normalizedText.length < 8) return false;
    final taskVerb = _containsAnyHelper(normalizedText, const [
      '幫我',
      '我想',
      '開始',
      '動手',
      '規劃',
      '設計',
      '產出',
      '生成',
      '建立',
      '製作',
      '整理',
      '寫',
      '完成',
      '接下來',
      '第一步',
      '做一個',
      '做個',
      '弄一個',
    ]);
    final taskObject = _containsAnyHelper(normalizedText, const [
      '直播',
      '帶貨',
      '角色',
      '腳本',
      '影片',
      '圖片',
      '文件',
      '報告',
      '專案',
      '工作流',
      '流程',
      '玩法',
      '橋',
      '插件',
      '資產',
      'semidao',
      'semi dao',
    ]);
    return taskVerb && taskObject;
  }

  bool hasRecentDigitalAssetInvocationCard(String assetId, String doorId) {
    final messages = config.currentConversation?.messages;
    if (messages == null || messages.isEmpty) return false;
    return messages.reversed
        .take(8)
        .any(
          (message) =>
              message.content.startsWith(digitalAssetInvocationCardPrefix) &&
              message.content.contains(assetId) &&
              message.content.contains(doorId),
        );
  }

  List<String> fallbackDigitalAssetMatchReasons(
    DigitalAsset asset,
    String normalizedText,
  ) {
    final reasons = <String>[];
    for (final term in meaningfulDigitalAssetTerms(asset)) {
      if (normalizedText.contains(term.toLowerCase())) {
        reasons.add('關鍵線索：$term');
      }
      if (reasons.length >= 4) break;
    }
    if (reasons.isEmpty && asset.creativeTags.isNotEmpty) {
      reasons.add('創意標籤：${asset.creativeTags.first}');
    }
    if (reasons.isEmpty && asset.purposeTags.isNotEmpty) {
      reasons.add('目的標籤：${asset.purposeTags.first}');
    }
    return reasons;
  }

  bool digitalAssetMatchesRequest(DigitalAsset asset, String normalizedText) {
    final haystack =
        '${asset.title} ${asset.kind.label} ${asset.summary} '
                '${asset.capabilities.join(' ')} ${asset.reusableScenes.join(' ')} '
                '${asset.tags.join(' ')} ${asset.purposeTags.join(' ')} '
                '${asset.locationTags.join(' ')} ${asset.propertyTags.join(' ')} '
                '${asset.creativeTags.join(' ')}'
            .toLowerCase();
    final semanticPairs = const [
      ['創建角色', '角色'],
      ['創造角色', '角色'],
      ['直播角色', '角色'],
      ['直播帶貨', '直播'],
      ['帶貨', '銷售'],
      ['企劃', '企劃'],
      ['腳本', '腳本'],
      ['文案', '文案'],
      ['報告', '報告'],
      ['文件', '文件'],
      ['圖片', '圖片'],
      ['影片', '影片'],
      ['召喚替身', '角色'],
      ['semidao', 'semidao'],
      ['semi dao', 'semidao'],
      ['插件', '插件'],
      ['能力', '能力'],
      ['工作流', '工作流'],
      ['流程', '工作流'],
      ['引擎', '引擎'],
      ['adapter', 'adapter'],
      ['知識包', '知識'],
    ];
    final pairMatched = semanticPairs.any(
      (pair) =>
          normalizedText.contains(pair.first) && haystack.contains(pair.last),
    );
    if (pairMatched) return true;

    return meaningfulDigitalAssetTerms(
      asset,
    ).any((term) => normalizedText.contains(term.toLowerCase()));
  }

  /// 列舉資產中有意義的關鍵詞。純函數，改為 static。
  static Iterable<String> meaningfulDigitalAssetTerms(DigitalAsset asset) sync* {
    const ignored = {
      '數位資產',
      '跨專案引用',
      '多 agent 共用',
      '多 Agent 共用',
      '跨專案',
      '共用',
      '重用',
      '可重用',
      '任務',
      '專案',
      '本機',
      '桌面',
    };
    final buckets = [
      asset.title.split(RegExp(r'[\s·／/、,，:：-]+')),
      [asset.kind.label],
      asset.capabilities,
      asset.reusableScenes,
      asset.tags,
      asset.purposeTags,
      asset.locationTags,
      asset.propertyTags,
      asset.creativeTags,
    ];
    for (final bucket in buckets) {
      for (final raw in bucket) {
        final term = raw.trim();
        if (term.length < 2 || ignored.contains(term)) continue;
        yield term;
      }
    }
  }

  /// 從 invocation card 推導重用計畫。
  DigitalAssetReusePlanCardData reusePlanFromDigitalAsset(
    DigitalAssetInvocationCardData card,
  ) {
    final normalized =
        '${card.assetTitle} ${card.assetKind} ${card.assetSummary} ${card.capabilities.join(' ')} ${card.reusableScenes.join(' ')} ${card.request}'
            .toLowerCase();
    final suggestedAction = suggestedActionForReusedAsset(normalized);
    final primaryScene = card.reusableScenes.isNotEmpty
        ? card.reusableScenes.first
        : '目前任務';
    final bridgeStep = card.capabilities.isNotEmpty
        ? '確認可用能力：${card.capabilities.take(3).join('、')}'
        : '檢查是否需要補開能力橋';
    return DigitalAssetReusePlanCardData(
      assetId: card.assetId,
      assetTitle: card.assetTitle,
      assetKind: card.assetKind,
      targetProjectId: card.targetProjectId,
      targetProjectTitle: card.targetProjectTitle,
      request: card.request,
      suggestedAction: suggestedAction,
      planSummary: '我會先把「$primaryScene」這包既有成果接到目前專案，先產出可檢查的第一版，再補缺口。',
      nextSteps: [
        '套用「${card.assetTitle}」到目前專案',
        suggestedAction,
        bridgeStep,
        '產出後寫回第二大腦與數位資產 Registry',
      ],
      capabilities: card.capabilities,
      reusableScenes: card.reusableScenes,
    );
  }

  /// 依據輸入文字推薦重用資產的第一步動作。純函數，改為 static。
  static String suggestedActionForReusedAsset(String normalized) {
    final mentionsRole = _containsAnyHelper(normalized, const [
      '角色',
      '創建角色',
      '創造角色',
      'avatar',
    ]);
    final mentionsScript = _containsAnyHelper(normalized, const ['腳本', '文案', '台詞']);
    if (mentionsRole && !mentionsScript) {
      return '先整理角色定位與角色資產需求';
    }
    if (_containsAnyHelper(normalized, const ['直播', '帶貨', '商品', '銷售', '腳本'])) {
      return '先產出商品直播腳本大綱';
    }
    if (mentionsRole) {
      return '先整理角色定位與角色資產需求';
    }
    if (_containsAnyHelper(normalized, const ['整理', '歸檔', '資料夾', '規則'])) {
      return '先產出整理規則與執行前核對清單';
    }
    if (_containsAnyHelper(normalized, const ['文件', '報告', '簡報', '摘要'])) {
      return '先產出文件大綱與摘要草案';
    }
    if (_containsAnyHelper(normalized, const ['工作流', '流程', '自動化', '引擎'])) {
      return '先拆成可執行的工作流步驟';
    }
    if (_containsAnyHelper(normalized, const ['插件', '橋', 'adapter', '能力'])) {
      return '先整理能力接入檢查表';
    }
    return '先整理可執行的第一步草案';
  }

  /// _containsAny 的純函數版本，供 static 方法使用。
  /// 原本的 _containsAny 委派至 ChatController.containsAny，此處直接實作
  /// 「text 是否包含 needles 任一字串」的判斷。
  static bool _containsAnyHelper(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }
}
