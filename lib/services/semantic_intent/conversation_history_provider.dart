// conversation_history_provider.dart
// 從對話訊息中提取最近 N 條，用於 LLM 語意理解的歷史注入。
// 設計文件 §4.1：最近 5 條，每條截斷至 200 字。

import '../../models/conversation.dart';

class ConversationHistoryProvider {
  /// 從 [messages] 中提取最近 [count] 條 user/assistant 訊息。
  /// 每條 content 截斷至 [maxChars] 字。
  /// 回傳型別為 record list，供 L3 LLM 引擎直接使用。
  static List<({String role, String content})> extract(
    List<Message> messages, {
    int count = 5,
    int maxChars = 200,
  }) {
    final filtered = messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();

    final recent = filtered.length > count
        ? filtered.sublist(filtered.length - count)
        : filtered;

    return recent.map((m) {
      final content = m.content.length > maxChars
          ? m.content.substring(0, maxChars)
          : m.content;
      return (role: m.role, content: content);
    }).toList();
  }
}
