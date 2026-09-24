/// canvas_connect 工具——連接畫布上的兩個節點
///
/// Phase 1.5 A3：Agent Loop 新增畫布協作能力。
/// 此工具讓 Agent 在 EntityGraph 上建立兩個節點之間的關聯邊，
/// 用於把規劃步驟串成流程（例如：A depends on B）。
///
/// 依賴 EntityGraphService.addRelation()。
library;

import '../agent_tool.dart';
import '../../../services/entity_graph/entity_graph_service.dart';
import '../../../models/entity_graph/entity.dart';
import '../../../services/memory_store.dart';
import '../../../services/project_door_store.dart';
import '../../../services/digital_asset_registry_store.dart';
import '../../../widgets/canvas/v2/canvas_controller.dart' show NodeTypePorts;

/// canvas_connect 工具的執行器介面
///
/// 實作類別負責呼叫 EntityGraphService.addRelation()。
abstract class CanvasConnectExecutor {
  /// 連接兩個畫布節點，建立關聯邊。
  ///
  /// [sourceId] — 來源節點 ID
  /// [targetId] — 目標節點 ID
  /// [relationType] — 關聯類型（relates, depends, derives, blocks, contains, references）
  Future<void> connect({
    required String sourceId,
    required String targetId,
    String relationType = 'depends',
  });
}

/// EntityGraph 實作——透過 EntityGraphService.addRelation() 建立關聯。
class EntityGraphCanvasConnectExecutor implements CanvasConnectExecutor {
  final EntityGraphService _entityGraph;

  EntityGraphCanvasConnectExecutor()
      : _entityGraph = EntityGraphService.withSqliteCanvasStore(
          memoryStore: MemoryStore(),
          doorStore: ProjectDoorStore(),
          assetStore: DigitalAssetRegistryStore(),
        );

  @override
  Future<void> connect({
    required String sourceId,
    required String targetId,
    String relationType = 'depends',
  }) async {
    // 解析 relationType 字串為 RelationType enum；無效時預設 depends。
    RelationType type;
    try {
      type = RelationType.values.byName(relationType);
    } on ArgumentError {
      type = RelationType.depends;
    }

    // [教練 Agent 2026-08-15 使用者 驗屍報告] 修「成功但隱形」——
    // 舊工具不帶 port 資訊，畫布載入時要求 sourcePort/targetPort
    // 非 null 才還原連線 → agent 連了等於沒連（DB 有、畫布看不到）。
    // 修：自動推斷 port——來源第一個 output port、目標第一個 input
    // port（workflow 節點的標準配置）。非 workflow 節點照舊不帶 port。
    String? sourcePort;
    String? targetPort;
    final sourceEntity = await _entityGraph.getEntity(sourceId);
    final targetEntity = await _entityGraph.getEntity(targetId);
    final sourceType = sourceEntity?.canvasProps?.nodeType;
    final targetType = targetEntity?.canvasProps?.nodeType;
    if (sourceType != null && targetType != null) {
      final sourcePorts = NodeTypePorts.portsFor(sourceType);
      final targetPorts = NodeTypePorts.portsFor(targetType);
      final outPort = sourcePorts.where((p) => p.isOutput).firstOrNull;
      final inPort = targetPorts.where((p) => !p.isOutput).firstOrNull;
      sourcePort = outPort?.name;
      targetPort = inPort?.name;
    }

    final relation = EntityRelation(
      sourceId: sourceId,
      targetId: targetId,
      type: type,
      sourcePort: sourcePort,
      targetPort: targetPort,
    );

    await _entityGraph.addRelation(relation);
  }
}

/// canvas_connect AgentTool
///
/// 讓 LLM 自主連接畫布上的兩個節點，建立關聯邊。
class CanvasConnectTool extends AgentTool {
  final CanvasConnectExecutor _executor;

  CanvasConnectTool(this._executor);

  @override
  String get name => 'canvas_connect';

  @override
  String get description =>
      '連接畫布上的兩個節點，建立它們之間的關聯。用於把規劃步驟串成流程。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'sourceId',
          description: '來源節點 ID',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'targetId',
          description: '目標節點 ID',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'relationType',
          description: '關聯類型：relates, depends, derives, blocks, contains, references',
          defaultValue: 'depends',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final sourceId = args['sourceId']?.toString();
    final targetId = args['targetId']?.toString();
    final relationType = args['relationType']?.toString() ?? 'depends';

    if (sourceId == null || sourceId.isEmpty) {
      return AgentToolResult.failure('sourceId 為必填參數。');
    }
    if (targetId == null || targetId.isEmpty) {
      return AgentToolResult.failure('targetId 為必填參數。');
    }

    try {
      await _executor.connect(
        sourceId: sourceId,
        targetId: targetId,
        relationType: relationType,
      );
      return AgentToolResult.success(
        '已連接節點 $sourceId → $targetId（$relationType）',
        metadata: {
          'sourceId': sourceId,
          'targetId': targetId,
          'relationType': relationType,
        },
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}
