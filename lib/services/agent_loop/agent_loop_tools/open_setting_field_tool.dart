// open_setting_field_tool.dart
// P0b: Agent 工具 — 引導使用者到設定頁面
//
// 讓 Agent 能直接帶使用者到設定頁，而不只是口頭說「去設定」。
// 桌面版：觸發系統 tab → 設定頁
// 手機版（未來）：觸發路由到 /settings
//
// 設計原則：
// - Agent 不碰 key 內容，只負責「帶路」
// - 導航透過 callback 注入，工具本身不依賴 BuildContext
// - target 參數讓 Agent 能指定要開哪個設定區塊

import '../agent_tool.dart';

/// 導航回呼型別
/// [target] = 設定目標（'settings', 'golden_keys', 'pairing'）
/// [provider] = 指定要設定的 provider（如 'minimax'），可選
typedef OnNavigateToSetting = void Function({
  required String target,
  String? provider,
});

class OpenSettingFieldTool extends AgentTool {
  final OnNavigateToSetting? onNavigate;

  OpenSettingFieldTool({this.onNavigate});

  @override
  String get name => 'open_setting';

  @override
  String get description =>
      '帶使用者到設定頁面。當使用者需要設定 API Key 或其他服務時，'
      '用此工具直接開啟設定頁，而不是只口頭引導。'
      '使用後請接著告訴使用者要在哪個欄位貼上什麼。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'target',
          description: '設定目標：'
              '"settings" = 一般設定頁（API Key、Gateway URL）；'
              '"golden_keys" = 金鑰匙中心（能力總覽）；'
              '"pairing" = 手機配對頁',
          required: true,
          defaultValue: 'settings',
        ),
        AgentToolParamSpec(
          name: 'provider',
          description: '指定要設定的 provider（如 minimax, openai, kimi, glm）。'
              '設定頁會自動切換到該 provider。',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final target = args['target']?.toString() ?? 'settings';
    final provider = args['provider']?.toString();

    if (onNavigate == null) {
      // 沒有導航回呼 — fallback 到口頭引導
      final lines = <String>[];
      lines.add('無法自動開啟設定頁。請手動操作：');
      lines.add('1. 點左側「系統」圖示');
      lines.add('2. 點「設定」');
      if (provider != null) {
        lines.add('3. 選擇 provider: $provider');
        lines.add('4. 貼上 API Key');
        lines.add('5. 按「測試連線」');
      }
      return AgentToolResult.success(lines.join('\n'));
    }

    try {
      onNavigate!(target: target, provider: provider);

      final lines = <String>[];
      lines.add('已開啟設定頁。');
      if (provider != null) {
        lines.add('已切換到 $provider 設定區塊。');
        lines.add('請使用者貼上 API Key 後按「測試連線」。');
      }
      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      return AgentToolResult.failure('開啟設定頁失敗：$e');
    }
  }
}
