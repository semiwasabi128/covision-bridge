// check_capability_status_tool_test.dart
// P0b: 測試 check_capability_status Agent 工具

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/check_capability_status_tool.dart';

void main() {
  group('CheckCapabilityStatusTool', () {
    test('tool name is check_capability_status', () {
      final tool = CheckCapabilityStatusTool();
      expect(tool.name, 'check_capability_status');
    });

    test('has empty param specs (no params needed)', () {
      final tool = CheckCapabilityStatusTool();
      expect(tool.paramSpecs, isEmpty);
    });

    test('description mentions querying system setup status', () {
      final tool = CheckCapabilityStatusTool();
      expect(tool.description, contains('設定狀態'));
      expect(tool.description, contains('provider'));
    });

    test('toPromptDescription generates valid prompt section', () {
      final tool = CheckCapabilityStatusTool();
      final desc = tool.toPromptDescription();
      expect(desc, contains('check_capability_status'));
      // 零參數工具：prompt 不再包含「參數」段（2026 整頓後的格式）
      expect(desc, startsWith('- check_capability_status'));
      expect(desc, contains('設定狀態'));
    });
  });
}
