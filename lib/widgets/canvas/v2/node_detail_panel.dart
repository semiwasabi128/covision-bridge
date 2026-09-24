// node_detail_panel.dart
// 節點詳情面板 (Inspector Panel) — 顯示選中節點的詳細資訊
// 建立日期: 2026-08-02
//
// 功能：
// - 顯示節點標題（可編輯）
// - 顯示節點類型
// - 顯示節點參數
// - 顯示執行結果（如果有）
// - 顯示連入/連出的節點列表
// - 操作按鈕：刪除、複製、執行

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/widgets/canvas/v2/node_connection.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 節點詳情面板
///
/// 顯示在畫布右側或底部的浮動面板，展示選中節點的完整資訊
class NodeDetailPanel extends StatefulWidget {
  /// 選中的節點
  final OpenCanvasNode? node;

  /// 當前畫布上的所有連線
  final List<NodeConnection>? connections;

  /// 所有節點（用於顯示連入/連出節點列表）
  final Map<String, OpenCanvasNode>? allNodes;

  /// 標題變更回調
  final ValueChanged<String>? onTitleChanged;

  /// 參數變更回調
  final void Function(String key, dynamic value)? onParamChanged;

  /// 刪除節點回調
  final VoidCallback? onDelete;

  /// 複製節點回調
  final VoidCallback? onDuplicate;

  /// 執行節點回調
  final VoidCallback? onExecute;

  /// [教練 Agent 2026-08-15 使用者回饋] 關閉面板回調——明確的 X 按鈕
  final VoidCallback? onClose;

  const NodeDetailPanel({
    super.key,
    required this.node,
    this.connections,
    this.allNodes,
    this.onTitleChanged,
    this.onParamChanged,
    this.onDelete,
    this.onDuplicate,
    this.onExecute,
    this.onClose,
  });

  @override
  State<NodeDetailPanel> createState() => _NodeDetailPanelState();
}

class _NodeDetailPanelState extends State<NodeDetailPanel> {
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  late FocusNode _titleFocusNode;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.node?.entity.title ?? '');
    _titleFocusNode = FocusNode();
    _titleFocusNode.addListener(_onTitleFocusChange);
  }

  @override
  void didUpdateWidget(NodeDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node?.entity.title != widget.node?.entity.title && !_isEditingTitle) {
      _titleController.text = widget.node?.entity.title ?? '';
    }
  }

  @override
  void dispose() {
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
      _titleController.text = widget.node?.entity.title ?? '';
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
    if (newTitle.isNotEmpty && newTitle != widget.node?.entity.title) {
      widget.onTitleChanged?.call(newTitle);
    }
    setState(() => _isEditingTitle = false);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    if (node == null) {
      return const SizedBox.shrink();
    }

    final colors = BridgeDSColors.of(context);
    final nodeType = node.entity.canvasProps?.nodeType;
    final params = node.entity.canvasProps?.params ?? {};

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(
          left: BorderSide(color: colors.borderDefault, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          _buildHeader(colors, node, nodeType),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Node type badge
                  if (nodeType != null) _buildNodeTypeBadge(colors, nodeType),

                  const SizedBox(height: 16),

                  // Parameters section
                  if (nodeType != null && params.isNotEmpty) ...[
                    _buildSectionTitle(colors, '參數'),
                    const SizedBox(height: 8),
                    ..._buildParamsSection(colors, params, nodeType),
                    const SizedBox(height: 24),
                  ],

                  // Execution result section
                  if (params.containsKey('_lastOutput') || params.containsKey('_lastImageB64')) ...[
                    _buildSectionTitle(colors, '執行結果'),
                    const SizedBox(height: 8),
                    _buildExecutionResult(colors, params),
                    const SizedBox(height: 24),
                  ],

                  // Connections section
                  if (widget.connections != null && widget.allNodes != null) ...[
                    _buildSectionTitle(colors, '連線'),
                    const SizedBox(height: 8),
                    _buildConnectionsSection(colors, node, widget.connections!, widget.allNodes!),
                    const SizedBox(height: 24),
                  ],

                  // Node info section
                  _buildSectionTitle(colors, '節點資訊'),
                  const SizedBox(height: 8),
                  _buildNodeInfo(colors, node),
                ],
              ),
            ),
          ),

          // Action buttons
          _buildActionButtons(colors, node, nodeType),
        ],
      ),
    );
  }

  Widget _buildHeader(BridgeDSColors colors, OpenCanvasNode node, WorkflowNodeType? nodeType) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.borderDefault, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Node type icon
          if (nodeType != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: workflowNodeTypeColor(nodeType).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                workflowNodeTypeIcon(nodeType),
                style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
              ),
            )
          else
            Icon(Icons.widgets, size: 24, color: colors.textSecondary),

          const SizedBox(width: 12),

          // Title
          Expanded(
            child: _isEditingTitle
                ? Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        setState(() => _isEditingTitle = false);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textPrimary,
                        fontWeight: FontWeight.w600,),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.accentBlue, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.accentBlue, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors.accentBlue, width: 1.5),
                        ),
                        filled: true,
                        fillColor: colors.canvas,
                      ),
                      onSubmitted: (_) => _commitTitle(),
                      onTapOutside: (_) => _commitTitle(),
                    ),
                  )
                : GestureDetector(
                    onTap: _startEditingTitle,
                    child: Text(
                      node.entity.title.isNotEmpty
                          ? node.entity.title
                          : workflowNodeTypeLabel(nodeType ?? WorkflowNodeType.input),
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textPrimary,
                        fontWeight: FontWeight.w600,),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),

          // [教練 Agent 2026-08-15 使用者回饋] 明確的關閉按鈕——面板不再幽靈出沒
          if (widget.onClose != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
              tooltip: '關閉面板',
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildNodeTypeBadge(BridgeDSColors colors, WorkflowNodeType nodeType) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: workflowNodeTypeColor(nodeType).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        workflowNodeTypeLabel(nodeType),
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: workflowNodeTypeColor(nodeType),
          fontWeight: FontWeight.w500,),
      ),
    );
  }

  Widget _buildSectionTitle(BridgeDSColors colors, String title) {
    return Text(
      title,
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,),
    );
  }

  List<Widget> _buildParamsSection(BridgeDSColors colors, Map<String, dynamic> params, WorkflowNodeType nodeType) {
    final widgets = <Widget>[];

    // Filter out internal params (starting with _)
    final visibleParams = params.entries.where((e) => !e.key.startsWith('_'));

    for (final entry in visibleParams) {
      widgets.add(_ParamRow(
        label: _paramLabel(entry.key),
        value: entry.value,
        onChanged: (value) {
          final newParams = Map<String, dynamic>.from(params);
          newParams[entry.key] = value;
          widget.onParamChanged?.call(entry.key, value);
        },
      ));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  Widget _buildExecutionResult(BridgeDSColors colors, Map<String, dynamic> params) {
    final textOutput = params['_lastOutput']?.toString();
    final imageB64 = params['_lastImageB64']?.toString();
    final imageUrl = params['_lastImageUrl']?.toString();

    final hasText = textOutput != null && textOutput.isNotEmpty;
    final hasImage = (imageB64 != null && imageB64.isNotEmpty) ||
        (imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('file_id:'));

    if (!hasText && !hasImage) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '尚未執行',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage) ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderDefault),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageB64 != null && imageB64.isNotEmpty
                  ? Image.memory(
                      base64.decode(imageB64),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('⚠️ 圖片載入失敗', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,)),
                      ),
                    )
              : Image.network(
                  imageUrl ?? '',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('⚠️ 圖片載入失敗', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,)),
                  ),
                ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (hasText)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderDefault),
            ),
            child: SelectableText(
              textOutput!,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary,
                fontFamily: 'SF Mono',),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectionsSection(
    BridgeDSColors colors,
    OpenCanvasNode node,
    List<NodeConnection> connections,
    Map<String, OpenCanvasNode> allNodes,
  ) {
    final inputConnections = connections.where((c) => c.toNodeId == node.id).toList();
    final outputConnections = connections.where((c) => c.fromNodeId == node.id).toList();

    if (inputConnections.isEmpty && outputConnections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '無連線',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inputConnections.isNotEmpty) ...[
          _buildConnectionList(colors, '連入', inputConnections, allNodes, isInput: true),
          const SizedBox(height: 12),
        ],
        if (outputConnections.isNotEmpty)
          _buildConnectionList(colors, '連出', outputConnections, allNodes, isInput: false),
      ],
    );
  }

  Widget _buildConnectionList(
    BridgeDSColors colors,
    String title,
    List<NodeConnection> connections,
    Map<String, OpenCanvasNode> allNodes, {
    required bool isInput,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,
            fontWeight: FontWeight.w500,),
        ),
        const SizedBox(height: 6),
        ...connections.map((conn) {
          final connNonNull = conn;
          final sourceId = isInput ? connNonNull.fromNodeId : connNonNull.toNodeId;
          final sourceNode = allNodes[sourceId];
          if (sourceNode == null) return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.borderDefault, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  isInput ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 14,
                  color: colors.accentBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sourceNode.entity.title.isNotEmpty
                        ? sourceNode.entity.title
                        : workflowNodeTypeLabel(
                            sourceNode.entity.canvasProps?.nodeType ?? WorkflowNodeType.input,
                          ),
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary,),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  isInput ? connNonNull.toPortId : connNonNull.fromPortId,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNodeInfo(BridgeDSColors colors, OpenCanvasNode node) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow('ID', node.id, colors),
          const SizedBox(height: 6),
          _InfoRow('位置', '(${node.position.dx.toStringAsFixed(0)}, ${node.position.dy.toStringAsFixed(0)})', colors),
          const SizedBox(height: 6),
          _InfoRow('類型', node.entity.type.name, colors),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BridgeDSColors colors, OpenCanvasNode node, WorkflowNodeType? nodeType) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.borderDefault, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Execute button (if executable)
          if (_isExecutable(nodeType))
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onExecute,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('執行'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.canvas,
          side: BorderSide(color: colors.accentPurple, width: 1.5),
                  foregroundColor: BridgeDSColors.of(context).textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),

          if (_isExecutable(nodeType)) const SizedBox(width: 8),

          // Duplicate button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onDuplicate,
              icon: Icon(Icons.content_copy, size: 16, color: colors.textSecondary),
              label: Text('複製', style: TextStyle(color: colors.textSecondary)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                side: BorderSide(color: colors.borderDefault),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Delete button
          IconButton(
            onPressed: widget.onDelete,
            icon: Icon(Icons.delete, size: 18, color: colors.accentRed),
            style: IconButton.styleFrom(
              backgroundColor: colors.accentRed.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  bool _isExecutable(WorkflowNodeType? nodeType) {
    if (nodeType == null) return false;
    return switch (nodeType) {
      WorkflowNodeType.input || WorkflowNodeType.output || WorkflowNodeType.merge => false,
      WorkflowNodeType.schedule => false,
      _ => true,
    };
  }

  String _paramLabel(String key) {
    const labels = {
      'model': '模型',
      'prompt': '提示詞',
      'temperature': '溫度',
      'maxTokens': '最大 Token',
      'toolName': '工具名稱',
      'args': '參數',
      'source': '來源',
      'content': '內容',
      'size': '尺寸',
      'seed': '種子',
      'duration': '時長',
      'text': '文字',
      'voice': '語音',
      'speed': '語速',
      'condition': '條件',
      'mode': '模式',
      'displayMode': '顯示模式',
      'label': '標籤',
      'inputType': '輸入類型',
      'scheduleType': '排程類型',
      'time': '時間',
      'weekday': '星期',
      'dayOfMonth': '日期',
      'date': '指定日期',
      'cronExpr': 'Cron 運算式',
    };
    return labels[key] ?? key;
  }
}

/// 參數編輯行
class _ParamRow extends StatefulWidget {
  final String label;
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;

  const _ParamRow({
    required this.label,
    required this.value,
    this.onChanged,
  });

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _valueToString());
  }

  @override
  void didUpdateWidget(_ParamRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = _valueToString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _valueToString() {
    final value = widget.value;

    if (value == null) return '';
    if (value is double) {
      final d = value;
      return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderDefault, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              widget.label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary,),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textPrimary,),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.accentBlue, width: 1.5),
                ),
              ),
              onSubmitted: (value) {
                final parsed = _parseValue(value);
                widget.onChanged?.call(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }

  dynamic _parseValue(String value) {
    // Try to parse as number first
    if (double.tryParse(value) != null) {
      final d = double.tryParse(value)!;
      return d == d.truncateToDouble() ? d.toInt() : d;
    }
    // Try to parse as boolean
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
    // Return as string
    return value;
  }
}

/// 資訊列
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final BridgeDSColors colors;

  const _InfoRow(this.label, this.value, this.colors);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary, fontFamily: 'SF Mono'),
          ),
        ),
      ],
    );
  }
}