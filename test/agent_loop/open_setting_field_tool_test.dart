// open_setting_field_tool_test.dart
// P0b: 測試 open_setting Agent 工具

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/open_setting_field_tool.dart';

void main() {
  group('OpenSettingFieldTool', () {
    test('tool name is open_setting', () {
      final tool = OpenSettingFieldTool();
      expect(tool.name, 'open_setting');
    });

    test('has target and provider param specs', () {
      final tool = OpenSettingFieldTool();
      expect(tool.paramSpecs.length, 2);
      expect(tool.paramSpecs[0].name, 'target');
      expect(tool.paramSpecs[0].required, isTrue);
      expect(tool.paramSpecs[1].name, 'provider');
      expect(tool.paramSpecs[1].required, isFalse);
    });

    test('description mentions opening settings page', () {
      final tool = OpenSettingFieldTool();
      expect(tool.description, contains('設定頁'));
      expect(tool.description, contains('API Key'));
    });

    test('execute without navigate callback returns fallback instructions', () async {
      final tool = OpenSettingFieldTool();
      final result = await tool.execute({'target': 'settings', 'provider': 'minimax'});
      expect(result.success, isTrue);
      expect(result.content, contains('手動操作'));
      expect(result.content, contains('minimax'));
    });

    test('execute without provider returns generic fallback', () async {
      final tool = OpenSettingFieldTool();
      final result = await tool.execute({'target': 'settings'});
      expect(result.success, isTrue);
      expect(result.content, contains('手動操作'));
    });

    test('execute with navigate callback calls it', () async {
      String? capturedTarget;
      String? capturedProvider;
      final tool = OpenSettingFieldTool(
        onNavigate: ({required String target, String? provider}) {
          capturedTarget = target;
          capturedProvider = provider;
        },
      );
      final result = await tool.execute({
        'target': 'settings',
        'provider': 'minimax',
      });
      expect(result.success, isTrue);
      expect(result.content, contains('已開啟設定頁'));
      expect(capturedTarget, 'settings');
      expect(capturedProvider, 'minimax');
    });

    test('execute with callback but no provider still succeeds', () async {
      String? capturedTarget;
      String? capturedProvider;
      final tool = OpenSettingFieldTool(
        onNavigate: ({required String target, String? provider}) {
          capturedTarget = target;
          capturedProvider = provider;
        },
      );
      final result = await tool.execute({'target': 'golden_keys'});
      expect(result.success, isTrue);
      expect(capturedTarget, 'golden_keys');
      expect(capturedProvider, isNull);
    });

    test('toPromptDescription generates valid prompt section', () {
      final tool = OpenSettingFieldTool();
      final desc = tool.toPromptDescription();
      expect(desc, contains('open_setting'));
      expect(desc, contains('target'));
      expect(desc, contains('provider'));
    });
  });
}
