// canvas_snapshot_service.dart
// [教練 Agent 2026-07-22] Phase A — 畫布狀態快照服務
//
// 核心理念：畫布是 Agent 的主場。Agent 不靠截圖看畫布——靠結構化資料。
// 快照服務維護一個 always-updated 的 JSON，描述畫布的完整狀態。
//
// 三個職責：
// 1. 生成完整快照（載入時全量注入）
// 2. 生成拓撲分析（entryPoints/exitPoints/chains/orphans）
// 3. 生成變更描述（增量注入用）
//
// 快照 ≠ 截圖。快照是結構化的 JSON，Agent 讀 JSON 比讀圖快 100 倍。

import 'dart:async';

import 'package:bridge_app/services/vault/canvas_event_bus.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';

/// 畫布狀態快照服務
///
/// 單例。監聽 CanvasEventBus 事件，維護最新快照。
/// 提供 generateSnapshot()、analyzeTopology()、describeChange()、describeFullState()。
class CanvasSnapshotService {
  CanvasSnapshotService._();
  static final CanvasSnapshotService instance = CanvasSnapshotService._();

  StreamSubscription<CanvasEvent>? _eventSub;
  CanvasController? _controller;
  String? _canvasId;

  /// 當前快照（null = 畫布未初始化）
  Map<String, dynamic>? _snapshot;

  /// 最後一次變更描述（給 Agent 增量注入用）
  String? _lastChangeDescription;

  /// 注入回呼——由 ChatController 注入，把畫布狀態推進 Agent 對話
  void Function(String description, {required bool isFull})? onInject;

  /// debounce 計時器（避免拖曳時瘋狂更新）
  Timer? _debounceTimer;

  /// token 預算控制——10 秒內超過 5 次注入切靜默模式
  final List<DateTime> _injectHistory = [];
  bool _silentMode = false;
  Timer? _silentTimer;

  /// 連接畫布控制器
  void attach(CanvasController controller, {String? canvasId}) {
    _controller = controller;
    _canvasId = canvasId;
    _startListening();
  }

  /// 斷開連接
  void detach() {
    _eventSub?.cancel();
    _eventSub = null;
    _debounceTimer?.cancel();
    _silentTimer?.cancel();
    _controller = null;
    _snapshot = null;
    _lastChangeDescription = null;
  }

  void _startListening() {
    _eventSub?.cancel();
    _eventSub = CanvasEventBus.instance.stream.listen(_onCanvasEvent);
  }

  void _onCanvasEvent(CanvasEvent event) {
    switch (event.type) {
      case CanvasEventType.canvasLoaded:
        // 載入畫布 → 生成完整快照 → 全量注入
        _canvasId = event.data?['canvasId'] as String?;
        _refreshSnapshot();
        final desc = describeFullState();
        _inject(desc, isFull: true);
        break;

      case CanvasEventType.nodeAdded:
      case CanvasEventType.nodeRemoved:
      case CanvasEventType.connectionAdded:
      case CanvasEventType.connectionRemoved:
      case CanvasEventType.canvasCleared:
        // 結構性變化 → debounce 後增量注入
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          _refreshSnapshot();
          final desc = describeChange(event);
          _inject(desc, isFull: false);
        });
        break;

      case CanvasEventType.nodeParamsChanged:
        // 參數變化 → 更新快照但不注入（太頻繁）
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 800), () {
          _refreshSnapshot();
        });
        break;

      default:
        // nodeMoved, nodeSelected, toolChanged, doodleAdded → 不處理
        break;
    }
  }

  // ── 快照生成 ──────────────────────────────────────────

  /// 生成完整快照
  Map<String, dynamic> generateSnapshot() {
    final ctrl = _controller;
    if (ctrl == null) {
      return {'error': 'Canvas not attached', 'canvasConnected': false};
    }
    final state = ctrl.state;
    final nodes = state.nodes.values.toList();
    final connections = state.connections.toList();

    return {
      'canvasId': _canvasId,
      'timestamp': DateTime.now().toIso8601String(),
      'summary': {
        'nodeCount': nodes.length,
        'connectionCount': connections.length,
        'selectedNodeIds': state.selectedNodeIds.toList(),
        'activeTool': state.activeTool.name,
      },
      'nodes': nodes.map((n) {
        final props = n.entity.canvasProps;
        return {
          'id': n.id,
          'label': props?.nodeType != null
              ? _nodeTypeLabel(props!.nodeType!)
              : n.entity.title,
          'type': n.entity.type.name,
          'nodeType': props?.nodeType?.name,
          'position': {'x': n.position.dx.round(), 'y': n.position.dy.round()},
          'params': props?.params ?? {},
          'ports': (props?.ports ?? []).map((p) => {
            'name': p.name,
            'isOutput': p.isOutput,
          }).toList(),
          'visualState': props?.visualState.name ?? 'idle',
          'isSelected': state.selectedNodeIds.contains(n.id),
        };
      }).toList(),
      'connections': connections.map((c) => {
        'id': c.id,
        'from': {'nodeId': c.fromNodeId, 'port': c.fromPortId},
        'to': {'nodeId': c.toNodeId, 'port': c.toPortId},
      }).toList(),
      'topology': analyzeTopology(nodes, connections),
      'canvasConnected': true,
    };
  }

  /// 拓撲分析——Agent 的「結構化視覺」
  ///
  /// 不用看圖就知道：工作流從哪開始、到哪結束、有沒有斷線、有沒有孤兒節點。
  Map<String, dynamic> analyzeTopology([
    List? nodesList,
    List? connectionsList,
  ]) {
    final ctrl = _controller;
    if (ctrl == null) return {};

    final nodes = nodesList ?? ctrl.state.nodes.values.toList();
    final connections = connectionsList ?? ctrl.state.connections.toList();

    if (nodes.isEmpty) return {};

    // 建立鄰接表
    final hasInput = <String, bool>{}; // nodeId → 是否有 input 連線
    final hasOutput = <String, bool>{};
    final outgoing = <String, List<String>>{}; // nodeId → 下游 nodes
    final incoming = <String, List<String>>{};

    for (final n in nodes) {
      hasInput[n.id] = false;
      hasOutput[n.id] = false;
      outgoing[n.id] = [];
      incoming[n.id] = [];
    }

    for (final c in connections) {
      hasInput[c.toNodeId] = true;
      hasOutput[c.fromNodeId] = true;
      outgoing[c.fromNodeId]?.add(c.toNodeId);
      incoming[c.toNodeId]?.add(c.fromNodeId);
    }

    // entry points：沒有 input 連線的節點
    final entryPoints = nodes.where((n) => !hasInput[n.id]!).map((n) => n.id).toList();

    // exit points：沒有 output 連線的節點
    final exitPoints = nodes.where((n) => !hasOutput[n.id]!).map((n) => n.id).toList();

    // orphan nodes：完全沒有連線的節點
    final orphans = nodes.where((n) => !hasInput[n.id]! && !hasOutput[n.id]!).map((n) => n.id).toList();

    // 鏈：從 entry 到 exit 的路徑（DFS，最多 20 層防循環）
    final chains = <List<String>>[];
    final exitSet = exitPoints.map((e) => e.toString()).toSet();
    for (final entry in entryPoints) {
      _findChains(entry.toString(), [], outgoing, chains, exitSet);
    }

    // 斷連 port：有 input port 但沒連線的節點
    final disconnectedInputs = <Map<String, dynamic>>[];
    for (final n in nodes) {
      final props = n.entity.canvasProps;
      final inputPorts = (props?.ports ?? []).where((p) => !p.isOutput);
      if (inputPorts.isNotEmpty && !hasInput[n.id]!) {
        disconnectedInputs.add({'nodeId': n.id, 'label': _nodeTypeLabel(props!.nodeType!)});
      }
    }

    return {
      'entryPoints': entryPoints,
      'exitPoints': exitPoints,
      'chains': chains,
      'orphanNodes': orphans,
      'disconnectedInputs': disconnectedInputs,
    };
  }

  void _findChains(
    String current,
    List<String> path,
    Map<String, List<String>> outgoing,
    List<List<String>> chains,
    Set<String> exitPoints, {
    int depth = 0,
  }) {
    if (depth > 20) return; // 防循環

    final newPath = [...path, current];

    if (exitPoints.contains(current) && path.isNotEmpty) {
      chains.add(newPath);
    }

    final next = outgoing[current] ?? [];
    if (next.isEmpty && path.isNotEmpty) {
      chains.add(newPath);
    }

    for (final n in next) {
      _findChains(n, newPath, outgoing, chains, exitPoints, depth: depth + 1);
    }
  }

  // ── 描述生成（給 Agent 的文字）──────────────────────────

  /// 全量描述——載入畫布時用
  String describeFullState() {
    _refreshSnapshot();
    final s = _snapshot;
    if (s == null || s['canvasConnected'] != true) {
      return '畫布狀態：未連接';
    }

    final summary = s['summary'] as Map<String, dynamic>;
    final nodeCount = summary['nodeCount'] as int;
    final connCount = summary['connectionCount'] as int;
    final topology = s['topology'] as Map<String, dynamic>? ?? {};

    final parts = <String>[];
    parts.add('畫布狀態快照：$nodeCount 個節點 · $connCount 條連線');

    if (nodeCount == 0) {
      parts.add('畫布為空。');
      return parts.join('\n');
    }

    // 節點列表
    final nodes = s['nodes'] as List;
    final nodeLines = nodes.map((n) {
      final m = n as Map<String, dynamic>;
      final label = m['label'] ?? m['type'];
      final id = m['id'];
      final selected = m['isSelected'] == true ? ' [已選取]' : '';
      return '  - $id: $label$selected';
    }).join('\n');
    parts.add('節點：\n$nodeLines');

    // 連線列表
    if (connCount > 0) {
      final conns = s['connections'] as List;
      final connLines = conns.map((c) {
        final m = c as Map<String, dynamic>;
        final from = (m['from'] as Map)['nodeId'];
        final to = (m['to'] as Map)['nodeId'];
        return '  - $from → $to';
      }).join('\n');
      parts.add('連線：\n$connLines');
    }

    // 拓撲分析
    final entryPoints = topology['entryPoints'] as List? ?? [];
    final exitPoints = topology['exitPoints'] as List? ?? [];
    final orphans = topology['orphanNodes'] as List? ?? [];
    final chains = topology['chains'] as List? ?? [];
    final disconnected = topology['disconnectedInputs'] as List? ?? [];

    if (entryPoints.isNotEmpty || exitPoints.isNotEmpty) {
      parts.add('入口：${entryPoints.join(', ')}');
      parts.add('出口：${exitPoints.join(', ')}');
    }

    if (chains.isNotEmpty) {
      final chainDesc = chains.take(5).map((c) {
        final list = c as List;
        return list.join(' → ');
      }).join(' | ');
      parts.add('流程：$chainDesc');
    }

    // 結構問題
    final issues = <String>[];
    if (orphans.isNotEmpty) {
      issues.add('未連接的孤立節點：${orphans.join(', ')}');
    }
    if (disconnected.isNotEmpty) {
      final labels = disconnected.map((d) => (d as Map)['label']).join(', ');
      issues.add('有輸入端口未連接：$labels');
    }
    if (issues.isNotEmpty) {
      parts.add('注意：${issues.join('；')}');
    } else if (nodeCount > 0 && connCount > 0) {
      parts.add('狀態：結構完整');
    }

    return parts.join('\n');
  }

  /// 變更描述——增量注入用
  String describeChange(CanvasEvent event) {
    _refreshSnapshot();
    final s = _snapshot;
    if (s == null) return '';

    final summary = s['summary'] as Map<String, dynamic>;
    final nodeCount = summary['nodeCount'] as int;
    final connCount = summary['connectionCount'] as int;

    final parts = <String>[];

    // [小葵 2026-09-16 Blue 令] 人稱分流——agent 工具入口操作前會 mark，
    // 這裡 consume：是 agent 做的就說「你（小橋）」，使用者做的才說「使用者」。
    // 病例：小橋在 chat 頁建了排程節點 → canvas 頁事件卻說「使用者新增」，
    // 小橋自己都不認得自己的作品（「兩個小橋」問題）。
    final actor = CanvasMcpRegistry.instance.consumeLastActorIsAgent()
        ? '你（小橋）'
        : '使用者';

    switch (event.type) {
      case CanvasEventType.nodeAdded:
        parts.add('$actor新增了 ${event.nodeType ?? '節點'}（${event.nodeId}）');
        break;
      case CanvasEventType.nodeRemoved:
        parts.add('$actor刪除了節點（${event.nodeId ?? '?'}）');
        break;
      case CanvasEventType.connectionAdded:
        final d = event.data ?? {};
        parts.add('$actor建立了連線：${d['from'] ?? '?'} → ${d['to'] ?? '?'}');
        break;
      case CanvasEventType.connectionRemoved:
        parts.add('$actor移除了連線（${event.nodeId ?? '?'}）');
        break;
      case CanvasEventType.canvasCleared:
        parts.add('$actor清空了畫布');
        break;
      default:
        return '';
    }

    parts.add('目前畫布：$nodeCount 節點 · $connCount 連線');

    // 結構問題提醒
    final topology = s['topology'] as Map<String, dynamic>? ?? {};
    final orphans = topology['orphanNodes'] as List? ?? [];
    final disconnected = topology['disconnectedInputs'] as List? ?? [];

    if (orphans.isNotEmpty && event.type == CanvasEventType.nodeAdded) {
      parts.add('注意：新節點尚未連接');
    }
    if (disconnected.isNotEmpty && event.type == CanvasEventType.nodeRemoved) {
      parts.add('注意：有節點的輸入端因刪除而懸空');
    }

    _lastChangeDescription = parts.join('\n');
    return _lastChangeDescription!;
  }

  // ── 內部方法 ──────────────────────────────────────────

  void _refreshSnapshot() {
    _snapshot = generateSnapshot();
  }

  void _inject(String description, {required bool isFull}) {
    if (onInject == null) return;

    // token 預算控制
    final now = DateTime.now();
    _injectHistory.removeWhere((t) => now.difference(t).inSeconds > 10);

    if (_injectHistory.length >= 5) {
      if (!_silentMode) {
        _silentMode = true;
        _silentTimer?.cancel();
        _silentTimer = Timer(const Duration(seconds: 3), () {
          _silentMode = false;
          // 靜默結束後注入一次摘要
          _refreshSnapshot();
          onInject?.call(describeFullState(), isFull: true);
        });
      }
      return; // 靜默模式下不注入
    }

    _injectHistory.add(now);
    onInject?.call(description, isFull: isFull);
  }

  String _nodeTypeLabel(dynamic nodeType) {
    return nodeType.toString().split('.').last;
  }

  /// 取得當前快照 JSON（給 Agent canvas_get_state_snapshot 工具用）
  Map<String, dynamic> get currentSnapshot => _snapshot ?? generateSnapshot();
}
