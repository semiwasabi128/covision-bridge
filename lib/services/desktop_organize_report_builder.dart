class DesktopOrganizeReportBuilder {
  const DesktopOrganizeReportBuilder();

  String build(Map<String, dynamic> metadata) {
    final rootPath = _string(metadata['rootPath']);
    final rootName = _basename(rootPath) ?? '授權資料夾';
    final executed = metadata['executed'] == true;
    final categoryCounts = _categoryCounts(metadata['categoryCounts']);
    final samples = _sampleMaps(metadata['samples']);
    final suggestions = _stringList(metadata['suggestions']);
    final skipped = _stringList(metadata['skipped']);
    final recordPath = _string(metadata['recordPath']);

    return [
      '# 桌面整理報告：$rootName',
      '',
      '資料來源：Bridge Desktop 實際掃描資料。',
      '產出方式：本地確定性報告產生器，不使用雲端模型補寫樣本檔名。',
      '',
      '## 1. 本次目標',
      '- 掃描位置：${rootPath.isEmpty ? '未標示' : rootPath}',
      '- 安全狀態：${executed ? '已依使用者確認執行整理計畫' : '只讀掃描，尚未搬移、改名或刪除'}',
      '- 檔案數：${_int(metadata['fileCount'])}',
      '- 資料夾數：${_int(metadata['folderCount'])}',
      '',
      '## 2. 整理狀態',
      if (executed) ...[
        '- 已建立資料夾：${_int(metadata['createdFolderCount'])} 個',
        '- 已移動檔案：${_int(metadata['movedCount'])} 個',
        '- 未移動或保留原處：${_int(metadata['skippedCount'])} 個',
        if (recordPath.isNotEmpty) '- 整理紀錄：$recordPath',
      ] else ...[
        '- 預計建立資料夾：${_int(metadata['plannedFolderCount'])} 個',
        '- 預計移動檔案：${_int(metadata['plannedMoveCount'])} 個',
        '- 保留原處：${_int(metadata['skippedCount'])} 個',
        '- 下一步：請先確認整理計畫，再進入搬移或改名階段。',
      ],
      '',
      '## 3. 分類統計',
      if (categoryCounts.isEmpty)
        '- 尚未取得分類統計。'
      else
        for (final entry in _sortedCounts(categoryCounts))
          '- ${entry.key}：${entry.value} 個',
      '',
      '## 4. 真實樣本檔案',
      if (samples.isEmpty)
        '- 沒有可列出的樣本檔案。'
      else
        for (final sample in samples.take(40)) _sampleLine(sample),
      '',
      '## 5. 整理建議',
      if (suggestions.isEmpty)
        '- 目前沒有額外建議。'
      else
        for (final suggestion in suggestions.take(12)) '- $suggestion',
      '',
      '## 6. 保留原處或需要人工確認',
      if (skipped.isEmpty)
        '- 目前沒有記錄到需要人工確認的檔案。'
      else
        for (final item in skipped.take(30)) '- $item',
      '',
      '## 7. 建議下一步',
      if (executed) ...[
        '- 檢查分類資料夾是否符合你的工作習慣。',
        '- 若分類方向正確，可以保存整理規則，讓這個資料夾成為受管資料夾。',
        '- 若需要改變方式，可以直接說：「改成依日期整理」或「截圖另外分一類」。',
      ] else ...[
        '- 先確認上方分類方向是否正確。',
        '- 如果要換整理方式，可以直接告訴我新的規則。',
        '- 確認後再執行整理計畫，Bridge 才會搬移檔案。',
      ],
      '',
      '> 這份報告只反映 Bridge Desktop 掃描 metadata 中已存在的檔案、分類與計畫；沒有出現在掃描資料中的檔名不會被加入報告。',
    ].join('\n');
  }

  String _sampleLine(Map<String, String> sample) {
    final name = sample['name'] ?? '';
    final kind = sample['kind'] ?? '其他';
    final path = sample['path'] ?? '';
    final pathPart = path.isEmpty ? '' : '，位置：$path';
    return '- $kind：$name$pathPart';
  }

  List<MapEntry<String, int>> _sortedCounts(Map<String, int> counts) {
    final entries = counts.entries.toList();
    entries.sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  Map<String, int> _categoryCounts(Object? value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      result[key] = _int(entry.value);
    }
    return result;
  }

  List<Map<String, String>> _sampleMaps(Object? value) {
    if (value is! List) return const [];
    final result = <Map<String, String>>[];
    for (final item in value) {
      if (item is! Map) continue;
      final name = _string(item['name']);
      if (name.isEmpty) continue;
      result.add({
        'name': name,
        'kind': _string(item['kind'], fallback: '其他'),
        'path': _string(item['path']),
      });
    }
    return result;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String? _basename(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return null;
    final parts = clean.split(RegExp(r'[/\\]+')).where((part) {
      return part.trim().isNotEmpty;
    }).toList();
    if (parts.isEmpty) return clean;
    return parts.last;
  }
}
