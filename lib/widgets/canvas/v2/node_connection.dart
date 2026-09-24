// node_connection.dart
// 畫布連線模型 — 兩個節點之間的有向連線。
// 建立日期: 2026-07-15
// 參考: graph_edit Connection + LiteGraph LLink
//
// 設計: 連線從 output port → input port，有明確方向和資料型別。

import 'package:flutter/material.dart';
import 'package:bridge_app/models/entity_graph/entity.dart' show PortDataType;
import '../../../theme/bridge_design_system.dart';

/// 畫布上兩個節點之間的連線。
/// 從 fromNodeId 的 fromPortId（output port）連到 toNodeId 的 toPortId（input port）。
class NodeConnection {
  final String id;
  final String fromNodeId;
  final String fromPortId;
  final String toNodeId;
  final String toPortId;

  /// 連線顏色（依資料型別決定，可在 UI 層覆寫）
  final Color color;

  /// 是否有動畫（執行中流動效果）
  final bool animated;

  const NodeConnection({
    required this.id,
    required this.fromNodeId,
    required this.fromPortId,
    required this.toNodeId,
    required this.toPortId,
    this.color = BridgeDS.brightCyan,
    this.animated = false,
  });

  NodeConnection copyWith({
    String? id,
    String? fromNodeId,
    String? fromPortId,
    String? toNodeId,
    String? toPortId,
    Color? color,
    bool? animated,
  }) {
    return NodeConnection(
      id: id ?? this.id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      fromPortId: fromPortId ?? this.fromPortId,
      toNodeId: toNodeId ?? this.toNodeId,
      toPortId: toPortId ?? this.toPortId,
      color: color ?? this.color,
      animated: animated ?? this.animated,
    );
  }

  /// 連線 ID 的標準格式：fromPort-toPort
  static String makeId(String fromPort, String toPort) =>
      '${fromPort}__${toPort}';

  /// 檢查此連線是否涉及指定節點
  bool involves(String nodeId) =>
      fromNodeId == nodeId || toNodeId == nodeId;

  /// 檢查此連線是否涉及指定 port
  bool involvesPort(String nodeId, String portId) =>
      (fromNodeId == nodeId && fromPortId == portId) ||
      (toNodeId == nodeId && toPortId == portId);

  @override
  String toString() =>
      'NodeConnection($fromNodeId.$fromPortId → $toNodeId.$toPortId)';

  /// 檢查兩個端口資料類型是否兼容
  /// - any 匹配所有類型
  /// - 相同類型匹配
  /// - 不同類型為不匹配
  static bool isPortTypeMatch(PortDataType fromType, PortDataType toType) {
    // any 匹配所有類型
    if (fromType == PortDataType.any || toType == PortDataType.any) {
      return true;
    }
    // 相同類型匹配
    return fromType == toType;
  }

  /// [教練 Agent 2026-08-15 Phase 2.5-A] 型別靜態色 — port 圓點、標籤、連線曲線同色。
  /// BridgeDS 靜態 token（CustomPainter 無 context 也能用）。
  /// text=藍 / image=洋紅 / audio=琥珀 / video=紅 / json=綠 / file=紫 / any=灰白
  static Color typeColor(PortDataType type) {
    switch (type) {
      case PortDataType.text:
        return BridgeDS.accentBlue;
      case PortDataType.image:
        return BridgeDS.accentMagenta;
      case PortDataType.audio:
        return BridgeDS.accentYellow;
      case PortDataType.video:
        return BridgeDS.accentRed;
      case PortDataType.json:
        return BridgeDS.accentGreen;
      case PortDataType.file:
        return BridgeDS.accentPurple;
      case PortDataType.any:
        return const Color(0xFF9C9C9D); // BridgeDS.textTertiary 同值，萬用灰
    }
  }
}
