/// [Sprint 11] 門主題漂移偵測器——規則版，寧可漏報不可誤報
class DoorDriftDetector {
  /// 檢查最近訊息是否偏離門主題
  /// 回傳 true = 可能漂移
  static bool checkDrift({
    required String doorTitle,
    required List<String> recentMessages,
    int checkWindow = 5,
  }) {
    if (doorTitle.isEmpty) return false;

    // 從門 title 提取關鍵詞（連續中文 ≥2 字 or 英文 ≥3 字）
    var titleWords = <String>[];
    final cjkPattern = RegExp(r'[\u4e00-\u9fff]{2,}');
    final engPattern = RegExp(r'[A-Za-z]{3,}');
    titleWords.addAll(cjkPattern.allMatches(doorTitle).map((m) => m.group(0)!));
    titleWords.addAll(engPattern.allMatches(doorTitle).map((m) => m.group(0)!));

    // 過濾泛詞
    const genericWords = {'專案', '計畫', '項目', '新的', '橋樑'};
    titleWords = titleWords.where((w) => !genericWords.contains(w)).toList();

    // 如果門 title 沒有 specific 詞，不報漂移
    if (titleWords.isEmpty) return false;

    // 檢查最近訊息是否包含任何門 title 詞
    final recentText = recentMessages.take(checkWindow).join(' ').toLowerCase();
    for (final word in titleWords) {
      if (recentText.contains(word.toLowerCase())) {
        return false; // 有匹配 = 沒漂移
      }
    }
    return true; // 所有詞都沒匹配 = 可能漂移
  }
}
