// canvas_props.dart
// CanvasEntry — 畫布節點查詢結果
// 建立日期: 2026-07-10
//
// 設計文件: entity-graph-service-design.md §2.1
//
// CanvasProps / CanvasVisualState / CanvasNodeOrigin / CanvasNodeRole
// 定義在 entity.dart 中（同一檔案，避免循環依賴）。
// 本檔只放 CanvasEntry。

import 'entity.dart';

/// 畫布節點查詢結果：Entity + CanvasProps 的組合。
class CanvasEntry {
  final Entity entity;
  final CanvasProps props;

  const CanvasEntry({required this.entity, required this.props});

  @override
  String toString() =>
      'CanvasEntry(entity: ${entity.id}, ${props})';
}
