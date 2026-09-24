import 'dart:io';

import '../../../models/bridge_action.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../models/second_brain_trace.dart';
import '../../../services/bridge_action_executor.dart';
import 'bridge_action_ui_helper.dart';

/// [Sprint 17 Step 7] 從 chat_screen.dart 提取的橋樑 insight / trace 相關輔助函數。
/// 這些方法原本是 _ChatScreenState 的私有方法，現在改為頂層函數，
/// 參數化後由 chat_screen 呼叫。

String? bridgeInsightLabel(BridgeAction? action) {
  if (action == null) return null;
  switch (action.type) {
    case BridgeActionType.browse:
      return '新聞與網頁搜尋橋：查詢最新網頁資料，整理重點與來源。';
    case BridgeActionType.vision:
      return '圖片辨識橋：讀取圖片內容，整理可見線索。';
    case BridgeActionType.generateMusic:
      return '音樂生成橋：需要音樂服務才能產出音訊。';
    case BridgeActionType.generateImage:
      return '圖片生成橋：依照提示詞產生角色或素材圖。';
    case BridgeActionType.generateVideo:
      return '影片生成橋：需要影片服務才能產出影片。';
    case BridgeActionType.generateAnimation:
      return '角色動態接口：目前保留給未來穩定動畫插件。';
    case BridgeActionType.document:
      return '文件生成橋：把內容整理成可保存文件。';
    case BridgeActionType.desktopFiles:
      return '桌面整理橋：先只讀掃描授權資料夾，產生分類與整理計畫。';
    case BridgeActionType.unknown:
      return null;
  }
}

String? bridgeInsightLabelForResult(
  BridgeAction action,
  BridgeActionResult result,
) {
  final base = bridgeInsightLabel(action);
  if (action.type != BridgeActionType.browse) return base;
  final metadata = result.metadata;
  final query = metadata?['query']?.toString().trim();
  final count = metadata?['sourceCount']?.toString().trim();
  final health = metadata?['sourceHealth']?.toString();
  final parts = <String>[
    if (query != null && query.isNotEmpty) '查詢「$query」',
    if (count != null && count.isNotEmpty) '來源 $count 筆',
    if (health == 'sources_missing') '需要補來源',
  ];
  if (parts.isEmpty) return base;
  return '新聞與網頁搜尋橋：${parts.join('，')}。';
}

SecondBrainTrace bridgeSecondBrainTrace(
  BridgeAction action, {
  BridgeActionResult? result,
  CapabilityGapCardData? capabilityGap,
  String? agentName,
  String? activeProjectDoorTitle,
  SecondBrainRoom Function()? documentAssetRoomForCurrentContext,
}) {
  final label = bridgeInsightLabel(action) ?? action.type.displayLabel;
  final query =
      result?.metadata?['query']?.toString().trim().isNotEmpty == true
      ? result!.metadata!['query'].toString().trim()
      : action.prompt.trim();
  final status = result?.status;
  final bridgeRoom = action.type == BridgeActionType.browse
      ? 'Bridges'
      : 'Capabilities';
  final sourceMaps = BridgeActionUIHelper.searchSourceMaps(result?.metadata);
  final recalled = <SecondBrainMemoryTrace>[
    SecondBrainMemoryTrace(
      content: action.type == BridgeActionType.browse
          ? '正在用新聞與網頁搜尋橋查詢「$query」，完成後會整理摘要、來源與時間敏感提醒。'
          : '正在使用「$label」處理這輪任務。',
      room: bridgeRoom,
      sourceLabel: label,
      sourcePath: 'local://bridge/${action.type.legacyType}',
      reason: capabilityGap != null
          ? '這輪命中能力缺口，因此先保留任務並引導到金鑰匙中心。'
          : result == null
          ? '這輪需求已命中正式橋能力，思維儀表先追蹤橋樑執行狀態。'
          : '橋樑已回傳結果，思維儀表同步整理查詢、來源與下一步。',
      retrievalSignals: [
        '使用者請求：$query',
        '使用橋：$label',
        if (status != null) '執行狀態：${bridgeStatusLabel(status)}',
        if (capabilityGap != null) '缺口：${capabilityGap.missing}',
      ],
      freshnessLabel: result == null ? '執行中' : '剛完成',
      sourcePreview: result?.message.trim().isNotEmpty == true
          ? result!.message.trim()
          : query,
      tags: const ['正式橋', '能力路由', '思維儀表'],
      trustScore: result?.status == BridgeActionStatus.completed ? 82 : 64,
    ),
    ...sourceMaps.take(3).map((source) {
      final title = source['title']?.toString().trim().isNotEmpty == true
          ? source['title'].toString().trim()
          : source['url']?.toString().trim().isNotEmpty == true
          ? source['url'].toString().trim()
          : '搜尋來源';
      final url = source['url']?.toString().trim();
      return SecondBrainMemoryTrace(
        content: title,
        room: 'Bridges',
        sourceLabel: title,
        sourcePath: url == null || url.isEmpty ? null : url,
        reason: '這是搜尋橋回傳的可追查來源，使用者可以用它驗證回答。',
        retrievalSignals: [
          '查詢：$query',
          if (url != null && url.isNotEmpty) '可點證據：$url',
        ],
        freshnessLabel: '剛查到',
        sourcePreview: url ?? title,
        tags: const ['來源', '證據', '新聞與網頁搜尋橋'],
        trustScore: 76,
      );
    }),
  ];
  final outputs = <SecondBrainOutputTrace>[
    if (result != null)
      SecondBrainOutputTrace(
        title: action.type == BridgeActionType.browse
            ? '搜尋摘要與來源卡'
            : action.type == BridgeActionType.document
            ? documentAssetTraceTitle(result)
            : action.type == BridgeActionType.desktopFiles
            ? desktopFilesAssetTraceTitle(result)
            : '橋樑執行結果',
        kind: action.type.displayLabel,
        path: action.type == BridgeActionType.document
            ? documentAssetPrimaryPath(result)
            : action.type == BridgeActionType.desktopFiles
            ? desktopFilesPrimaryPath(result)
            : sourceMaps.isNotEmpty
            ? sourceMaps.first['url']?.toString()
            : 'local://conversation/latest-bridge-result',
      ),
  ];
  return SecondBrainTrace(
    agentName: agentName,
    recalledMemories: recalled,
    newInsights: [
      if (action.type == BridgeActionType.browse && result != null)
        SecondBrainNewInsightTrace(
          content: '搜尋結果已寫入「橋樑房間」，之後可以回查查詢字、來源、擷取時間與摘要。',
          room: SecondBrainRoom.bridges.label,
          tags: const ['搜尋結果', '可點證據', '新聞與網頁搜尋橋'],
        ),
      if (action.type == BridgeActionType.vision && result != null)
        SecondBrainNewInsightTrace(
          content: '圖片辨識結果已寫入「檔案房間」，之後可以回查圖片來源、辨識目的與畫面線索。',
          room: SecondBrainRoom.files.label,
          tags: const ['圖片辨識', '圖片線索', 'Vision橋'],
        ),
      if (action.type == BridgeActionType.document && result != null)
        SecondBrainNewInsightTrace(
          content:
              '文件資產已產出，將依目前情境掛到「${(documentAssetRoomForCurrentContext?.call() ?? SecondBrainRoom.files).zhLabel}」，之後可從第二大腦調閱或接續改寫。',
          room: (documentAssetRoomForCurrentContext?.call() ?? SecondBrainRoom.files).label,
          tags: const ['文件資產', '資料地圖', '文件產出橋'],
        ),
      if (action.type == BridgeActionType.desktopFiles && result != null)
        SecondBrainNewInsightTrace(
          content: '桌面整理結果已寫入「檔案房間」，之後可以回查掃描位置、分類建議與整理紀錄。',
          room: SecondBrainRoom.files.label,
          tags: const ['桌面整理', '檔案地圖', '桌面整理橋'],
        ),
    ],
    outputs: outputs,
    associations: [
      '使用者需求 ↔ $label ↔ ${result == null ? '等待執行' : '結果整理'}',
      if (sourceMaps.isNotEmpty) '搜尋橋 ↔ ${sourceMaps.length} 個來源 ↔ 可點證據',
      if (action.type == BridgeActionType.browse && result != null)
        '新聞與網頁搜尋橋 ↔ 橋樑房間 ↔ ${query.isEmpty ? '搜尋結果' : query}',
      if (action.type == BridgeActionType.vision && result != null)
        '圖片辨識橋 ↔ 檔案房間 ↔ ${result.metadata?['imageSource']?.toString() ?? '已附加圖片'}',
      if (action.type == BridgeActionType.document && result != null)
        '文件產出橋 ↔ 第二大腦索引 ↔ ${activeProjectDoorTitle ?? '檔案房間'}',
      if (action.type == BridgeActionType.desktopFiles && result != null)
        '桌面整理橋 ↔ 檔案房間 ↔ ${desktopFilesPrimaryPath(result) ?? '授權資料夾'}',
      if (capabilityGap != null) '能力缺口 ↔ 金鑰匙中心 ↔ 回到原任務',
    ],
  );
}

String documentAssetTraceTitle(BridgeActionResult result) {
  final title = result.metadata?['title']?.toString().trim();
  if (title != null && title.isNotEmpty) return '文件資產：$title';
  return '文件資產';
}

String? documentAssetPrimaryPath(BridgeActionResult result) {
  final metadataPath = result.metadata?['path']?.toString().trim();
  if (metadataPath != null && metadataPath.isNotEmpty) return metadataPath;
  final mediaUrl = result.mediaUrl?.trim();
  if (mediaUrl != null && mediaUrl.isNotEmpty) return mediaUrl;
  return null;
}

String desktopFilesAssetTraceTitle(BridgeActionResult result) {
  final root = desktopFilesPrimaryPath(result);
  final rootName = basename(root);
  final executed = result.metadata?['executed'] == true;
  if (rootName == null || rootName.isEmpty) {
    return executed ? '桌面整理紀錄' : '桌面整理計畫';
  }
  return executed ? '桌面整理紀錄：$rootName' : '桌面整理計畫：$rootName';
}

String? desktopFilesPrimaryPath(BridgeActionResult result) {
  final recordPath = result.metadata?['recordPath']?.toString().trim();
  if (recordPath != null && recordPath.isNotEmpty) return recordPath;
  final rootPath = result.metadata?['rootPath']?.toString().trim();
  if (rootPath != null && rootPath.isNotEmpty) return rootPath;
  return null;
}

String? basename(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final normalized = trimmed.replaceAll('\\', Platform.pathSeparator);
  final parts = normalized
      .split(Platform.pathSeparator)
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) return trimmed;
  return parts.last;
}

String bridgeStatusLabel(BridgeActionStatus status) {
  switch (status) {
    case BridgeActionStatus.completed:
      return '完成';
    case BridgeActionStatus.needsProvider:
      return '缺少能力';
    case BridgeActionStatus.needsConfirmation:
      return '等待確認';
    case BridgeActionStatus.unsupported:
      return '未完成';
  }
}
