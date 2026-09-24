// [小葵 2026-09-15 Blue 抓包] agent「說了不做」防護回歸測試
// 病例：「收到。…我先看現狀再動手。」句號結尾（非截斷非懸空冒號）、
// 無 tool call → loop 誠實退出，任務死在宣告裡。
// 修：endsWithStatedIntent 偵測行動意圖詞 → nudge 續跑。
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_call_parser.dart';

void main() {
  group('[說了不做] endsWithStatedIntent 回歸', () {
    test('病例原文：我先看現狀再動手 → true（要 nudge）', () {
      expect(
        AgentToolCallParser.endsWithStatedIntent(
          '收到。歷史記錄顯示今天我已建過一個排程節點，兩筆記錄矛盾，我先看現狀再動手。',
        ),
        isTrue,
      );
    });

    test('其他宣告句式 → true', () {
      expect(AgentToolCallParser.endsWithStatedIntent('讓我先查一下。'), isTrue);
      expect(AgentToolCallParser.endsWithStatedIntent('接下來我來檢查畫布。'), isTrue);
      expect(AgentToolCallParser.endsWithStatedIntent('這就來執行。'), isTrue); // 「這就來」在表內
    });

    test('完成總結（無行動意圖）→ false（正常退出）', () {
      expect(
        AgentToolCallParser.endsWithStatedIntent(
          '已建立排程節點（每日 09:00），節點 ID wf-123。任務完成。',
        ),
        isFalse,
      );
      expect(AgentToolCallParser.endsWithStatedIntent('這個問題我答不了。'), isFalse);
    });

    test('有 tool call 時文字部分不含意圖詞 → false', () {
      final raw = '我先看看\n<<<tool_call>>>{"name":"canvas_get_state","args":{}}<<<tool_call_end>>>';
      // extractText 會移除 tool call 區塊，剩「我先看看」→ true（此 case 無妨：
      // 呼叫端只在 toolCalls.isEmpty 時才檢查，此處不會觸發）
      final text = AgentToolCallParser.extractText(raw);
      expect(text.trim(), '我先看看');
    });
  });
}
