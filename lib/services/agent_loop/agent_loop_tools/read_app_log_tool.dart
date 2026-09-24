// read_app_log_tool.dart
// [Phase 1 2026-07-17] 原生 Agent 自維修工具 #4：讀取 App Log
//
// 讓 Agent 能讀取 App 運行時的 debugPrint 輸出。
// 用於診斷 bug、確認修復是否生效、追蹤事件流程。
// 依賴 AppLogBuffer（全域 ring buffer，在 main.dart 安裝）。

import '../agent_tool.dart';
import '../app_log_buffer.dart';

class ReadAppLogTool extends AgentTool {
  @override
  String get name => 'read_app_log';

  @override
  String get description =>
      '讀取 App 運行時的 log（debugPrint 輸出）。用於診斷 bug、確認修復是否生效、'
      '追蹤事件流程。Log 存在 ring buffer 中（最近 500 行）。'
      '可用 filter 參數過濾包含特定關鍵字的行，例如 "AgentSensor" 或 "error"。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'tail_lines',
          description: '取最後幾行（預設 100）',
          required: false,
          defaultValue: '100',
        ),
        AgentToolParamSpec(
          name: 'filter',
          description: '關鍵字過濾（只回傳包含此字串的行），例如 "AgentSensor" 或 "error"',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final tailLines = int.tryParse(args['tail_lines']?.toString() ?? '100') ?? 100;
      final filter = args['filter']?.toString();

      final log = appLogBuffer.read(tailLines: tailLines, filter: filter);
      return AgentToolResult.success(log);
    } catch (e) {
      return AgentToolResult.failure('讀取 log 失敗：$e');
    }
  }
}
