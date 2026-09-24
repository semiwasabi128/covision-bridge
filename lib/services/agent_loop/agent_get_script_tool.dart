// agent_get_script_tool.dart
// [搬遷 2026-09-13] agent_get_script——招式全文讀取（兩階段檢索的第二階）
//
// 病根：agent_search_knowledge 只回 120 字 snippet，agent 搜到招式後
// 看不到完整內容（Blue 偏好段落在第 3 行就被截斷）。服務層 getScript
// 一直存在但沒有對外工具——搜得到讀不到。
//
// 修：本工具以 ID 取全文。與 agent_search_knowledge 成對：
// search（拿 ID+摘要）→ get_script（拿全文）。

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart';

class AgentGetScriptTool extends AgentTool {
  @override
  String get name => 'agent_get_script';

  @override
  String get description =>
      '以 ID 讀取招式/腳本全文。先用 agent_search_knowledge 搜到 ID，'
      '再呼叫此工具拿完整內容（截圖偏好、步驟、避坑都在全文裡）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'script_id',
          description: 'agent_search_knowledge 回傳的 ID（如 skill_hermes_xxx）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final id = args['script_id'] as String? ?? '';
      if (id.trim().isEmpty) {
        return AgentToolResult.failure('script_id 不能為空');
      }
      final script = AgentKnowledgeService.instance.getScript(id);
      if (script == null) {
        return AgentToolResult.failure('找不到腳本：$id（用 agent_search_knowledge 先搜）');
      }
      final cat = script.category != null ? ' [${script.category}]' : '';
      final desc = script.description?.isNotEmpty == true ? '${script.description}\n\n' : '';
      return AgentToolResult.success(
        '招式全文：${script.title}$cat\n\n$desc${script.content}',
      );
    } catch (e) {
      return AgentToolResult.failure('讀取失敗: $e');
    }
  }
}
