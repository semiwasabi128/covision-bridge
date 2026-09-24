// canvas_edge.dart
// 畫布連結邊 — 包裝 Connection + 衍生視覺屬性
// Sprint 18-2

import 'package:bridge_app/models/brain_container/connection.dart';
import 'package:bridge_app/models/brain_container/connection_type.dart';
import 'package:flutter/material.dart';

/// 畫布上的一條邊，對應一則 [Connection]。
///
/// 連結兩個 CanvasNode 的 ID，渲染時由 widget 查找兩端節點位置。
class CanvasEdge {
  /// 對應的 Connection ID
  final String id;

  /// 起點節點 ID
  final String fromNodeId;

  /// 終點節點 ID
  final String toNodeId;

  /// 底層連結
  final Connection connection;

  CanvasEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.connection,
  });

  /// 從 Connection 建構
  factory CanvasEdge.fromConnection(Connection conn) {
    return CanvasEdge(
      id: conn.id,
      fromNodeId: conn.fromMemoryId,
      toNodeId: conn.toMemoryId,
      connection: conn,
    );
  }

  // ── 衍生視覺屬性 ──

  /// 連結類型對應的配色
  Color get color => typeColor(connection.type);

  /// 連結類型配色（靜態，供外部使用）
  static Color typeColor(ConnectionType type) {
    switch (type) {
      case ConnectionType.strongTie:
        return const Color(0xFF42A5F5); // 藍 — 向量相似
      case ConnectionType.weakTie:
        return const Color(0xFF9CCC65); // 黃綠 — 概念共振
      case ConnectionType.temporalTie:
        return const Color(0xFFFFCA28); // 琥珀 — 時序
      case ConnectionType.intentionTie:
        return const Color(0xFFAB47BC); // 紫 — 意圖
      case ConnectionType.doorTie:
        return const Color(0xFFFF7043); // 橘 — 門
      case ConnectionType.bridgeTie:
        return const Color(0xFF26C6DA); // 青 — 橋
    }
  }

  /// 連結強度 → 線寬（0.5px ~ 3.0px）
  double get strokeWidth {
    return 0.5 + connection.strength * 2.5;
  }

  /// 連結是否為虛線（weak tie 用虛線，其他用實線）
  bool get isDashed => connection.type == ConnectionType.weakTie;

  /// 連結透明度（dormant 連結不顯示，此處已過濾）
  double get opacity {
    return 0.3 + connection.strength * 0.5;
  }

  /// 繪製路徑（世界座標 → 螢幕座標）
  ///
  /// 返回兩端點之間的路徑。如果有 [controlPoint] 則畫貝茲曲線。
  Path buildPath(Offset fromScreen, Offset toScreen, {Offset? controlPoint}) {
    final path = Path();
    path.moveTo(fromScreen.dx, fromScreen.dy);
    if (controlPoint != null) {
      path.quadraticBezierTo(
        controlPoint.dx,
        controlPoint.dy,
        toScreen.dx,
        toScreen.dy,
      );
    } else {
      path.lineTo(toScreen.dx, toScreen.dy);
    }
    return path;
  }

  CanvasEdge copyWith({
    String? fromNodeId,
    String? toNodeId,
    Connection? connection,
  }) {
    return CanvasEdge(
      id: id,
      fromNodeId: fromNodeId ?? this.fromNodeId,
      toNodeId: toNodeId ?? this.toNodeId,
      connection: connection ?? this.connection,
    );
  }

  @override
  String toString() =>
      'CanvasEdge($fromNodeId → $toNodeId, type: ${connection.type.name}, '
      'strength: ${connection.strength.toStringAsFixed(2)})';
}
