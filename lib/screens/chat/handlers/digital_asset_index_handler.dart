// [教練 Agent Sprint 17 Step 7 — 2026-07-07]
// DigitalAssetIndexHandler — 數位資產索引邏輯，從 chat_screen.dart _ChatScreenState 拆出。
//
// 職責：
//   1. 把四種橋樑動作結果（web_search / vision / document / desktop_file_plan）
//      索引到第二大腦檔案庫（SecondBrainFileIndexStore）並註冊為數位資產
//      （DigitalAssetRegistryStore）。
//   2. 三個輔助判斷（資產重用標題 / 資產重用桌面 prompt / 創意標籤推斷）
//      以靜態方法提供，方便外部沿用。
//
// 設計：
// - 依賴全部透過 DigitalAssetIndexHandlerConfig 構造函數傳入，handler 不持有
//   ChatScreenState，方便測試與單獨復用。
// - 純搬移，不改邏輯：方法內容與 chat_screen.dart 原始版本一致，只把
//   _currentConversation / _activeProjectDoor / _secondBrainFileIndexStore /
//   _digitalAssetRegistry 等欄位存取改為 config.xxx。
// - _documentAssetPrimaryPath / _documentAssetRoomForCurrentContext /
//   _basename / _desktopCategorySummary 四個跨畫面回調以 Function 形式注入。

import '../../../models/conversation.dart';
import '../../../services/bridge_action_executor.dart';
import '../../../models/digital_asset.dart';
import '../../../models/project_door.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../services/digital_asset_registry_store.dart';
import '../../../services/second_brain_file_index_store.dart';
import '../helpers/bridge_action_ui_helper.dart';

/// 數位資產索引 handler 的依賴封裝。
///
/// 把原本散在 _ChatScreenState 的欄位與跨畫面回調集中成一個 config，
/// 構造時一次傳入，handler 內部不再回頭存取 ChatScreen。
class DigitalAssetIndexHandlerConfig {
  const DigitalAssetIndexHandlerConfig({
    required this.secondBrainFileIndexStore,
    required this.digitalAssetRegistry,
    required this.activeProjectDoor,
    required this.currentConversation,
    required this.documentAssetPrimaryPath,
    required this.documentAssetRoomForCurrentContext,
    required this.basename,
    required this.desktopCategorySummary,
  });

  /// 第二大腦檔案索引庫（upsert SecondBrainFileEntry）。
  final SecondBrainFileIndexStore secondBrainFileIndexStore;

  /// 數位資產登錄庫（registerAsset）。
  final DigitalAssetRegistryStore digitalAssetRegistry;

  /// 目前作用中的專案門（可能為 null）。
  final ProjectDoor? activeProjectDoor;

  /// 目前對話（呼叫端保證非 null 時才使用索引方法）。
  final Conversation? currentConversation;

  /// 從 BridgeActionResult 取出文件資產主要路徑的回調。
  final String? Function(BridgeActionResult) documentAssetPrimaryPath;

  /// 依目前情境決定文件資產要掛到哪個第二大腦房間的回調。
  final SecondBrainRoom Function() documentAssetRoomForCurrentContext;

  /// 取路徑檔名（basename）的回調。
  final String? Function(String?) basename;

  /// 把桌面整理 metadata 換成主要分類摘要的回調。
  final String Function(Map<String, dynamic>) desktopCategorySummary;
}

/// 數位資產索引 handler。
///
/// 把 chat_screen.dart 的 _indexBrowseResult / _indexVisionResult /
/// _indexDocumentAssetResult / _indexDesktopFilesResult 四個方法搬過來，
/// 另外附帶 _isReuseDrivenDocumentTitle / _isReuseDrivenDesktopPrompt /
/// _creativeTagsForAssetText 三個輔助靜態方法。
class DigitalAssetIndexHandler {
  DigitalAssetIndexHandler({required this.config});

  final DigitalAssetIndexHandlerConfig config;

  // ─── 四個索引方法 ───

  Future<DigitalAsset?> indexBrowseResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'web_search') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final query = metadata['query']?.toString().trim();
    if (query == null || query.isEmpty) return null;

    final searchQueries = BridgeActionUIHelper.stringListFromMetadata(metadata['searchQueries']);
    final sourceMaps = BridgeActionUIHelper.searchSourceMaps(metadata);
    final primarySource = sourceMaps.isNotEmpty ? sourceMaps.first : null;
    final primaryTitle =
        primarySource?['title']?.toString().trim().isNotEmpty == true
        ? primarySource!['title'].toString().trim()
        : null;
    final primaryUrl =
        primarySource?['url']?.toString().trim().isNotEmpty == true
        ? primarySource!['url'].toString().trim()
        : 'local://bridge/web-search/${config.currentConversation!.id}/${resultMsg.id}';
    final fetchedAt = metadata['fetchedAt']?.toString().trim();
    final sourceCount = metadata['sourceCount']?.toString().trim();
    final sourceHealth = metadata['sourceHealth']?.toString().trim();
    final projectTitle = config.activeProjectDoor?.title;
    final projectFlow = config.activeProjectDoor?.currentFlow;
    final now = DateTime.now();

    await config.secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'web-search-${config.currentConversation!.id}-${resultMsg.id}',
        title: '搜尋結果：$query',
        path: primaryUrl,
        room: SecondBrainRoom.bridges,
        summary: '新聞與網頁搜尋橋查詢「$query」，已整理摘要、時間線索與可點來源。',
        contentDigest: [
          '來源橋：新聞與網頁搜尋橋',
          '原始查詢：$query',
          if (searchQueries.isNotEmpty)
            '實際搜尋：${searchQueries.take(3).join(' / ')}',
          if (fetchedAt != null && fetchedAt.isNotEmpty) '擷取時間：$fetchedAt',
          if (sourceCount != null && sourceCount.isNotEmpty)
            '來源數量：$sourceCount',
          if (sourceHealth != null && sourceHealth.isNotEmpty)
            '來源狀態：$sourceHealth',
          if (primaryTitle != null) '主要來源：$primaryTitle',
          '主要連結：$primaryUrl',
          if (projectTitle != null) '關聯專案門：$projectTitle',
          if (projectFlow != null && projectFlow.isNotEmpty)
            '目前水流：$projectFlow',
        ].join('。'),
        contentExcerpt: BridgeActionUIHelper.compactExcerpt(result.message),
        tags: [
          '搜尋結果',
          '新聞與網頁搜尋橋',
          '可點證據',
          if (metadata['timeSensitive'] == true) '時間敏感',
          if (projectTitle != null) '專案門',
          ?projectTitle,
          ?projectFlow,
        ],
        keywords: [
          query,
          ...searchQueries.take(5),
          '搜尋',
          '新聞',
          '網頁',
          '來源',
          ?primaryTitle,
          ?projectTitle,
          ?projectFlow,
        ],
        indexedAt: now,
        trustScore: sourceMaps.isEmpty ? 66 : 82,
      ),
    );

    return config.digitalAssetRegistry.registerAsset(
      id: 'digital-web-search-${config.currentConversation!.id}-${resultMsg.id}',
      title: '搜尋知識包：$query',
      kind: DigitalAssetKind.knowledgePack,
      summary: '新聞與網頁搜尋橋整理出的可重用知識包，包含查詢、摘要、時間線索與可點來源。',
      sourceProjectDoorId: config.activeProjectDoor?.id ?? '',
      sourceConversationId: config.currentConversation!.id,
      sourceLabel: projectTitle ?? '搜尋任務',
      capabilities: const ['新聞與網頁搜尋橋'],
      reusableScenes: const ['資料查證', '報告引用', '任務背景資料', '跨專案研究'],
      tags: [
        '數位資產',
        '搜尋結果',
        '知識包',
        '新聞與網頁搜尋橋',
        if (metadata['timeSensitive'] == true) '時間敏感',
      ],
      purposeTags: const ['資料查證', '知識整理', 'Agent 可調用'],
      locationTags: [
        '主要連結：$primaryUrl',
        if (projectTitle != null) '來源專案：$projectTitle',
        SecondBrainRoom.bridges.zhLabel,
      ],
      propertyTags: [
        '搜尋摘要',
        '可點證據',
        if (sourceCount != null && sourceCount.isNotEmpty) '來源數：$sourceCount',
      ],
      creativeTags: creativeTagsForAssetText(
        '$query $projectTitle $projectFlow',
        fallback: '知識整理',
      ),
    );
  }

  Future<DigitalAsset?> indexVisionResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'vision') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final prompt = metadata['prompt']?.toString().trim();
    final imageSource = metadata['imageSource']?.toString().trim();
    final imageCount = metadata['imageCount']?.toString().trim();
    final model = metadata['model']?.toString().trim();
    final provider = metadata['provider']?.toString().trim();
    final projectTitle = config.activeProjectDoor?.title;
    final projectFlow = config.activeProjectDoor?.currentFlow;
    final path = imageSource != null && imageSource.isNotEmpty
        ? imageSource
        : 'local://bridge/vision/${config.currentConversation!.id}/${resultMsg.id}';
    final title = prompt == null || prompt.isEmpty
        ? '圖片辨識結果'
        : '圖片辨識：${BridgeActionUIHelper.compactExcerpt(prompt, maxChars: 28)}';
    final now = DateTime.now();

    await config.secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'vision-result-${config.currentConversation!.id}-${resultMsg.id}',
        title: title,
        path: path,
        room: SecondBrainRoom.files,
        summary: '圖片辨識橋已讀取圖片，整理畫面摘要、重要細節與可用線索。',
        contentDigest: [
          '來源橋：圖片辨識橋',
          if (prompt != null && prompt.isNotEmpty) '辨識目的：$prompt',
          if (imageSource != null && imageSource.isNotEmpty)
            '圖片來源：$imageSource',
          if (imageCount != null && imageCount.isNotEmpty) '圖片數量：$imageCount',
          if (provider != null && provider.isNotEmpty) 'Provider：$provider',
          if (model != null && model.isNotEmpty) '模型：$model',
          if (projectTitle != null) '關聯專案門：$projectTitle',
          if (projectFlow != null && projectFlow.isNotEmpty)
            '目前水流：$projectFlow',
        ].join('。'),
        contentExcerpt: BridgeActionUIHelper.compactExcerpt(result.message),
        tags: [
          '圖片辨識',
          'Vision橋',
          '圖片線索',
          if (projectTitle != null) '專案門',
          ?projectTitle,
          ?projectFlow,
        ],
        keywords: [
          '圖片',
          '辨識',
          '視覺',
          'Vision',
          if (prompt != null && prompt.isNotEmpty) prompt,
          if (imageSource != null && imageSource.isNotEmpty) imageSource,
          ?projectTitle,
          ?projectFlow,
        ],
        indexedAt: now,
        trustScore: 78,
      ),
    );

    return config.digitalAssetRegistry.registerAsset(
      id: 'digital-vision-result-${config.currentConversation!.id}-${resultMsg.id}',
      title: title,
      kind: DigitalAssetKind.mediaAsset,
      summary: '圖片辨識橋產生的圖像線索資產，可被後續報告、創作、整理或專案判斷引用。',
      sourceProjectDoorId: config.activeProjectDoor?.id ?? '',
      sourceConversationId: config.currentConversation!.id,
      sourceLabel: projectTitle ?? '圖片辨識任務',
      capabilities: const ['圖片辨識橋'],
      reusableScenes: const ['圖像內容分析', '創作參考', '報告素材', '視覺線索回收'],
      tags: const ['數位資產', '圖片辨識', '圖像線索', 'Vision橋'],
      purposeTags: const ['圖像理解', '素材整理', 'Agent 可調用'],
      locationTags: [
        '圖片來源：$path',
        if (projectTitle != null) '來源專案：$projectTitle',
        SecondBrainRoom.files.zhLabel,
      ],
      propertyTags: [
        '圖片',
        '辨識摘要',
        if (imageCount != null && imageCount.isNotEmpty) '圖片數：$imageCount',
      ],
      creativeTags: creativeTagsForAssetText(
        '$title $prompt $projectTitle',
        fallback: '視覺創意',
      ),
    );
  }

  Future<DigitalAsset?> indexDocumentAssetResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'document') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final title = metadata['title']?.toString().trim();
    final documentTitle = title == null || title.isEmpty ? '橋樑文件' : title;
    final documentType = metadata['documentType']?.toString().trim();
    final format = metadata['format']?.toString().trim();
    final generationMode = metadata['generationMode']?.toString().trim();
    final provider = metadata['provider']?.toString().trim();
    final path = config.documentAssetPrimaryPath(result);
    if (path == null || path.isEmpty) return null;
    final reuseDriven = isReuseDrivenDocumentTitle(documentTitle);

    final exportPaths = metadata['exportPaths'];
    final exportSummary = exportPaths is Map
        ? exportPaths.entries
              .map((entry) => '${entry.key}：${entry.value}')
              .join(' / ')
        : path;
    final projectTitle = config.activeProjectDoor?.title;
    final projectFlow = config.activeProjectDoor?.currentFlow;
    final room = config.documentAssetRoomForCurrentContext();
    final now = DateTime.now();

    await config.secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'document-asset-${config.currentConversation!.id}-${resultMsg.id}',
        title: documentTitle,
        path: path,
        room: room,
        summary:
            '文件資產：$documentTitle。${projectTitle == null ? '目前未掛專案門，先存入檔案房間。' : '掛在專案門「$projectTitle」。'}',
        contentDigest: [
          '來源橋：文件產出橋',
          if (documentType != null && documentType.isNotEmpty)
            '文件類型：$documentType',
          if (format != null && format.isNotEmpty) '格式：$format',
          if (generationMode != null && generationMode.isNotEmpty)
            '產出方式：$generationMode',
          if (provider != null && provider.isNotEmpty) 'Provider：$provider',
          if (projectFlow != null && projectFlow.isNotEmpty)
            '目前水流：$projectFlow',
          if (reuseDriven) '資產重用：由已引用數位資產推進產生',
          '實際位置：$path',
        ].join('。'),
        contentExcerpt: exportSummary,
        tags: [
          '文件資產',
          '文件產出橋',
          if (documentType != null && documentType.isNotEmpty) documentType,
          if (format != null && format.isNotEmpty) ...format.split('/'),
          if (reuseDriven) '資產重用成果',
          if (reuseDriven) '不重新造輪子',
          if (projectTitle != null) '專案門',
          ?projectTitle,
          ?projectFlow,
        ],
        keywords: [
          documentTitle,
          '文件',
          '報告',
          '輸出',
          ?projectTitle,
          ?projectFlow,
          if (documentType != null && documentType.isNotEmpty) documentType,
        ],
        indexedAt: now,
        trustScore: 78,
      ),
    );

    return config.digitalAssetRegistry.registerAsset(
      id: 'digital-document-asset-${config.currentConversation!.id}-${resultMsg.id}',
      title: documentTitle,
      kind: DigitalAssetKind.documentAsset,
      summary: reuseDriven
          ? '資產重用閉環產生的文件資產，代表既有數位資產已推進成目前專案的下一步成果。'
          : '文件產出橋產生的文件資產，可被後續專案、Agent 或任務收尾流程引用。',
      sourceProjectDoorId: config.activeProjectDoor?.id ?? '',
      sourceConversationId: config.currentConversation!.id,
      sourceLabel: projectTitle ?? '聊天任務',
      capabilities: const ['文件產出橋'],
      reusableScenes: const ['任務收尾歸檔', '報告再加工', '跨專案文件引用'],
      tags: [
        '數位資產',
        '文件資產',
        '文件產出橋',
        if (reuseDriven) '資產重用成果',
        if (reuseDriven) '不重新造輪子',
        if (documentType != null && documentType.isNotEmpty) documentType,
        if (format != null && format.isNotEmpty) ...format.split('/'),
      ],
      purposeTags: [
        '任務收尾',
        '文件再利用',
        'Agent 可調用',
        if (reuseDriven) '資產重用',
        if (reuseDriven) '下一步任務草案',
      ],
      locationTags: [
        '檔案位置：$path',
        if (projectTitle != null) '來源專案：$projectTitle',
        if (room.zhLabel.isNotEmpty) room.zhLabel,
      ],
      propertyTags: [
        '文件',
        if (reuseDriven) '資產重用成果',
        if (documentType != null && documentType.isNotEmpty) documentType,
        if (format != null && format.isNotEmpty) ...format.split('/'),
      ],
      creativeTags: creativeTagsForAssetText(
        '$documentTitle $documentType $projectTitle $projectFlow',
        fallback: '知識整理',
      ),
    );
  }

  Future<DigitalAsset?> indexDesktopFilesResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'desktop_file_plan') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final rootPath = metadata['rootPath']?.toString().trim();
    if (rootPath == null || rootPath.isEmpty) return null;

    final executed = metadata['executed'] == true;
    final recordPath = metadata['recordPath']?.toString().trim();
    final path = executed && recordPath != null && recordPath.isNotEmpty
        ? recordPath
        : rootPath;
    final rootName = config.basename(rootPath) ?? '授權資料夾';
    final title = executed ? '桌面整理紀錄：$rootName' : '桌面整理計畫：$rootName';
    final categorySummary = config.desktopCategorySummary(metadata);
    final suggestions = BridgeActionUIHelper.stringListFromMetadata(metadata['suggestions']);
    final samples = BridgeActionUIHelper.desktopSampleNames(metadata['samples']);
    final prompt = metadata['prompt']?.toString().trim();
    final projectTitle = config.activeProjectDoor?.title;
    final now = DateTime.now();
    final reuseDriven = isReuseDrivenDesktopPrompt(prompt);

    await config.secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'desktop-files-${config.currentConversation!.id}-${resultMsg.id}',
        title: title,
        path: path,
        room: SecondBrainRoom.files,
        summary: executed
            ? '桌面整理橋已完成整理紀錄：$rootName。'
            : '桌面整理橋已只讀掃描：$rootName，等待使用者確認是否執行。',
        contentDigest: [
          '來源橋：桌面整理橋',
          if (prompt != null && prompt.isNotEmpty) '原始任務：$prompt',
          '掃描位置：$rootPath',
          '檔案數：${metadata['fileCount'] ?? 0}',
          '資料夾數：${metadata['folderCount'] ?? 0}',
          '主要分類：$categorySummary',
          if (executed) ...[
            '已建立資料夾：${metadata['createdFolderCount'] ?? 0}',
            '已移動檔案：${metadata['movedCount'] ?? 0}',
            if (recordPath != null && recordPath.isNotEmpty) '整理紀錄：$recordPath',
          ] else ...[
            '預計建立資料夾：${metadata['plannedFolderCount'] ?? 0}',
            '預計移動檔案：${metadata['plannedMoveCount'] ?? 0}',
            '保留原處：${metadata['skippedCount'] ?? 0}',
            '安全狀態：只讀掃描，尚未搬移、改名或刪除',
          ],
          if (projectTitle != null) '關聯專案門：$projectTitle',
          if (reuseDriven) '資產重用：依既有整理規則或數位資產推進',
        ].join('。'),
        contentExcerpt: [
          if (suggestions.isNotEmpty) '建議：${suggestions.take(3).join(' / ')}',
          if (samples.isNotEmpty) '樣本：${samples.take(8).join('、')}',
        ].join('\n'),
        tags: [
          '桌面整理',
          '檔案地圖',
          '桌面整理橋',
          executed ? '整理紀錄' : '整理計畫',
          if (reuseDriven) '資產重用成果',
          if (reuseDriven) '套用既有規則',
          rootName,
          if (categorySummary != '尚無分類') ...categorySummary.split('、'),
          ?projectTitle,
        ],
        keywords: [
          rootName,
          rootPath,
          '桌面',
          '整理',
          '檔案',
          '分類',
          '掃描',
          if (executed) '整理紀錄' else '整理計畫',
          ?projectTitle,
          ...samples.take(12),
        ],
        indexedAt: now,
        trustScore: executed ? 84 : 74,
      ),
    );

    return config.digitalAssetRegistry.registerAsset(
      id: 'digital-desktop-files-${config.currentConversation!.id}-${resultMsg.id}',
      title: title,
      kind: executed
          ? DigitalAssetKind.documentAsset
          : DigitalAssetKind.workflowEngine,
      summary: executed
          ? '桌面整理橋產生的整理紀錄，可供之後追蹤與回顧。'
          : reuseDriven
          ? '由既有數位資產或整理規則推進出的桌面整理計畫，可作為這次任務的安全核對基礎。'
          : '桌面整理橋產生的整理計畫，可作為受管資料夾規則或後續整理流程的基礎。',
      sourceProjectDoorId: config.activeProjectDoor?.id ?? '',
      sourceConversationId: config.currentConversation!.id,
      sourceLabel: projectTitle ?? rootName,
      capabilities: const ['桌面整理橋', '文件產出橋'],
      reusableScenes: const ['資料夾整理', '受管資料夾規則', '任務收尾歸檔'],
      tags: [
        '數位資產',
        '桌面整理',
        '檔案地圖',
        executed ? '整理紀錄' : '整理計畫',
        if (reuseDriven) '資產重用成果',
        if (reuseDriven) '套用既有規則',
        rootName,
      ],
      purposeTags: [
        '檔案整理',
        '任務收尾',
        'Agent 可調用',
        if (reuseDriven) '資產重用',
        if (reuseDriven) '受管資料夾規則候選',
      ],
      locationTags: [
        '掃描位置：$rootPath',
        if (projectTitle != null) '來源專案：$projectTitle',
      ],
      propertyTags: [
        executed ? '整理紀錄' : '整理計畫',
        if (reuseDriven) '套用既有規則',
        '資料夾規則候選',
        ...(categorySummary == '尚無分類'
            ? const <String>[]
            : categorySummary.split('、')),
      ],
      creativeTags: const ['流程創意', '資料整理'],
    );
  }

  // ─── 三個輔助靜態方法 ───

  static bool isReuseDrivenDocumentTitle(String title) {
    final normalized = title.toLowerCase();
    return normalized.contains('資產重用') ||
        normalized.contains('digital asset') ||
        normalized.contains('reuse');
  }

  static bool isReuseDrivenDesktopPrompt(String? prompt) {
    final normalized = prompt?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return normalized.contains('依照「') ||
        normalized.contains('已引用') ||
        normalized.contains('資產重用') ||
        normalized.contains('整理規則') ||
        normalized.contains('digital asset') ||
        normalized.contains('reuse');
  }

  static List<String> creativeTagsForAssetText(
    String value, {
    required String fallback,
  }) {
    final text = value.toLowerCase();
    final tags = <String>{};
    if (text.contains('直播') || text.contains('銷售') || text.contains('帶貨')) {
      tags.add('內容商務');
    }
    if (text.contains('角色') || text.contains('agent')) {
      tags.add('角色創作');
    }
    if (text.contains('企劃') || text.contains('報告') || text.contains('文件')) {
      tags.add('知識整理');
    }
    if (text.contains('流程') || text.contains('規則') || text.contains('整理')) {
      tags.add('流程創意');
    }
    if (tags.isEmpty) tags.add(fallback);
    return tags.toList(growable: false);
  }
}
