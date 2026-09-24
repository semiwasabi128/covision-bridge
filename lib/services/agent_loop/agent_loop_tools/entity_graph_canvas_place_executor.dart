// entity_graph_canvas_place_executor.dart
// canvas_place 的正式實作——接 EntityGraphService
// Phase 1.5 C2：把 A3 stub 替換為正式 executor
//
// 取代 StubCanvasPlaceExecutor。

import 'dart:ui' show Offset;
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/brain_container/brain_container_service.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart' show NodeTypePorts;
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';
import 'package:flutter/foundation.dart';

import 'canvas_place_tool.dart';

/// 正式實作 CanvasPlaceExecutor——透過 EntityGraphService 操作畫布。
///
/// 支援兩種模式：
/// 1. 已有 entityId → 直接 addToCanvas
/// 2. 只有 content → 先建記憶 → 取得 ID → addToCanvas
class EntityGraphCanvasPlaceExecutor implements CanvasPlaceExecutor {
  late final EntityGraphService _entityGraph;

  EntityGraphCanvasPlaceExecutor() {
    _entityGraph = EntityGraphService.withSqliteCanvasStore(
      memoryStore: MemoryStore(),
      doorStore: ProjectDoorStore(),
      assetStore: DigitalAssetRegistryStore(),
    );
  }

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
    String targetId = entityId ?? '';

    // [教練 Agent 2026-08-15 通盤檢討] 工作流節點——nodeType 有傳就建工作流節點
    if (targetId.isEmpty && nodeType != null && nodeType.isNotEmpty) {
      final parsedType = WorkflowNodeType.values
          .where((t) => t.name == nodeType)
          .firstOrNull;
      if (parsedType == null) {
        throw StateError('未知的工作流節點型別：$nodeType（可用：'
            '${WorkflowNodeType.values.map((t) => t.name).join(", ")}）');
      }
      // [教練 Agent 2026-08-16 教練模式最終修復] 工作流節點一律走正宮路徑——
      // CanvasMcpRegistry → 畫布 controller.addWorkflowNode。
      //
      // 之前的寫法（自建 EntityGraphService + writeMemory + setCanvasProps）
      // 是平行宇宙：ID 格式不同（無 wf- 前綴）、沒帶 canvasId、
      // 畫布 UI 的 controller 完全不知道——agent 回報「建好了」但
      // 使用者畫布永遠看不到。走 registry 的話節點直接進當前畫布的
      // controller state（UI 即時顯示）＋正確掛 canvasId。
      final registry = CanvasMcpRegistry.instance;
      final ctrl = registry.controller;
      if (ctrl == null) {
        throw StateError('畫布未就緒——請先切到畫布頁面再建工作流節點');
      }
      final nodeId = await ctrl.addWorkflowNode(
        parsedType,
        Offset(x ?? 300, y ?? 300),
      );
      // 預填 params（使用者鐵則：不建空白節點）
      if (params != null && params.isNotEmpty) {
        ctrl.updateNodeParams(nodeId, parsedType, params);
      }
      debugPrint('[CanvasPlace] 工作流節點 $parsedType 走正宮路徑已放置 '
          '($x, $y) node=$nodeId params=${params?.keys.join(",")}');
      return nodeId;
    }

    // 如果沒有 entityId，先用 content 建新記憶
    if (targetId.isEmpty && content != null && content.isNotEmpty) {
      targetId = await _createMemoryFromContent(content, entityType ?? 'annotation');
    }

    if (targetId.isEmpty) {
      throw StateError('無法取得 entityId：既沒有傳入也無法從 content 建立');
    }

    // 預設位置：如果沒給 x/y，用自動佈局（略偏移避免重疊）
    final posX = x ?? _autoLayoutX();
    final posY = y ?? _autoLayoutY();

    await _entityGraph.addToCanvas(targetId, x: posX, y: posY);

    // 如果是建議節點，設定 visualState 為 idle（等待確認）
    if (asSuggestion) {
      await _entityGraph.updateCanvasVisualState(
        targetId,
        CanvasVisualState.idle,
      );
    }

    debugPrint('[CanvasPlace] 已放置 $targetId 於 ($posX, $posY)'
        '${asSuggestion ? ' [建議節點]' : ''}');

    return targetId;
  }

  /// 從 content 建立新記憶，回傳 memory ID
  Future<String> _createMemoryFromContent(String content, String entityType) async {
    final brain = BrainContainerService.instance;

    // 確保初始化
    if (!brain.isInitialized) {
      for (var i = 0; i < 30; i++) {
        if (brain.isInitialized) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // 用 writeMemory 建記憶
    final success = await brain.writeMemory(
      content: content,
      agent: 'canvas_place',
      source: MemorySource.idea,
      tags: ['canvas-placed', entityType],
      importance: 3,
    );

    if (!success) {
      throw StateError('BrainContainer.writeMemory 失敗');
    }

    // 取最新一條記憶的 ID
    final memories = await brain.getAllMemories(limit: 1);
    if (memories.isEmpty) {
      throw StateError('writeMemory 後查不到記憶');
    }

    return memories.first.id;
  }

  /// [教練 Agent 2026-08-16 教練模式] 工作流節點專用——輕量直寫。
  ///
  /// 不走 writeMemory 完整管線（嵌入→分類→寫入→連結→生長），
  /// 避開 partialSuccess 靜默吞錯。失敗直接 throw 帶原因。
  Future<String> _createWorkflowNodeEntity(String title) async {
    final brain = BrainContainerService.instance;

    if (!brain.isInitialized) {
      for (var i = 0; i < 30; i++) {
        if (brain.isInitialized) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    return brain.writeMemoryFast(
      content: title,
      agent: 'canvas_place',
      tags: ['canvas-placed', 'workflow_node'],
    );
  }

  // 簡易自動佈局——在畫布中央附近隨機偏移
  static double _lastX = 200;
  static double _lastY = 150;

  double _autoLayoutX() {
    _lastX += 30;
    if (_lastX > 600) _lastX = 200;
    return _lastX;
  }

  double _autoLayoutY() {
    _lastY += 30;
    if (_lastY > 400) _lastY = 150;
    return _lastY;
  }
}
