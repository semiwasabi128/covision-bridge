// port_widget.dart
// 畫布 Port UI Widget — 圓點 + 標籤 + 拖曳偵測
// 建立日期: 2026-07-15
// 參考: graph_edit BasicNodePortWidget + LiteGraph drawNode port rendering
//
// 純 UI Widget，不負責狀態管理。
// 拖曳偵測透過 GlobalKey + RenderMetaData 標記 port 位置，
// 讓 GraphCanvas 的 RenderObject 層能取得 port 的世界座標。

import 'package:flutter/material.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

// ── Port 位置標記 ──────────────────────────────────────

/// 附加在 PortWidget 的 RenderMetaData 上的資料。
/// RenderObject 層透過 visitChildren + findRootAncestorStateOfType
/// 可以取得所有 port 的座標，用來繪製連線。
class PortMetadata {
  /// 節點 ID
  final String nodeId;

  /// Port 名稱（對應 PortDef.name）
  final String portName;

  /// 是否為輸入埠
  final bool isInput;

  /// 資料型別
  final PortDataType dataType;

  /// 方向向量：input = (-1, 0) 向左，output = (1, 0) 向右
  final Offset direction;

  /// PortWidget 的 GlobalKey，用於取得 RenderBox → 螢幕座標
  final GlobalKey portKey;

  PortMetadata({
    required this.nodeId,
    required this.portName,
    required this.isInput,
    required this.dataType,
    required this.direction,
    required this.portKey,
  });

  /// 唯一識別：nodeId.portName
  String get id => '$nodeId.$portName';

  @override
  String toString() => 'PortMetadata($id, input: $isInput, type: ${dataType.name})';
}

// ── Port 顏色 helper ──────────────────────────────────

/// 根據資料型別取得 port 顏色。
/// [教練 Agent 2026-08-15 Phase 2.5-A] 與 NodeConnection.typeColor 對齊（連線同色系統）。
/// text=藍 / image=洋紅 / audio=琥珀 / video=紅 / json=綠 / file=紫 / any=灰白
Color portDataTypeColor(BuildContext context, PortDataType type) {
  final ds = BridgeDSColors.of(context);
  switch (type) {
    case PortDataType.text:
      return ds.accentBlue; // 藍
    case PortDataType.image:
      return ds.accentMagenta; // 洋紅（原 accentRed 跟 video 撞色）
    case PortDataType.audio:
      return ds.accentYellow; // 琥珀
    case PortDataType.video:
      return ds.accentRed; // 紅
    case PortDataType.json:
      return ds.accentGreen; // 綠
    case PortDataType.file:
      return ds.accentPurple; // 紫
    case PortDataType.any:
      return ds.textSecondary; // 灰白（萬用）
  }
}

// ── PortWidget ────────────────────────────────────────

/// 畫布 Port UI Widget。
///
/// 顯示為 12px 圓點 + 中文標籤。
/// 透過 [GlobalKey] 和 [RenderMetaData] 標記位置，
/// 讓 GraphCanvas RenderObject 層能取得 port 的世界座標來繪製連線。
///
/// 拖曳偵測透過 [onDragStart] 回調通知 CanvasController。
/// [教練 Agent 2026-08-15 Phase 2.5-C] 改為 StatefulWidget：
/// - hover 時圓點放大（16px）＋光暈 → 使用者確定「抓得到」
/// - 命中區域最小 26×26（對齊 ComfyUI 體感）＋ opaque，
///   修「每三次拉線一次變成拖整個節點」的問題
class PortWidget extends StatefulWidget {
  /// 節點 ID
  final String nodeId;

  /// Port 定義
  final PortDef port;

  /// 是否為輸入埠（true = 左側，false = 右側）
  final bool isInput;

  /// 是否處於折疊狀態（折疊時只顯示圓點，不顯示標籤）
  final bool isCollapsed;

  /// 開始拖曳連線的回調（從此 port 拖出一條連線）
  /// 參數：nodeId, portName, isInput, portKey
  final void Function(String nodeId, String portName, bool isInput, GlobalKey portKey)?
      onDragStart;

  /// 拖曳結束的回調（嘗試在此 port 建立連線）
  final void Function(String nodeId, String portName, bool isInput)?
      onDragEnd;

  /// 點擊 port 的回調
  final void Function(String nodeId, String portName, bool isInput)?
      onTap;

  /// 此 port 是否為連線拖曳的合法目標（true = 高亮可連）
  final bool isConnectionTarget;

  /// 此 port 是否正在被拖曳中（source port）
  final bool isDragSource;

  /// [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳連線中：此 port 是型別相容的合法目標（亮）
  final bool isCompatibleTarget;

  /// [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳連線中：此 port 方向對但型別不相容（變暗）
  final bool isDimmed;

  /// port 的 GlobalKey，外部可傳入以便共享
  final GlobalKey? portKey;

  /// port 的中文標籤（若不指定，由 [portDataTypeLabel] 自動產生）
  final String? label;

  const PortWidget({
    super.key,
    required this.nodeId,
    required this.port,
    required this.isInput,
    this.isCollapsed = false,
    this.onDragStart,
    this.onDragEnd,
    this.onTap,
    this.isConnectionTarget = false,
    this.isDragSource = false,
    this.isCompatibleTarget = false,
    this.isDimmed = false,
    this.portKey,
    this.label,
  });

  @override
  State<PortWidget> createState() => _PortWidgetState();
}

class _PortWidgetState extends State<PortWidget> {
  bool _hovered = false;

  // ── 以下 getter 轉發，讓既有程式碼不用改 ──
  String get nodeId => widget.nodeId;
  PortDef get port => widget.port;
  bool get isInput => widget.isInput;
  bool get isCollapsed => widget.isCollapsed;
  void Function(String, String, bool, GlobalKey)? get onDragStart => widget.onDragStart;
  void Function(String, String, bool)? get onDragEnd => widget.onDragEnd;
  void Function(String, String, bool)? get onTap => widget.onTap;
  bool get isConnectionTarget => widget.isConnectionTarget;
  bool get isDragSource => widget.isDragSource;
  bool get isCompatibleTarget => widget.isCompatibleTarget;
  bool get isDimmed => widget.isDimmed;
  GlobalKey? get portKey => widget.portKey;
  String? get label => widget.label;

  @override
  Widget build(BuildContext context) {
    final key = portKey ?? GlobalKey();
    final color = portDataTypeColor(context, port.dataType);
    final portLabel = label ?? portDataTypeLabel(port.dataType);

    // [教練 Agent 2026-08-15 統一錨點] 外層不再掛 MetaData——
    // 連線錨點只有一個真相來源：_buildPortRow 裡圓點上的 MetaData。
    // （先前外層列+內層圓點雙 MetaData，覆蓋順序寫反導致列中心覆蓋圓點，
    //  工具/LLM 節點 port 列寬、偏移最劇——使用者 實測回報。）
    return MouseRegion(
      // [教練 Agent 2026-08-15 Phase 2.5-C] hover 放大回饋——抓得到才拉得出
      cursor: SystemMouseCursors.click,
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: key,
        onTap: onTap != null
            ? () => onTap!(nodeId, port.name, isInput)
            : null,
        onPanStart: onDragStart != null
            ? (_) => onDragStart!(nodeId, port.name, isInput, key)
            : null,
        onPanEnd: onDragEnd != null
            ? (details) => onDragEnd!(nodeId, port.name, isInput)
            : null,
        child: _buildPortRow(context, color, portLabel),
      ),
    );
  }

  Widget _buildPortRow(BuildContext context, Color color, String portLabel) {
    final ds = BridgeDSColors.of(context);
    // [教練 Agent 2026-08-15 統一錨點] 圓點本身掛獨立 MetaData——
    // 連線錨點綁圓點中心，不再綁整個 port 列（列中心含標籤，永遠偏移）。
    // _visitPorts 先訪父（列）再訪子（圓點），內層覆蓋外層 → 錨點=圓點。
    // 所有節點型別＋未來新增/外掛節點自動繼承（全走 PortWidget）。
    final dot = MetaData(
      metaData: PortMetadata(
        nodeId: nodeId,
        portName: port.name,
        isInput: isInput,
        dataType: port.dataType,
        direction: isInput ? const Offset(-1, 0) : const Offset(1, 0),
        portKey: portKey ?? GlobalKey(),
      ),
      child: _buildDot(context, color),
    );

    if (isCollapsed) {
      // 折疊狀態：只顯示圓點
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: dot,
      );
    }

    final labelWidget = Text(
      portLabel,
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
        // [教練 Agent 2026-08-15 Phase 2.5-B] 相容目標亮藍、拖曳中不相容變暗
        color: isConnectionTarget || isCompatibleTarget || _hovered
            ? ds.accentBlue
            : (isDimmed ? ds.textQuaternary : ds.textTertiary),
        fontWeight: (isConnectionTarget || isCompatibleTarget || _hovered) ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    final children = <Widget>[dot, const SizedBox(width: 6), labelWidget];

    // [教練 Agent 2026-08-15 Phase 2.5-C] 命中區域 32px 高（兩輪實測調整）——
    // 修「放大的圓點視覺範圍 > 命中範圍」造成 1/3 機率點到節點本體：
    // - minHeight 32 + 對稱 padding，圓點垂直置中
    // - 相邻 port 列無縫相接（Column 直疊），整個左/右邊帶都是 port 地盤
    return Container(
      constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: _hovered ? ds.surfaceGlassHover : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isInput ? children : children.reversed.toList(),
      ),
    );
  }

  /// 建立 port 圓點
  /// [教練 Agent 2026-08-15 Phase 2.5-C] hover 時放大到 16px（抓得到的視覺確定感）
  Widget _buildDot(BuildContext context, Color color) {
    final ds = BridgeDSColors.of(context);
    // 相容目標 = 亮 + 光暈；不相容 = 半暗
    final isActive = isConnectionTarget || isDragSource || isCompatibleTarget || _hovered;
    final effectiveColor = isDimmed && !isActive
        ? color.withValues(alpha: 0.25)
        : color;
    final dotSize = (isCompatibleTarget || _hovered) ? 16.0 : 12.0;

    return Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: isActive ? effectiveColor : effectiveColor.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive
              ? ds.textPrimary.withValues(alpha: 0.8)
              : ds.borderDefault,
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: effectiveColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

// ── 資料型別標籤 helper ────────────────────────────────

/// Port 資料型別的中文標籤。
String portDataTypeLabel(PortDataType type) {
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
      return '資料';
  }
}

// ── Port 位置查詢工具 ─────────────────────────────────

/// 從 GlobalKey 取得 port 圓點中心的螢幕座標。
/// GraphCanvas RenderObject 層呼叫此方法來取得連線的起點/終點。
Offset? getPortCenter(GlobalKey portKey) {
  final ctx = portKey.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(box.size.center(Offset.zero));
}

/// 從 GlobalKey 取得 port 圓點邊緣的座標（用於連線起點）。
/// input port 取左邊緣，output port 取右邊緣。
Offset? getPortEdge(GlobalKey portKey, bool isInput) {
  final ctx = portKey.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final edge = isInput ? Offset.zero : Offset(box.size.width, 0);
  return box.localToGlobal(edge);
}
