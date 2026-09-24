// graph_canvas.dart
// 畫布渲染核心 — RenderObject 層，負責背景網格、節點定位、連線繪製、手勢處理。
// 建立日期: 2026-07-15
// 參考: graph_edit GraphCanvasInternalRenderObject + LiteGraph LGraphCanvas
//
// 設計:
// - 用 CustomPaint + Stack 組合，不用 MultiChildRenderObject（簡化實作）
// - 背景 CustomPaint 畫網格 + 連線
// - 節點用 Positioned + NodeWidget
// - 手勢由 GestureDetector 統一處理

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // [教練 Agent 2026-07-23] HardwareKeyboard
import 'package:cross_file/cross_file.dart'; // [教練 Agent 2026-08-16] XFile — Finder 拖放
import 'package:desktop_drop/desktop_drop.dart'; // [教練 Agent 2026-08-16] Finder 拖放
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/widgets/canvas/v2/port_widget.dart';
import 'canvas_controller.dart';
import 'canvas_state.dart';
import 'connection_curve.dart';
import 'node_connection.dart';
import 'node_search_box.dart';
import '../../../theme/bridge_design_system.dart';
import '../../../theme/tier.dart'; // [教練 Agent 2026-08-16] Tier — 拖放提示文字
import '../../../theme/tier_style.dart'; // [教練 Agent 2026-08-16] TierStyle — 拖放提示文字

/// 畫布主視窗 — 整合背景渲染 + 節點 + 連線 + 手勢。
class GraphCanvas extends StatefulWidget {
  final CanvasController controller;

  /// NodeWidget builder（由 parent 提供，避免循環依賴）
  final Widget Function(BuildContext context, OpenCanvasNode node, CanvasController controller) nodeBuilder;

  /// 雙擊空白處新增節點的回調
  final void Function(Offset screenPos, Offset worldPos)? onDoubleTapEmpty;

  /// 點擊節點的回調（用於開啟參數面板）
  final void Function(String nodeId)? onNodeDoubleTap;

  /// [教練 Agent 2026-08-15 使用者 提案] 單節點執行回調（右鍵選單「執行此節點」）
  final Future<void> Function(String nodeId)? onNodeExecute;

  /// [教練 Agent 2026-08-16 使用者 提案] Finder 拖檔進畫布——
  /// 於 drop 位置建對應節點（圖→vision 輸入、文字→input）。
  /// null = 不啟用拖放。
  final void Function(List<XFile> files, Offset screenPos)? onFilesDropped;

  const GraphCanvas({
    super.key,
    required this.controller,
    required this.nodeBuilder,
    this.onDoubleTapEmpty,
    this.onNodeDoubleTap,
    /// [教練 Agent 2026-08-15 使用者 提案] 單節點執行——從右鍵選單觸發
    this.onNodeExecute,
    this.onFilesDropped,
  });

  @override
  State<GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<GraphCanvas> {
  /// 連線拖曳中追蹤的目標 port（滑鼠 hover 到的 input port）
  String? _hoveredPort;

  /// [教練 Agent 2026-08-16 使用者 提案] Finder 拖檔懸停中——顯示藍色 overlay
  bool _fileDragHovering = false;

  /// 雙擊偵測
  final _doubleTapTracker = <DateTime>[];
  Offset? _lastTapPos;

  /// NodeSearchBox 顯示狀態
  bool _showSearchBox = false;
  Offset _searchBoxPos = Offset.zero;
  Offset _searchBoxWorldPos = Offset.zero;

  /// [教練 Agent 2026-08-02] Context menu 顯示狀態
  OverlayEntry? _contextMenuEntry;

  /// [教練 Agent 2026-07-23] Port 位置更新 — 已於 2026-08-15 移除條件式快取
  /// （_lastVpOffset/_lastVpScale/_lastNodeCount/_nodePositionsHash）：
  /// 那個最佳化造成 port 座標 stale，連線端點畫在舊位置。
  Offset? _lastVpOffset;
  double? _lastVpScale;
  int _lastNodeCount = -1;
  int _nodePositionsHash = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // [教練 Agent 2026-08-15 使用者 提案] Cmd+C/Cmd+V 快捷鍵——多選複製貼上
    HardwareKeyboard.instance.addHandler(_onKeyCombo);
    // 首次 build 後更新 port 位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePortPositions();
    });
  }

  /// [教練 Agent 2026-08-15 使用者 提案] Cmd+C 複製選中節點（多選支援）／
  /// Cmd+V 貼上到視野中心。與右鍵「複製」同機制（立即建節點）。
  bool _onKeyCombo(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isCmd = pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    if (!isCmd) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      final ids = widget.controller.state.selectedNodeIds;
      if (ids.isEmpty) return false;
      // 複製每個選中節點（多選全複製）
      for (final id in ids) {
        widget.controller.duplicateNode(id);
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      // 貼上＝無操作（複製已立即建節點）；預留未來真正的剪貼簿
      return false;
    }
    return false;
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});

    // [教練 Agent 2026-08-15 修復] 永遠在下一幀重算 port 位置。
    // 舊的「只有 viewport/節點數/位置變才重算」最佳化是 stale 來源：
    // 節點載入內容後「尺寸」改變（圖片/文字非同步載入）→ port 移位，
    // 快取沒更新 → 連線端點畫在舊位置（節點邊緣任意點）。
    // _updatePortPositions 內建 0.5px 門檻，位置沒變就不 setState，無回圈。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePortPositions();
    });
  }

  /// 快速計算所有節點位置的 hash，用於判斷是否需要更新 port 位置
  int _computeNodePositionsHash(Map<String, OpenCanvasNode> nodes) {
    int hash = 0;
    for (final node in nodes.values) {
      hash ^= node.position.dx.hashCode ^ node.position.dy.hashCode;
    }
    return hash;
  }

  /// 走訪 RenderObject 樹，找出所有 PortMetadata 標記的 port，
  /// 更新它們的座標到 controller 的 portPositions map。
  ///
  /// [教練 Agent 2026-07-20 修復] 原本用 localToGlobal 存全螢幕座標，
  /// 但 _CanvasBackgroundPainter 在 GraphCanvas 本地座標系統裡畫連線，
  /// 視窗不在 (0,0) 時連線會偏移。改存 canvas 本地座標。
  void _updatePortPositions() {
    if (!mounted) return;
    final canvasRo = context.findRenderObject();
    if (canvasRo == null) return;
    _visitPorts(canvasRo, canvasRo);
    // [教練 Agent 2026-07-23] 只在 port 位置實際變化時才觸發重繪，避免多餘重建
    if (mounted && _portPositionsChanged) {
      _portPositionsChanged = false;
      setState(() {});
    }
  }

  /// port 位置是否有變化的旗標（由 _visitPorts 設定）
  bool _portPositionsChanged = false;

  void _visitPorts(RenderObject canvasRo, RenderObject ro) {
    // [教練 Agent 2026-08-15 統一錨點] 先遞迴子節點、再寫入自己——
    // PortWidget 的圓點（內層 MetaData）會覆蓋 port 列（外層 MetaData），
    // 保證連線錨點 = 圓點中心（不是含標籤的列中心）。
    ro.visitChildren((child) => _visitPorts(canvasRo, child));
    if (ro is RenderMetaData) {
      final meta = ro.metaData;
      if (meta is PortMetadata && ro.hasSize) {
        // 先轉全螢幕，再轉回 canvas 本地——跨 RenderObject 樹的標準做法
        final globalCenter = ro.localToGlobal(ro.size.center(Offset.zero));
        // canvasRo 是 GraphCanvas 的 RenderObject，需要 RenderBox 介面
        final canvasBox = canvasRo as RenderBox;
        final localCenter = canvasBox.globalToLocal(globalCenter);
        final key = '${meta.nodeId}:${meta.portName}';
        final old = widget.controller.portPositions[key];
        // [教練 Agent 2026-07-23] 只在位置真正變化時更新+標記
        if (old == null || (old - localCenter).distance > 0.5) {
          widget.controller.updatePortPosition(meta.nodeId, meta.portName, localCenter);
          _portPositionsChanged = true;
        }
      }
    }
  }

  @override
  void didUpdateWidget(GraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    HardwareKeyboard.instance.removeHandler(_onKeyCombo); // [教練 Agent 2026-08-15] 快捷鍵清理
    _hideContextMenu(); // [教練 Agent 2026-08-02] 清理 context menu
    super.dispose();
  }

  // ── 座標轉換 ──────────────────────────────────────────

  Offset _screenToWorld(Offset screen) {
    return widget.controller.state.viewport.screenToWorld(screen);
  }

  Offset _worldToScreen(Offset world) {
    return widget.controller.state.viewport.worldToScreen(world);
  }

  // ── 手勢處理 ──────────────────────────────────────────
  //
  // [教練 Agent 2026-07-23] 手勢重新設計：
  // - 左鍵拖曳空白 = 框選節點
  // - 中鍵拖曳 = 平移畫布
  // - Shift+點擊節點 = 增減選取
  // - 左鍵點擊節點 = 單選
  // - 左鍵拖曳節點 = 移動節點

  /// 框選起點（螢幕座標），null = 不在框選中
  Offset? _boxSelectStart;

  /// 框選目前位置（螢幕座標）
  Offset _boxSelectCurrent = Offset.zero;

  /// [教練 Agent 2026-07-24] 節點拖曳絕對位置追蹤 — 避免增量累積誤差
  Offset? _nodeDragStartWorld;
  Offset? _nodeDragStartPos;

  /// 是否正在用中鍵平移
  bool _isMiddleButtonPan = false;
  // [教練 Agent 2026-08-16 使用者 提案] 中鍵雙擊偵測——時間戳＋位置
  DateTime? _lastMiddleDown;
  Offset _lastMiddlePos = Offset.zero;

  /// 中鍵平移 — 上一幀位置，用於計算 delta
  Offset _lastPanPos = Offset.zero;

  /// 框選前的選取快照（用於 Shift+框選累加）
  Set<String>? _preBoxSelectIds;

  /// 是否正在左鍵框選（由 Listener 驅動，不靠 GestureDetector）
  bool _isBoxSelecting = false;

  /// [教練 Agent 2026-08-15] 按下點是否在 port 上——
  /// port 上按下 = 絕對是拉線（使用者鐵則：「不要懷疑他」），
  /// 節點拖曳看到此旗標必須讓路。
  bool _pointerStartedOnPort = false;

  /// [教練 Agent 2026-08-15] port 幾何命中（canvas 本地座標，半徑 24px≈放大後的圓點+padding）
  /// [教練 Agent 2026-08-15] 平手時優先「已連線的 input port」——
  /// 拔線是高頻操作，不能被鄰近 output 搶走命中（使用者回報：想拔線長出新線）。
  (String, String, bool)? _hitTestPort(Offset screenPos) {
    final portPositions = widget.controller.portPositions;
    final connections = widget.controller.state.connections;
    String? bestKey;
    double bestDist = double.infinity;
    bool bestIsConnectedInput = false;
    for (final entry in portPositions.entries) {
      final d = (entry.value - screenPos).distance;
      if (d >= 24) continue;
      final idx = entry.key.indexOf(':');
      final nodeId = entry.key.substring(0, idx);
      final portName = entry.key.substring(idx + 1);
      final node = widget.controller.state.nodes[nodeId];
      final portDef = node?.entity.canvasProps?.ports
          .where((p) => p.name == portName)
          .firstOrNull;
      if (portDef == null) continue;
      final isConnectedInput = !portDef.isOutput &&
          connections.any((c) => c.toNodeId == nodeId && c.toPortId == portName);
      if (bestKey == null) {
        bestKey = entry.key;
        bestDist = d;
        bestIsConnectedInput = isConnectedInput;
        continue;
      }
      // 距離明顯較近（>4px）者贏；平手時已連線 input 優先（拔線高頻，不可被搶）
      final clearlyCloser = d < bestDist - 4;
      final tieBreakConnected = (bestDist - d).abs() <= 4 &&
          isConnectedInput && !bestIsConnectedInput;
      if (clearlyCloser || tieBreakConnected) {
        bestKey = entry.key;
        bestDist = d;
        bestIsConnectedInput = isConnectedInput;
      }
    }
    if (bestKey == null) return null;
    final idx = bestKey.indexOf(':');
    final nodeId = bestKey.substring(0, idx);
    final portName = bestKey.substring(idx + 1);
    final node = widget.controller.state.nodes[nodeId];
    final portDef = node?.entity.canvasProps?.ports
        .where((p) => p.name == portName)
        .firstOrNull;
    if (portDef == null) return null;
    // [教練 Agent 2026-08-15 修復] fromOutput = portDef.isOutput（之前寫反成 !isOutput，
    // 導致按 input port 被當成從 output 拉新線——拔線永遠觸發不了、
    // 還長出一堆垃圾連線堆在 input 上）。
    return (nodeId, portName, portDef.isOutput);
  }

  /// [教練 Agent 2026-08-15 使用者 提案：hover 線變胖 + 抓線頭拔線]
  /// 命中測試：座標是否在某條連線附近。回傳 (連線, 在線上的位置 t)。
  (NodeConnection, double)? _hitTestConnection(Offset screenPos) {
    NodeConnection? best;
    double bestT = 0;
    double bestDist = double.infinity;
    final vp = widget.controller.state.viewport;
    for (final conn in widget.controller.state.connections) {
      final fromPos = widget.controller.portPositions['${conn.fromNodeId}:${conn.fromPortId}'];
      final toPos = widget.controller.portPositions['${conn.toNodeId}:${conn.toPortId}'];
      if (fromPos == null || toPos == null) continue;
      final curve = ConnectionCurve(start: fromPos, end: toPos);
      final metric = curve.buildPath().computeMetrics().first;
      const step = 8.0;
      for (double t = 0; t <= metric.length; t += step) {
        final tangent = metric.getTangentForOffset(t);
        if (tangent == null) continue;
        final d = (tangent.position - screenPos).distance;
        if (d < bestDist) {
          bestDist = d;
          best = conn;
          bestT = t / metric.length;
        }
      }
    }
    // 容差 10px（= hover 變胖後的線寬一半＋光暈），且不可比 port 命中（24px）先搶
    if (best == null || bestDist > 10) return null;
    // 命中的必須是「靠近 input 端的那半段」（t < 0.5 = 靠 input）——
    // output 端的線留給拉新線/不做互動，避免誤抓
    if (bestT > 0.6) return null;
    return (best, bestT);
  }

  /// [教練 Agent 2026-08-15 使用者 提案] 目前 hover 的連線 ID（線變胖用）
  String? _hoveredConnectionId;

  /// [教練 Agent 2026-08-15 相容節點快選] 拖線放空處保留的拖曳 context
  ConnectionDragState? _pendingDrag;

  /// 這次拖線是「從 port 拉出」的（雙擊空白也會用 searchBox，要區分）
  bool _isDragFromPort = false;

  /// [教練 Agent 2026-08-15] 背景網格 CustomPaint 的 key——滾輪命中測試用
  final GlobalKey _backgroundKey = GlobalKey();

  /// hover 偵測：滑鼠在線附近 → 記住 ID 觸發變胖
  void _updateConnectionHover(Offset screenPos) {
    final hit = _hitTestConnection(screenPos);
    final newId = hit?.$1.id;
    if (newId != _hoveredConnectionId) {
      setState(() => _hoveredConnectionId = newId);
    }
  }

  // ── [教練 Agent 2026-08-15 相容節點快選] helpers ──────────────

  /// 拖曳源 port 的資料型別
  PortDataType? _dragSourceType() {
    final drag = _pendingDrag;
    if (drag == null) return null;
    final node = widget.controller.state.nodes[drag.fromNodeId];
    final portDef = node?.entity.canvasProps?.ports
        .where((p) => p.name == drag.fromPortId)
        .firstOrNull;
    return portDef?.dataType;
  }

  /// 節點類型與拖曳源相容？（有任一 port 能接）
  bool _isTypeCompatibleWithDrag(WorkflowNodeType type) {
    final sourceType = _dragSourceType();
    if (sourceType == null) return true;
    final ports = NodeTypePorts.portsFor(type);
    if (_pendingDrag!.fromOutput) {
      // 找新節點的 input port 相容源型別
      return ports.any((p) => !p.isOutput && NodeConnection.isPortTypeMatch(sourceType, p.dataType));
    } else {
      // 找新節點的 output port 相容源的 input
      return ports.any((p) => p.isOutput && NodeConnection.isPortTypeMatch(p.dataType, sourceType));
    }
  }

  /// 快選提示文字
  String _dragFilterHint() {
    final t = _dragSourceType();
    final label = t == null ? '' : _portTypeLabelOf(t);
    return '接住「$label」${_pendingDrag!.fromOutput ? '輸出' : '輸入'}—只列相容節點';
  }

  String _portTypeLabelOf(PortDataType dataType) {
    switch (dataType) {
      case PortDataType.text: return '文字';
      case PortDataType.image: return '圖片';
      case PortDataType.audio: return '音訊';
      case PortDataType.video: return '影片';
      case PortDataType.json: return 'JSON';
      case PortDataType.file: return '檔案';
      default: return '任意';
    }
  }

  /// 新節點第一個相容 input port（output 拖曳用）
  String? _firstCompatibleInput(String nodeId, ConnectionDragState drag) {
    final node = widget.controller.state.nodes[nodeId];
    final ports = node?.entity.canvasProps?.ports ?? [];
    final sourceType = _dragSourceType();
    if (sourceType == null) return ports.where((p) => !p.isOutput).firstOrNull?.name;
    return ports
        .where((p) => !p.isOutput && NodeConnection.isPortTypeMatch(sourceType, p.dataType))
        .firstOrNull
        ?.name;
  }

  /// 新節點第一個相容 output port（input 反向拖曳用）
  String? _firstCompatibleOutput(String nodeId, ConnectionDragState drag) {
    final node = widget.controller.state.nodes[nodeId];
    final ports = node?.entity.canvasProps?.ports ?? [];
    final sourceType = _dragSourceType();
    if (sourceType == null) return ports.where((p) => p.isOutput).firstOrNull?.name;
    return ports
        .where((p) => p.isOutput && NodeConnection.isPortTypeMatch(p.dataType, sourceType))
        .firstOrNull
        ?.name;
  }

  void _onPointerDown(PointerDownEvent event) {
    // [教練 Agent 2026-08-15] 中鍵永遠先處理 — 不被 dragState 絆住
    if (event.buttons == kMiddleMouseButton) {
      // [教練 Agent 2026-08-16 使用者 提案] 中鍵雙擊＝縮放至符合——
      // 兩次中鍵按下間隔 <300ms 且位置相近（沒被拿來拖曳平移）
      final now = DateTime.now();
      final isDoubleMiddleTap = _lastMiddleDown != null &&
          now.difference(_lastMiddleDown!) < const Duration(milliseconds: 300) &&
          (event.localPosition - _lastMiddlePos).distance < 8;
      _lastMiddleDown = now;
      _lastMiddlePos = event.localPosition;
      if (isDoubleMiddleTap) {
        _lastMiddleDown = null; // 吃掉三連擊
        _isMiddleButtonPan = false;
        widget.controller
            .fitToContent(context.size ?? const Size(800, 600));
        setState(() {});
        return;
      }

      // 先取消正在進行的連線拖曳
      if (widget.controller.state.dragState != null) {
        widget.controller.endConnectionDrag(null, null);
        setState(() {});
      }
      _isMiddleButtonPan = true;
      _lastPanPos = event.localPosition;
      return;
    }

    // [教練 Agent 2026-08-01] 右鍵 — 取消連線拖曳
    if (event.buttons == kSecondaryButton) {
      if (widget.controller.state.dragState != null) {
        widget.controller.endConnectionDrag(null, null);
        setState(() {});
      }
      widget.controller.clearSelection();
      setState(() {});
      return;
    }

    if (widget.controller.state.dragState != null) {
      _checkPortHit(event.localPosition);
      return;
    }

    // 左鍵
    if (event.buttons == kPrimaryButton) {
      // [教練 Agent 2026-08-15] PORT 絕對優先：按下點在 port 上（半徑 24px 內）
      // → 直接啟動拉線（同步、繞過手勢競技場），節點拖曳讓路。
      // 使用者游標已在放大的 port 上按下 = 意圖明確是連線，不需要猜。
      // [教練 Agent 2026-08-16 使用者回饋修正] port 命中必須排在連線命中之前——
      // 連線終點錨在 input port 圓心，兩者容差區重疊；先測線的話，
      // 在 port 上按下拉新線會被搶成「抓線頭拔線」。port 上永遠是拉線；
      // 抓線拔線保留給「在線上但不在任何 port 上」（>24px 離 port）。
      // 拔線不受影響：命中已連線的 input port → startConnectionDrag 同一條路。
      final portHit = _hitTestPort(event.localPosition);
      if (portHit != null) {
        _pointerStartedOnPort = true;
        _isDragFromPort = true;
        final (nodeId, portName, fromOutput) = portHit;
        final worldPos = _screenToWorld(event.localPosition);
        widget.controller.startConnectionDrag(nodeId, portName, fromOutput, worldPos);
        return;
      }
      _pointerStartedOnPort = false;
      _isDragFromPort = false;

      // [教練 Agent 2026-08-15 使用者 提案：抓線頭拔線]
      // 命中一條已存在的連線（hover 變胖那條）→ 抓住它的 input 端。
      // 之後：放開在空白 = 拔除；接到別的 input = 搬家。
      final connHit = _hitTestConnection(event.localPosition);
      if (connHit != null) {
        final (conn, _) = connHit;
        _pointerStartedOnPort = true; // 節點拖曳讓路
        _isDragFromPort = true;
        widget.controller.startConnectionDrag(
            conn.toNodeId, conn.toPortId, false, _screenToWorld(event.localPosition));
        return;
      }

      final worldPos = _screenToWorld(event.localPosition);
      final hitNode = _hitTestNode(worldPos);

      if (hitNode != null) {
        // [教練 Agent 2026-07-23] 點擊節點 — 即時選取，繞過 GestureDetector 手勢競爭
        final isSelected = widget.controller.state.selectedNodeIds.contains(hitNode.id);
        if (HardwareKeyboard.instance.isShiftPressed) {
          widget.controller.toggleNodeSelection(hitNode.id);
        } else if (!isSelected) {
          // 點擊未選中的節點 → 替換為單選
          widget.controller.selectNode(hitNode.id);
        }
        // 點擊已選中的節點 → 保留多選狀態，讓拖曳能連動
        // 不啟動框選
        _boxSelectStart = null;
        _isBoxSelecting = false;
      } else {
        // 空白處 — 開始框選
        _boxSelectStart = event.localPosition;
        _boxSelectCurrent = event.localPosition;
        _isBoxSelecting = true;
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        _preBoxSelectIds = isShift
            ? Set<String>.from(widget.controller.state.selectedNodeIds)
            : null;
        if (!isShift) {
          widget.controller.clearSelection();
        }
      }
    }
  }

  /// [教練 Agent 2026-07-23] 統一指標移動處理 — 由 Listener 直接驅動，
  /// 不依賴 GestureDetector（中鍵不會觸發 pan 手勢）
  void _onPointerMove(PointerMoveEvent event) {
    // 中鍵平移
    if (_isMiddleButtonPan) {
      final delta = event.localPosition - _lastPanPos;
      _lastPanPos = event.localPosition;
      widget.controller.pan(delta);
      return;
    }

    // 左鍵框選
    // [教練 Agent 2026-07-24] 修正：框選碰到節點不取消 — 群選一定會碰到節點
    // 改為：只在框選起點是空白處時允許框選，之後即使碰到節點也繼續
    if (_isBoxSelecting && _boxSelectStart != null) {
      _boxSelectCurrent = event.localPosition;
      _updateBoxSelection();
      setState(() {});
      return;
    }

    // 連線拖曳
    final state = widget.controller.state;
    if (state.dragState != null) {
      final worldPos = _screenToWorld(event.localPosition);
      widget.controller.updateConnectionDrag(worldPos);
      _checkPortHit(event.localPosition);
      return;
    }

    // [教練 Agent 2026-08-15 使用者 提案] 閒置時 hover 偵測——線變胖默契
    _updateConnectionHover(event.localPosition);
  }

  /// [教練 Agent 2026-07-23] 統一指標釋放處理
  void _onPointerUp(PointerUpEvent event) async {
    if (_isMiddleButtonPan) {
      _isMiddleButtonPan = false;
    }

    if (_isBoxSelecting) {
      _isBoxSelecting = false;
      _boxSelectStart = null;
      _preBoxSelectIds = null;
      setState(() {});
    }

    // [教練 Agent 2026-08-01] 連線拖曳 — 放開時檢查是否在 port 上
    final state = widget.controller.state;
    if (state.dragState != null) {
      _checkPortHit(event.localPosition);
      // 如果放開時 hover 到了某個 port，完成連線
      if (_hoveredPort != null) {
        // _hoveredPort 格式是 "nodeId:portId"
        final parts = _hoveredPort!.split(':');
        if (parts.length >= 2) {
          final toNodeId = parts[0];
          final toPortId = parts.sublist(1).join(':');
          // [教練 Agent 2026-08-15 Phase 1] 接不上時告訴使用者「為什麼」
          final error = await widget.controller.endConnectionDrag(toNodeId, toPortId);
          if (error != null && mounted) {
            _showConnectionError(error);
          }
        }
        setState(() => _hoveredPort = null);
      } else {
        // 沒有 hover 到任何 port → [教練 Agent 2026-08-15 相容節點快選]
        // ComfyUI 同款：拖線放空處彈出「能接的節點」清單，
        // 選了自動建節點在放開位置並接線。
        // [教練 Agent 2026-08-15 使用者回饋] 拔線手勢（抓住現有連線拖到空白）
        // = 拔除，不彈快選——只有「從 port 拉的新線」才彈快選。
        final drag = state.dragState;
        final isDetachGesture = drag?.detachedConnectionId != null;
        if (drag != null && _isDragFromPort && !isDetachGesture) {
          setState(() {
            _showSearchBox = true;
            _searchBoxPos = event.localPosition;
            _searchBoxWorldPos = _screenToWorld(event.localPosition);
            _pendingDrag = drag;
            widget.controller.cancelDragKeepSearch(); // 清 dragState 但保留快選 context
          });
        } else {
          widget.controller.endConnectionDrag(null, null);
          setState(() {});
        }
      }
    }

    // [教練 Agent 2026-08-15] 重置 port 優先旗標
    _pointerStartedOnPort = false;
  }

  /// [教練 Agent 2026-08-15 Phase 1] 連線錯誤提示（Phase 2.5 會升級為氣泡動畫）
  void _showConnectionError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🚫 $message'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 360,
      ),
    );
  }

  /// [教練 Agent 2026-07-23] 根據框選矩形更新選取
  void _updateBoxSelection() {
    if (_boxSelectStart == null) return;

    final rect = Rect.fromPoints(_boxSelectStart!, _boxSelectCurrent);
    final viewport = widget.controller.state.viewport;

    final selected = <String>{};
    if (_preBoxSelectIds != null) {
      selected.addAll(_preBoxSelectIds!);
    }

    for (final node in widget.controller.state.nodes.values) {
      final screenPos = viewport.worldToScreen(node.position);
      final nodeRect = Rect.fromLTWH(
        screenPos.dx,
        screenPos.dy,
        node.width * viewport.scale,
        node.height * viewport.scale,
      );
      if (rect.overlaps(nodeRect)) {
        selected.add(node.id);
      }
    }

    widget.controller.selectMultiple(selected);
  }

  /// 偵測滑鼠位置是否在某個 port 上
  void _checkPortHit(Offset screenPos) {
    final portPositions = widget.controller.portPositions;
    for (final entry in portPositions.entries) {
      final pos = entry.value;
      if ((pos - screenPos).distance < 20) {
        setState(() => _hoveredPort = entry.key);
        return;
      }
    }
    if (_hoveredPort != null) {
      setState(() => _hoveredPort = null);
    }
  }

  /// 偵測世界座標是否擊中某個節點
  /// [教練 Agent 2026-07-23] 修正：使用實際渲染尺寸估算（NodeWidget minWidth 200, maxWidth 320）
  /// 而非 model 的預設 120x80，否則點擊節點邊緣會被誤判為空白處
  OpenCanvasNode? _hitTestNode(Offset worldPos) {
    for (final node in widget.controller.state.nodes.values) {
      final (estW, estH) = node.estimatedRenderSize;
      final rect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        estW,
        estH,
      );
      if (rect.contains(worldPos)) return node;
    }
    return null;
  }

  /// 處理單擊空白 — 記錄點擊位置
  void _onDoubleTapDown(TapDownDetails details) {
    _searchBoxWorldPos = _screenToWorld(details.localPosition);
    // [教練 Agent 2026-08-03] 用 localPosition — 因為 NodeSearchBox 在 Stack 內，Positioned 用 local
    _searchBoxPos = details.localPosition;
  }

  /// 單擊空白處 — 依當前工具決定行為
  void _onSingleTapUp(TapUpDetails details) {
    _hideContextMenu(); // [教練 Agent 2026-08-02] 點擊時隱藏 context menu

    // [教練 Agent 2026-08-15 使用者回饋] 命中節點就不清除選取——
    // 之前點節點：NodeWidget onTap 先選取（亮），外層 GestureDetector
    // 的 tap 冒泡又 clearSelection（滅）→ 選取框閃一下就消失。
    final hitNode = _hitTestNode(_screenToWorld(details.localPosition));
    if (hitNode != null) return;

    final tool = widget.controller.state.activeTool;
    // select 模式：僅清除選取
    if (tool == CanvasTool2.select) {
      widget.controller.clearSelection();
      return;
    }
    // addNode 模式：在點擊位置彈出節點搜尋框，然後回到 select
    if (tool == CanvasTool2.addNode) {
      _searchBoxWorldPos = _screenToWorld(details.localPosition);
      _searchBoxPos = details.localPosition;
      // 回到 select 模式（一次性使用）
      widget.controller.setTool(CanvasTool2.select);
      if (widget.onDoubleTapEmpty != null) {
        widget.onDoubleTapEmpty!(_searchBoxPos, _searchBoxWorldPos);
      }
      return;
    }
    // 其他模式也清除選取
    widget.controller.clearSelection();
  }

  /// [教練 Agent 2026-08-01] 雙擊空白處 — 彈出節點選擇器
  void _onDoubleTapOnEmpty() {
    _hideContextMenu(); // [教練 Agent 2026-08-02] 隱藏 context menu

    // 檢查是否點到節點 — 如果點到節點就不彈（讓節點的 onDoubleTap 處理）
    // _onDoubleTapDown 已記錄位置，hit test 用世界座標
    final worldPos = _searchBoxWorldPos;
    final hitNode = _hitTestNode(worldPos);
    if (hitNode != null) return; // 點到節點了，不處理

    // 取消正在進行的連線拖曳
    if (widget.controller.state.dragState != null) {
      widget.controller.endConnectionDrag(null, null);
      setState(() {});
      return;
    }

    setState(() => _showSearchBox = true);
    if (widget.onDoubleTapEmpty != null) {
      widget.onDoubleTapEmpty!(_searchBoxPos, worldPos);
    }
  }

  /// [教練 Agent 2026-08-02] 右鍵 — 取消連線拖曳或顯示 context menu
  void _onSecondaryTapDown(TapDownDetails details) {
    // 先隱藏可能存在的 context menu
    _hideContextMenu();

    // 如果有連線拖曳中，先取消
    if (widget.controller.state.dragState != null) {
      widget.controller.endConnectionDrag(null, null);
      setState(() {});
      return;
    }

    final worldPos = _screenToWorld(details.localPosition);
    final hitNode = _hitTestNode(worldPos);

    // 清除選取（原有行為）
    widget.controller.clearSelection();
    setState(() {});

    // 顯示對應的 context menu
    if (hitNode != null) {
      // 右鍵在節點上
      widget.controller.selectNode(hitNode.id);
      setState(() {});
      _showNodeContextMenu(hitNode.id, details.globalPosition);
    } else {
      // 右鍵在空白處
      _showEmptyContextMenu(details.globalPosition, details.localPosition, worldPos);
    }
  }

  /// [教練 Agent 2026-08-02] 顯示空白處 context menu
  void _showEmptyContextMenu(Offset globalPos, Offset localPos, Offset worldPos) {
    _contextMenuEntry?.remove();

    final colors = BridgeDSColors.of(context);
    // [教練 Agent 2026-08-15 使用者回饋修正] 先存畫布尺寸——onTap 閉包裡的
    // context 是「選單自己的」（~160px 小框），拿它當畫布尺寸算 fit
    // 會把 scale 壓到超小。這裡的 context 才是畫布本體。
    final canvasSize = context.size;

    _contextMenuEntry = OverlayEntry(
      builder: (context) => _wrapWithBarrier(
        globalPos,
        Material(
          color: colors.surfaceElevated,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 160),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderDefault, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMenuItem(
                  icon: Icons.add,
                  label: '新增節點',
                  onTap: () {
                    _hideContextMenu();
                    // [教練 Agent 2026-08-15 使用者回饋修正] 之前呼叫 onDoubleTapEmpty
                    // 回呼，但 workspace 端是空實作（快選框已移到本 widget 內部）。
                    // 直接用內部機制：在右鍵位置彈 NodeSearchBox。
                    setState(() {
                      _searchBoxWorldPos = worldPos;
                      _searchBoxPos = localPos;
                      _showSearchBox = true;
                    });
                  },
                ),
                // [教練 Agent 2026-08-15 使用者回饋] 移除「貼上」——複製是立即建節點，
                // 沒有剪貼簿機制，留著佔位只會誤導。
                const Divider(height: 1),
                _buildMenuItem(
                  icon: Icons.select_all,
                  label: '全選',
                  onTap: () {
                    _hideContextMenu();
                    widget.controller.selectAll();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.fit_screen,
                  label: '縮放至符合',
                  onTap: () {
                    _hideContextMenu();
                    // [教練 Agent 2026-08-15 使用者回饋] 用彈出前存的畫布尺寸
                    if (canvasSize != null) {
                      widget.controller.fitToContent(canvasSize);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  /// [教練 Agent 2026-08-02] 顯示節點 context menu
  void _showNodeContextMenu(String nodeId, Offset globalPos) {
    _contextMenuEntry?.remove();

    final colors = BridgeDSColors.of(context);

    _contextMenuEntry = OverlayEntry(
      builder: (context) => _wrapWithBarrier(
        globalPos,
        Material(
          color: colors.surfaceElevated,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 160),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderDefault, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // [小葵 2026-09-24 Blue 令·加回] 「執行此節點」2026-08-15 被
                // 移除（當時判斷「測試＋整流執行就夠」）——但單顆重跑情境
                // 證明有存在價值：工作流中途一顆失敗（如 safety 拒絕），
                // 用戶不想整條重跑重花錢，只想重跑那一顆。paid 計費照走
                // PaidActionGate（_executeSingleNode 走 CapabilityExecutor）。
                if (widget.onNodeExecute != null)
                  _buildMenuItem(
                    icon: Icons.play_arrow,
                    label: '執行此節點',
                    onTap: () {
                      _hideContextMenu();
                      widget.onNodeExecute!(nodeId);
                    },
                  ),
                _buildMenuItem(
                  icon: Icons.copy,
                  label: '複製',
                  onTap: () {
                    _hideContextMenu();
                    // [教練 Agent 2026-08-15 使用者回饋] 複製＝同型別新節點（含參數）在原位置右下
                    widget.controller.duplicateNode(nodeId);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.delete_outline,
                  label: '刪除',
                  onTap: () {
                    _hideContextMenu();
                    widget.controller.removeSelectedNodes();
                  },
                ),
                // [教練 Agent 2026-08-15 使用者回饋] 移除「連接到...」——拉線就是連接
                // （從 port 拉出、相容快選），這選項多餘。
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  /// [教練 Agent 2026-08-02] 隱藏 context menu
  void _hideContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  /// [教練 Agent 2026-08-16 使用者回饋] context menu 加全螢幕 barrier——
  /// 以前只有點畫布背景會關，點節點卡/其他面板選單會賴著不走。
  /// 現在：選單外面任何地方點一下（含右鍵），立即消失。
  Widget _wrapWithBarrier(Offset globalPos, Widget menu) {
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, // 整片都吃事件，不用真的透明可見
          onTapDown: (_) => _hideContextMenu(),
          onSecondaryTapDown: (_) => _hideContextMenu(), // 右鍵也立即關
          child: const SizedBox.expand(),
        ),
      ),
      Positioned(left: globalPos.dx, top: globalPos.dy, child: menu),
    ]);
  }

  /// [教練 Agent 2026-08-02] 建構 menu item
  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final colors = BridgeDSColors.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled ? colors.textPrimary : colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: BridgeDS.body.copyWith(
                color: enabled ? colors.textPrimary : colors.textSecondary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 縮放
  void _onScaleStart(ScaleStartDetails details) {}

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 2) {
      // 雙指縮放
      final newScale = widget.controller.state.viewport.scale * details.scale;
      widget.controller.zoom(newScale, details.focalPoint);
    }
  }

  /// 滾輪縮放
  /// [教練 Agent 2026-08-15 使用者回饋修正] 滑鼠在節點內容或彈窗上滾輪時，
  /// 應該捲動「那個」內容而不是縮放畫布。用 PointerSignalResolver——
  /// 內層 Scrollable 會註冊自己的 handler，resolver 只呼叫
  /// 最深層的註冊者：節點/彈窗有捲動 → 它們贏；空白處 → 畫布縮放。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, _resolveCanvasZoom);
    }
  }

  void _resolveCanvasZoom(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    final event = signal;
    if (!mounted) return;
    {
      // [教練 Agent 2026-08-16 使用者回饋修正] 滑鼠在節點卡上時，只有命中
      // 「可捲動 widget」才讓它贏得滾輪；節點卡其他區域（標題、port、
      // 空白 padding）應該放行給畫布縮放。Resolver 只保證最深層的
      // 註冊者贏得，但 Scrollable 必然會註冊——所以偵測 hitTest 路徑
      // 中是否有 Scrollable 即可，它在節點卡空白處不會出現。
      if (_hitTestScrollableAt(event.position)) return;

      final state = widget.controller.state;
      // [教練 Agent 2026-07-23] 使用動態 minScale，允許內容變大時縮得更遠
      final minScale = widget.controller.dynamicMinScale;
      final newScale = state.viewport.scale * (event.scrollDelta.dy > 0 ? 0.9 : 1.1);
      final clamped = newScale.clamp(minScale, CanvasViewport.maxScale);
      // [教練 Agent 2026-07-23] 將全域座標轉為畫布局部座標，以滑鼠為中心縮放
      final renderBox = context.findRenderObject() as RenderBox?;
      final localFocalPoint = renderBox?.globalToLocal(event.position) ?? event.position;
      widget.controller.zoom(clamped, localFocalPoint);
    }
  }

  /// [教練 Agent 2026-08-16] 偵測滾輪位置是否命中「可捲動 widget」。
  /// 用 hitTest 拿到不透明覆蓋路徑，裡頭任意一個 RenderBox 是
  /// Scrollable 內部的 RenderViewport（或是 Scrollable 自身 RenderObject）
  /// 就視為命中。節點卡空白處不會有 Scrollable 命中，於是畫布照縮放。
  bool _hitTestScrollableAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final result = BoxHitTestResult();
    final local = box.globalToLocal(globalPosition);
    // hitTest 內部會檢查座標是否在 box 內，超出不需要繼續
    if (!box.size.contains(local)) return false;
    box.hitTest(result, position: local);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderViewport) return true; // Scrollable 內部 viewport
      if (target is RenderAbstractViewport) return true;
      // TextField 內部滾輪由 RenderEditable 處理，它會透過
      // Scrollable 注冊 resolver——這層 RenderEditable 屬於 Scrollable 樹，
      // 上溯 ancestor 一定會遇到 RenderViewport，不過 hitTest path 是
      // 自下而上的，所以 RenderViewport 必然在 path 中。
    }
    return false;
  }

  // ── 建構 UI ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final viewport = state.viewport;

    // [教練 Agent 2026-08-16 使用者 提案] Finder 拖檔進畫布——
    // DropTarget 包整個畫布，drag 進來時邊框亮藍提示可放。
    Widget canvasBody = LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: MouseRegion(
              // [教練 Agent 2026-08-15 使用者 提案修正] 閒置 hover 偵測——
              // Listener.onPointerMove 只在按住時觸發，滑鼠閒置移動
              // 必須走 MouseRegion.onHover，線變胖才會出現。
              onHover: (e) {
                if (widget.controller.state.dragState == null) {
                  _updateConnectionHover(e.localPosition);
                }
              },
              child: GestureDetector(
              onTapUp: _onSingleTapUp,
              onDoubleTapDown: _onDoubleTapDown,
              onDoubleTap: _onDoubleTapOnEmpty, // [教練 Agent 2026-08-01] 修復：雙擊空白彈出節點選擇器
              onSecondaryTapDown: _onSecondaryTapDown, // [教練 Agent 2026-08-01] 右鍵取消連線
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 背景網格 + 連線
                  Positioned.fill(
                    child: CustomPaint(
                      key: _backgroundKey,
                      painter: _CanvasBackgroundPainter(
                        viewport: viewport,
                        connections: state.connections,
                        nodes: state.nodes,
                        portPositions: widget.controller.portPositions,
                        worldToScreen: viewport.worldToScreen,
                        dragState: state.dragState,
                        hoveredConnectionId: _hoveredConnectionId,
                        screenSize: Size(constraints.maxWidth, constraints.maxHeight),
                        backgroundColor: BridgeDSColors.of(context).canvas,
                        gridColor: BridgeDSColors.of(context).borderStrong,
                      ),
                    ),
                  ),

                  // 節點
                  ...state.nodes.values.map((node) {
                    final screenPos = viewport.worldToScreen(node.position);
                    return Positioned(
                      left: screenPos.dx,
                      top: screenPos.dy,
                      // [教練 Agent 2026-07-23] 節點跟著 viewport scale 縮放，
                      // 縮小時不擁擠，放大時看得清楚
                      child: Transform.scale(
                        scale: viewport.scale,
                        alignment: Alignment.topLeft,
                        child: GestureDetector(
                          // [教練 Agent 2026-07-23] 拖曳開始時快照一次供 undo
                          // [教練 Agent 2026-07-24] 修正拖曳偏移：localPosition 已是世界座標（GestureDetector 在 Transform 內）
                          // 不能再呼叫 _screenToWorld()，否則雙重轉換。scale 越小偏移越大。
                          // [教練 Agent 2026-08-15] port 上按下 = 拉線（已在 Listener 同步啟動 dragState），
                          // 節點拖曳讓路——不搶、不 beginMove。
                          onPanStart: (details) {
                            if (_pointerStartedOnPort) return;
                            widget.controller.beginMove();
                            _nodeDragStartWorld = details.localPosition;
                            _nodeDragStartPos = node.position;
                          },
                          // 節點拖曳移動（不冒泡到畫布的 pan）
                          onPanUpdate: (details) {
                            if (_pointerStartedOnPort) return;
                            // localPosition 已經是世界座標（在 Transform 內），直接用
                            final worldDelta = details.localPosition - _nodeDragStartWorld!;
                            final newPos = _nodeDragStartPos! + worldDelta;
                            widget.controller.moveNode(node.id, newPos);
                          },
                          // 雙擊開啟參數面板
                          onDoubleTap: () {
                            if (_pointerStartedOnPort) return;
                            widget.onNodeDoubleTap?.call(node.id);
                          },
                          child: widget.nodeBuilder(context, node, widget.controller),
                        ),
                      ),
                    );
                  }),

                  // [教練 Agent 2026-07-23] 框選矩形
                  if (_boxSelectStart != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BoxSelectPainter(
                          rect: Rect.fromPoints(_boxSelectStart!, _boxSelectCurrent),
                        ),
                      ),
                    ),

                  // NodeSearchBox
                  if (_showSearchBox)
                    NodeSearchBox(
                      screenPos: _searchBoxPos,
                      // [教練 Agent 2026-08-15 相容快選] 拖線放空 → 只列相容節點，
                      // 選了自動建節點＋接線
                      compatFilter: _pendingDrag == null ? null : (type) => _isTypeCompatibleWithDrag(type),
                      filterHint: _pendingDrag == null ? null : _dragFilterHint(),
                      onSelected: (type) async {
                        final drag = _pendingDrag;
                        setState(() {
                          _showSearchBox = false;
                          _pendingDrag = null;
                        });
                        final newNodeId = await widget.controller.addWorkflowNode(type, _searchBoxWorldPos);
                        // 自動接線：拖曳源 → 新節點
                        if (drag != null) {
                          String? error;
                          if (drag.fromOutput) {
                            // output → 新節點第一個相容 input
                            final inputPort = _firstCompatibleInput(newNodeId, drag);
                            if (inputPort != null) {
                              error = await widget.controller.connect(
                                  drag.fromNodeId, drag.fromPortId, newNodeId, inputPort);
                            }
                          } else {
                            // input ← 新節點第一個相容 output（反方向）
                            final outputPort = _firstCompatibleOutput(newNodeId, drag);
                            if (outputPort != null) {
                              error = await widget.controller.connect(
                                  newNodeId, outputPort, drag.fromNodeId, drag.fromPortId);
                            }
                          }
                          if (error != null && mounted) _showConnectionError(error);
                        }
                      },
                      onCancel: () {
                        setState(() {
                          _showSearchBox = false;
                          _pendingDrag = null;
                        });
                      },
                    ),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );

    // [教練 Agent 2026-08-16 使用者 提案] Finder 拖檔進畫布
    if (widget.onFilesDropped == null) return canvasBody;
    return DropTarget(
      onDragEntered: (_) => setState(() => _fileDragHovering = true),
      onDragExited: (_) => setState(() => _fileDragHovering = false),
      onDragDone: (details) {
        setState(() => _fileDragHovering = false);
        // details.localPosition 是 DropTarget（=畫布）本地座標，直接當 screenPos 用
        widget.onFilesDropped!(details.files, details.localPosition);
      },
      child: Stack(
        children: [
          canvasBody,
          // 拖曳懸停提示：整片藍色 overlay + 邊框
          if (_fileDragHovering)
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.8),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.08),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_done_outlined,
                          size: 20, color: BridgeDSColors.of(context).accentBlue),
                      const SizedBox(width: 8),
                      Text('放開以加入畫布',
                          style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 背景繪製 ──────────────────────────────────────────────

class _CanvasBackgroundPainter extends CustomPainter {
  final CanvasViewport viewport;
  final List<NodeConnection> connections;
  final Map<String, OpenCanvasNode> nodes;
  final Map<String, Offset> portPositions;
  final Offset Function(Offset) worldToScreen;
  final ConnectionDragState? dragState;
  final Size screenSize;
  final Color backgroundColor;
  final Color gridColor;

  /// [教練 Agent 2026-08-15 使用者 提案：hover 線變胖] 目前 hover 中的連線 ID
  final String? hoveredConnectionId;

  _CanvasBackgroundPainter({
    required this.viewport,
    required this.connections,
    required this.nodes,
    required this.portPositions,
    required this.worldToScreen,
    required this.dragState,
    required this.screenSize,
    required this.backgroundColor,
    required this.gridColor,
    this.hoveredConnectionId,
  });

  void _drawGrid(Canvas canvas, Size size) {
    const gridSize = 40.0;
    final scale = viewport.scale;
    final offsetX = viewport.offset.dx % (gridSize * scale);
    final offsetY = viewport.offset.dy % (gridSize * scale);
    final step = gridSize * scale;

    final paint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    // 細網格
    for (double x = offsetX; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = offsetY; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // 粗網格（每 5 格）
    final bigStep = step * 5;
    final bigOffsetX = viewport.offset.dx % bigStep;
    final bigOffsetY = viewport.offset.dy % bigStep;
    // [教練 Agent 2026-08-12] 粗網格降低亮度（不再那麼白銳）
    final bigPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double x = bigOffsetX; x < size.width; x += bigStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), bigPaint);
    }
    for (double y = bigOffsetY; y < size.height; y += bigStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), bigPaint);
    }
  }

  void _drawConnections(Canvas canvas) {
    // [教練 Agent 2026-08-15 fan-out 分點] 同一個 port 上有多條線時，
    // 端點沿垂直方向扇形展開（間距 10px）——一條線一個點，
    // 使用者才看得出「要拔哪一條」（使用者 提案）。
    // 索引規則：同一 port 的連線依在 connections 裡的順序编号。
    final fanIndex = <String, int>{};
    final fanCount = <String, int>{};
    for (final c in connections) {
      fanCount['${c.fromNodeId}:${c.fromPortId}'] =
          (fanCount['${c.fromNodeId}:${c.fromPortId}'] ?? 0) + 1;
      fanCount['${c.toNodeId}:${c.toPortId}'] =
          (fanCount['${c.toNodeId}:${c.toPortId}'] ?? 0) + 1;
    }
    Offset fanOut(String key, Offset pos, int total) {
      if (total <= 1) return pos;
      final i = fanIndex[key] ?? 0;
      fanIndex[key] = i + 1;
      // 展開間距 10px，奇數條置中
      // [教練 Agent 2026-08-16 使用者 抓包] 間距必須乘 viewport.scale——
      // 節點卡隨縮放變小，但扇形展開是螢幕像素寫死 10px，
      // 縮小到一定程度線端點就「跑出」卡片外（視覺脫落）。
      // 乘上 scale 讓扇形與卡片等比例，任何縮放都貼著 port。
      final spread = (i - (total - 1) / 2) * 10.0 * viewport.scale;
      return pos + Offset(0, spread);
    }

    for (final conn in connections) {
      final fromKey = '${conn.fromNodeId}:${conn.fromPortId}';
      final toKey = '${conn.toNodeId}:${conn.toPortId}';

      final fromPos = portPositions[fromKey];
      final toPos = portPositions[toKey];

      if (fromPos == null || toPos == null) continue;

      // fan-out 端點
      final fromEnd = fanOut(fromKey, fromPos, fanCount[fromKey] ?? 1);
      final toEnd = fanOut(toKey, toPos, fanCount[toKey] ?? 1);

      // 檢查端口類型兼容性
      final fromNode = nodes[conn.fromNodeId];
      final toNode = nodes[conn.toNodeId];
      bool isTypeMismatch = false;
      // [教練 Agent 2026-08-15 Phase 2.5-A] 提升作用域：連線色要讀取 fromPortDef
      PortDef? fromPortDef;

      if (fromNode != null && toNode != null) {
        // [小葵 2026-09-23 修 bug·灰線] 埠定義以 NodeTypePorts（程式碼）
        // 為真相源——DB 快照是節點建立當下的，程式碼改版後舊節點
        // 讀不到新埠（如 vision 的 original）→ 線色 fallback 灰色。
        final fromNodeType = fromNode.entity.canvasProps?.nodeType;
        final toNodeType = toNode.entity.canvasProps?.nodeType;
        final fromPorts = fromNodeType != null
            ? NodeTypePorts.portsFor(fromNodeType)
            : (fromNode.entity.canvasProps?.ports ?? const <PortDef>[]);
        final toPorts = toNodeType != null
            ? NodeTypePorts.portsFor(toNodeType)
            : (toNode.entity.canvasProps?.ports ?? const <PortDef>[]);
        fromPortDef = fromPorts
            .where((p) => p.isOutput && p.name == conn.fromPortId)
            .firstOrNull;
        final toPortDef = toPorts
            .where((p) => !p.isOutput && p.name == conn.toPortId)
            .firstOrNull;

        if (fromPortDef != null && toPortDef != null) {
          isTypeMismatch = !NodeConnection.isPortTypeMatch(fromPortDef.dataType, toPortDef.dataType);
        }
      }

      // [教練 Agent 2026-08-15 Phase 2.5-A] 連線顏色 = 資料型別色（與 port 同色）
      // [教練 Agent 2026-08-15 使用者 提問修正] 線色一律取「來源 port」——線裡流的
      // 資料是來源給的，目標不改變線色。port 定義解析不到（舊版資料）
      // → 灰色虛線誠實標示，不再 fallback 成藍色造成「接上後變色」的錯覺。
      final Color lineColor;
      if (isTypeMismatch) {
        lineColor = BridgeDS.orange500;
      } else if (fromPortDef != null) {
        lineColor = NodeConnection.typeColor(fromPortDef.dataType);
      } else {
        lineColor = BridgeDS.textMuted.withValues(alpha: 0.5);
      }

      ConnectionCurve(
        start: fromEnd,
        end: toEnd,
        color: lineColor,
        animated: conn.animated,
        dashed: isTypeMismatch,
        // [教練 Agent 2026-08-15 使用者 提案] hover 中的線變胖（4px）——
        // 「這條線可以抓」的視覺默契
        strokeWidth: conn.id == hoveredConnectionId ? 4.5 : 2.0,
      ).paint(canvas);
    }

    // 拖曳中預覽連線
    if (dragState != null) {
      final fromKey = '${dragState!.fromNodeId}:${dragState!.fromPortId}';
      final fromPos = portPositions[fromKey] ?? worldToScreen(dragState!.fromWorldPos);
      final toPos = worldToScreen(dragState!.currentWorldPos);

      // [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳中的線 = 源 port 型別色（半透明）
      ConnectionCurve(
        start: fromPos,
        end: toPos,
        color: _dragTypeColor.withValues(alpha: 0.6),
        strokeWidth: 1.5,
      ).paint(canvas);
    }
  }

  /// [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳預覽線的型別色
  Color get _dragTypeColor {
    final node = nodes[dragState!.fromNodeId];
    final portDef = node?.entity.canvasProps?.ports
        .where((p) => p.name == dragState!.fromPortId)
        .firstOrNull;
    if (portDef == null) return BridgeDS.brightCyan;
    return NodeConnection.typeColor(portDef.dataType);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 背景填充
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    _drawGrid(canvas, size);
    _drawConnections(canvas);
  }

  @override
  bool shouldRepaint(covariant _CanvasBackgroundPainter oldDelegate) {
    return true; // 簡化：每幀重繪（viewport 或 connections 變化時由 setState 觸發）
  }
}

/// [教練 Agent 2026-07-23] 框選矩形繪製
class _BoxSelectPainter extends CustomPainter {
  final Rect rect;

  _BoxSelectPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = BridgeDS.infoBlue.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = BridgeDS.infoBlue.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _BoxSelectPainter oldDelegate) {
    return rect != oldDelegate.rect;
  }
}
