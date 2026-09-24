/// canvas_remove 工具——從畫布上移除節點及其關聯連線
///
/// Phase 1.5 A3：Agent Loop「溝通修改」使用案例。
/// 當使用者要求修改規劃時，Agent 可以移除畫布上不需要的步驟節點。
///
/// 注意：此工具只移除畫布上的呈現（CanvasProps）及相關連線（EntityRelation），
/// 不刪除底層記憶（Memory / FlowStep 等 Entity 本身）。
library;

import '../agent_tool.dart';
import '../../../models/entity_graph/canvas_props.dart';
import '../../../models/entity_graph/entity.dart';
import '../../../services/entity_graph/entity_graph_service.dart';
import '../../../services/memory_store.dart';
import '../../../services/project_door_store.dart';
import '../../../services/digital_asset_registry_store.dart';

/// canvas_remove 工具的執行器介面
///
/// [教練 Agent 2026-08-18 雙系統修正] 精確刪除走 MCP 路徑（V2 controller = 使用者看到的 UI），
/// 模糊查詢仍走 EntityGraph（因為它有 label/類型 metadata）。
/// 不再兩條路徑分裂，刪除的真實對象就是 UI 上的節點。
abstract class CanvasRemoveExecutor {
  /// 精確刪除——走 MCP 確保 UI 同步
  Future<void> remove({required String entityId});

  /// 模糊查詢——掃 EntityGraph 拿候選清單（給 find_nodes 複用）
  Future<List<AgentFuzzyMatch>> findMatches({
    String? labelContains,
    String? typeName,
    double? positionX,
    double? positionY,
    double? radius,
  });
}

class AgentFuzzyMatch {
  final String entityId;
  final String title;
  final String? nodeTypeName;
  final double x;
  final double y;
  final double score;
  AgentFuzzyMatch({
    required this.entityId,
    required this.title,
    required this.nodeTypeName,
    required this.x,
    required this.y,
    required this.score,
  });
}

class EntityGraphCanvasRemoveExecutor implements CanvasRemoveExecutor {
  final EntityGraphService _entityGraph;

  EntityGraphCanvasRemoveExecutor()
      : _entityGraph = EntityGraphService.withSqliteCanvasStore(
          memoryStore: MemoryStore(),
          doorStore: ProjectDoorStore(),
          assetStore: DigitalAssetRegistryStore(),
        );

  @override
  Future<void> remove({required String entityId}) async {
    final relations = await _entityGraph.getRelations(entityId);
    for (final relation in relations) {
      await _entityGraph.removeRelation(
        relation.sourceId,
        relation.targetId,
        relation.type,
      );
    }
    final reverseRelations = await _entityGraph.getReverseRelations(entityId);
    for (final relation in reverseRelations) {
      await _entityGraph.removeRelation(
        relation.sourceId,
        relation.targetId,
        relation.type,
      );
    }
    await _entityGraph.removeFromCanvas(entityId);
  }

  @override
  Future<List<AgentFuzzyMatch>> findMatches({
    String? labelContains,
    String? typeName,
    double? positionX,
    double? positionY,
    double? radius,
  }) async {
    final entries = await _entityGraph.getCanvasNodes();
    final matches = <AgentFuzzyMatch>[];

    for (final entry in entries) {
      double score = 0;
      final props = entry.props;
      final nodeTypeName = props.nodeType?.toString().split('.').last;

      if (labelContains != null && labelContains.isNotEmpty) {
        final title = entry.entity.title.toLowerCase();
        final needle = labelContains.toLowerCase();
        if (title.contains(needle)) {
          score += 0.6;
        } else if (labelContains.length >= 4 &&
            title.contains(needle.substring(0, needle.length - 1))) {
          score += 0.3;
        }
      }

      if (typeName != null && typeName.isNotEmpty) {
        if (nodeTypeName != null && nodeTypeName.toLowerCase() == typeName.toLowerCase()) {
          score += 0.5;
        } else if (typeName.toLowerCase() == 'flowstep' && nodeTypeName == null) {
          score += 0.3;
        }
      }

      if (positionX != null && positionY != null) {
        final dx = props.x - positionX;
        final dy = props.y - positionY;
        final dist = dx * dx + dy * dy;
        final r = radius ?? 100.0;
        if (dist <= r * r) {
          score += 0.4 * (1 - (dist / (r * r)).clamp(0, 1));
        }
      }

      if (score > 0) {
        matches.add(AgentFuzzyMatch(
          entityId: entry.entity.id,
          title: entry.entity.title,
          nodeTypeName: nodeTypeName,
          x: props.x,
          y: props.y,
          score: score.clamp(0, 1),
        ));
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }
}

/// [教練 Agent 2026-08-18 雙系統修正] 混合 executor：
/// 精確刪除走 MCP（V2 controller = 使用者看到的世界），
/// 模糊查詢走 EntityGraph（有 label/類型 metadata）。
/// 解掉「雙系統分裂」：原生 Agent刪除的對象 = UI 顯示的對象。
class HybridCanvasRemoveExecutor implements CanvasRemoveExecutor {
  final dynamic mcpExecutor; // McpCanvasExecutor — 用 dynamic 避免循環 import
  final EntityGraphCanvasRemoveExecutor entityExecutor;

  HybridCanvasRemoveExecutor(this.mcpExecutor, this.entityExecutor);

  @override
  Future<void> remove({required String entityId}) async {
    // 精確刪除：走 MCP 路徑，確保 V2 controller（UI 真實狀態）真的少一個節點
    try {
      await (mcpExecutor.removeNode as Future<void> Function(String))(entityId);
      return;
    } catch (e) {
      // MCP 失敗時 fallback 到 EntityGraph（相容舊行為，至少不卡死）
      // ignore: avoid_print
    print('[HybridCanvasRemove] MCP 刪除失敗 ($entityId): $e，fallback EntityGraph');
      await entityExecutor.remove(entityId: entityId);
    }
  }

  @override
  Future<List<AgentFuzzyMatch>> findMatches({
    String? labelContains,
    String? typeName,
    double? positionX,
    double? positionY,
    double? radius,
  }) {
    return entityExecutor.findMatches(
      labelContains: labelContains,
      typeName: typeName,
      positionX: positionX,
      positionY: positionY,
      radius: radius,
    );
  }
}

class CanvasRemoveTool extends AgentTool {
  final CanvasRemoveExecutor _executor;
  CanvasRemoveTool(this._executor);

  /// [教練 Agent 2026-08-18] 便利建構式：自動組成混合 executor
  factory CanvasRemoveTool.hybrid(dynamic mcpExecutor,
      {EntityGraphCanvasRemoveExecutor? entityExec}) {
    return CanvasRemoveTool(HybridCanvasRemoveExecutor(
      mcpExecutor,
      entityExec ?? EntityGraphCanvasRemoveExecutor(),
    ));
  }

  @override
  String get name => 'canvas_remove';

  @override
  String get description =>
      '從畫布上移除節點及其關聯連線。支援精確（entityId）或模糊匹配。\n'
      '**操作既有節點前先呼叫 canvas_get_state 看現狀**，需要清掉重複/舊節點但只有座標或 label 沒有 ID 時，用模糊參數（entityLabel/positionX/positionY/entityType）。\n'
      '模糊匹配回傳候選清單（顯示 entityId + label + 座標），確認後再執行刪除。\n'
      '這只移除畫布上的呈現，不刪除底層記憶。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'entityId',
          description: '精確節點 ID（如 wf-xxx）。精確模式刪一個。',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'entityLabel',
          description: '模糊：label 包含此字串。會回傳符合的候選清單（包含 entityId、座標）讓你選。',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'entityType',
          description: '模糊：工作流節點型別名（input/llm/tool/knowledge/condition/output/...）。例如 entityType=llm 列出所有 LLM 節點。',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'positionX',
          description: '模糊：目標座標 X',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'positionY',
          description: '模糊：目標座標 Y',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'radius',
          description: '模糊：座標半徑（預設 100），半徑內的節點都列入候選',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'dryRun',
          description: 'true=只回傳候選清單不真的刪（建議第一次用模糊時先開）',
          required: false,
          defaultValue: "false",
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final entityId = args['entityId']?.toString();
    final entityLabel = args['entityLabel']?.toString();
    final entityType = args['entityType']?.toString();
    final positionX = (args['positionX'] as num?)?.toDouble();
    final positionY = (args['positionY'] as num?)?.toDouble();
    final radius = (args['radius'] as num?)?.toDouble();
    final dryRun = args['dryRun'] == true;

    if (entityId != null && entityId.isNotEmpty) {
      try {
        await _executor.remove(entityId: entityId);
        return AgentToolResult.success('已從畫布移除節點 $entityId 及其關聯連線');
      } catch (e) {
        return AgentToolResult.failure(e.toString());
      }
    }

    final hasFuzzy = (entityLabel != null && entityLabel.isNotEmpty) ||
        (entityType != null && entityType.isNotEmpty) ||
        (positionX != null && positionY != null);
    if (!hasFuzzy) {
      return AgentToolResult.failure(
        '必須提供 entityId（精確）或以下任一模糊條件：entityLabel、entityType、positionX+positionY。',
      );
    }

    try {
      final matches = await _executor.findMatches(
        labelContains: entityLabel,
        typeName: entityType,
        positionX: positionX,
        positionY: positionY,
        radius: radius,
      );

      if (matches.isEmpty) {
        return AgentToolResult.failure(
          '模糊匹配無結果。請放寬條件（縮短 label、放寬類型、擴大半徑）或先 canvas_get_state 看現狀。',
        );
      }

      final preview = matches
          .map((m) =>
              '  - ${m.entityId} | ${m.nodeTypeName ?? "non-workflow"} | '
              '"${m.title}" | (${m.x.toStringAsFixed(0)}, ${m.y.toStringAsFixed(0)}) | score=${m.score.toStringAsFixed(2)}')
          .join('\n');

      if (dryRun || matches.length > 1) {
        return AgentToolResult.success(
          '找到 ${matches.length} 個符合的節點（按匹配分數排序）：\n$preview\n\n'
          '確認要刪除這些嗎？把上面的 entityId 逐一傳入 entityId 精確刪除，或放寬/收緊模糊條件。',
        );
      }

      final only = matches.first;
      await _executor.remove(entityId: only.entityId);
      return AgentToolResult.success(
        '已從畫布移除節點 ${only.entityId}（label="${only.title}"）及其關聯連線',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}
