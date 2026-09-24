/// 使用者意圖分類器
/// 根據輸入內容判斷使用者當下的意圖類型
/// 用於動態切換教練 Agent的靈魂個性
enum UserIntent {
  chat,      // 閒聊、日常對話、問候
  creative,  // 創意發想、腦力激盪、點子徵求
  document,  // 記錄文檔、整理資訊、存檔
  reminder,  // 日常提醒、待辦、記得叫我
  review,    // 審視、複盤、檢討、計畫評估
}

class IntentClassifier {
  /// 根據使用者輸入判斷意圖
  /// 回傳最可能的一個意圖（簡化版：單一意圖）
  static UserIntent classify(String content) {
    final text = content.toLowerCase();

    // ===== 創意發想 (最高優先，因為有明確關鍵字) =====
    // ⚠️ 移除容易在日常對話誤觸的英文詞
    // 排除「我計畫設計一個...」這種宣告語句（「計畫」優先於「設計一個」）
    if (!text.contains('計畫') && !text.contains('打算')) {
      final creativeMarkers = [
        '幫我想', '有沒有點子', '腦力激盪', '發想', '創意',
        '靈感', '能不能想', '想想看',
        '設計一個', '規劃一個', '發明', '創造', '想像',
        '來腦力激盪',
      ];
      for (final marker in creativeMarkers) {
        if (text.contains(marker)) return UserIntent.creative;
      }
    } else {
      // 有「計畫」或「打算」時，只保留強創意關鍵字
      final strongCreativeMarkers = [
        '幫我想', '有沒有點子', '腦力激盪', '發想',
        '能不能想', '想想看',
        '來腦力激盪',
      ];
      for (final marker in strongCreativeMarkers) {
        if (text.contains(marker)) return UserIntent.creative;
      }
    }

    // ===== 日常提醒（優先於審視，避免「複盤」等詞在提醒語境被誤判）=====
    final reminderMarkers = [
      '提醒', '記得叫我', '叫我起床',
      '到時候叫我', '不要忘了', '別忘了',
      '待辦', 'todo', 'to do', '清單', '列表',
      '幾點叫我', '時間到', '到時候', '等一下叫我',
    ];
    for (final marker in reminderMarkers) {
      if (text.contains(marker)) return UserIntent.reminder;
    }

    // ===== 審視複盤 =====
    final reviewMarkers = [
      '複盤', '審視', '檢討', '評估',
      '分析一下這個', '為什麼失敗', '為什麼沒成功',
      '哪裡出錯', '問題出在哪', '盲點', '風險評估',
      '值得嗎', '這樣對嗎', '有沒有漏掉',
      '驗證這個', '重新評估',
      '測試驅動', 'tdd', '系統化排查', '除錯',
    ];
    for (final marker in reviewMarkers) {
      if (text.contains(marker)) return UserIntent.review;
    }

    // ===== 記錄文檔 =====
    // 問句不觸發（避免「你記住了嗎？」誤判）
    final isQuestion = text.endsWith('?') || text.endsWith('？') || text.contains('嗎');
    if (!isQuestion) {
      final documentMarkers = [
        '記錄', '整理成', '存檔', '歸檔', '文件',
        '寫成', '寫一份', '做成', '輸出', '產出',
        '筆記', '摘要', '總結', '歸納', '條列',
        '寫下', '記下來', '保存', '建檔', '文件化',
        '記住', '幫我記',
      ];
      for (final marker in documentMarkers) {
        if (text.contains(marker)) return UserIntent.document;
      }
    } else {
      // 問句中只保留強 document 關鍵字
      final strongDocumentMarkers = [
        '整理成', '寫成', '產出', '摘要', '總結',
      ];
      for (final marker in strongDocumentMarkers) {
        if (text.contains(marker)) return UserIntent.document;
      }
    }

    // ===== 閒聊（預設 fallback） =====
    return UserIntent.chat;
  }

  /// 取得意圖的中文名稱（用於除錯或 UI 顯示）
  static String intentName(UserIntent intent) {
    switch (intent) {
      case UserIntent.chat:
        return '閒聊';
      case UserIntent.creative:
        return '創意發想';
      case UserIntent.document:
        return '記錄文檔';
      case UserIntent.reminder:
        return '日常提醒';
      case UserIntent.review:
        return '審視複盤';
    }
  }

  /// 取得意圖對應的圖示
  static String intentIcon(UserIntent intent) {
    switch (intent) {
      case UserIntent.chat:
        return '💬';
      case UserIntent.creative:
        return '✨';
      case UserIntent.document:
        return '📝';
      case UserIntent.reminder:
        return '🔔';
      case UserIntent.review:
        return '🔍';
    }
  }
}
