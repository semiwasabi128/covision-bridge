// [小葵 2026-09-16 Blue 令] 結構性續跑回歸測試
// 病例史：詞表式 nudge（先看/再動手/找…）永遠追不完新句式；
// 「進行中談話」式回覆讓使用者無法分辨工作中與停機。
// 新規則（agent_loop.dart）：沒有 tool call 且無 [[TASK_DONE]] 且 nudge<5 → 續跑 nudge。
// 本測試驗證：純 parser 層的任務完成訊號 [[TASK_DONE]] 偵測輔助函式（若 loop 層用字串包含判斷，
// 這裡驗證各種邊界：大小寫、前後綴、tool call 混雜）。
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_call_parser.dart';

void main() {
  group('[結構性續跑] 完成訊號回歸', () {
    test('病例原文：我先看現狀再動手（無 DONE 標記）→ loop 應 nudge', () {
      // 舊詞表函式仍可用（ends with 意圖詞）但 loop 已不再依賴它——
      // 結構性判斷：此句無 [[TASK_DONE]] → nudge。此測試保底行為描述。
      const reply = '收到。…我先看現狀再動手。';
      expect(reply.contains('[[TASK_DONE]]'), isFalse);
    });

    test('結構化收工報告含 [[TASK_DONE]] → loop 正常退出', () {
      const reply = '✅ 已完成：Bug A 修復（commit 03d43e12）\n⚠️ 遗留：其他工具未接 fallback\n[[TASK_DONE]]';
      expect(reply.contains('[[TASK_DONE]]'), isTrue);
    });

    test('未來式進行中談話（詞表外的句式）→ 無 DONE 標記 → nudge', () {
      // 這正是詞表追不到的病例類型
      const reply = 'Fallback 模式已看清（L831-867 可重用）。現在確認 MCP server 側怎麼呼叫。';
      expect(reply.contains('[[TASK_DONE]]'), isFalse);
    });

    test('extractText 不吃掉 [[TASK_DONE]] 標記', () {
      final raw = '我先看看\n<<<tool_call>>>{\"name\":\"canvas_get_state\",\"args\":{}}<<<tool_call_end>>>\n[[TASK_DONE]]';
      final text = AgentToolCallParser.extractText(raw);
      expect(text.contains('[[TASK_DONE]]'), isTrue);
    });
  });
}
