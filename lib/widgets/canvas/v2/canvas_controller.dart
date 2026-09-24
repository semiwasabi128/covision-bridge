// canvas_controller.dart
// 畫布統一狀態管理 — 所有畫布操作的唯一入口。
// 建立日期: 2026-07-15
// 參考: fldraw FlDrawController + graph_edit GraphCanvasController
//
// 設計:
// - ChangeNotifier，UI 用 listenable 監聽變化
// - 所有操作透過 method → 修改 _state → notifyListeners()
// - 持久化 debounce 500ms 寫入 EntityGraphService
// - 支援 undo/redo（快照式）

import 'dart:async';
import 'dart:io';
import 'dart:math' show Random; // [教練 Agent 2026-08-15 Phase 1] 節點 ID 隨機尾碼
import 'package:flutter/material.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/vault/canvas_event_bus.dart'; // [教練 Agent 2026-07-22] 人機共視事件
import 'canvas_state.dart';
import 'canvas_snapshot.dart';
import 'node_connection.dart';

/// 每種 WorkflowNodeType 的預設 port 定義
class NodeTypePorts {
  static List<PortDef> portsFor(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.input:
        return [
          // [v213b Blue 設計] input 加 trigger 輸入接頭——排程/手動/上游
          // 都能接在 input「前面」，觸發它。排程時間到 → trigger → input
          // 內容匯入 → 下游推論。觸發語意一目了然，不再「schedule 直連
          // LLM、input 內容到底有沒有匯進去」的疑惑。
          const PortDef(name: 'trigger', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.llm:
        return [
          const PortDef(name: 'input', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.tool:
        return [
          const PortDef(name: 'input', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.move: // 🥋 [Blue 拍板] 招式節點——同 tool 款 ports
        return [
          const PortDef(name: 'input', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.imageGen:
        return [
          // [教練 Agent 2026-08-21] image 輸入——圖生圖。有接圖走
          // generateImageWithReference（付費閘門照走），沒接走純文生圖。
          const PortDef(name: 'image', dataType: PortDataType.image, isOutput: false),
          const PortDef(name: 'prompt', dataType: PortDataType.text, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.image, isOutput: true),
        ];
      case WorkflowNodeType.vision:
        return [
          const PortDef(name: 'image', dataType: PortDataType.image, isOutput: false),
          const PortDef(name: 'prompt', dataType: PortDataType.text, isOutput: false),
          // [小葵 2026-09-22 修 bug] 原圖直通輸出——拖圖上畫布的節點
          // 之前只有文字輸出（分析結果），接不進 characterLock 的
          // reference（圖片輸入）＝圖生圖鏈路被斷。加此埠讓原圖可以
          // 往下傳（真·圖生圖，不繞道圖生文再生圖）。
          // [小葵 2026-09-23 修 bug] 埠名不可與輸入埠同名 'image'——
          // portPositions 以 nodeId:portName 為 key，同名互相覆蓋，
          // 命中判定抓錯定義（輸出埠被判成輸入埠）＝接線永遠失敗。
          // 改名 'original'（原圖輸出）。
          const PortDef(name: 'original', dataType: PortDataType.image, isOutput: true),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.characterLock:
        return [
          const PortDef(name: 'reference', dataType: PortDataType.image, isOutput: false),
          const PortDef(name: 'prompt', dataType: PortDataType.text, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.image, isOutput: true),
        ];
      case WorkflowNodeType.videoGen:
        return [
          const PortDef(name: 'prompt', dataType: PortDataType.text, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.video, isOutput: true),
        ];
      case WorkflowNodeType.musicGen:
        return [
          const PortDef(name: 'prompt', dataType: PortDataType.text, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.audio, isOutput: true),
        ];
      case WorkflowNodeType.tts:
        return [
          const PortDef(name: 'text', dataType: PortDataType.text, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.audio, isOutput: true),
        ];
      case WorkflowNodeType.condition:
        return [
          const PortDef(name: 'input', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'true', dataType: PortDataType.text, isOutput: true),
          const PortDef(name: 'false', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.merge:
        return [
          const PortDef(name: 'a', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'b', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.output:
        return [
          const PortDef(name: 'input', dataType: PortDataType.any, isOutput: false),
        ];
      case WorkflowNodeType.subWorkflow:
        return [
          const PortDef(name: 'trigger', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.schedule:
        return [
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.knowledge: // [教練 Agent 2026-08-16] vault 知識節點
        return [
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
      case WorkflowNodeType.materialPool: // [教練 Agent 2026-08-25 F-1] 素材池
        return [
          const PortDef(name: 'input', dataType: PortDataType.any, isOutput: false),
          const PortDef(name: 'output', dataType: PortDataType.text, isOutput: true),
        ];
    }
  }

  /// 每種類型的預設參數
  static Map<String, dynamic> defaultParams(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.input:
        return {'source': 'manual', 'content': ''};
      case WorkflowNodeType.llm:
        return {'model': '', 'prompt': '', 'temperature': 0.7, 'maxTokens': 2000};
      case WorkflowNodeType.tool:
        return {'toolName': 'browse', 'args': '{}'};
      case WorkflowNodeType.imageGen:
        return {'prompt': '', 'size': '1024x1024', 'seed': -1};
      case WorkflowNodeType.vision:
        return {'prompt': '', 'serviceId': 'openai_vision'};
      case WorkflowNodeType.characterLock:
        return {'prompt': '', 'reference': '', 'serviceId': 'openai_character', 'size': '1024x1024'};
      case WorkflowNodeType.videoGen:
        return {'prompt': '', 'duration': 5, 'serviceId': ''};
      case WorkflowNodeType.musicGen:
        return {'prompt': '', 'duration': 30, 'serviceId': ''};
      case WorkflowNodeType.tts:
        return {'text': '', 'voice': 'default', 'speed': 1.0};
      case WorkflowNodeType.move: // 🥋 [Blue 拍板] 招式——moveId/moveName 擇一
        return {'moveId': '', 'moveName': ''};
      case WorkflowNodeType.condition:
        return {'condition': ''};
      case WorkflowNodeType.merge:
        return {'mode': 'concat'};
      case WorkflowNodeType.output:
        return {'displayMode': 'text', 'label': '輸出'};
      case WorkflowNodeType.subWorkflow:
        return {'workflowId': ''};
      case WorkflowNodeType.schedule:
        return {
          'scheduleType': 'daily', // daily | weekly | monthly | once
          'time': '09:00',
          'weekday': 1, // 1=Mon..7=Sun (weekly 用)
          'dayOfMonth': 1, // 1-31 (monthly 用)
          'date': '', // YYYY-MM-DD (once 用)
          'label': '排程',
        };
      case WorkflowNodeType.knowledge: // [教練 Agent 2026-08-16] vault 知識節點
        return {
          'query': '',
          'mode': 'semantic', // semantic | fullText
          'topK': 5,
          'room': '', // 空 = 全部房間
          'label': '📚 知識',
        };
      case WorkflowNodeType.materialPool: // [教練 Agent 2026-08-25 F-1] 素材池
        return {
          'topic': '', // 發想主題；空 = 用上游輸入
          'count': 3, // 候選發想條數
          'candidates': <String>[], // AI 產出的候選
          'adoptedIndex': -1, // 被採用的候選索引（-1 = 未採用）
          'coCreated': false, // 機制 4：共視產物標記
        };
    }
  }
}

/// 畫布統一狀態管理
class CanvasController extends ChangeNotifier {
  CanvasState _state = const CanvasState();
  CanvasState get state => _state;

  EntityGraphService? _entityGraph; // [教練 Agent 2026-08-15 Phase 1] final → nullable 可清引用
  String? _canvasId;

  /// [教練 Agent 2026-07-23] 切換畫布時更新 canvasId
  String? get canvasId => _canvasId;
  set canvasId(String? id) => _canvasId = id;

  /// [教練 Agent 2026-08-02] 節點結果完成回調 — 當節點執行完成時觸發
  /// 用於將節點結果推送到畫布對話框
  void Function(String nodeId, String nodeTitle, String result)? onNodeResult;

  /// 持久化 debounce
  Timer? _persistTimer;

  /// [教練 Agent 2026-08-15 Phase 2.5-C] 抓住的連線本體（斷線時同步刪 DB 用）
  NodeConnection? _lastDetachedConnection;

  /// [教練 Agent 2026-08-15 Phase 1] 節點 ID 隨機尾碼（防同毫秒碰撞）
  static final Random _idRand = Random();

  // ── Undo/Redo ─────────────────────────────────────────
  /// [教練 Agent 2026-07-23] 快照式 undo/redo，上限 30 步
  static const int _maxHistory = 30;
  final List<CanvasState> _undoStack = [];
  final List<CanvasState> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// 建立只含結構性資料的快照（不含 viewport / dragState / editingNodeId）
  CanvasState _snapshot() {
    return CanvasState(
      nodes: Map<String, OpenCanvasNode>.from(_state.nodes),
      connections: List<NodeConnection>.from(_state.connections),
      selectedNodeIds: Set<String>.from(_state.selectedNodeIds),
    );
  }

  /// 在變更前呼叫 — 推入 undo stack 並清 redo
  void _pushUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// 恢復上一步
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    final prev = _undoStack.removeLast();
    _state = _state.copyWith(
      nodes: prev.nodes,
      connections: prev.connections,
      selectedNodeIds: prev.selectedNodeIds,
    );
    notifyListeners();
    _schedulePersist();
  }

  /// 恢復下一步
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    final next = _redoStack.removeLast();
    _state = _state.copyWith(
      nodes: next.nodes,
      connections: next.connections,
      selectedNodeIds: next.selectedNodeIds,
    );
    notifyListeners();
    _schedulePersist();
  }

  /// [教練 Agent 2026-07-23] 拖曳開始時呼叫 — 只快照一次
  void beginMove() {
    _pushUndo();
  }

  /// port 位置快取（key = "nodeId:portId"，value = 螢幕座標）
  /// 由 RenderObject 在 layout 時更新
  final Map<String, Offset> _portPositions = {};
  Map<String, Offset> get portPositions => _portPositions;

  CanvasController({
    EntityGraphService? entityGraph,
    String? canvasId,
  })  : _entityGraph = entityGraph,
        _canvasId = canvasId;

  // ── 載入 ──────────────────────────────────────────────

  /// 從 EntityGraphService 載入畫布節點
  Future<void> loadFromStore() async {
    if (_entityGraph == null || _canvasId == null) return;

    final entries = await _entityGraph!.getCanvasNodes(canvasId: _canvasId);
    final nodes = <String, OpenCanvasNode>{};
    final connections = <NodeConnection>[];

    for (final entry in entries) {
      final node = OpenCanvasNode.fromCanvasEntry(
        entry.entity,
        entry.props,
      );
      nodes[node.id] = node;

      // 載入 Entity 之間的關係作為連線
      final relations = await _entityGraph!.getRelations(entry.entity.id);
      for (final rel in relations) {
        // 工作流連線用 RelationType.depends + sourcePort/targetPort 標識
        if (rel.type == RelationType.depends &&
            rel.sourcePort != null &&
            rel.targetPort != null) {
          // [教練 Agent 2026-08-15 修復] DB 載入也要過型別檢查——
          // 舊資料裡的型別不匹配連線（範本 bug 時期寫入的）不再復活；
          // 沒有 port 定義的（舊版節點）放行以保相容。
          // 注意：此時節點尚未寫入 _state，用 local nodes map 查型別。
          bool typeOk = true;
          final fromNodeType = nodes[rel.sourceId]?.entity.canvasProps?.nodeType;
          final toNodeType = nodes[rel.targetId]?.entity.canvasProps?.nodeType;
          if (fromNodeType != null && toNodeType != null) {
            final fromPorts = NodeTypePorts.portsFor(fromNodeType);
            final toPorts = NodeTypePorts.portsFor(toNodeType);
            final fp = fromPorts.where((p) => p.name == rel.sourcePort && p.isOutput).firstOrNull;
            final tp = toPorts.where((p) => p.name == rel.targetPort && !p.isOutput).firstOrNull;
            if (fp != null && tp != null) {
              typeOk = NodeConnection.isPortTypeMatch(fp.dataType, tp.dataType);
            }
          }
          if (!typeOk) {
            // 靜默丟棄壞連線＋同步刪 DB（不讓它再復活）
            await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
            continue;
          }
          // [教練 Agent 2026-08-15 使用者 驗屍報告] 幽靈連線淨化——
          // relation 另一端節點已被刪除（DB 殘骸）時，連線隱形存在於
          // state（渲染層 portPositions 查不到就 skip），analyzer 卻看
          // 得到 → 「測試」報了你看不見的線。載入時直接刪除＋清 DB。
          if (!entries.any((e) => e.entity.id == rel.targetId)) {
            await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
            debugPrint('[Canvas] 幽靈連線淨化: ${rel.sourceId} → ${rel.targetId}（目標節點不存在）');
            continue;
          }
          if (!entries.any((e) => e.entity.id == rel.sourceId)) {
            await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
            debugPrint('[Canvas] 幽靈連線淨化: ${rel.sourceId} → ${rel.targetId}（來源節點不存在）');
            continue;
          }
          final connId = NodeConnection.makeId(
            '${rel.sourceId}:${rel.sourcePort}',
            '${rel.targetId}:${rel.targetPort}',
          );
          connections.add(NodeConnection(
            id: connId,
            fromNodeId: rel.sourceId,
            fromPortId: rel.sourcePort!,
            toNodeId: rel.targetId,
            toPortId: rel.targetPort!,
          ));
        }
      }

      // [教練 Agent 2026-08-15 通盤檢討] 入向孤兒清掃——
      // relation 的「來源」節點已刪時，它不會被任何 entry 的出向讀取
      // 讀到（永久 DB 垃圾）。從目標端的反向關聯補撈，來源不存在即刪。
      final reverseRels = await _entityGraph!.getReverseRelations(entry.entity.id);
      for (final rel in reverseRels) {
        if (!entries.any((e) => e.entity.id == rel.sourceId)) {
          await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
          debugPrint('[Canvas] 入向孤兒清掃: ${rel.sourceId} → ${rel.targetId}（來源節點不存在）');
        }
      }
    }

    _state = _state.copyWith(nodes: nodes, connections: connections);
    notifyListeners();
  }

  // ── 節點操作 ──────────────────────────────────────────

  /// [教練 Agent 2026-08-15 批量載入模式] 修多重宇宙範本匯入卡 3 分鐘：
  /// 35 次串行 DB 寫入（11 節點×2＋13 連線）鎖爭用。批量期間
  /// addWorkflowNode/connect 只動 state（不寫 DB、不 emit、不 pushUndo），
  /// endBatch 一次 transaction 寫入 + emit 一次 batchLoaded。
  bool _batchMode = false;
  final List<(String, CanvasProps)> _batchProps = [];
  final List<EntityRelation> _batchRelations = [];

  void beginBatch() {
    _batchMode = true;
    _batchProps.clear();
    _batchRelations.clear();
  }

  Future<void> endBatch() async {
    _batchMode = false;
    if (_entityGraph != null) {
      // 單一 transaction：SQLite 一次 commit，鎖爭用歸零
      await _entityGraph!.upsertCanvasPropsBatch(_batchProps);
      await _entityGraph!.addRelationsBatch(_batchRelations);
    }
    _batchProps.clear();
    _batchRelations.clear();
    _schedulePersist();
    notifyListeners();
    CanvasEventBus.instance.emit(CanvasEventType.batchLoaded);
  }

  /// [教練 Agent 2026-08-26 使用者 基礎規則] 排版間距保證——
  /// 新節點落點與既有節點距離 < [minDist] 時自動螺旋找空位。
  /// 這是基礎規則（controller 層），不論人手動放、Agent 工具放、
  /// HTTP /add_node 放、範本載入放，一律生效——節點永遠不該疊在一起。
  /// 節點寬約 200-320，260 = 含呼吸空隙的最小間距。
  Offset _ensureSpacing(Offset pos) {
    const minDist = 260.0;
    bool tooClose(double cx, double cy) => _state.nodes.values.any((n) {
          final dx = n.position.dx - cx;
          final dy = n.position.dy - cy;
          return dx * dx + dy * dy < minDist * minDist;
        });
    if (!tooClose(pos.dx, pos.dy)) return pos;
    // 網格螺旋找最近空位（與 Agent add_node 工具同思路，下沉到 controller）
    for (var ring = 1; ring <= 8; ring++) {
      for (var dx = -ring; dx <= ring; dx++) {
        for (var dy = -ring; dy <= ring; dy++) {
          if (dx.abs() != ring && dy.abs() != ring) continue; // 只走外圈
          final cx = pos.dx + dx * 260;
          final cy = pos.dy + dy * 260;
          if (!tooClose(cx, cy)) return Offset(cx, cy);
        }
      }
    }
    return pos; // 8 圈還找不到（>60 節點塞滿）就照原樣
  }

  /// 新增工作流節點，回傳節點 ID
  Future<String> addWorkflowNode(WorkflowNodeType type, Offset worldPos) async {
    if (!_batchMode) _pushUndo();
    final nodeId = 'wf-${DateTime.now().millisecondsSinceEpoch}-${_idRand.nextInt(999999)}'; // [教練 Agent 2026-08-15 Phase 1] 加隨機尾碼防碰撞
    final ports = NodeTypePorts.portsFor(type);
    final params = NodeTypePorts.defaultParams(type);
    // [教練 Agent 2026-08-26 使用者 基礎規則] 落點防重疊——基礎層保證
    final spacedPos = _batchMode ? worldPos : _ensureSpacing(worldPos);

    final props = CanvasProps(
      x: spacedPos.dx,
      y: spacedPos.dy,
      canvasId: _canvasId,
      nodeType: type,
      params: params,
      ports: ports,
      origin: CanvasNodeOrigin.createdOnCanvas,
    );

    final entity = Entity(
      id: nodeId,
      type: EntityType.flowstep,
      title: '',  // title 由 nodeType label 動態生成
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      source: EntitySource.human,
      tags: ['workflow', type.name],
      relations: const [],
      canvasProps: props,
      underlying: null,
    );

    // 持久化
    if (_batchMode) {
      _batchProps.add((nodeId, props));
    } else if (_entityGraph != null) {
      await _entityGraph!.setCanvasProps(nodeId, props);
    }

    // 更新 state
    final node = OpenCanvasNode.fromCanvasEntry(entity, props);
    _state = _state.copyWith(
      nodes: {..._state.nodes, nodeId: node},
      selectedNodeIds: {nodeId},
    );
    if (!_batchMode) {
      notifyListeners();
      CanvasEventBus.instance.emit(CanvasEventType.nodeAdded, nodeId: nodeId, nodeType: type.name);
    }
    return nodeId;
  }

  /// 新增標注節點（非工作流）
  Future<void> addAnnotation(Offset worldPos, String text) async {
    _pushUndo();
    final nodeId = 'anno-${DateTime.now().millisecondsSinceEpoch}-${_idRand.nextInt(999999)}'; // [教練 Agent 2026-08-15 Phase 1] 加隨機尾碼防碰撞

    final props = CanvasProps(
      x: worldPos.dx,
      y: worldPos.dy,
      canvasId: _canvasId,
      params: {'title': text},
      origin: CanvasNodeOrigin.createdOnCanvas,
    );

    final entity = Entity(
      id: nodeId,
      type: EntityType.annotation,
      title: text,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      source: EntitySource.human,
      tags: const ['annotation'],
      relations: const [],
      canvasProps: props,
      underlying: null,
    );

    if (_entityGraph != null) {
      await _entityGraph!.setCanvasProps(nodeId, props);
    }

    final node = OpenCanvasNode.fromCanvasEntry(entity, props);
    _state = _state.copyWith(
      nodes: {..._state.nodes, nodeId: node},
    );
    notifyListeners();
  }

  /// 移動節點
  void moveNode(String nodeId, Offset newPos) {
    final node = _state.nodes[nodeId];
    if (node == null) return;

    // [教練 Agent 2026-07-23] 若該節點在選取集合中，連動移動所有選中節點
    if (_state.selectedNodeIds.contains(nodeId) && _state.selectedNodeIds.length > 1) {
      // beginMove() 由 graph_canvas 拖曳開始時呼叫，這裡不重複 push
      final delta = newPos - node.position;
      final updatedNodes = Map<String, OpenCanvasNode>.from(_state.nodes);
      for (final id in _state.selectedNodeIds) {
        final n = updatedNodes[id];
        if (n == null) continue;
        final target = n.position + delta;
        updatedNodes[id] = n.copyWith(
          position: target,
          entity: Entity(
            id: n.entity.id,
            type: n.entity.type,
            title: n.entity.title,
            createdAt: n.entity.createdAt,
            updatedAt: DateTime.now(),
            companionId: n.entity.companionId,
            source: n.entity.source,
            tags: n.entity.tags,
            relations: n.entity.relations,
            canvasProps: (n.entity.canvasProps ?? CanvasProps(x: 0, y: 0))
                .copyWith(x: target.dx, y: target.dy),
            underlying: n.entity.underlying,
          ),
        );
      }
      _state = _state.copyWith(nodes: updatedNodes);
      notifyListeners();
      CanvasEventBus.instance.emit(CanvasEventType.nodeMoved, nodeId: nodeId, data: {'x': newPos.dx, 'y': newPos.dy});
      _schedulePersist();
      return;
    }

    final updatedNode = node.copyWith(
      position: newPos,
      entity: Entity(
        id: node.entity.id,
        type: node.entity.type,
        title: node.entity.title,
        createdAt: node.entity.createdAt,
        updatedAt: DateTime.now(),
        companionId: node.entity.companionId,
        source: node.entity.source,
        tags: node.entity.tags,
        relations: node.entity.relations,
        canvasProps: (node.entity.canvasProps ?? CanvasProps(x: 0, y: 0))
            .copyWith(x: newPos.dx, y: newPos.dy),
        underlying: node.entity.underlying,
      ),
    );

    _state = _state.copyWith(
      nodes: {..._state.nodes, nodeId: updatedNode},
    );
    notifyListeners();
    CanvasEventBus.instance.emit(CanvasEventType.nodeMoved, nodeId: nodeId, data: {'x': newPos.dx, 'y': newPos.dy});
    _schedulePersist();
  }

  /// 刪除節點（含相關連線）
  Future<void> removeNode(String nodeId) async {
    final node = _state.nodes[nodeId];
    if (node == null) return;

    _pushUndo();

    // 移除相關連線
    final remainingConns = _state.connections
        .where((c) => !c.involves(nodeId))
        .toList();

    // 移除節點
    final remainingNodes = Map<String, OpenCanvasNode>.from(_state.nodes);
    remainingNodes.remove(nodeId);

    // 持久化
    if (_entityGraph != null) {
      // [教練 Agent 2026-08-15 幽靈連線根因] 級聯刪除 relations——
      // 之前只 removeFromCanvas（刪 CanvasProps），relations 留在 DB
      // → 下次載入復活成隱形連線（渲染層 skip、analyzer 看得到）。
      // [修正] getRelations 只查出向，入向要 getReverseRelations——雙向清。
      final outRels = await _entityGraph!.getRelations(nodeId);
      final inRels = await _entityGraph!.getReverseRelations(nodeId);
      for (final rel in [...outRels, ...inRels]) {
        await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
      }
      await _entityGraph!.removeFromCanvas(nodeId);
    }

    final newSelection = Set<String>.from(_state.selectedNodeIds)..remove(nodeId);

    _state = _state.copyWith(
      nodes: remainingNodes,
      connections: remainingConns,
      selectedNodeIds: newSelection,
      clearEditingNode: nodeId == _state.editingNodeId,
    );
    notifyListeners();
    CanvasEventBus.instance.emit(CanvasEventType.nodeRemoved, nodeId: nodeId);
  }

  /// 更新節點參數
  void updateNodeParams(String nodeId, WorkflowNodeType? nodeType, Map<String, dynamic> params) {
    final node = _state.nodes[nodeId];
    if (node == null) return;

    _pushUndo();

    final oldProps = node.entity.canvasProps ?? CanvasProps(x: 0, y: 0);
    final newProps = oldProps.copyWith(nodeType: nodeType, params: params);

    final updatedEntity = Entity(
      id: node.entity.id,
      type: node.entity.type,
      title: node.entity.title,
      createdAt: node.entity.createdAt,
      updatedAt: DateTime.now(),
      companionId: node.entity.companionId,
      source: node.entity.source,
      tags: node.entity.tags,
      relations: node.entity.relations,
      canvasProps: newProps,
      underlying: node.entity.underlying,
    );

    final updatedNode = OpenCanvasNode.fromCanvasEntry(updatedEntity, newProps,
        isSelected: _state.selectedNodeIds.contains(nodeId));

    _state = _state.copyWith(
      nodes: {..._state.nodes, nodeId: updatedNode},
    );
    notifyListeners();
    CanvasEventBus.instance.emit(CanvasEventType.nodeParamsChanged, nodeId: nodeId, nodeType: nodeType?.name, data: params);
    _schedulePersist();
  }

  // ── 連線操作 ──────────────────────────────────────────

  /// 建立連線
  /// [教練 Agent 2026-08-15 Phase 1] 完整驗證：自連拒絕、型別匹配、循環偵測
  /// 回傳錯誤訊息（null = 成功），讓 UI 層能顯示「為什麼接不上」。
  /// [教練 Agent 2026-08-21] 報錯訊息用人話節點名（不是 ID）
  String _nodeLabel(String nodeId) {
    final n = _state.nodes[nodeId];
    final t = n?.entity.canvasProps?.nodeType;
    return t != null ? '$nodeId($t)' : nodeId;
  }

  Future<String?> connect(String fromNodeId, String fromPortId, String toNodeId, String toPortId) async {
    // 1. 自連拒絕
    if (fromNodeId == toNodeId) {
      return '節點不能連到自己';
    }

    // 2. 節點存在檢查
    final fromNode = _state.nodes[fromNodeId];
    final toNode = _state.nodes[toNodeId];
    if (fromNode == null || toNode == null) {
      return '找不到節點';
    }

    // 3. 型別匹配（isPortTypeMatch 終於被呼叫了）
    // [教練 Agent 2026-08-21 畫布能力修復] port 名驗證＋自動矯正——
    // 舊行為：port 名不存在時靜默跳過檢查、照樣建連線 → DB 有邊、
    // 畫布上 port 不存在線畫不出來 =「agent 說連好了，人卻看不到線」。
    // 修：(a) port 名錯誤 → 自動落到該節點第一個合法 output/input port；
    //     (b) 節點沒有任何 output/input port → 明確報錯。
    var resolvedFromPort = fromPortId;
    var resolvedToPort = toPortId;
    final fromNodeType = _nodeTypeOf(fromNodeId);
    final toNodeType = _nodeTypeOf(toNodeId);
    if (fromNodeType != null && toNodeType != null) {
      final fromPorts = NodeTypePorts.portsFor(fromNodeType);
      final toPorts = NodeTypePorts.portsFor(toNodeType);
      final fromOut = fromPorts.where((p) => p.isOutput).toList();
      final toIn = toPorts.where((p) => !p.isOutput).toList();
      if (fromOut.isEmpty) {
        return '${_nodeLabel(fromNodeId)} 沒有任何輸出 port，不能作為連線來源';
      }
      if (toIn.isEmpty) {
        return '${_nodeLabel(toNodeId)} 沒有任何輸入 port，不能作為連線目標';
      }
      var fromPortDef = fromPorts.where((p) => p.name == fromPortId && p.isOutput).firstOrNull;
      if (fromPortDef == null) {
        resolvedFromPort = fromOut.first.name;
        fromPortDef = fromOut.first;
      }
      var toPortDef = toPorts.where((p) => p.name == toPortId && !p.isOutput).firstOrNull;
      if (toPortDef == null) {
        resolvedToPort = toIn.first.name;
        toPortDef = toIn.first;
      }
      if (!NodeConnection.isPortTypeMatch(fromPortDef.dataType, toPortDef.dataType)) {
        return '${_portTypeLabel(fromPortDef.dataType)} 輸出不能接 ${_portTypeLabel(toPortDef.dataType)} 輸入';
      }
      fromPortId = resolvedFromPort;
      toPortId = resolvedToPort;
    }

    // 4. 循環偵測（to → ... → from 已有路徑 = 接了會成環）
    if (_wouldCreateCycle(fromNodeId, toNodeId)) {
      return '這條線會形成循環（A→B→C→A），工作流必須是單向的';
    }

    // 檢查是否已存在
    if (_state.hasConnection(fromNodeId, fromPortId, toNodeId, toPortId)) return null;

    _pushUndo();

    // [教練 Agent 2026-08-21 使用者回饋] 全面解除單一連入限制——任何 input port
    // 都可接多條線。語意：多源全部匯入（executor 的 UpstreamData 本來
    // 就是收集所有上游：文字合併、圖片取用清單），等同隱式 merge。
    // 原「多源塞同一 input 語意不明」的顧慮在執行層不存在——上游收集
    // 天然支援多源；明確要控制合併順序時再用 merge 節點。
    // （舊行為：新線踢掉舊線，使用者接第二條線時第一條默默消失。）

    final conn = NodeConnection(
      id: NodeConnection.makeId('${fromNodeId}:$fromPortId', '${toNodeId}:$toPortId'),
      fromNodeId: fromNodeId,
      fromPortId: fromPortId,
      toNodeId: toNodeId,
      toPortId: toPortId,
    );

    _state = _state.copyWith(
      connections: [..._state.connections, conn],
    );

    // 持久化為 Entity 關係
    if (_batchMode) {
      _batchRelations.add(EntityRelation(
        sourceId: fromNodeId,
        targetId: toNodeId,
        type: RelationType.depends,
        sourcePort: fromPortId,
        targetPort: toPortId,
      ));
    } else if (_entityGraph != null) {
      await _entityGraph!.addRelation(EntityRelation(
        sourceId: fromNodeId,
        targetId: toNodeId,
        type: RelationType.depends,
        sourcePort: fromPortId,
        targetPort: toPortId,
      ));
    }

    if (!_batchMode) {
      notifyListeners();
      CanvasEventBus.instance.emit(CanvasEventType.connectionAdded, data: {'from': fromNodeId, 'to': toNodeId, 'fromPort': fromPortId, 'toPort': toPortId});
    }
    return null;
  }

  /// [教練 Agent 2026-08-15 Phase 1] 取得節點的 WorkflowNodeType
  WorkflowNodeType? _nodeTypeOf(String nodeId) {
    final node = _state.nodes[nodeId];
    if (node == null) return null;
    return node.entity.canvasProps?.nodeType;
  }

  /// [教練 Agent 2026-08-15 Phase 1] 型別中文名（給錯誤訊息用）
  static String _portTypeLabel(PortDataType type) {
    switch (type) {
      case PortDataType.text:
        return '文字';
      case PortDataType.image:
        return '圖片';
      case PortDataType.audio:
        return '音訊';
      case PortDataType.video:
        return '影片';
      case PortDataType.json:
        return 'JSON';
      case PortDataType.file:
        return '檔案';
      case PortDataType.any:
        return '任意';
    }
  }

  /// [教練 Agent 2026-08-15 Phase 1] 循環偵測：新增 from→to 後，
  /// 若 to 已有路徑能回到 from，就會成環。
  bool _wouldCreateCycle(String fromNodeId, String toNodeId) {
    if (fromNodeId == toNodeId) return true;
    // 從 to 出發 DFS，看能不能走到 from
    final visited = <String>{};
    final stack = <String>[toNodeId];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == fromNodeId) return true;
      if (!visited.add(current)) continue;
      for (final conn in _state.connections) {
        if (conn.fromNodeId == current) {
          stack.add(conn.toNodeId);
        }
      }
    }
    return false;
  }

  /// [教練 Agent 2026-08-15 Phase 1] 從 DB 刪除 relation（fire-and-forget）
  void _removeRelationFromDb(NodeConnection c) {
    final graph = _entityGraph;
    if (graph == null) return;
    // EntityGraphService.removeRelation(sourceId, targetId, type)——沒有 port 參數，
    // 同一對節點若有多條 relation 會一起刪，之後 persist 重建時以 state 為準。
    unawaited(graph.removeRelation(c.fromNodeId, c.toNodeId, RelationType.depends));
  }

  /// 移除連線
  /// [教練 Agent 2026-08-15 Phase 1] 同步刪除 DB relation（修「刪線復活」bug）
  void disconnect(String connectionId) {
    final conn = _state.connections.where((c) => c.id == connectionId).firstOrNull;
    _pushUndo();
    _state = _state.copyWith(
      connections: _state.connections.where((c) => c.id != connectionId).toList(),
    );
    if (conn != null) {
      _removeRelationFromDb(conn);
    }
    notifyListeners();
    CanvasEventBus.instance.emit(CanvasEventType.connectionRemoved, nodeId: connectionId);
  }

  /// 開始連線拖曳
  /// [教練 Agent 2026-08-15 Phase 2.5-C] 從「已連接的 input port」拖出 = 抓住現有連線的尾巴。
  /// [教練 Agent 2026-08-15 使用者回饋修正] 抓 input 端 → 拖曳線就從 input 端長出來
  /// （不是從源頭 output 端）——「抓哪端、哪端跟滑鼠走」。
  /// 放開時：接到新 output → 搬線（換源頭）；放開空白 → 斷線。
  void startConnectionDrag(String nodeId, String portId, bool fromOutput, Offset worldPos) {
    String? detachedConnectionId;
    String dragFromNodeId = nodeId;
    String dragFromPortId = portId;
    bool dragFromOutput = fromOutput;

    // 抓住現有連線：從 input port 拖出且該 port 已有連入
    if (!fromOutput) {
      final existing = _state.connections
          .where((c) => c.toNodeId == nodeId && c.toPortId == portId)
          .firstOrNull;
      if (existing != null) {
        detachedConnectionId = existing.id;
        // 拖曳線保持在 input 端（抓住的那端），方向=true input 端出發
        // 記住原連線供「接到新 output」時換源頭用
        _lastDetachedConnection = existing;
        _state = _state.copyWith(
          connections: _state.connections.where((c) => c.id != existing.id).toList(),
        );
      }
    }

    _state = _state.copyWith(
      dragState: ConnectionDragState(
        fromNodeId: dragFromNodeId,
        fromPortId: dragFromPortId,
        fromOutput: dragFromOutput,
        fromWorldPos: worldPos,
        currentWorldPos: worldPos,
        detachedConnectionId: detachedConnectionId,
      ),
    );
    notifyListeners();
  }

  /// 更新連線拖曳位置
  void updateConnectionDrag(Offset worldPos) {
    if (_state.dragState == null) return;
    _state = _state.copyWith(
      dragState: _state.dragState!.copyWith(currentWorldPos: worldPos),
    );
    notifyListeners();
  }

  /// [教練 Agent 2026-08-15 相容節點快選] 拖線放空處 → 清掉 dragState
  /// 但 UI 保留快選 context（_pendingDrag），等使用者選節點後接線。
  /// 若拖的是「抓住的現有連線」，先還原它（快選取消時線不消失）。
  void cancelDragKeepSearch() {
    final drag = _state.dragState;
    // 還原抓住的連線（如果有的話）
    if (drag?.detachedConnectionId != null && _lastDetachedConnection != null) {
      final restored = _lastDetachedConnection!;
      if (!_state.connections.any((c) => c.id == restored.id)) {
        _state = _state.copyWith(
          connections: [..._state.connections, restored],
        );
      }
    }
    _state = _state.copyWith(clearDragState: true);
    notifyListeners();
  }

  /// 完成連線拖曳
  /// [教練 Agent 2026-08-15 Phase 1] 回傳連線錯誤訊息（null = 成功或無目標），
  /// UI 層（graph_canvas）負責顯示。
  /// [教練 Agent 2026-08-15 Phase 2.5-C] 放開無目標時：
  /// - 一般拖曳 → 取消
  /// - 抓住的現有連線 → 斷線完成（不復原）
  Future<String?> endConnectionDrag(String? toNodeId, String? toPortId) async {
    final drag = _state.dragState;
    if (drag == null) return null;

    String? error;
    bool connected = false;
    if (toNodeId != null && toPortId != null && toNodeId != drag.fromNodeId) {
      if (drag.fromOutput) {
        // output → input
        error = await connect(drag.fromNodeId, drag.fromPortId, toNodeId, toPortId);
        connected = error == null;
      } else {
        // input → output（反方向拖曳）
        error = await connect(toNodeId, toPortId, drag.fromNodeId, drag.fromPortId);
        connected = error == null;
      }
    }

    // [教練 Agent 2026-08-15 Phase 2.5-C] 抓住的連線沒接到新目標 → 正式斷線
    if (drag.detachedConnectionId != null && !connected) {
      // DB relation 同步刪除（state 裡的連線在 startConnectionDrag 已移除）
      final detached = _lastDetachedConnection;
      if (detached != null) {
        _removeRelationFromDb(detached);
      }
      _schedulePersist();
      CanvasEventBus.instance.emit(CanvasEventType.connectionRemoved,
          nodeId: drag.detachedConnectionId, data: {'reason': 'detached'});
    }
    _lastDetachedConnection = null;

    _state = _state.copyWith(clearDragState: true);
    notifyListeners();
    return error;
  }

  // ── 選取 ──────────────────────────────────────────────

  void selectNode(String nodeId, {bool additive = false}) {
    if (additive) {
      _state = _state.copyWith(
        selectedNodeIds: {..._state.selectedNodeIds, nodeId},
      );
    } else {
      _state = _state.copyWith(selectedNodeIds: {nodeId});
    }
    notifyListeners();
  }

  void selectMultiple(Set<String> ids) {
    _state = _state.copyWith(selectedNodeIds: ids);
    notifyListeners();
  }

  /// [教練 Agent 2026-08-15 使用者回饋] 全選——右鍵選單「全選」接線用
  void selectAll() {
    _state = _state.copyWith(selectedNodeIds: _state.nodes.keys.toSet());
    notifyListeners();
  }

  /// [教練 Agent 2026-08-15 使用者回饋] 複製節點——同型別新節點（含參數）在原位置右下
  Future<String?> duplicateNode(String nodeId) async {
    final node = _state.nodes[nodeId];
    if (node == null) return null;
    final props = node.entity.canvasProps;
    if (props?.nodeType == null) return null;

    final newId = await addWorkflowNode(props!.nodeType!, node.position + const Offset(30, 30));
    // 複製參數（保留 label；_last* 是執行殘留不複製）
    final newParams = Map<String, dynamic>.from(props.params)
      ..removeWhere((k, _) => k.startsWith('_last'));
    updateNodeParams(newId, props.nodeType, newParams);
    return newId;
  }

  /// [教練 Agent 2026-07-23] 切換節點選取（Shift+點擊用）
  void toggleNodeSelection(String nodeId) {
    final newSelection = Set<String>.from(_state.selectedNodeIds);
    if (newSelection.contains(nodeId)) {
      newSelection.remove(nodeId);
    } else {
      newSelection.add(nodeId);
    }
    _state = _state.copyWith(selectedNodeIds: newSelection);
    notifyListeners();
  }

  void clearSelection() {
    _state = _state.copyWith(
      selectedNodeIds: {},
      clearEditingNode: true,
    );
    notifyListeners();
  }

  /// [教練 Agent 2026-07-23] 刪除所有選中節點（含相關連線）
  Future<void> removeSelectedNodes() async {
    if (_state.selectedNodeIds.isEmpty) return;

    _pushUndo();

    final idsToRemove = Set<String>.from(_state.selectedNodeIds);

    // 移除相關連線
    final removedConns = _state.connections
        .where((c) => idsToRemove.contains(c.fromNodeId) || idsToRemove.contains(c.toNodeId))
        .toList();
    final remainingConns = _state.connections
        .where((c) => !idsToRemove.contains(c.fromNodeId) && !idsToRemove.contains(c.toNodeId))
        .toList();

    // [教練 Agent 2026-08-15 Phase 2.5-C] 刪節點時同步刪 DB relation（修刪節點後連線復活）
    for (final c in removedConns) {
      _removeRelationFromDb(c);
    }

    // 移除節點
    final remainingNodes = Map<String, OpenCanvasNode>.from(_state.nodes);
    for (final id in idsToRemove) {
      remainingNodes.remove(id);
    }

    // 持久化
    if (_entityGraph != null) {
      for (final id in idsToRemove) {
        // [教練 Agent 2026-08-15 幽靈連線根因] 級聯刪 relations（同 removeNode）
        // [修正] 雙向清——getRelations 出向＋getReverseRelations 入向
        final outRels = await _entityGraph!.getRelations(id);
        final inRels = await _entityGraph!.getReverseRelations(id);
        for (final rel in [...outRels, ...inRels]) {
          await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
        }
        await _entityGraph!.removeFromCanvas(id);
      }
    }

    _state = _state.copyWith(
      nodes: remainingNodes,
      connections: remainingConns,
      selectedNodeIds: {},
      clearEditingNode: _state.editingNodeId != null && idsToRemove.contains(_state.editingNodeId),
    );
    notifyListeners();
    for (final id in idsToRemove) {
      CanvasEventBus.instance.emit(CanvasEventType.nodeRemoved, nodeId: id);
    }
  }

  /// [教練 Agent 2026-07-23] 清空畫布 — 移除所有節點與連線
  Future<void> clearCanvas() async {
    if (_state.nodes.isEmpty && _state.connections.isEmpty) return;

    _pushUndo();

    // 持久化：逐一移除節點
    if (_entityGraph != null) {
      for (final nodeId in _state.nodes.keys.toList()) {
        // [教練 Agent 2026-08-15 幽靈連線根因] 級聯刪 relations（同 removeNode）
        // [修正] 雙向清——getRelations 出向＋getReverseRelations 入向
        final outRels = await _entityGraph!.getRelations(nodeId);
        final inRels = await _entityGraph!.getReverseRelations(nodeId);
        for (final rel in [...outRels, ...inRels]) {
          await _entityGraph!.removeRelation(rel.sourceId, rel.targetId, rel.type);
        }
        await _entityGraph!.removeFromCanvas(nodeId);
      }
    }

    _state = _state.copyWith(
      nodes: {},
      connections: [],
      selectedNodeIds: {},
      clearEditingNode: true,
      clearDragState: true,
    );
    // [教練 Agent 2026-07-25] 清空實際尺寸快取
    ActualSizeCache.clear();
    notifyListeners();
    CanvasEventBus.instance.emit(CanvasEventType.canvasCleared);
  }

  void startEditing(String nodeId) {
    _state = _state.copyWith(editingNodeId: nodeId);
    notifyListeners();
  }

  void stopEditing() {
    _state = _state.copyWith(clearEditingNode: true);
    notifyListeners();
  }

  // ── Viewport ─────────────────────────────────────────

  void pan(Offset delta) {
    _state = _state.copyWith(
      viewport: _state.viewport.copyWith(offset: _state.viewport.offset + delta),
    );
    notifyListeners();
  }

  /// [教練 Agent 2026-07-23] 自動置中並縮放以涵蓋所有節點。
  /// 在畫布載入、新增節點、匯入範本後呼叫。
  ///
  /// [canvasSize] = 畫布可見區域的像素大小。
  /// [padding] = 內容與畫布邊緣的留白（預設 80px）。
  void fitToContent(Size canvasSize, {double padding = 80}) {
    final nodes = _state.nodes.values;
    if (nodes.isEmpty) {
      _state = _state.copyWith(viewport: const CanvasViewport());
      notifyListeners();
      return;
    }

    // [教練 Agent 2026-07-24] context.size 已經是 canvas 區域的實際大小（不含 sidebar/chat panel）
    // 之前錯誤地又扣了 600px，導致 scale 被壓到 0.236，節點全部擠在一起
    final availW = canvasSize.width - padding * 2;
    final availH = canvasSize.height - padding * 2;

    // [教練 Agent 2026-07-24] 按節點類型精確估算渲染尺寸
    // model 的 width/height 是預設 120x70，但 IntrinsicWidth 會根據內容撐開
    // 之前全部估 280x180 導致 bounding box 不準，fitToContent 縮放比例錯誤
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in nodes) {
      final (estW, estH) = node.estimatedRenderSize;
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > node.position.dx + estW ? maxX : node.position.dx + estW;
      maxY = maxY > node.position.dy + estH ? maxY : node.position.dy + estH;
    }

    final contentW = maxX - minX;
    final contentH = maxY - minY;

    // 計算能涵蓋所有內容的 scale — 取 min 確保兩個維度都放得下
    // [教練 Agent 2026-08-15 使用者回饋] 上限 1.0——「縮放至符合」的語意是
    // 「把工作流裝進視野」，不是「縮到越小越好」。內容小於視野時
    // 保持 1.0（不放大），內容大於視野時才縮小。
    double scale = 1.0;
    if (contentW > 0 && contentH > 0) {
      final scaleX = availW / contentW;
      final scaleY = availH / contentH;
      scale = scaleX < scaleY ? scaleX : scaleY;
      scale = scale.clamp(dynamicMinScale, 1.0);
    }

    // 置中：讓 content 中心出現在 canvas 中心
    final contentCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final offset = canvasCenter - contentCenter * scale;

    _state = _state.copyWith(
      viewport: CanvasViewport(offset: offset, scale: scale),
    );
    notifyListeners();
  }

  /// [教練 Agent 2026-07-24] 只置中不縮放 — 保持當前 scale，平移到內容中心
  /// 用於範本載入後：不縮放，讓使用者以 scale=1.0 看到正確的節點間距
  void centerOnContent(Size canvasSize, {double padding = 80}) {
    final nodes = _state.nodes.values;
    if (nodes.isEmpty) {
      _state = _state.copyWith(viewport: const CanvasViewport());
      notifyListeners();
      return;
    }

    // 計算所有節點的 bounding box
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in nodes) {
      final (estW, estH) = node.estimatedRenderSize;
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > node.position.dx + estW ? maxX : node.position.dx + estW;
      maxY = maxY > node.position.dy + estH ? maxY : node.position.dy + estH;
    }

    // 保持當前 scale，只平移到內容中心
    final scale = _state.viewport.scale;
    final contentCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final offset = canvasCenter - contentCenter * scale;

    _state = _state.copyWith(
      viewport: CanvasViewport(offset: offset, scale: scale),
    );
    notifyListeners();
  }

  /// [教練 Agent 2026-07-23] 動態最小縮放 — 根據內容範圍自動放寬下限。
  /// 內容越多越大，允許縮得更遠。
  double get dynamicMinScale {
    final nodes = _state.nodes.values;
    if (nodes.isEmpty) return CanvasViewport.minScale;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in nodes) {
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > node.position.dx + node.width ? maxX : node.position.dx + node.width;
      maxY = maxY > node.position.dy + node.height ? maxY : node.position.dy + node.height;
    }

    final contentW = maxX - minX;
    final contentH = maxY - minY;
    // 如果內容範圍 > 2000px，允許縮到更小
    final maxDim = contentW > contentH ? contentW : contentH;
    if (maxDim > 2000) return 0.05;
    if (maxDim > 1000) return 0.1;
    return CanvasViewport.minScale; // 0.2
  }

  /// [教練 Agent 2026-07-22] Phase C — 平移到指定世界座標
  void panTo(Offset worldPos) {
    // 將世界座標置中：viewport offset = -worldPos + screenCenter/ scale
    // 簡化：直接設 offset 讓目標節點出現在左上象限
    _state = _state.copyWith(
      viewport: _state.viewport.copyWith(offset: -worldPos + const Offset(300, 200)),
    );
    notifyListeners();
  }

  void zoom(double newScale, Offset focalPoint) {
    // [教練 Agent 2026-07-23] 使用動態 minScale，允許內容變大時縮得更遠
    final minScale = dynamicMinScale;
    final clamped = newScale.clamp(minScale, CanvasViewport.maxScale);
    // 以 focalPoint 為中心縮放
    final oldScale = _state.viewport.scale;
    final scaleRatio = clamped / oldScale;
    final newOffset = focalPoint + (_state.viewport.offset - focalPoint) * scaleRatio;

    _state = _state.copyWith(
      viewport: CanvasViewport(offset: newOffset, scale: clamped),
    );
    notifyListeners();
  }

  void resetViewport() {
    _state = _state.copyWith(viewport: const CanvasViewport());
    notifyListeners();
  }

  // ── 工具切換 ──────────────────────────────────────────

  void setTool(CanvasTool2 tool) {
    _state = _state.copyWith(activeTool: tool);
    notifyListeners();
  }

  // ── Port 位置快取 ────────────────────────────────────

  void updatePortPosition(String nodeId, String portId, Offset screenPos) {
    _portPositions['$nodeId:$portId'] = screenPos;
  }

  Offset? getPortPosition(String nodeId, String portId) {
    return _portPositions['$nodeId:$portId'];
  }

  // ── 持久化 ────────────────────────────────────────────

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), _persist);
  }

  Future<void> _persist() async {
    if (_entityGraph == null) return;
    for (final node in _state.nodes.values) {
      final props = node.entity.canvasProps;
      if (props != null) {
        await _entityGraph!.updateCanvasProps(node.id, props);
      }
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    // [教練 Agent 2026-08-15 Phase 1] 完整清理：flush 未持久化的狀態 + 清引用，
    // 防止多畫布切換時寫到舊畫布的 DB。
    _persist();
    _entityGraph = null;
    _canvasId = null;
    super.dispose();
  }

  // ── 人機共視：CanvasSnapshot ──────────────────────────

  /// [教練 Agent 2026-07-24] 生成畫布完整快照 — 讓原生 Agent看到使用者看到的
  ///
  /// 這是人機共視的核心。原生 Agent呼叫此方法後，會得到：
  /// - 每個節點的真實座標和尺寸
  /// - 哪些節點在 viewport 可見範圍內
  /// - 哪些節點互相重疊
  /// - 所有連線的資訊
  ///
  /// 用法：
  ///   final snapshot = controller.getSnapshot(context.size!);
  ///   print(snapshot.toReport());  // 文字報告
  ///   print(snapshot.toJson());    // JSON 格式
  CanvasSnapshot getSnapshot(Size canvasPixelSize) {
    final vp = _state.viewport;
    final nodes = _state.nodes.values.toList();

    // 計算可見範圍（世界座標）
    final visibleRect = Rect.fromLTWH(
      -vp.offset.dx / vp.scale,
      -vp.offset.dy / vp.scale,
      canvasPixelSize.width / vp.scale,
      canvasPixelSize.height / vp.scale,
    );

    // 建立每個節點的 bounds
    final nodeBoundsList = <NodeBounds>[];
    for (final node in nodes) {
      final (w, h) = node.estimatedRenderSize;
      final rect = Rect.fromLTWH(node.position.dx, node.position.dy, w, h);
      final isVisible = rect.overlaps(visibleRect);
      final isFullyVisible = visibleRect.contains(rect.topLeft) &&
          visibleRect.contains(rect.bottomRight);

      nodeBoundsList.add(NodeBounds(
        id: node.id,
        nodeType: node.entity.canvasProps?.nodeType,
        title: node.entity.canvasProps?.nodeType != null
            ? _nodeTypeName(node.entity.canvasProps!.nodeType!)
            : node.entity.title,
        x: node.position.dx,
        y: node.position.dy,
        width: w,
        height: h,
        right: node.position.dx + w,
        bottom: node.position.dy + h,
        isVisible: isVisible,
        isFullyVisible: isFullyVisible,
      ));
    }

    // 偵測重疊
    final overlaps = <OverlapPair>[];
    for (var i = 0; i < nodeBoundsList.length; i++) {
      for (var j = i + 1; j < nodeBoundsList.length; j++) {
        final a = nodeBoundsList[i];
        final b = nodeBoundsList[j];
        final rectA = a.worldRect;
        final rectB = b.worldRect;
        if (rectA.overlaps(rectB)) {
          final overlapRect = rectA.intersect(rectB);
          overlaps.add(OverlapPair(
            a: a,
            b: b,
            overlapWidth: overlapRect.width,
            overlapHeight: overlapRect.height,
            overlapArea: overlapRect.width * overlapRect.height,
          ));
        }
      }
    }

    // 建立連線資訊
    final connectionInfos = _state.connections.map((conn) {
      final fromNode = _state.nodes[conn.fromNodeId];
      final toNode = _state.nodes[conn.toNodeId];
      return ConnectionInfo(
        id: conn.id,
        fromNodeId: conn.fromNodeId,
        fromNodeTitle: fromNode?.entity.canvasProps?.nodeType != null
            ? _nodeTypeName(fromNode!.entity.canvasProps!.nodeType!)
            : fromNode?.entity.title ?? '?',
        fromNodeType: fromNode?.entity.canvasProps?.nodeType?.name ?? '?',
        fromPort: conn.fromPortId,
        toNodeId: conn.toNodeId,
        toNodeTitle: toNode?.entity.canvasProps?.nodeType != null
            ? _nodeTypeName(toNode!.entity.canvasProps!.nodeType!)
            : toNode?.entity.title ?? '?',
        toNodeType: toNode?.entity.canvasProps?.nodeType?.name ?? '?',
        toPort: conn.toPortId,
      );
    }).toList();

    final visible = nodeBoundsList.where((n) => n.isVisible).length;
    final fullyVisible = nodeBoundsList.where((n) => n.isFullyVisible).length;

    return CanvasSnapshot(
      nodes: nodeBoundsList,
      connections: connectionInfos,
      overlaps: overlaps,
      viewport: vp,
      canvasPixelSize: canvasPixelSize,
      visibleRect: visibleRect,
      totalNodes: nodeBoundsList.length,
      visibleNodes: visible,
      fullyVisibleNodes: fullyVisible,
      hiddenNodes: nodeBoundsList.length - visible,
      totalConnections: connectionInfos.length,
      overlapCount: overlaps.length,
    );
  }

  /// [教練 Agent 2026-07-24] 把 snapshot 寫到桌面文件（debug + 未來原生 Agent可用）
  Future<void> writeSnapshotToFile(Size canvasPixelSize) async {
    final snapshot = getSnapshot(canvasPixelSize);
    final home = Platform.environment['HOME']!;
    final f = File('$home/Desktop/bridge_snapshot.txt');
    await f.writeAsString(snapshot.toReport());
  }
}

/// [教練 Agent 2026-07-24] 節點類型中文名稱（controller 內部用）
String _nodeTypeName(WorkflowNodeType type) {
  return switch (type) {
    WorkflowNodeType.input => '輸入',
    WorkflowNodeType.llm => 'LLM推論',
    WorkflowNodeType.tool => '工具',
    WorkflowNodeType.imageGen => '圖片生成',
    WorkflowNodeType.vision => '視覺分析',
    WorkflowNodeType.characterLock => '角色鎖定',
    WorkflowNodeType.videoGen => '影片生成',
    WorkflowNodeType.musicGen => '音樂生成',
    WorkflowNodeType.tts => '語音合成',
    WorkflowNodeType.move => '招式', // [Blue 拍板]
    WorkflowNodeType.condition => '條件分支',
    WorkflowNodeType.merge => '合併',
    WorkflowNodeType.output => '輸出',
    WorkflowNodeType.subWorkflow => '子工作流',
    WorkflowNodeType.schedule => '排程',
    WorkflowNodeType.knowledge => 'Vault知識', // [教練 Agent 2026-08-16]
    WorkflowNodeType.materialPool => '素材池', // [教練 Agent 2026-08-25 F-1]
  };
}
