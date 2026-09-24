// extraction_prompt.dart
// LLM 語意記憶提取 — prompt 模板 + JSON 解析
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
//
// 核心思路：用 LLM 判斷「這段話包含什麼值得長期記住的資訊？」
// 不靠關鍵字前綴，靠語意理解。

import 'dart:convert';

/// 提取結果的單筆記憶。
class ExtractedFact {
  final String content;
  final String category;
  final int importance;

  const ExtractedFact({
    required this.content,
    required this.category,
    required this.importance,
  });

  @override
  String toString() =>
      'ExtractedFact(content: $content, category: $category, importance: $importance)';
}

/// 記憶提取 prompt 建構器。
///
/// 設計原則：
/// 1. 保守 — 不確定就不提取，better to miss than over-extract
/// 2. 語意導向 — 理解使用者意圖，不靠前綴詞
/// 3. 結構化輸出 — JSON array，方便解析
/// 4. 分類 — 每筆記憶標註大腦房間
class ExtractionPrompt {
  /// 建構 system prompt。
  static String buildSystemPrompt() {
    return '''你是一個記憶提取器。你的任務是分析使用者的訊息，判斷其中是否包含值得長期記住的事實。

## 什麼是「值得記住」的？
- 使用者的身份資訊：名字、年齡、生日、職業、家庭成員
- **身分宣告與自我定位**：使用者對自己「是什麼人」的宣稱，例如「我決定要做一個遊戲製作人」「我想成為設計師」「我是一個創作者」——這是極重要的自我認同資訊，必須提取，importance 4-5
- 穩定的偏好與習慣：喜歡/討厭的事物、工作方式、生活習慣
- 目標與計畫：正在進行的專案、未來規劃、學習目標
- 人際關係：家人、朋友、同事的資訊
- 生活情境：最近在忙什麼、搬家、換工作等重大變化
- 技能與專長：會什麼工具、擅長什麼領域

## 什麼是「不值得記住」的？
- 問題和詢問（使用者在問你東西）
- 對 AI 的指令（「幫我搜尋」「生成圖片」「翻譯這個」）
- 純粹的打招呼（「嗨」「你好」「早安」）
- 對事物的即時評論（除非反映穩定偏好）
- 流程性對話（「好」「可以」「謝謝」）
- 情緒發洩但不含具體事實

## 判斷原則
- 寧可漏抓也不要過度提取
- 只提取「使用者本人的事實」，不提取對話內容本身
- 如果使用者說「我叫建新」，提取「使用者名叫建新」
- 如果使用者說「我最近在搞一個 Flutter app」，提取「使用者正在開發 Flutter app」
- 如果使用者說「那個 API 文件寫得真爛」，不提取（這是即時評論，不是穩定偏好）
- 如果使用者說「我討厭寫文件」，提取「使用者不喜歡寫文件」
- 如果使用者說「我決定要做一個遊戲製作人」，提取「使用者決定成為遊戲製作人（自我定位宣告）」，importance 5
- 將提取內容用第三人稱描述（「使用者...」），方便未來檢索時理解

## 輸出格式
嚴格輸出 JSON 陣列，不要加 markdown code block，不要加解釋文字。
如果沒有值得記住的，輸出空陣列 `[]`。

每筆記憶的格式：
```json
{
  "content": "使用者...",
  "category": "stream",
  "importance": 3
}
```

category 可選值：
- stream: 正在進行的工作流、任務進度、專案動態。水流是當下阻力最小的路徑——正在做的事就是水流。
- doors: 新機會、新入口、從當下水流分出來的分岔。門做完後回到的是門被創立時的母水流。
- pendulums: 外部壓力、焦慮、注意力被擄獲、集體恐慌。識別它，不被牽著走。
- heartMind: 理性與感性的交會——「想到 vs 想要」「判斷 vs 直覺」。衝突時內在分裂，和諧時心腦合一。
- fraile: 發光時刻、真正的熱情、不需要解釋就被理解的共振。獨特本質的展現。
- bridges: 不同工作流之間的連接路徑。「這件事跟那件事有關」「從另一個門回來可以接續這條水流」。

importance: 1-5（5 最重要）。
- 一般事實給 3
- 核心身份、自我定位宣告給 4-5
- 水流方向轉換、門的出現給 4-5
- 擺錘警報、注意力主權危機給 4（及時提醒很重要）
- 橋的發現（跨水流連結）給 4（幫助未來導航）''';
  }

  /// 建構 user prompt（使用者的原始訊息）。
  static String buildUserPrompt(String userMessage) {
    return '分析以下訊息，提取值得長期記住的事實：\n\n$userMessage';
  }

  /// [小葵 2026-09-22 偷學令③ Dreaming] 建構批次 user prompt。
  ///
  /// 多則訊息一起分析（借鏡 supermemory dreaming：相關訊息分組後
  /// 一起做夢，跨訊息的因果與關聯才有機會浮現——逐則抽取永遠看不到）。
  static String buildBatchUserPrompt(List<String> messages) {
    final body = messages.asMap().entries
        .map((e) => '[訊息 ${e.key + 1}] ${e.value}')
        .join('\n---\n');
    return '分析以下同一輪對話中的多則訊息（按時間順序），'
        '提取值得長期記住的事實。\n'
        '特別注意跨訊息才能看出的關聯：後續訊息修正/推翻/補充前面訊息的地方'
        '（以較新者為準）：\n\n$body';
  }

  /// 解析 LLM 回傳的 JSON。
  ///
  /// 容錯策略：
  /// 1. 嘗試直接 jsonDecode
  /// 2. 若失敗，嘗試從 ```json ... ``` 中提取
  /// 3. 若再失敗，嘗試找第一個 [ 到最後一個 ]
  /// 4. 全部失敗回傳空列表
  static List<ExtractedFact> parseResponse(String rawResponse) {
    final cleaned = _stripCodeBlock(rawResponse).trim();
    if (cleaned.isEmpty) return [];

    // 嘗試直接解析
    List<ExtractedFact>? result = _tryParseJsonArray(cleaned);
    if (result != null) return result;

    // 嘗試找 JSON 陣列邊界
    final bracketStart = cleaned.indexOf('[');
    final bracketEnd = cleaned.lastIndexOf(']');
    if (bracketStart >= 0 && bracketEnd > bracketStart) {
      final jsonStr = cleaned.substring(bracketStart, bracketEnd + 1);
      result = _tryParseJsonArray(jsonStr);
      if (result != null) return result;
    }

    // 全部失敗
    return [];
  }

  /// 移除 markdown code block 包裹。
  static String _stripCodeBlock(String text) {
    // ```json\n...\n``` 或 ```\n...\n```
    final codeBlockPattern = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```');
    final match = codeBlockPattern.firstMatch(text);
    if (match != null) {
      return match.group(1) ?? text;
    }
    return text;
  }

  /// 嘗試將字串解析為 JSON 陣列。
  static List<ExtractedFact>? _tryParseJsonArray(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return [];

      final facts = <ExtractedFact>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final content = item['content']?.toString().trim() ?? '';
        if (content.isEmpty) continue;
        if (content.length < 3) continue;

        final category = item['category']?.toString().trim() ?? 'stream';
        final importance = _parseIntSafe(item['importance'], 3);

        facts.add(ExtractedFact(
          content: content,
          category: _normalizeCategory(category),
          importance: importance.clamp(1, 5),
        ));
      }
      return facts;
    } catch (_) {
      return null;
    }
  }

  /// 安全解析整數。
  static int _parseIntSafe(dynamic value, int defaultValue) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// 正規化分類名稱。
  static String _normalizeCategory(String category) {
    final lower = category.toLowerCase().trim();
    const validCategories = {
      'stream', 'doors', 'pendulums', 'heartmind', 'fraile', 'bridges'
    };
    if (validCategories.contains(lower)) return lower;
    // 嘗試模糊匹配
    if (lower.contains('stream') || lower.contains('流')) return 'stream';
    if (lower.contains('door') || lower.contains('門')) return 'doors';
    if (lower.contains('pendulum') || lower.contains('擺') || lower.contains('壓')) return 'pendulums';
    if (lower.contains('heart') || lower.contains('心')) return 'heartmind';
    if (lower.contains('fraile') || lower.contains('靈') || lower.contains('頻')) return 'fraile';
    if (lower.contains('bridge') || lower.contains('橋') || lower.contains('連結')) return 'bridges';
    return 'stream'; // 預設
  }
}
