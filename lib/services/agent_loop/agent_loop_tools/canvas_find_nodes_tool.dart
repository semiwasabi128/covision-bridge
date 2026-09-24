/// canvas_find_nodes 工具——模糊查詢畫布上的節點
///
/// [教練 Agent 2026-08-17] 配合 canvas_remove 模糊刪除設計：
/// 提供 label/type/座標 任一條件，回傳所有符合的 entityId + label + 座標。
/// Agent 可以先 canvas_find_nodes 確認目標，再 canvas_remove 精確刪。
/// 也可用於「調整既有節點」前的清單查詢（canvas_update_node 之前知道有誰）。
library;

import '../agent_tool.dart';
import '../../../services/entity_graph/entity_graph_service.dart';
import '../../../services/memory_store.dart';
import '../../../services/project_door_store.dart';
import '../../../services/digital_asset_registry_store.dart';
import 'canvas_remove_tool.dart';

class CanvasFindNodesTool extends AgentTool {
  final CanvasRemoveExecutor _removeExecutor;

  CanvasFindNodesTool(this._removeExecutor);

  @override
  String get name => 'canvas_find_nodes';

  @override
  String get description =>
      '模糊查詢畫布上所有符合條件的節點。回傳 entityId + label + 座標清單。\n'
      '**這是 canvas_remove 模糊刪除的搭檔**：先 find 再 remove，避免刪錯。\n'
      '也用在 canvas_update_node 之前確認目標節點存在。\n'
      '至少提供一個條件：entityLabel / entityType / positionX+Y。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'entityLabel',
          description: 'label 包含此字串（不分大小寫）',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'entityType',
          description: '工作流節點型別（input/llm/tool/knowledge/condition/output/...）',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'positionX',
          description: '座標 X',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'positionY',
          description: '座標 Y',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'radius',
          description: '座標半徑（預設 100）',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final entityLabel = args['entityLabel']?.toString();
    final entityType = args['entityType']?.toString();
    final positionX = (args['positionX'] as num?)?.toDouble();
    final positionY = (args['positionY'] as num?)?.toDouble();
    final radius = (args['radius'] as num?)?.toDouble();

    if ((entityLabel == null || entityLabel.isEmpty) &&
        (entityType == null || entityType.isEmpty) &&
        (positionX == null || positionY == null)) {
      return AgentToolResult.failure(
        '至少提供一個條件：entityLabel / entityType / positionX+Y。',
      );
    }

    try {
      final matches = await _removeExecutor.findMatches(
        labelContains: entityLabel,
        typeName: entityType,
        positionX: positionX,
        positionY: positionY,
        radius: radius,
      );

      if (matches.isEmpty) {
        return AgentToolResult.success(
          '沒有符合條件的節點。放寬條件或先 canvas_get_state 看現狀。',
        );
      }

      final preview = matches
          .map((m) =>
              '  - ${m.entityId} | ${m.nodeTypeName ?? "non-workflow"} | '
              '"${m.title}" | (${m.x.toStringAsFixed(0)}, ${m.y.toStringAsFixed(0)}) | score=${m.score.toStringAsFixed(2)}')
          .join('\n');
      return AgentToolResult.success(
        '找到 ${matches.length} 個符合的節點：\n$preview',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}
