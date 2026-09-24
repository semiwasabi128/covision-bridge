// node_search_box.dart
// 節點搜尋框 — 雙擊空白彈出，即時過濾 11 種節點類型。
// 建立日期: 2026-07-15
// 參考: LiteGraph showSearchBox

import 'package:flutter/material.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/services.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 節點搜尋框 — 雙擊空白處彈出，或拖線放空處（相容節點快選）。
class NodeSearchBox extends StatefulWidget {
  /// 選擇節點類型後的回調
  final void Function(WorkflowNodeType type) onSelected;

  /// 取消
  final VoidCallback onCancel;

  /// [教練 Agent 2026-08-15 相容節點快選] 只顯示相容的節點類型。
  /// 傳入後：標題顯示「相容節點」、清單預先過濾、
  /// 不相容的節點不出現（ComfyUI link-release 快選同款）。
  final bool Function(WorkflowNodeType type)? compatFilter;

  /// 快選模式的說明文字（如「接住 text 輸出」）
  final String? filterHint;

  /// 螢幕座標（彈出位置）
  final Offset screenPos;

  const NodeSearchBox({
    super.key,
    required this.onSelected,
    required this.onCancel,
    required this.screenPos,
    this.compatFilter,
    this.filterHint,
  });

  @override
  State<NodeSearchBox> createState() => _NodeSearchBoxState();
}

class _NodeSearchBoxState extends State<NodeSearchBox> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = -1;
  List<_NodeTypeEntry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = _baseTypes;
    _controller.addListener(_onSearch);
    // 自動聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  /// [教練 Agent 2026-08-15 相容快選] 過濾後的基底清單
  List<_NodeTypeEntry> get _baseTypes =>
      widget.compatFilter != null
          ? _allTypes.where((e) => widget.compatFilter!(e.type)).toList()
          : _allTypes;

  void _onSearch() {
    final query = _controller.text.toLowerCase();
    setState(() {
      final base = _baseTypes;
      _filtered = query.isEmpty
          ? base
          : base
              .where((e) =>
                  e.label.toLowerCase().contains(query) ||
                  e.type.name.toLowerCase().contains(query))
              .toList();
      _selectedIndex = 0;
    });
  }

  void _onKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = _selectedIndex < 0 ? 0 : (_selectedIndex + 1) % _filtered.length;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex = _selectedIndex < 0 ? 0 : (_selectedIndex - 1 + _filtered.length) % _filtered.length;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_filtered.isNotEmpty && _selectedIndex >= 0) {
          widget.onSelected(_filtered[_selectedIndex].type);
        } else if (_filtered.isNotEmpty) {
          widget.onSelected(_filtered[0].type);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static final _allTypes = WorkflowNodeType.values.map((type) {
    return _NodeTypeEntry(
      type: type,
      label: workflowNodeTypeLabel(type),
      icon: workflowNodeTypeIcon(type),
      tooltip: workflowNodeTypeDescription(type),
      color: workflowNodeTypeColor(type),
    );
  }).toList();

  @override
  Widget build(BuildContext context) {
    // 確保彈出位置不超出畫面
    final screenSize = MediaQuery.of(context).size;
    final boxWidth = 280.0;
    final boxHeight = 360.0;
    final left = (widget.screenPos.dx + boxWidth > screenSize.width)
        ? screenSize.width - boxWidth - 16
        : widget.screenPos.dx;
    final top = (widget.screenPos.dy + boxHeight > screenSize.height)
        ? screenSize.height - boxHeight - 16
        : widget.screenPos.dy;

    return Stack(
      children: [
        // 背景遮罩 — 點擊關閉
        GestureDetector(
          onTap: widget.onCancel,
          child: Container(color: Colors.transparent),
        ),
        // 搜尋框
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: RawKeyboardListener(
              focusNode: _focusNode,
              onKey: _onKey,
              child: Container(
                width: boxWidth,
                constraints: BoxConstraints(maxHeight: boxHeight),
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BridgeDSColors.of(context).borderDefault, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // [教練 Agent 2026-08-15 相容快選] 提示條
                    if (widget.filterHint != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Row(
                          children: [
                            Icon(Icons.link, size: 14, color: BridgeDSColors.of(context).accentBlue),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.filterHint!,
                                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                                      color: BridgeDSColors.of(context).textTertiary,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 搜尋輸入
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
                        decoration: InputDecoration(
                          hintText: '搜尋節點類型...',
                          hintStyle: TextStyle(color: BridgeDSColors.of(context).textMuted),
                          prefixIcon: Icon(Icons.search, color: BridgeDSColors.of(context).accentBlue, size: 18),
                          filled: true,
                          fillColor: BridgeDSColors.of(context).canvas,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: BridgeDSColors.of(context).borderDefault),
                    // 結果列表
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final entry = _filtered[index];
                          final isSelected = index == _selectedIndex;
                          return _SearchResultTile(
                            entry: entry,
                            isSelected: isSelected,
                            onTap: () => widget.onSelected(entry.type),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeTypeEntry {
  final WorkflowNodeType type;
  final String label;
  final String icon;
  final String tooltip;
  final Color color;

  const _NodeTypeEntry({
    required this.type,
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.color,
  });
}

class _SearchResultTile extends StatefulWidget {
  final _NodeTypeEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isActive = _isHovered || widget.isSelected;
    final textColor = BridgeDSColors.of(context).textPrimary;
    final mutedColor = BridgeDSColors.of(context).textMuted;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? entry.color.withValues(alpha: 0.25)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? entry.color : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(entry.icon, style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.label,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: isActive ? textColor : mutedColor,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,),
                    ),
                  ),
                  if (isActive)
                    Icon(Icons.keyboard_arrow_right, color: entry.color, size: 16),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 4),
                child: Text(
                  entry.tooltip,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: mutedColor,),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
