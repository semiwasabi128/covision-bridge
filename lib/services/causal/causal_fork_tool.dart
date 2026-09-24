// causal_fork_tool.dart
// [因果引擎 L4 2026-09-12] causal_fork——狀態分叉工具（Agent 可呼叫）
//
// 讓 agent 能執行可執行的反事實：「如果我在這裡加一個節點，世界會差在哪？」
// 快照 → A 線干預（加節點）→ diff → 還原 → 報告（等級 3 反事實模擬）。
//
// 誠實邊界：只分叉畫布域（可序列化狀態）；外部世界不可分叉。
// 工具回覆強制標示證據等級 3——模擬結論，非實測。

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/mcp_canvas_tools.dart';
import 'package:bridge_app/services/causal/causal_fork_service.dart';

class CausalForkTool extends AgentTool {
  final McpCanvasExecutor executor;
  CausalForkTool(this.executor);

  @override
  String get name => 'causal_fork';

  @override
  String get description =>
      '狀態分叉（反事實模擬）：快照畫布 → 在 A 線執行一次干預（新增節點）→ '
      '對照快照 diff 出差異 → 還原畫布。回答「如果…會怎樣」用這個，'
      '不要用想像的。結果標等級 3（反事實模擬）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'node_type',
          description: 'A 線要新增的節點類型（如 input/text/llm）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'x',
          description: '新節點 X 座標',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'y',
          description: '新節點 Y 座標',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'question',
          description: '這次分叉想回答的反事實問題（例如：如果在這裡加節點會改變什麼）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final type = (args['node_type'] ?? 'text') as String;
      final x = (args['x'] is num ? (args['x'] as num).toDouble() : 300.0);
      final y = (args['y'] is num ? (args['y'] as num).toDouble() : 300.0);
      final question = (args['question'] ?? '') as String;

      final fd = await CausalForkService.instance.run(
        intervention: 'do: addNode($type, $x, $y)',
        baselineDescription: question.isEmpty ? '不改變的平行世界' : question,
        getState: () => executor.getState(),
        intervene: () async {
          await executor.addNode(type, x, y);
          return executor.getState();
        },
        // 還原：把 A 線新增的節點刪掉（restore 世界回到快照）
        restore: (before) async {
          final after = await executor.getState();
          final beforeIds = (before['nodes'] as List? ?? [])
              .map((n) => (n as Map)['id'] as String)
              .toSet();
          for (final n in (after['nodes'] as List? ?? [])) {
            final id = (n as Map)['id'] as String;
            if (!beforeIds.contains(id)) {
              await executor.removeNode(id);
            }
          }
        },
      );

      return AgentToolResult.success(fd.report);
    } catch (e) {
      return AgentToolResult.failure('分叉失敗: $e');
    }
  }
}
