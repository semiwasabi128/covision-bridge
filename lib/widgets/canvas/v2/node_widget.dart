// node_widget.dart
// 畫布節點 UI Widget — title bar + ports + inline widgets
// 建立日期: 2026-07-15
// 參考: graph_edit BasicNodeWidget + LiteGraph drawNode
//
// 純 UI Widget，不負責狀態管理。
// 狀態由 CanvasController 管理，本 Widget 只負責呈現和回調通知。
//
// 節點結構：
// ┌─────────────────────────┐
// │ 🔧 Title Bar（雙擊編輯）  │  ← 30px 高，單擊折疊/展開
// ├─────────────────────────┤
// │ ● 輸入                  │  ← input port（左側圓點）
// │                         │
// │  [下拉：模型選擇]        │  ← inline widget
// │  [文字框：prompt]       │  ← inline widget
// │  [滑桿：temperature]    │  ← inline widget
// │                         │
// │            結果 ●       │  ← output port（右側圓點）
// └─────────────────────────┘

import 'dart:convert';
import 'dart:io'; // [小葵 2026-09-23] 參考圖本體預覽——File
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'asset_preview.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'canvas_controller.dart' show NodeTypePorts;
import 'package:bridge_app/services/voice/native_audio_bytes_player.dart';
import 'package:bridge_app/widgets/canvas/v2/port_widget.dart';
import 'package:bridge_app/widgets/canvas/v2/sub_workflow_picker.dart';
import 'package:bridge_app/services/capability/service_registry.dart';
import 'package:bridge_app/services/semicanvas/canvas_tts_service.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

// ── 回調型別 ──────────────────────────────────────────

/// Port 拖曳起始回調
typedef PortDragStartCallback = void Function(
  String nodeId,
  String portName,
  bool isInput,
  GlobalKey portKey,
);

/// Port 拖曳結束回調
typedef PortDragEndCallback = void Function(
  String nodeId,
  String portName,
  bool isInput,
);

// ── NodeWidget ────────────────────────────────────────

/// 畫布節點 UI Widget。
///
/// 結構：title bar（30px）+ input ports（左）+ inline widgets（中）+ output ports（右）
///
/// 特色：
/// - title bar 雙擊進入 inline 編輯標題
/// - title bar 單擊折疊/展開
/// - inline widgets 根據 nodeType 顯示不同組合
/// - port 是 12px 圓點，支援拖曳偵測
/// - 選中時邊框高亮
class NodeWidget extends StatefulWidget {
  /// 節點 ID（Entity ID）
  final String nodeId;

  /// 節點標題
  final String title;

  /// 工作流節點型別（null = 非工作流節點，只顯示 title bar）
  final WorkflowNodeType? nodeType;

  /// 節點參數（model, prompt, temperature...）
  final Map<String, dynamic> params;

  /// Port 定義列表
  final List<PortDef> ports;

  /// 是否被選中
  final bool isSelected;

  /// 是否折疊
  final bool isCollapsed;

  /// 視覺狀態（idle/active/done/blocked）
  final CanvasVisualState visualState;

  /// 標題變更回調
  final ValueChanged<String>? onTitleChanged;

  /// 參數變更回調
  final void Function(String key, dynamic value)? onParamChanged;

  /// 折疊/展開回調
  final VoidCallback? onToggleCollapse;

  /// 點擊節點回調（選取）
  final VoidCallback? onTap;

  /// 雙擊 body 回調（開啟參數面板）
  final VoidCallback? onDoubleTap;

  /// Port 拖曳起始回調
  final PortDragStartCallback? onPortDragStart;

  /// Port 拖曳結束回調
  final PortDragEndCallback? onPortDragEnd;

  /// Port 點擊回調
  final void Function(String nodeId, String portName, bool isInput)?
      onPortTap;

  /// [教練 Agent 2026-07-23] 刪除節點回調
  final VoidCallback? onDelete;

  /// 連線拖曳中的目標 port ID（格式 "nodeId.portName"），null = 無拖曳
  final String? activeConnectionTargetPort;

  /// 連線拖曳中的來源 port ID，null = 無拖曳
  final String? activeDragSourcePort;

  /// [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳連線中：型別相容的可接 port 集合（亮）
  /// 格式 "nodeId.portName"，null = 無拖曳（全部正常顯示）
  final Set<String>? compatiblePorts;

  /// [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳連線中：不相容 port 要變暗
  final bool dimIncompatiblePorts;

  const NodeWidget({
    super.key,
    required this.nodeId,
    required this.title,
    this.nodeType,
    this.params = const {},
    this.ports = const [],
    this.isSelected = false,
    this.isCollapsed = false,
    this.visualState = CanvasVisualState.idle,
    this.onTitleChanged,
    this.onParamChanged,
    this.onToggleCollapse,
    this.onTap,
    this.onDoubleTap,
    this.onPortDragStart,
    this.onPortDragEnd,
    this.onPortTap,
    this.onDelete,
    this.activeConnectionTargetPort,
    this.activeDragSourcePort,
    this.compatiblePorts,
    this.dimIncompatiblePorts = false,
  });

  @override
  State<NodeWidget> createState() => _NodeWidgetState();
}

class _NodeWidgetState extends State<NodeWidget>
    with SingleTickerProviderStateMixin {
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  late FocusNode _titleFocusNode;
  final GlobalKey _nodeKey = GlobalKey();

  // [小葵 2026-09-24 Blue 令·修閃爍] base64 解碼快取——縮放/平移每幀重建
  // widget 時，同圖只解一次。key＝b64 字串本身（identity），上限 32 張
  // （簡單 LRU：超過就清空，節點縮圖場景 32 張遠夠用）。
  static final _decodeCache = <String, Uint8List>{};
  static Uint8List _cachedDecode(String b64) {
    final hit = _decodeCache[b64];
    if (hit != null) return hit;
    if (_decodeCache.length >= 32) _decodeCache.clear();
    final bytes = base64.decode(b64);
    _decodeCache[b64] = bytes;
    return bytes;
  }

  // [教練 Agent 2026-08-25 F-1] 機制 1：AI 注意力光暈
  // Agent 正在處理本節點（visualState.active）時呼吸光暈——
  // 人一眼看到「AI 現在在看這裡」。共視宣言機制 1 落地。
  late final AnimationController _haloController;
  Animation<double>? _haloAnim;

  @override
  void initState() {
    super.initState();
    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _haloAnim = Tween(begin: 0.18, end: 0.45).animate(
      CurvedAnimation(parent: _haloController, curve: Curves.easeInOut),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    if (widget.visualState == CanvasVisualState.active) {
      _haloController.repeat(reverse: true);
    }
    _titleController = TextEditingController(text: widget.title);
    _titleFocusNode = FocusNode();
    _titleFocusNode.addListener(_onTitleFocusChange);
    // [教練 Agent 2026-07-24] 測量實際渲染尺寸，寫到 debug 文件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureAndLogSize();
    });
  }

  void _measureAndLogSize() {
    final ro = _nodeKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final size = ro.size;

    // 寫入 ActualSizeCache，讓 hitTest/snapshot 用實際尺寸
    ActualSizeCache.set(widget.nodeId, size);

    // [小葵 2026-09-17 凍死根因修復] 移除 Desktop debug 寫檔——
    // 這段 2026-07-25 的測量日誌每個節點每次 build 都同步 append
    // ~/Desktop/bridge_node_sizes.txt（累積 61.7MB/95 萬行），
    // canvas tab on-stage 時數百節點齊發同步 open+write 卡死主 isolate
    // （MCP /navigate canvas 100% 重現凍結，卡點=Builtin_File_Open）。
    // ActualSizeCache（記憶體）保留——那才是 hitTest/snapshot 真正的消費者。
  }

  @override
  void didUpdateWidget(NodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title && !_isEditingTitle) {
      _titleController.text = widget.title;
    }
    // [教練 Agent 2026-08-25 F-1] 注意力光暈啟停——只在狀態變化時切換
    if (oldWidget.visualState != widget.visualState) {
      if (widget.visualState == CanvasVisualState.active) {
        _haloController.repeat(reverse: true);
      } else {
        _haloController.stop();
        _haloController.value = 0;
        if (mounted) setState(() {});
      }
    }
    // [教練 Agent 2026-07-25] 內容變了，重新測量尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureAndLogSize();
    });
  }

  @override
  void dispose() {
    _haloController.dispose();
    _titleFocusNode.removeListener(_onTitleFocusChange);
    _titleFocusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onTitleFocusChange() {
    if (!_titleFocusNode.hasFocus && _isEditingTitle) {
      _commitTitle();
    }
  }

  void _startEditingTitle() {
    setState(() {
      _isEditingTitle = true;
      _titleController.text = widget.title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNode.requestFocus();
      _titleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleController.text.length,
      );
    });
  }

  void _commitTitle() {
    final newTitle = _titleController.text.trim();
    if (newTitle.isNotEmpty && newTitle != widget.title) {
      widget.onTitleChanged?.call(newTitle);
    }
    setState(() => _isEditingTitle = false);
  }

  void _cancelEditingTitle() {
    setState(() {
      _isEditingTitle = false;
      _titleController.text = widget.title;
    });
  }

  // ── 分離 ports ──
  // [小葵 2026-09-23 修 bug·灰線] 埠定義以 NodeTypePorts（程式碼）為真相源——
  // DB 裡存的 ports 是節點建立當下的快照，程式碼改版（如 vision 加
  // original 埠）後舊節點不會更新，線色/命中都讀不到新埠 → 灰色虛線。
  // 有 nodeType 就動態解析；非工作流節點 fallback 用 DB 快照。
  List<PortDef> get _livePorts => widget.nodeType != null
      ? NodeTypePorts.portsFor(widget.nodeType!)
      : widget.ports;

  List<PortDef> get _inputPorts =>
      _livePorts.where((p) => !p.isOutput).toList();
  List<PortDef> get _outputPorts =>
      _livePorts.where((p) => p.isOutput).toList();

  // ── 建構 UI ──

  @override
  Widget build(BuildContext context) {
    final typeColor = widget.nodeType != null
        ? workflowNodeTypeColor(widget.nodeType!)
        : BridgeDSColors.of(context).textTertiary;

    // 注意：onTap/onDoubleTap 由 GraphCanvas 的 Positioned 包裝層處理，
    // 這裡只負責顯示。title bar 的單擊(折疊)和雙擊(編輯)由內部 GestureDetector 處理。
    // [教練 Agent 2026-08-25 F-1] 機制 1：active 時注意力光暈（呼吸）蓋過一般 shadow
    final isAttention = widget.visualState == CanvasVisualState.active;
    final haloAlpha = isAttention ? (_haloAnim?.value ?? 0.3) : 0.0;
    return Container(
        key: _nodeKey,
        constraints: const BoxConstraints(minWidth: 200),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surfaceElevated,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          // [教練 Agent 2026-08-15 使用者 視覺調整] 細邊框發亮——
          // 邊框帶節點型別色，外面加一層同色柔光（blur 6），
          // 像卡片內緣透光。選中時亮藍框＋更強光暈。
          border: Border.all(
            color: widget.isSelected
                ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.9)
                : typeColor.withValues(alpha: 0.55),
            width: widget.isSelected ? 1.5 : 1,
          ),
          boxShadow: isAttention
              ? [
                  // AI 正在處理：注意力光暈（青藍色呼吸，1.6s 週期）
                  BoxShadow(
                    color: BridgeDSColors.of(context).accentBlue
                        .withValues(alpha: haloAlpha),
                    blurRadius: 22,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: typeColor.withValues(alpha: 0.2),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  BoxShadow(
                    color: (widget.isSelected
                            ? BridgeDSColors.of(context).accentBlue
                            : typeColor)
                        .withValues(alpha: widget.isSelected ? 0.30 : 0.16),
                    blurRadius: widget.isSelected ? 14 : 6,
                    spreadRadius: widget.isSelected ? 2 : 1,
                  ),
                ],
        ),
        child: _NodeResizeWrapper(
          nodeType: widget.nodeType,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTitleBar(typeColor),
                if (!widget.isCollapsed) ...[
                  _buildBody(),
                ],
              ],
            ),
          ),
        ),
    );
  }

  // ── Title Bar ──

  Widget _buildTitleBar(Color typeColor) {
    return GestureDetector(
      onTap: widget.onToggleCollapse,
      onDoubleTap: _startEditingTitle,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(BridgeDS.roundComfortable),
            topRight: Radius.circular(BridgeDS.roundComfortable),
          ),
        ),
        child: Row(
          children: [
            // 節點型別圖示
            if (widget.nodeType != null)
              Text(
                workflowNodeTypeIcon(widget.nodeType!),
                style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
              )
            else
              Icon(Icons.widgets, size: 14, color: typeColor),
            SizedBox(width: 6),
            // 標題文字 or 編輯框
            Expanded(
              child: _isEditingTitle
                  ? _buildTitleEditor()
                  : Text(
                      widget.title,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w500,),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            // 視覺狀態指示
            if (widget.nodeType != null) ...[
              SizedBox(width: 4),
              _buildVisualStateDot(),
            ],
            // [教練 Agent 2026-07-23] 刪除按鈕 — 紅色叉叉
            if (widget.onDelete != null) ...[
              SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onDelete,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitleEditor() {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditingTitle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _titleController,
        focusNode: _titleFocusNode,
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
          fontWeight: FontWeight.w500,),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1.5),
          ),
          filled: true,
          fillColor: BridgeDSColors.of(context).canvas,
        ),
        textAlign: TextAlign.start,
        onSubmitted: (_) => _commitTitle(),
        onTapOutside: (_) => _commitTitle(),
      ),
    );
  }

  Widget _buildVisualStateDot() {
    final color = switch (widget.visualState) {
      CanvasVisualState.idle => BridgeDSColors.of(context).textMuted,
      CanvasVisualState.active => BridgeDSColors.of(context).accentBlue,
      CanvasVisualState.done => BridgeDSColors.of(context).accentGreen,
      CanvasVisualState.blocked => BridgeDSColors.of(context).accentRed,
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  // ── Body（ports + inline widgets） ──
  // [教練 Agent 2026-08-16 使用者 佈局指示] port 列只佔「上方」——
  // 左右兩欄 port 行的其餘高度全是浪費的留白。
  // 新結構：上排 Row（左 input ports｜中間不撐滿｜右 output ports），
  // inline widgets（文字輸入等）在下方展開、左右吃滿整張卡寬。
  Widget _buildBody() {
    final inputPorts = _inputPorts;
    final outputPorts = _outputPorts;
    final hasInlineWidgets = widget.nodeType != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上排：port 列（只佔 port 實際高度，不往下撐）
          if (inputPorts.isNotEmpty || outputPorts.isNotEmpty)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInputPortsColumn(inputPorts),
                  const Spacer(),
                  _buildOutputPortsColumn(outputPorts),
                ],
              ),
            ),
          // 下方：inline widgets 全寬展開（左右到卡邊，含 port 列地盤）
          if (hasInlineWidgets)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: _buildInlineWidgets(),
            ),
        ],
      ),
    );
  }

  // ── Input Ports（左側） ──

  Widget _buildInputPortsColumn(List<PortDef> inputPorts) {
    if (inputPorts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final port in inputPorts)
          PortWidget(
            nodeId: widget.nodeId,
            port: port,
            isInput: true,
            isCollapsed: false,
            onDragStart: widget.onPortDragStart,
            onDragEnd: widget.onPortDragEnd,
            onTap: widget.onPortTap,
            isConnectionTarget:
                widget.activeConnectionTargetPort == '${widget.nodeId}.${port.name}',
            isDragSource:
                widget.activeDragSourcePort == '${widget.nodeId}.${port.name}',
            // [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳引導
            isCompatibleTarget: widget.compatiblePorts != null &&
                widget.compatiblePorts!.contains('${widget.nodeId}.${port.name}'),
            isDimmed: widget.dimIncompatiblePorts &&
                widget.compatiblePorts != null &&
                !widget.compatiblePorts!.contains('${widget.nodeId}.${port.name}'),
          ),
      ],
    );
  }

  // ── Output Ports（右側） ──

  Widget _buildOutputPortsColumn(List<PortDef> outputPorts) {
    if (outputPorts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final port in outputPorts)
          PortWidget(
            nodeId: widget.nodeId,
            port: port,
            isInput: false,
            isCollapsed: false,
            onDragStart: widget.onPortDragStart,
            onDragEnd: widget.onPortDragEnd,
            onTap: widget.onPortTap,
            isConnectionTarget:
                widget.activeConnectionTargetPort == '${widget.nodeId}.${port.name}',
            isDragSource:
                widget.activeDragSourcePort == '${widget.nodeId}.${port.name}',
            // [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳引導
            isCompatibleTarget: widget.compatiblePorts != null &&
                widget.compatiblePorts!.contains('${widget.nodeId}.${port.name}'),
            isDimmed: widget.dimIncompatiblePorts &&
                widget.compatiblePorts != null &&
                !widget.compatiblePorts!.contains('${widget.nodeId}.${port.name}'),
          ),
      ],
    );
  }

  // ── Inline Widgets（根據 nodeType 顯示） ──

  Widget _buildInlineWidgets() {
    final type = widget.nodeType;
    if (type == null) return const SizedBox.shrink();

    final widgets = _inlineWidgetsForType(type);
    if (widgets.isEmpty) return const SizedBox.shrink();

    // [教練 Agent 2026-08-01] 執行結果顯示 — 文字 + 圖片
    final lastOutput = widget.params['_lastOutput']?.toString();
    final lastImageB64 = widget.params['_lastImageB64']?.toString();
    final lastImageUrl = widget.params['_lastImageUrl']?.toString();
    final hasError = widget.visualState == CanvasVisualState.blocked;
    final hasImage = (lastImageB64 != null && lastImageB64.isNotEmpty) ||
        (lastImageUrl != null && lastImageUrl.isNotEmpty && !lastImageUrl.startsWith('file_id:'));

    // 圖片預覽 widget
    Widget? imagePreview;
    if (hasImage && !hasError) {
      imagePreview = Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        constraints: const BoxConstraints(maxHeight: 160),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          // [小葵 2026-09-24 Blue 令·修閃爍] 縮放/平移時每幀重建 widget，
          // 舊碼每次 base64.decode 整張重解——解碼期間空白 → 閃爍。
          // 修：解碼結果進靜態快取（b64 前 64 字當 key，同圖只解一次）＋
          // gaplessPlayback（重繪時保留舊幀，不閃白）。
          child: lastImageB64 != null && lastImageB64.isNotEmpty
              ? Image.memory(
                  _cachedDecode(lastImageB64),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('⚠️ 圖片載入失敗', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  ),
                )
              : Image.network(
                  lastImageUrl!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('⚠️ 圖片載入失敗', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  ),
                ),
        ),
      );
    }

    // [小葵 2026-09-23 共視] 參考圖本體預覽——拖圖進畫布的節點
    // （params['image']=本地路徑）直接顯示縮圖，不用跑工作流。
    // 舊版只渲染「執行結果」，參考圖本身永遠看不到。
    final refImagePath = widget.params['image']?.toString();
    Widget? refImagePreview;
    if (refImagePath != null &&
        refImagePath.isNotEmpty &&
        !refImagePath.startsWith('http') &&
        imagePreview == null) {
      final f = File(refImagePath.replaceAll('file://', ''));
      if (f.existsSync()) {
        refImagePreview = Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: BridgeDSColors.of(context).accentMagenta.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          constraints: const BoxConstraints(maxHeight: 160),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Image.file(f,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('⚠️ 圖片載入失敗',
                              style: TierStyle.of(context, Tier.cardBody)
                                  .toTextStyle()),
                        )),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: TextButton.icon(
                    onPressed: () async {
                      // [小葵 2026-09-23] showAssetPreview 吃 bytes——本地檔先讀入
                      Uint8List? bytes;
                      try {
                        bytes = await f.readAsBytes();
                      } catch (_) {
                        bytes = null;
                      }
                      if (bytes != null) {
                        await showAssetPreview(
                          context,
                          title: widget.title,
                          imageBytes: bytes,
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_full, size: 14),
                    label: const Text('原圖'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // [小葵 2026-09-23 Blue 令·共視] 檔案卡預覽——任何外部拖入的檔案
    // 都要直接看到「是什麼檔、多大」，不是只看到一串路徑。
    // 圖片已由 params['image'] 縮圖預覽；這裡補其他型別的檔案卡。
    // [小葵 2026-09-23 Blue 令·二] 影片/音樂/PDF 節點本體就是預覽視窗——
    // qlmanage（macOS Quick Look）生縮圖（影片=海報幀、PDF=首頁）、
    // 音檔內建播放器。不只型別圖示＋大小。
    final filePathParam = widget.params['_filePath']?.toString();
    Widget? fileCard;
    if (filePathParam != null &&
        filePathParam.isNotEmpty &&
        refImagePreview == null) {
      final f = File(filePathParam.replaceAll('file://', ''));
      if (f.existsSync()) {
        final size = f.lengthSync();
        final sizeLabel = size > 1048576
            ? '${(size / 1048576).toStringAsFixed(1)} MB'
            : '${(size / 1024).toStringAsFixed(0)} KB';
        final ext = filePathParam.split('.').last.toLowerCase();
        final isVideo = ['mp4', 'webm', 'mov', 'avi', 'mkv'].contains(ext);
        final isAudio = ['mp3', 'wav', 'm4a', 'aiff', 'flac'].contains(ext);
        final isPdf = ext == 'pdf';
        final kindLabel = isPdf
            ? '📄 PDF'
            : (isVideo ? '🎬 影片' : (isAudio ? '🎵 音檔' : '📎 檔案'));
        // qlmanage 縮圖：影片/PDF 才需要（音檔縮圖無意義，給播放器）
        final needsThumb = isVideo || isPdf;

        fileCard = Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: BridgeDSColors.of(context).borderDefault,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(kindLabel),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$sizeLabel',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle(),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Process.run('open', [f.path]),
                    icon: const Icon(Icons.launch, size: 14),
                    label: const Text('開啟'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                  ),
                ],
              ),
              // 本體預覽：影片/PDF 顯示 Quick Look 縮圖（海報幀/首頁）
              if (needsThumb)
                FutureBuilder<String?>(
                  future: _quickLookThumbnail(f.path),
                  builder: (ctx, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(File(snap.data!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink()),
                      ),
                    );
                  },
                ),
              // 本體預覽：音檔直接內建播放（不用開外部程式）
              if (isAudio)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _InlineAudioPlayer(path: f.path),
                ),
            ],
          ),
        );
      }
    }

    // [小葵 2026-09-24 Blue 令·定案圖組] 圖組展示——output 節點帶
    // _galleryB64s/_galleryUrls（整條上游鏈的定稿）時，渲染縮圖牆：
    // 2 列 wrap，每張可點 showAssetPreview 放大。定案＝導覽＋成果展示。
    final galleryB64s = (widget.params['_galleryB64s'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final galleryUrls = (widget.params['_galleryUrls'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.startsWith('http'))
            .toList() ??
        const <String>[];
    Widget? galleryWall;
    if (galleryB64s.length + galleryUrls.length > 1) {
      galleryWall = Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🖼️ 定案圖組（${galleryB64s.length + galleryUrls.length} 張）',
                style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in galleryB64s)
                  GestureDetector(
                    onTap: () => showAssetPreview(context,
                        title: widget.title,
                        imageBytes: base64.decode(b)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 108,
                        height: 108,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: Image.memory(
                            _cachedDecode(b),
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => const SizedBox(
                                width: 108,
                                height: 108,
                                child: Center(
                                    child: Icon(Icons.broken_image, size: 24))),
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final u in galleryUrls)
                  GestureDetector(
                    onTap: () => showAssetPreview(context,
                        title: widget.title, imageUrl: u),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 108,
                        height: 108,
                        child: Image.network(
                          u,
                          gaplessPlayback: true,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              width: 108,
                              height: 108,
                              child: Center(
                                  child: Icon(Icons.broken_image, size: 24))),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    // 文字結果 widget
    // [小葵 2026-09-24 Blue 令·定案圖組導覽] output 成果的文字若是
    // 「路徑: /xxx」格式，不顯示路徑文字——改「📂 前往資料夾」按鈕
    // （PathFinder 開啟該檔所在資料夾）。定案圖組看到的是導覽不是檔名。
    String? outputFilePath;
    if (lastOutput != null && lastOutput.contains('路徑: ')) {
      final idx = lastOutput.indexOf('路徑: ');
      final candidate = lastOutput
          .substring(idx + '路徑: '.length)
          .split('\n')
          .first
          .trim();
      if (candidate.startsWith('/') && File(candidate).existsSync()) {
        outputFilePath = candidate;
      }
    }
    final textResult = (lastOutput != null && lastOutput.isNotEmpty)
        ? (outputFilePath != null
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () =>
                        Process.run('open', ['-R', outputFilePath!]),
                    icon: const Icon(Icons.folder_open, size: 14),
                    label: const Text('前往資料夾'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                  ),
                ),
              )
            : Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: hasError
                      ? BridgeDSColors.of(context).accentRed.withValues(alpha: 0.08)
                      : BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasError
                        ? BridgeDSColors.of(context).accentRed.withValues(alpha: 0.2)
                        : BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: SelectableText(
                    lastOutput,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: hasError
                          ? BridgeDSColors.of(context).accentRed
                          : BridgeDSColors.of(context).textSecondary,
                        fontFamily: 'SF Mono',),
                  ),
                ),
              ))
        : const SizedBox.shrink();

    // [教練 Agent 2026-08-21] 自律——成果大預覽
    // 所有工作流成果（圖/文/影/音）都要能「大大的看見」。
    final videoUrl = _mediaUrlFromOutput(lastOutput, ['.mp4', '.webm', 'video']);
    final audioUrl = _mediaUrlFromOutput(lastOutput, ['.mp3', '.wav', '.m4a', '.aiff', 'audio', 'music', 'tts_']);
    final hasArticle = lastOutput != null &&
        lastOutput.length > 200 &&
        videoUrl == null &&
        audioUrl == null &&
        lastImageB64 == null &&
        lastImageUrl == null;
    final canPreview = hasImage || hasArticle || videoUrl != null || audioUrl != null;

    final previewButton = canPreview
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showAssetPreview(
                  context,
                  title: widget.title,
                  imageBytes: (lastImageB64 != null && lastImageB64.isNotEmpty)
                      ? base64.decode(lastImageB64)
                      : null,
                  imageUrl: (lastImageUrl != null &&
                          lastImageUrl.startsWith('http'))
                      ? lastImageUrl
                      : null,
                  videoUrl: videoUrl,
                  audioUrl: audioUrl,
                  articleText: hasArticle ? lastOutput : null,
                ),
                icon: const Icon(Icons.open_in_full, size: 14),
                label: const Text('查看成果'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    // [小葵 2026-09-23 修 bug] 沒跑過的節點也要顯示本體預覽（參考圖縮圖/
    // 檔案卡）——舊條件 imagePreview!=null || canPreview 只認「執行結果」，
    // 剛拖進來的節點兩者皆 false → refImagePreview/fileCard 被吃掉，
    // Blue 看到的還是純文字卡。
    final hasInlinePreview = imagePreview != null ||
        refImagePreview != null ||
        fileCard != null ||
        galleryWall != null;

    final resultWidget = (hasInlinePreview || canPreview)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              imagePreview,
              refImagePreview,
              fileCard,
              galleryWall,
              textResult,
              previewButton,
            ].whereType<Widget>().toList(),
          )
        : textResult;

    // [教練 Agent 2026-08-25 F-1] 素材池採用 UI — 共識往返的「回應」端。
    // AI 候選（params['candidates']）逐條列出，人點「採用」→
    // adoptedIndex 寫入 + coCreated: true（機制 4 共視產物）。
    final isPool = widget.nodeType == WorkflowNodeType.materialPool;
    Widget? adoptUi;
    if (isPool) {
      final candidates = (widget.params['candidates'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      if (candidates.isNotEmpty) {
        final adopted = (widget.params['adoptedIndex'] as num?)?.toInt() ?? -1;
        adoptUi = Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD54F).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFFFD54F).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                adopted >= 0 ? '已採用（共視產物 ✓）' : 'AI 候選——點一條採用：',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                      color: const Color(0xFFFFD54F),
                    ),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < candidates.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          candidates[i],
                          style: TierStyle.of(context, Tier.cardBody)
                              .toTextStyle()
                              .copyWith(
                                color: i == adopted
                                    ? const Color(0xFFFFD54F)
                                    : BridgeDSColors.of(context).textSecondary,
                              ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (i == adopted)
                        const Icon(Icons.check_circle,
                            size: 16, color: Color(0xFFFFD54F))
                      else
                        TextButton(
                          onPressed: () {
                            // 採用 = 回應端：寫 adoptedIndex + coCreated
                            widget.onParamChanged?.call('adoptedIndex', i);
                            widget.onParamChanged?.call('coCreated', true);
                          },
                          child: const Text('採用',
                              style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...widgets,
        resultWidget,
        if (adoptUi != null) adoptUi,
      ],
    );
  }

  /// [教練 Agent 2026-08-21] 從文字 output 抽媒體 URL（影片/音樂生成結果
  /// 現在只是 output 裡的一條 URL）
  static String? _mediaUrlFromOutput(String? output, List<String> markers) {
    if (output == null) return null;
    final urlRegex = RegExp(r'https?://\S+');
    for (final m in urlRegex.allMatches(output)) {
      final url = m.group(0)!;
      for (final marker in markers) {
        if (url.toLowerCase().contains(marker)) {
          return url;
        }
      }
    }
    return null;
  }

  /// 根據節點型別返回對應的 inline widget 列表。
  /// 參考設計文件 §五 每種節點類型的 Port 定義。
  List<Widget> _inlineWidgetsForType(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.input:
        return [
          _inlineDropdown(
            key: 'inputType',
            label: '來源',
            value: widget.params['inputType']?.toString() ?? 'text',
            items: const ['text', 'image', 'file'],
            labels: const ['文字', '圖片', '檔案'],
          ),
          _inlineTextField(
            key: 'label',
            label: '標籤',
            hint: '顯示名稱',
          ),
          // [教練 Agent 2026-08-15 使用者 通盤檢討] content 欄——執行時整條鏈的
          // 源頭文字。之前卡片上沒這個欄位，使用者想填主題也沒得填
          // （analyzer 報空、使用者找不到哪裡填的謎底）。
          // [2026-08-27 Blue 抓包] 提示語按節點身分給對應例子——
          // 範本節點（角色與素材/主題與素材）給角色+素材格式，
          // 純主題節點給主題例子。舊版一律「主題」例子，
          // 照填會讓 LLM 拿不到角色，產出退化。
          _inlineTextArea(
            key: 'content',
            label: '內容',
            hint: _inputContentHint(),
          ),
        ];

      case WorkflowNodeType.llm:
        // Get models for the selected service
        final serviceId = widget.params['serviceId']?.toString() ?? '';
        final service = ServiceRegistry.instance.serviceById(serviceId);
        final availableModels = service?.models ?? [];
        
        return [
          // [教練 Agent 2026-08-01] 服務選擇（能力中心）
          _inlineDropdown(
            key: 'serviceId',
            label: '服務',
            value: serviceId,
            items: const [
              '', 'openai_llm', 'glm_llm', 'kimi_llm', 'minimax_llm', 'local_llm',
            ],
            labels: const [
              '（預設）', 'OpenAI', 'GLM (ZAI)', 'Kimi', 'MiniMax', '本地模型',
            ],
          ),
          _inlineDropdown(
            key: 'model',
            label: '模型',
            value: widget.params['model']?.toString() ?? '',
            items: availableModels.map((m) => m.id).toList(),
            labels: availableModels.map((m) => m.displayName ?? m.id).toList(),
          ),
          _inlineTextArea(
            key: 'prompt',
            label: '提示詞',
            // [2026-08-27 Blue 普查] 教 {input} 概念——佔位符會被上游
            // 內容替換（IG 範本「素材：{input}」的謎底就在這）
            hint: '提示詞模板，可用 {input} 帶入上游內容，例如：\n請把以下素材寫成貼文：{input}',
          ),
          _inlineSlider(
            key: 'temperature',
            label: '溫度',
            min: 0.0,
            max: 2.0,
            divisions: 20,
          ),
          _inlineNumberField(
            key: 'maxTokens',
            label: '最長回覆',
          ),
        ];

      case WorkflowNodeType.tool:
        return [
          _inlineDropdown(
            key: 'toolName',
            label: '工具',
            value: widget.params['toolName']?.toString() ?? '',
            items: const [
              'browse',
              'desktop_files',
              'memory_search',
              'code_exec',
              'web_search',
            ],
          ),
          _inlineTextArea(
            key: 'args',
            label: '參數',
            hint: '{"query": "..."}',
          ),
        ];

      case WorkflowNodeType.imageGen:
        // Get models for the selected service
        // [教練 Agent 2026-08-26 使用者決策] OpenAI Key 已停用——預設 MiniMax
        // [小葵 2026-09-23 Blue 令] OpenAI key 已恢復（golden_keys 有值）——
        // 「（已停用）」改回正常標籤，預設仍 MiniMax。
        final imageServiceId = widget.params['serviceId']?.toString() ?? 'minimax_image';
        final imageService = ServiceRegistry.instance.serviceById(imageServiceId);
        final availableImageModels = imageService?.models ?? [];
        
        return [
          // [教練 Agent 2026-08-01] 服務選擇（能力中心）
          _inlineDropdown(
            key: 'serviceId',
            label: '服務',
            value: imageServiceId,
            items: const [
              'minimax_image', 'gemini_image', 'openai_image',
            ],
            labels: const [
              'MiniMax image-01（預設）', 'Gemini Nano Banana', 'OpenAI',
            ],
          ),
          if (availableImageModels.isNotEmpty)
            _inlineDropdown(
              key: 'model',
              label: '模型',
              value: widget.params['model']?.toString() ?? '',
              items: availableImageModels.map((m) => m.id).toList(),
              labels: availableImageModels.map((m) => m.displayName ?? m.id).toList(),
            ),
          _inlineTextArea(
            key: 'prompt',
            label: '提示詞',
            // [2026-08-27 Blue 普查] 提醒 {input}——IG 範本 imageGen
            // 吃 LLM 產出；寫死靜態文字會讓圖跟資料流脫鉤
            hint: '圖片描述，可用 {input} 帶入上游（如 LLM 的產出）',
          ),
          _inlineDropdown(
            key: 'size',
            label: '尺寸',
            value: widget.params['size']?.toString() ?? '1024x1024',
            items: const ['1024x1024', '1792x1024', '1024x1792'],
          ),
          _inlineNumberField(
            key: 'seed',
            label: '種子',
          ),
        ];

      // [教練 Agent 2026-08-01] Vision 節點 — 圖片理解
      case WorkflowNodeType.vision:
        return [
          _inlineDropdown(
            key: 'serviceId',
            label: '服務',
            value: widget.params['serviceId']?.toString() ?? '',
            items: const ['', 'openai_vision'],
            labels: const ['（預設）', 'OpenAI GPT-4o Vision'],
          ),
          _inlineTextArea(
            key: 'prompt',
            label: '問題',
            // [2026-08-27 Blue 普查] 語意修正——這欄是「問 AI 什麼」，
            // 不是「描述圖片」（描述是 AI 的工作）。舊 hint 誤導。
            hint: '要問這張圖的問題，例如：這張圖裡的角色有哪些視覺特徵？',
          ),
        ];

      // [教練 Agent 2026-08-01] CharacterLock 節點 — 角色一致性
      case WorkflowNodeType.characterLock:
        return [
          _inlineDropdown(
            key: 'serviceId',
            label: '服務',
            value: widget.params['serviceId']?.toString() ?? '',
            items: const ['', 'openai_character', 'flux_character'],
            labels: const [
              '（預設）', 'OpenAI (~80%)', 'Flux+IP-Adapter (~90%)',
            ],
          ),
          _inlineTextArea(
            key: 'prompt',
            label: '提示詞',
            hint: '新場景/姿勢/服裝描述，可用 {input} 帶入上游',
          ),
          _inlineDropdown(
            key: 'size',
            label: '尺寸',
            value: widget.params['size']?.toString() ?? '1024x1024',
            items: const ['1024x1024', '1792x1024', '1024x1792'],
          ),
        ];

      case WorkflowNodeType.videoGen:
        // Get models for the selected service
        final videoServiceId = widget.params['serviceId']?.toString() ?? '';
        final videoService = ServiceRegistry.instance.serviceById(videoServiceId);
        final availableVideoModels = videoService?.models ?? [];
        
        return [
          // [教練 Agent 2026-08-01] 服務選擇
          _inlineDropdown(
            key: 'serviceId',
            label: '服務',
            value: videoServiceId,
            items: const ['', 'runway_video', 'minimax_video', 'kling_video'],
            labels: const ['（預設）', 'Runway Gen-3', 'MiniMax Video', 'Kling AI'],
          ),
          if (availableVideoModels.isNotEmpty)
            _inlineDropdown(
              key: 'model',
              label: '模型',
              value: widget.params['model']?.toString() ?? '',
              items: availableVideoModels.map((m) => m.id).toList(),
              labels: availableVideoModels.map((m) => m.displayName ?? m.id).toList(),
            ),
          _inlineTextArea(
            key: 'prompt',
            label: '提示詞',
            hint: '影片描述，可用 {input} 帶入上游',
          ),
          _inlineSlider(
            key: 'duration',
            label: '時長',
            min: 1,
            max: 30,
            divisions: 29,
            unit: '秒',
          ),
        ];

      case WorkflowNodeType.musicGen:
        // Get models for the selected service
        final musicServiceId = widget.params['serviceId']?.toString() ?? '';
        final musicService = ServiceRegistry.instance.serviceById(musicServiceId);
        final availableMusicModels = musicService?.models ?? [];
        
        return [
          // [教練 Agent 2026-08-01] 服務選擇
          _inlineDropdown(
            key: 'serviceId',
            label: '服務',
            value: musicServiceId,
            items: const ['', 'minimax_music', 'suno_music'],
            labels: const ['（預設）', 'MiniMax Music', 'Suno V4'],
          ),
          if (availableMusicModels.isNotEmpty)
            _inlineDropdown(
              key: 'model',
              label: '模型',
              value: widget.params['model']?.toString() ?? '',
              items: availableMusicModels.map((m) => m.id).toList(),
              labels: availableMusicModels.map((m) => m.displayName ?? m.id).toList(),
            ),
          _inlineTextArea(
            key: 'prompt',
            label: '提示詞',
            hint: '音樂描述，可用 {input} 帶入上游',
          ),
          _inlineSlider(
            key: 'duration',
            label: '時長',
            min: 5,
            max: 120,
            divisions: 23,
            unit: '秒',
          ),
        ];

      case WorkflowNodeType.tts:
        return [
          _inlineTextArea(
            key: 'text',
            label: '文字',
            hint: '要朗讀的文字，可用 {input} 帶入上游',
          ),
          _inlineDropdown(
            key: 'voice',
            label: '語音',
            value: widget.params['voice']?.toString() ?? '',
            items: const ['alloy', 'nova', 'shimmer', 'echo', 'onyx'],
            // [教練 Agent 2026-08-15 使用者回饋] 介面文字中文化——英文代號配中文說明
            labels: const ['合金（中性）', '新星（女聲）', '微光（柔和）', '回聲（沉穩）', '黑曜（男聲）'],
          ),
          _inlineSlider(
            key: 'speed',
            label: '語速',
            min: 0.5,
            max: 2.0,
            divisions: 15,
          ),
          // [小橋 2026-09-18] 試聽按鈕——用目前面板參數即時合成播放
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  final text = widget.params['text']?.toString() ?? '';
                  if (text.isEmpty) return;
                  final s =
                      double.tryParse(widget.params['speed']?.toString() ?? '') ?? 1.0;
                  // 面板語速 0.5–2.0，服務端 clamp 0.0–1.0 → 除以 2 對應
                  CanvasTtsService.instance.speak(text: text, speed: (s / 2).clamp(0.0, 1.0));
                },
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('試聽'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => CanvasTtsService.instance.stopSpeak(),
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('停止'),
              ),
            ],
          ),
        ];

      case WorkflowNodeType.move: // 🥋 [Blue 拍板] 招式節點——選招式
        // 招式清單從 SystemRoutineStore 撈（FutureBuilder 動態選單太重，
        // 用文字輸入 moveName 模糊匹配；moveId 留給範本/程式呼叫）
        return [
          _inlineTextField(
            key: 'moveName',
            label: '招式名稱',
            hint: '例如：發票歸檔（訓練AI夥伴錄的招式）',
          ),
          _inlineTextField(
            key: 'moveId',
            label: '招式 ID（進階）',
            hint: '留空用名稱模糊匹配',
          ),
        ];

      case WorkflowNodeType.condition:
        return [
          _inlineTextField(
            key: 'expression',
            label: '條件',
            // [教練 Agent 2026-08-15 使用者回饋] 提示詞說明語法——
            // input.contains("是") 這種判斷式，寫清楚可用寫法
            hint: '判斷式，如 input.contains("知識") 或 input.length > 10',
          ),
        ];

      case WorkflowNodeType.merge:
        return [
          _inlineDropdown(
            key: 'strategy',
            label: '合併模式',
            value: widget.params['strategy']?.toString() ?? 'concat',
            items: const ['concat', 'join', 'first', 'last'],
            labels: const ['串接', '合併', '首個', '末個'],
          ),
        ];

      case WorkflowNodeType.output:
        return [
          _inlineDropdown(
            key: 'displayMode',
            label: '顯示模式',
            value: widget.params['displayMode']?.toString() ?? 'text',
            items: const ['text', 'image', 'audio', 'preview'],
            labels: const ['文字', '圖片', '語音', '預覽'],
          ),
          _inlineTextField(
            key: 'label',
            label: '標籤',
            hint: '輸出標籤',
          ),
        ];

      case WorkflowNodeType.subWorkflow:
        // [教練 Agent 2026-08-15 使用者 提案] 子工作流改用選擇器——
        // 點擊彈出預設資料夾（~/Documents/bridge_workflows/）清單
        // ＋內建範本，也可瀏覽任意位置。不再手填 ID。
        return [
          _subWorkflowPickerField(),
        ];
      case WorkflowNodeType.schedule:
        return [
          _inlineDropdown(
            key: 'scheduleType',
            label: '類型',
            value: widget.params['scheduleType']?.toString() ?? 'daily',
            items: const ['daily', 'weekly', 'monthly', 'once', 'cron'],
            labels: const ['每天', '每週', '每月', '指定日期', '自訂 Cron'],
          ),
          _inlineTextField(
            key: 'time',
            label: '時間',
            hint: 'HH:MM',
          ),
          if ((widget.params['scheduleType'] ?? 'daily') == 'weekly')
            _inlineDropdown(
              key: 'weekday',
              label: '星期',
              value: widget.params['weekday']?.toString() ?? '1',
              items: const ['1', '2', '3', '4', '5', '6', '7'],
              labels: const ['週一', '週二', '週三', '週四', '週五', '週六', '週日'],
            ),
          if ((widget.params['scheduleType'] ?? 'daily') == 'monthly')
            _inlineDropdown(
              key: 'dayOfMonth',
              label: '幾號',
              value: widget.params['dayOfMonth']?.toString() ?? '1',
              items: [for (int d = 1; d <= 31; d++) d.toString()],
              labels: [for (int d = 1; d <= 31; d++) '$d 號'],
            ),
          if ((widget.params['scheduleType'] ?? 'daily') == 'once')
            _inlineTextField(
              key: 'date',
              label: '日期',
              hint: 'YYYY-MM-DD',
            ),
          if ((widget.params['scheduleType'] ?? 'daily') == 'cron')
            _inlineTextField(
              key: 'cronExpr',
              label: 'Cron 運算式',
              hint: '分 時 日 月 週（如 */15 * * * *）',
            ),
          _buildNextFireLabel(),
        ];
      case WorkflowNodeType.materialPool: // [教練 Agent 2026-08-25 F-1] 素材池
        return [
          _inlineTextArea(
            key: 'topic',
            label: '發想主題',
            hint: 'AI 針對什麼產候選？可含 {input} 帶入上游',
          ),
          _inlineDropdown(
            key: 'count',
            label: '候選數',
            value: widget.params['count']?.toString() ?? '3',
            items: const ['2', '3', '4', '5'],
            labels: const ['2 條', '3 條', '4 條', '5 條'],
          ),
        ];
      case WorkflowNodeType.knowledge: // [教練 Agent 2026-08-16] vault 知識節點
        return [
          _inlineTextArea(
            key: 'query',
            label: '檢索詞',
            hint: '要從 vault 撈什麼知識？可含 {input} 帶入上游',
          ),
          _inlineDropdown(
            key: 'mode',
            label: '模式',
            value: widget.params['mode']?.toString() ?? 'semantic',
            items: const ['semantic', 'fullText'],
            labels: const ['語意搜尋', '全文搜尋'],
          ),
          _inlineDropdown(
            key: 'topK',
            label: '筆數',
            value: widget.params['topK']?.toString() ?? '5',
            items: const ['3', '5', '8', '10'],
            labels: const ['3 筆', '5 筆', '8 筆', '10 筆'],
          ),
          _inlineTextField(
            key: 'room',
            label: '房間',
            hint: '留空 = 全部房間',
          ),
        ];
    }
  }

  /// [教練 Agent 2026-07-24] schedule 節點顯示下次觸發時間
  Widget _buildNextFireLabel() {
    final params = widget.params;
    final now = DateTime.now();

    // 用 ScheduleEngine 的靜態計算邏輯
    // 因為 calculateNextFire 是實例方法，這裡用簡易計算
    final next = _computeNextFire(params, now);
    if (next == null) return const SizedBox.shrink();

    final now2 = DateTime.now();
    final diff = next.difference(now2);
    String label;
    if (diff.isNegative) {
      label = '已過期';
    } else if (diff.inMinutes < 1) {
      label = '即將觸發';
    } else if (diff.inHours < 1) {
      label = '${diff.inMinutes} 分鐘後';
    } else if (diff.inHours < 24) {
      label = '${diff.inHours} 小時後';
    } else {
      label = '${diff.inDays} 天後';
    }

    final timeStr =
        '${next.month}/${next.day} ${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 12, color: BridgeDSColors.of(context).textMuted),
          const SizedBox(width: 4),
          Text(
            '$timeStr ($label)',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
        ],
      ),
    );
  }

  /// 簡易下次觸發時間計算（不含 cron，cron 不顯示下次時間）
  DateTime? _computeNextFire(Map<String, dynamic> params, DateTime now) {
    final scheduleType = params['scheduleType']?.toString() ?? 'daily';
    final timeStr = params['time']?.toString() ?? '09:00';
    final timeParts = timeStr.split(':');
    if (timeParts.length != 2) return null;
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return null;

    switch (scheduleType) {
      case 'daily':
        var target = DateTime(now.year, now.month, now.day, hour, minute);
        if (!target.isAfter(now)) {
          target = target.add(const Duration(days: 1));
        }
        return target;
      case 'weekly':
        final weekday = params['weekday'] as int? ?? 1;
        var target = DateTime(now.year, now.month, now.day, hour, minute);
        int daysUntil = (weekday - now.weekday) % 7;
        if (daysUntil < 0) daysUntil += 7;
        if (daysUntil == 0 && !target.isAfter(now)) daysUntil = 7;
        return target.add(Duration(days: daysUntil));
      case 'monthly':
        final dayOfMonth = params['dayOfMonth'] as int? ?? 1;
        var target = DateTime(now.year, now.month, dayOfMonth, hour, minute);
        if (!target.isAfter(now)) {
          var nm = now.month + 1;
          var ny = now.year;
          if (nm > 12) { nm = 1; ny++; }
          target = DateTime(ny, nm, dayOfMonth, hour, minute);
        }
        return target;
      case 'once':
        final dateStr = params['date']?.toString() ?? '';
        if (dateStr.isEmpty) return null;
        final dp = dateStr.split('-');
        if (dp.length != 3) return null;
        final y = int.tryParse(dp[0]);
        final m = int.tryParse(dp[1]);
        final d = int.tryParse(dp[2]);
        if (y == null || m == null || d == null) return null;
        return DateTime(y, m, d, hour, minute);
      default:
        return null; // cron 不在此計算
    }
  }

  // ── Inline 表單元件 ──

  Widget _inlineDropdown({
    required String key,
    required String label,
    required String value,
    required List<String> items,
    List<String>? labels,
  }) {
    final displayLabels = labels ?? items;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
          SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).canvas,
              borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
              border: Border.all(color: BridgeDSColors.of(context).borderDefault, width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : null,
                isExpanded: true,
                isDense: true,
                dropdownColor: BridgeDSColors.of(context).surfaceElevated,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
                hint: Text(
                  value.isEmpty ? '選擇...' : value,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,),
                ),
                items: [
                  for (var i = 0; i < items.length; i++)
                    DropdownMenuItem(
                      value: items[i],
                      child: Text(displayLabels[i],
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) widget.onParamChanged?.call(key, v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineTextField({
    required String key,
    required String label,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
          SizedBox(height: 2),
          _StatefulTextField(
            initialValue: widget.params[key]?.toString() ?? '',
            hint: hint,
            onChanged: (v) => widget.onParamChanged?.call(key, v),
          ),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-15 使用者 提案] 子工作流選擇器欄位——
  /// 顯示目前選的 workflowRef，點擊彈出 SubWorkflowPickerDialog。
  Widget _subWorkflowPickerField() {
    final ds = BridgeDSColors.of(context);
    final currentRef = widget.params['workflowRef']?.toString() ?? '';
    final display = currentRef.isEmpty
        ? '點擊選擇子工作流…'
        : currentRef.split('/').last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('子工作流',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted)),
          const SizedBox(height: 2),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final pick = await showDialog<SubWorkflowPick>(
                context: context,
                builder: (_) => SubWorkflowPickerDialog(currentRef: currentRef),
              );
              if (pick != null) {
                widget.onParamChanged?.call('workflowRef', pick.ref);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: ds.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ds.borderDefault),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 16, color: ds.accentBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      display,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                            color: currentRef.isEmpty ? ds.textMuted : ds.textPrimary,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.folder_open, size: 16, color: ds.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [2026-08-27] input content 提示語——按標籤身分給對應例子
  String _inputContentHint() {
    final label = widget.params['label']?.toString() ?? '';
    if (label.contains('素材') || label.contains('角色')) {
      return '角色＋素材，例如：\n角色：一隻傲嬌的虎斑貓店長\n素材：鹿角蕨上架、照顧懶人包三招';
    }
    if (label.contains('故事') || label.contains('主題與')) {
      return '主題或故事，例如：我家貓的一天（知識型）';
    }
    return '執行時餵給下游的主題文字，例如：介紹我家貓的三個冷知識';
  }

  Widget _inlineTextArea({
    required String key,
    required String label,
    String? hint,
    bool flexHeight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
          SizedBox(height: 2),
          _ResizableTextArea(
            initialValue: widget.params[key]?.toString() ?? '',
            hint: hint,
            onChanged: (v) => widget.onParamChanged?.call(key, v),
            flexHeight: flexHeight,
          ),
        ],
      ),
    );
  }

  Widget _inlineSlider({
    required String key,
    required String label,
    required double min,
    required double max,
    required int divisions,
    String? unit,
  }) {
    final value = (widget.params[key] as num?)?.toDouble() ?? min;
    final clamped = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(label,
                  style:
                      TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
              Spacer(),
              Text(
                unit != null
                    ? '${clamped.toStringAsFixed(0)} $unit'
                    : clamped.toStringAsFixed(1),
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape:
                  RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape:
                  RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: BridgeDSColors.of(context).accentBlue,
              inactiveTrackColor: BridgeDSColors.of(context).borderDefault,
              thumbColor: BridgeDSColors.of(context).accentBlue,
            ),
            child: Slider(
              value: clamped,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) => widget.onParamChanged?.call(key, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineNumberField({
    required String key,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
          SizedBox(height: 2),
          SizedBox(
            height: 28,
            child: TextField(
              controller: TextEditingController(
                  text: widget.params[key]?.toString() ?? ''),
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                filled: true,
                fillColor: BridgeDSColors.of(context).canvas,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                  borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                  borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                  borderSide:
                      BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1.5),
                ),
              ),
              onChanged: (v) {
                final num? parsed = num.tryParse(v);
                widget.onParamChanged?.call(key, parsed ?? v);
              },
            ),
          ),
        ],
      ),
    );
  }
}


// ── 節點拖拉調整大小 ──────────────────────────────────
// [教練 Agent 2026-07-24] 在節點右下角加 resize handle，讓使用者拖拉調整寬度

class _NodeResizeWrapper extends StatefulWidget {
  final Widget child;
  final WorkflowNodeType? nodeType;
  const _NodeResizeWrapper({required this.child, this.nodeType});

  @override
  State<_NodeResizeWrapper> createState() => _NodeResizeWrapperState();
}

class _NodeResizeWrapperState extends State<_NodeResizeWrapper> {
  @override
  Widget build(BuildContext context) {
    // [教練 Agent 2026-07-24] 移除縮放功能 — 節點大小由內容自動決定
    // 文字框靠行數自動撐大節點
    return widget.child;
  }
}

// ── _StatefulTextField ────────────────────────────────

/// 單行文字輸入框，用 StatefulWidget 管理 TextEditingController 生命週期。
///
/// 解決：每次 build 重建 controller 導致游標跳回開頭、焦點丟失。
class _StatefulTextField extends StatefulWidget {
  const _StatefulTextField({
    required this.initialValue,
    this.hint,
    this.onChanged,
  });

  final String initialValue;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  State<_StatefulTextField> createState() => _StatefulTextFieldState();
}

class _StatefulTextFieldState extends State<_StatefulTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _StatefulTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有當外部值與 controller 不同且使用者沒在輸入時才更新
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null, // [教練 Agent 2026-07-24] 自動換行 — 文字到邊界時往下移行
      minLines: 1,
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle:
            TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textQuaternary,),
        filled: true,
        fillColor: BridgeDSColors.of(context).canvas,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide:
              BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1.5),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

// ── _ResizableTextArea ────────────────────────────────

/// 多行文字輸入框，支援拖拉調整高度、滾輪事件攔截。
///
/// 解決：
/// 1. Controller 生命週期管理（不再每次 build 重建）
/// 2. 換行方向（maxLines: null 自然增長）
/// 3. 拖拉調整大小
/// 4. 滾輪事件不冒泡到畫布縮放
class _ResizableTextArea extends StatefulWidget {
  const _ResizableTextArea({
    required this.initialValue,
    this.hint,
    this.onChanged,
    this.flexHeight = false,
  });

  final String initialValue;
  final String? hint;
  final ValueChanged<String>? onChanged;
  /// [教練 Agent 2026-07-24] 為 true 時，textarea 會用 Expanded 撐滿父容器剩餘空間
  final bool flexHeight;

  @override
  State<_ResizableTextArea> createState() => _ResizableTextAreaState();
}

class _ResizableTextAreaState extends State<_ResizableTextArea> {
  late final TextEditingController _controller;
  late final ScrollController _scrollController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _scrollController = ScrollController();
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ResizableTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // [教練 Agent 2026-07-24] Listener 攔截滾輪事件，阻止冒泡到畫布 zoom handler
        // [教練 Agent 2026-07-25] 修正：Expanded/Flexible 必須直接在 Column 裡，
        // 不能被 Listener 包住，否則 ParentDataWidget assertion 爆炸
        widget.flexHeight
            ? Expanded(
                child: Listener(
                  onPointerSignal: _handleScrollSignal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: _buildTextField(),
                  ),
                ),
              )
            : Flexible(
                child: Listener(
                  onPointerSignal: _handleScrollSignal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: _buildTextField(),
                  ),
                ),
              ),
      ],
    );
  }

  /// [教練 Agent 2026-07-25] 抽出滾輪處理，供兩條路徑共用
  void _handleScrollSignal(PointerSignalEvent pointerSignal) {
    if (pointerSignal is PointerScrollEvent) {
      final newOffset = _scrollController.position.pixels +
          pointerSignal.scrollDelta.dy;
      _scrollController.position.moveTo(
        newOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  /// [教練 Agent 2026-07-24] 抽出 TextField 供 flexHeight 和非 flexHeight 共用
  Widget _buildTextField() {
    return TextField(
      controller: _controller,
      scrollController: _scrollController,
      focusNode: _focusNode,
      maxLines: null,
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textQuaternary,),
        filled: true,
        fillColor: BridgeDSColors.of(context).canvas,
        isDense: true,
        contentPadding: const EdgeInsets.all(6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide:
              BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide:
              BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide: BorderSide(
              color: BridgeDSColors.of(context).accentBlue, width: 1.5),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

// ══════════════════════════════════════════════════════
// [小葵 2026-09-23 Blue 令·二] 檔案本體預覽元件
// 影片/PDF：qlmanage（macOS Quick Look）縮圖——影片=海報幀、PDF=首頁
// 音檔：內建迷你播放器（native_audio_bytes_player，不開外部程式）
// ══════════════════════════════════════════════════════

/// Quick Look 縮圖產生器（帶記憶體快取——同檔案不重跑 qlmanage）
final Map<String, String?> _qlThumbCache = {};

Future<String?> _quickLookThumbnail(String filePath) async {
  if (_qlThumbCache.containsKey(filePath)) return _qlThumbCache[filePath];
  try {
    final dir = Directory.systemTemp.createTempSync('bridge_ql');
    final r = await Process.run(
        'qlmanage', ['-t', '-s', '480', '-o', dir.path, filePath]);
    if (r.exitCode != 0) {
      _qlThumbCache[filePath] = null;
      return null;
    }
    // qlmanage 輸出：<原檔名>.<ext>.png（同名加後綴）
    final base = filePath.split('/').last;
    final candidates = dir.listSync().whereType<File>().toList();
    File? thumb;
    for (final f in candidates) {
      if (f.path.split('/').last.startsWith(base)) {
        thumb = f;
        break;
      }
    }
    thumb ??= candidates.isNotEmpty ? candidates.first : null;
    _qlThumbCache[filePath] = thumb?.path;
    return thumb?.path;
  } catch (_) {
    _qlThumbCache[filePath] = null;
    return null;
  }
}

/// 迷你音檔播放器——節點卡內直接播放（點播放→載入 bytes→native player）
class _InlineAudioPlayer extends StatefulWidget {
  final String path;
  const _InlineAudioPlayer({super.key, required this.path});

  @override
  State<_InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<_InlineAudioPlayer> {
  bool _playing = false;
  bool _loading = false;

  Future<void> _toggle() async {
    final player = NativeAudioBytesPlayer();
    if (_playing) {
      await player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final bytes = await File(widget.path).readAsBytes();
      final ext = widget.path.split('.').last.toLowerCase();
      if (mounted) setState(() => _loading = false);
      await player.play(bytes, extension: ext);
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _loading = false, );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _toggle,
          icon: _loading
              ? const SizedBox(
                  height: 14, width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_playing ? Icons.stop : Icons.play_arrow, size: 18),
          tooltip: _playing ? '停止' : '播放',
        ),
        Text(
          _playing ? '播放中…' : '點播試聽',
          style: TierStyle.of(context, Tier.cardCaption).toTextStyle(),
        ),
      ],
    );
  }
}
