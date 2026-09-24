// canvas_event_bus.dart
// 人機共視事件系統
// [教練 Agent 2026-07-22] Phase 4+ — 畫布事件即時感知
//
// 核心理念：Agent 是畫布的主理人，必須即時知道使用者在畫布上做了什麼。
// 這是「人機共視」的基礎——雙向感知、即時互動、主動引導。
//
// 設計：
// 1. CanvasController 在每個操作後呼叫 CanvasEventBus.emit()
// 2. TemplateTutorialService 訂閱事件 → 教學中即時回應使用者動作
// 3. 未來：Agent Loop 訂閱 → 主動建議、提醒、引導
//
// 事件類型：
// - nodeAdded: 使用者新增節點
// - nodeRemoved: 使用者刪除節點
// - nodeMoved: 使用者移動節點
// - nodeEdited: 使用者編輯節點（雙擊進入編輯模式）
// - nodeParamsChanged: 使用者修改節點參數
// - nodeSelected: 使用者選取節點
// - connectionAdded: 使用者建立連線
// - connectionRemoved: 使用者移除連線
// - canvasCleared: 使用者清空畫布
// - doodleAdded: 使用者畫了塗鴉
// - toolChanged: 使用者切換工具

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 畫布事件類型
enum CanvasEventType {
  nodeAdded,
  nodeRemoved,
  nodeMoved,
  nodeEdited,
  nodeParamsChanged,
  nodeSelected,
  connectionAdded,
  connectionRemoved,
  canvasCleared,
  doodleAdded,
  toolChanged,
  canvasLoaded, // [教練 Agent 2026-07-22] Phase A — 載入畫布事件
  batchLoaded, // [教練 Agent 2026-08-15] 批量載入完成（範本匯入）
}

/// 畫布事件
class CanvasEvent {
  final CanvasEventType type;
  final String? nodeId;
  final String? nodeType;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  CanvasEvent({
    required this.type,
    this.nodeId,
    this.nodeType,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    final parts = <String>[type.name];
    if (nodeId != null) parts.add('node=$nodeId');
    if (nodeType != null) parts.add('type=$nodeType');
    if (data != null && data!.isNotEmpty) parts.add('data=$data');
    return 'CanvasEvent(${parts.join(', ')})';
  }
}

/// 畫布事件匯流排
///
/// 單例。CanvasController 操作後 emit 事件，
/// 訂閱者（教學服務、Agent Loop）即時收到通知。
class CanvasEventBus {
  CanvasEventBus._();
  static final CanvasEventBus instance = CanvasEventBus._();

  final _controller = StreamController<CanvasEvent>.broadcast();
  Stream<CanvasEvent> get stream => _controller.stream;

  /// 發出事件
  void emit(CanvasEventType type, {String? nodeId, String? nodeType, Map<String, dynamic>? data}) {
    final event = CanvasEvent(
      type: type,
      nodeId: nodeId,
      nodeType: nodeType,
      data: data,
    );
    debugPrint('[CanvasEventBus] $event');
    _controller.add(event);
  }

  /// 訂閱事件
  StreamSubscription<CanvasEvent> subscribe(void Function(CanvasEvent event) handler) {
    return _controller.stream.listen(handler);
  }

  void dispose() {
    _controller.close();
  }
}
