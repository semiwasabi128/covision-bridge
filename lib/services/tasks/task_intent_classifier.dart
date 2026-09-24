// task_intent_classifier.dart
// [隊友訊息流 第 1 刀 C6 2026-09-08]
// 任務型意圖分類器（Phase 2 自動派工）——純規則，零 LLM 成本零延遲。
// 設計稿 §4.1：多步驟/產出物/跨工具關鍵詞 → 自動派工；
// 誤判可一鍵轉普通對話（取消任務後原訊息仍在對話裡）。
//
// 設計鐵則：保守優先——寧可漏派（使用者按火箭鈕補派），
// 不可誤派閒聊（打擾信任）。觸發條件 = 指令前綴 AND 任務動詞。

/// 分類結果
enum TaskIntent {
  /// 明確任務句 → 自動派工
  task,

  /// 對話句（含問句、閒聊、短句）→ 正常對話
  chat,
}

class TaskIntentClassifier {
  /// 指令前綴——使用者明確在「下指令」的訊號
  static const _commandPrefixes = [
    '幫我', '請你', '麻煩你', '幫忙', '你來', '交給你', '去把', '把它',
    '派你', '這個任務', '下一個任務',
  ];

  /// 任務動詞——有實際產出物或動作的詞
  static const _taskVerbs = [
    '整理', '產生', '生成', '建立', '製作', '做一份', '做一個', '規劃',
    '分析', '匯整', '彙整', '統計', '寫一份', '寫一個', '打包', '分類',
    '排版', '設計', '翻譯', '總結', '摘要', '備份', '清點', '巡查',
    '排程', '自動化', '跑一', '執行', '處理', '最佳化', '優化',
  ];

  /// 強排除——這些詞出現時絕不派工（明確對話語境）
  static const _chatOnlyPatterns = [
    '?', '？', '嗎', '吧', '呢', '哈', 'XD', 'xd', '哈哈', '笑',
    '謝謝', '感謝', '早安', '晚安', '你好', '嗨', '嘿',
    '我覺得', '我認為', '我感覺', '我猜', '我想問', '什麼', '怎麼',
    '為什麼', '哪個', '如何', '好不好', '對不對',
  ];

  /// 分類一則使用者訊息
  static TaskIntent classify(String rawMessage) {
    final text = rawMessage.trim();

    // 太短不可能是指令（「幫我」+動詞至少 5-6 字）
    if (text.length < 6) return TaskIntent.chat;

    // 問句永遠是對話（「幫我看看這是什麼？」= 想知道答案，不是要產出）
    for (final p in _chatOnlyPatterns) {
      if (text.contains(p)) return TaskIntent.chat;
    }

    // 必須有指令前綴
    final hasPrefix =
        _commandPrefixes.any((p) => text.startsWith(p) || text.contains(p));
    if (!hasPrefix) return TaskIntent.chat;

    // 必須有任務動詞（有產出物的動作）
    final hasTaskVerb = _taskVerbs.any((v) => text.contains(v));
    if (!hasTaskVerb) return TaskIntent.chat;

    return TaskIntent.task;
  }
}
