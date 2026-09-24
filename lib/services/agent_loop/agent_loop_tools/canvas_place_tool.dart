/// canvas_place 工具——把理解結果放回畫布
///
/// Phase 1.5 A3（S24d）：Agent Loop 新增畫布協作能力。
/// 設計參考：open-canvas-unified-design.md §4（Agent 在畫布上的協作模型）+ §5.3
///
/// Agent 在畫布上的三種介入模式（§4.1）：
/// - 模式 1：Agent 觀察 → 在畫布上放一個理解節點
/// - 模式 2：Agent 標注 → 在現有節點上加標注
/// - 模式 3：Agent 建議 → 在畫布上放一個「建議節點」等確認
///
/// 此工具對應模式 1（放理解節點）和模式 3（放建議節點）。
///
/// 依賴 EntityGraphService（B1 還在實作中）。
/// 目前為 stub 實作，待 EntityGraphService 完成後接上。

import '../agent_tool.dart';

/// canvas_place 工具的執行器介面
///
/// 實作類別負責呼叫 EntityGraphService.addToCanvas()。
/// 目前只有 stub 實作，待 B1 EntityGraphService 完成後接上。
abstract class CanvasPlaceExecutor {
  /// 把內容放回畫布
  ///
  /// [entityId] — 已存在的 Entity ID（如果已有 Entity）
  /// [content] — 內容文字（如果沒有 entityId，則用 content + entityType 建新 Entity）
  /// [entityType] — Entity 類型（如 'memory', 'annotation', 'suggestion', 'screen_capture'）
  /// [x], [y] — 畫布座標（可選，不傳則自動佈局）
  /// [asSuggestion] — 是否以建議節點形式放入（需人確認才變正式節點）
  ///
  /// 回傳放置的 CanvasNode ID
  Future<String> place({
    String? entityId,
    String? content,
    String? entityType,
    double? x,
    double? y,
    bool asSuggestion = false,
    // [教練 Agent 2026-08-15 通盤檢討] 工作流節點支援——舊介面只能放標注/記憶，
    // agent 無法建 llm/imageGen 等工作流節點（畫布 v2 的主力）。
    String? nodeType,
    Map<String, dynamic>? params,
  });
}

/// Stub 實作——EntityGraphService 尚未完成時使用
class StubCanvasPlaceExecutor implements CanvasPlaceExecutor {
  final String reason;

  StubCanvasPlaceExecutor({this.reason = 'EntityGraphService 尚未實作（B1 進行中）'});

  @override
  Future<String> place({
    String? entityId,
    String? content,
    String? entityType,
    double? x,
    double? y,
    bool asSuggestion = false,
    String? nodeType,
    Map<String, dynamic>? params,
  }) async {
    throw UnsupportedError(reason);
  }
}

/// canvas_place AgentTool
///
/// 讓 LLM 自主把理解結果放回畫布。
/// 依賴 EntityGraphService（B1），目前為 stub。
class CanvasPlaceTool extends AgentTool {
  final CanvasPlaceExecutor _executor;

  CanvasPlaceTool(this._executor);

  @override
  String get name => 'canvas_place';

  @override
  String get description =>
      '把內容放回開放畫布。用於 Agent 在畫布上放置理解節點、建議節點或標注。'
      '可以放入已有的 Entity（傳 entityId），或建立新的內容節點（傳 content + entityType），'
      '或建立工作流節點（傳 nodeType 如 llm/imageGen/condition/merge/output + params）——'
      'nodeType 建的節點自帶 ports，可用 canvas_connect 串連線。'
      '座標可選，不傳則自動佈局。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'entityId',
          description: '已存在的 Entity ID。如果有傳，直接把該 Entity 放到畫布上。',
        ),
        AgentToolParamSpec(
          name: 'content',
          description: '內容文字。如果沒有 entityId，用此內容建立新節點。',
        ),
        AgentToolParamSpec(
          name: 'entityType',
          description: 'Entity 類型（memory, annotation, suggestion, screen_capture 等）。',
          defaultValue: 'annotation',
        ),
        // [教練 Agent 2026-08-15 通盤檢討] 工作流節點支援
        AgentToolParamSpec(
          name: 'nodeType',
          description: '工作流節點型別：input, llm, tool, imageGen, vision, '
              'characterLock, videoGen, musicGen, tts, condition, merge, output, '
              'subWorkflow, schedule, knowledge。有傳則建工作流節點（自帶 ports）。'
              '[2026-08-16] knowledge=vault 向量庫檢索節點。',
        ),
        AgentToolParamSpec(
          name: 'params',
          description: '工作流節點參數（JSON 物件），如 {"label": "我的LLM", "model": "glm-5.2"}。'
              '[2026-08-16 鐵則] 建節點必須預填 params——'
              'label 一定要給（白話任務名），llm 給 prompt/model，input 給 content，'
              'knowledge 給 query/mode/topK。嚴禁建空白節點讓使用者手填。',
        ),
        AgentToolParamSpec(
          name: 'x',
          description: '畫布 X 座標。不傳則自動佈局。',
        ),
        AgentToolParamSpec(
          name: 'y',
          description: '畫布 Y 座標。不傳則自動佈局。',
        ),
        AgentToolParamSpec(
          name: 'asSuggestion',
          description: '是否以建議節點形式放入（true = 需人確認，false = 直接放入）。',
          defaultValue: 'false',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final entityId = args['entityId']?.toString();
    final content = args['content']?.toString();
    final entityType = args['entityType']?.toString() ?? 'annotation';
    final x = _parseDouble(args['x']);
    final y = _parseDouble(args['y']);
    final asSuggestion = args['asSuggestion']?.toString().toLowerCase() == 'true';

    // 必須有 entityId 或 content 至少一個
    if ((entityId == null || entityId.isEmpty) &&
        (content == null || content.isEmpty)) {
      return AgentToolResult.failure(
        '必須提供 entityId 或 content 至少一個參數。',
      );
    }

    try {
      final nodeId = await _executor.place(
        entityId: entityId?.isNotEmpty == true ? entityId : null,
        content: content,
        entityType: entityType,
        x: x,
        y: y,
        asSuggestion: asSuggestion,
        nodeType: args['nodeType']?.toString(),
        params: args['params'] is Map<String, dynamic>
            ? args['params'] as Map<String, dynamic>
            : null,
      );
      final positionDesc = (x != null && y != null)
          ? '位置 ($x, $y)'
          : '自動佈局位置';
      final modeDesc = asSuggestion ? '建議節點（待確認）' : '正式節點';
      return AgentToolResult.success(
        '已將內容放回畫布。節點 ID: $nodeId，$positionDesc，$modeDesc。',
        metadata: {
          'nodeId': nodeId,
          'entityType': entityType,
          'asSuggestion': asSuggestion,
        },
      );
    } on UnsupportedError catch (e) {
      return AgentToolResult.failure('canvas_place 底層服務未實作：$e');
    } catch (e) {
      return AgentToolResult.failure('放回畫布失敗：$e');
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
