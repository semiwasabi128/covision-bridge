class ManagedFolderRuleNamer {
  const ManagedFolderRuleNamer();

  String title({
    required String folderLabel,
    required String categorySummary,
    String source = 'generated',
  }) {
    final folder = folderLabel.trim().isEmpty ? '這個資料夾' : folderLabel.trim();
    final focus = _focusLabel(categorySummary);
    final sourcePrefix = source == 'imported' ? '匯入的' : '';
    return '$folder：$sourcePrefix$focus整理規則';
  }

  String _focusLabel(String categorySummary) {
    final categories = _categories(categorySummary);
    if (categories.isEmpty) return '一般檔案';
    final nonOther = categories.where((item) => item != '其他').toList();
    final picked = nonOther.isEmpty ? categories : nonOther;
    return _joinChinese(picked.take(3).toList());
  }

  List<String> _categories(String value) {
    final text = value.trim();
    if (text.isEmpty || text == '尚無分類') return const [];
    final result = <String>[];
    for (final raw in text.split(RegExp(r'[、,，/]'))) {
      final clean = raw
          .trim()
          .replaceAll(RegExp(r'\s+\d+$'), '')
          .replaceAll(RegExp(r'\d+$'), '')
          .trim();
      if (clean.isEmpty || result.contains(clean)) continue;
      result.add(clean);
    }
    return result;
  }

  String _joinChinese(List<String> items) {
    if (items.isEmpty) return '一般檔案';
    if (items.length == 1) return items.single;
    if (items.length == 2) return '${items[0]}與${items[1]}';
    return '${items.take(items.length - 1).join('、')}與${items.last}';
  }
}
