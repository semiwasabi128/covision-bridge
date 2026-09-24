import 'bridge_action_executor.dart';

class BridgeActionExecutionEvidence {
  const BridgeActionExecutionEvidence();

  String? describe(BridgeActionResult result) {
    final metadata = result.metadata;
    if (metadata?['kind']?.toString() == 'web_search') {
      final query = metadata?['query']?.toString();
      final sourceCount = metadata?['sourceCount']?.toString();
      final fetchedAt = metadata?['fetchedAt']?.toString();
      final timeSensitive = metadata?['timeSensitive'] == true;
      final sourceHealth = metadata?['sourceHealth']?.toString();
      final rawQueries = metadata?['searchQueries'];
      final searchQueries = rawQueries is List
          ? rawQueries
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
          : const <String>[];
      final parts = [
        if (query != null && query.trim().isNotEmpty) '查詢「${query.trim()}」',
        if (searchQueries.isNotEmpty)
          '實際搜尋「${searchQueries.take(2).join(' / ')}」',
        if (sourceCount != null && sourceCount.trim().isNotEmpty)
          '來源 $sourceCount 筆',
        if (sourceHealth == 'sources_missing') '來源不足',
        if (timeSensitive) '時間敏感資料',
        if (fetchedAt != null && fetchedAt.trim().isNotEmpty)
          '擷取 ${_shortTime(fetchedAt)}',
      ];
      if (parts.isNotEmpty) return '搜尋證據：${parts.join(' / ')}';
    }

    final kind = metadata?['kind']?.toString();
    if (kind == 'vision') {
      final adapter = metadata?['adapter']?.toString();
      final model = metadata?['model']?.toString();
      final imageCount = metadata?['imageCount']?.toString();
      final parts = [
        if (adapter != null && adapter.trim().isNotEmpty) '執行橋 $adapter',
        if (model != null && model.trim().isNotEmpty) '模型 $model',
        if (imageCount != null && imageCount.trim().isNotEmpty)
          '圖片 $imageCount 張',
      ];
      if (parts.isNotEmpty) return '圖片辨識證據：${parts.join(' / ')}';
    }

    if (kind == 'document') {
      final path = metadata?['path']?.toString();
      final provider = metadata?['provider']?.toString();
      final documentType = metadata?['documentType']?.toString();
      final exportPaths = metadata?['exportPaths'];
      final plannedFormats = metadata?['plannedFormats'];
      final mode = _generationModeLabel(
        metadata?['generationMode']?.toString(),
      );
      final parts = [
        if (documentType != null && documentType.trim().isNotEmpty)
          '類型 $documentType',
        if (provider != null && provider.trim().isNotEmpty) '服務 $provider',
        ?mode,
        if (exportPaths is Map && exportPaths.isNotEmpty)
          '格式 ${exportPaths.keys.map((key) => key.toString()).join('、')}',
        if (plannedFormats is List && plannedFormats.isNotEmpty)
          '插件接口 ${plannedFormats.map((item) => item.toString()).join('、')}',
        if (path != null && path.trim().isNotEmpty) '保存 $path',
      ];
      if (parts.isNotEmpty) return '文件證據：${parts.join(' / ')}';
    }

    if (kind == 'desktop_file_plan') {
      final rootPath = metadata?['rootPath']?.toString();
      final fileCount = metadata?['fileCount']?.toString();
      final folderCount = metadata?['folderCount']?.toString();
      final categorySummary = metadata?['categorySummary']?.toString();
      final movedCount = metadata?['movedCount']?.toString();
      final recordPath = metadata?['recordPath']?.toString();
      final executed = metadata?['executed'] == true;
      final readOnly = metadata?['readOnly'] == true;
      final parts = [
        if (rootPath != null && rootPath.trim().isNotEmpty) '位置 $rootPath',
        if (fileCount != null && fileCount.trim().isNotEmpty) '檔案 $fileCount',
        if (folderCount != null && folderCount.trim().isNotEmpty)
          '資料夾 $folderCount',
        if (categorySummary != null && categorySummary.trim().isNotEmpty)
          '分類 $categorySummary',
        if (executed && movedCount != null && movedCount.trim().isNotEmpty)
          '已移動 $movedCount',
        if (recordPath != null && recordPath.trim().isNotEmpty)
          '紀錄 $recordPath',
        if (readOnly) '只讀掃描',
      ];
      if (parts.isNotEmpty) return '桌面整理證據：${parts.join(' / ')}';
    }

    if (kind == 'managed_folder_guard') {
      final folderLabel = metadata?['folderLabel']?.toString();
      final newFileCount = metadata?['newFileCount']?.toString();
      final categorySummary = metadata?['categorySummary']?.toString();
      final trigger = metadata?['trigger']?.toString();
      final parts = [
        if (folderLabel != null && folderLabel.trim().isNotEmpty)
          '資料夾 $folderLabel',
        if (newFileCount != null && newFileCount.trim().isNotEmpty)
          '新檔案 $newFileCount',
        if (categorySummary != null && categorySummary.trim().isNotEmpty)
          '分類 $categorySummary',
        if (trigger != null && trigger.trim().isNotEmpty) '觸發 $trigger',
      ];
      if (parts.isNotEmpty) return '受管資料夾守門證據：${parts.join(' / ')}';
    }

    if (kind == 'image') {
      final adapter = metadata?['adapter']?.toString();
      final model = metadata?['model']?.toString();
      final quality = metadata?['quality']?.toString();
      final mode = metadata?['mode']?.toString();
      final storage = metadata?['storage']?.toString();
      final parts = [
        if (adapter != null && adapter.trim().isNotEmpty) '執行橋 $adapter',
        if (model != null && model.trim().isNotEmpty) '模型 $model',
        if (quality != null && quality.trim().isNotEmpty) '品質 $quality',
        if (mode != null && mode.trim().isNotEmpty) mode,
        if (storage != null && storage.trim().isNotEmpty) '保存 $storage',
      ];
      if (parts.isNotEmpty) return '圖片證據：${parts.join(' / ')}';
    }

    if (kind == 'capability_gap') {
      final type = metadata?['type']?.toString();
      final provider = metadata?['provider']?.toString();
      final setupRoute = metadata?['setupRoute']?.toString();
      final parts = [
        if (type != null && type.trim().isNotEmpty) '能力 $type',
        if (provider != null && provider.trim().isNotEmpty) '建議服務 $provider',
        if (setupRoute != null && setupRoute.trim().isNotEmpty)
          '開通入口 $setupRoute',
      ];
      if (parts.isNotEmpty) return '能力缺口證據：${parts.join(' / ')}';
    }

    final decision = metadata?['executionDecision'];
    if (decision is! Map) return null;

    final mode = _modeLabel(decision['mode']?.toString());
    final override = _overrideLabel(decision['override']?.toString());
    final primaryKey = decision['primaryKey']?.toString();
    final backupKey = decision['backupKey']?.toString();
    final provider = metadata?['provider']?.toString();
    final adapter = metadata?['adapter']?.toString();
    final generationMode = _generationModeLabel(
      metadata?['generationMode']?.toString(),
    );

    final routeParts = [
      if (override != null) '本次選擇 $override',
      if (mode != null) '決策 $mode',
      if (primaryKey != null && primaryKey.isNotEmpty) '主路線 $primaryKey',
      if (backupKey != null && backupKey.isNotEmpty) '備援 $backupKey',
    ];
    final actualParts = [
      if (provider != null && provider.isNotEmpty) '服務 $provider',
      if (adapter != null && adapter.isNotEmpty) '執行橋 $adapter',
      ?generationMode,
    ];

    final route = routeParts.join(' / ');
    final actual = actualParts.join(' / ');
    if (route.isEmpty && actual.isEmpty) return null;
    if (actual.isEmpty) return '執行證據：$route';
    if (route.isEmpty) return '執行證據：$actual';
    return '執行證據：$route；實際 $actual';
  }

  String? _modeLabel(String? mode) {
    switch (mode) {
      case 'automatic':
        return '自動';
      case 'localFirst':
        return '本地優先';
      case 'cloudFirst':
        return '雲端優先';
      case 'hybrid':
        return '混合接力';
      case 'askEveryTime':
        return '每次詢問';
      case 'blocked':
        return '尚未就緒';
      default:
        return null;
    }
  }

  String? _overrideLabel(String? override) {
    switch (override) {
      case 'automatic':
        return '自動';
      case 'localFirst':
        return '本地';
      case 'cloudFirst':
        return '雲端';
      case 'none':
      default:
        return null;
    }
  }

  String? _generationModeLabel(String? mode) {
    switch (mode) {
      case 'provider_generated':
        return '雲端生成';
      case 'local_template':
        return '本地模板';
      case 'scan_metadata':
        return '實際掃描資料';
      default:
        return null;
    }
  }

  String _shortTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
