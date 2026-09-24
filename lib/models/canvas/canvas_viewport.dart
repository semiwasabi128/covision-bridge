// canvas_viewport.dart
// 無限畫布 viewport 狀態 — pan/zoom 座標轉換
// Sprint 18-2

import 'package:flutter/material.dart';

/// 畫布可視區域狀態。
///
/// 管理平移偏移量與縮放比例，負責世界座標 ↔ 螢幕座標轉換。
/// 不持有 widget 生命週期 — 純資料結構，由上層 State 管理。
class CanvasViewport {
  /// 平移偏移（螢幕座標，世界原點在螢幕上的位置）
  final Offset offset;

  /// 縮放比例（1.0 = 100%）
  final double scale;

  /// 最小/最大縮放
  // [教練 Agent 2026-08-20] 0.02——宇宙擴張 ×10 後全景需要更低的縮放下限
  static const double minScale = 0.02;
  static const double maxScale = 4.0;

  const CanvasViewport({
    this.offset = Offset.zero,
    this.scale = 1.0,
  });

  /// 預設初始 viewport
  factory CanvasViewport.initial() => const CanvasViewport(
        offset: Offset.zero,
        scale: 1.0,
      );

  /// 縮放鉗制
  double get clampedScale => scale.clamp(minScale, maxScale);

  /// 是否有效
  bool get isValid => scale > 0;

  /// 螢幕座標 → 世界座標
  Offset toWorld(Offset screenPoint) {
    return (screenPoint - offset) / scale;
  }

  /// 世界座標 → 螢幕座標
  Offset toScreen(Offset worldPoint) {
    return worldPoint * scale + offset;
  }

  /// 以指定焦點縮放（焦點為螢幕座標）
  ///
  /// 縮放時保持焦點點在螢幕上的位置不變。
  CanvasViewport zoom(double newScale, Offset focalPoint) {
    final clamped = newScale.clamp(minScale, maxScale);
    if (clamped == scale) return this;

    // 無偏移縮放: 新 offset = focalPoint - (focalPoint - oldOffset) * (newScale/oldScale)
    final ratio = clamped / scale;
    final newOffset = focalPoint - (focalPoint - offset) * ratio;

    return CanvasViewport(offset: newOffset, scale: clamped);
  }

  /// 平移
  CanvasViewport pan(Offset delta) {
    return CanvasViewport(offset: offset + delta, scale: scale);
  }

  /// 重置
  CanvasViewport reset() => const CanvasViewport();

  /// P11: 計算讓所有節點置中顯示的 viewport
  ///
  /// [bounds] = (minX, minY, maxX, maxY) 世界座標邊界
  /// [viewportSize] = 畫布可視區域大小
  /// [padding] = 邊距
  factory CanvasViewport.fitToBounds(
    (double minX, double minY, double maxX, double maxY) bounds,
    Size viewportSize, {
    double padding = 80,
  }) {
    final (minX, minY, maxX, maxY) = bounds;
    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    if (contentWidth <= 0 || contentHeight <= 0) {
      return CanvasViewport(
        offset: Offset(
          viewportSize.width / 2 - centerX,
          viewportSize.height / 2 - centerY,
        ),
        scale: 1.0,
      );
    }

    // 計算適合的縮放比例
    final scaleX = (viewportSize.width - padding * 2) / contentWidth;
    final scaleY = (viewportSize.height - padding * 2) / contentHeight;
    final scale = (scaleX < scaleY ? scaleX : scaleY)
        .clamp(minScale, maxScale);

    // 置中偏移
    return CanvasViewport(
      offset: Offset(
        viewportSize.width / 2 - centerX * scale,
        viewportSize.height / 2 - centerY * scale,
      ),
      scale: scale,
    );
  }

  /// 確保世界座標 [worldPoint] 可見，返回新的 viewport
  CanvasViewport ensureVisible(
    Offset worldPoint,
    Size viewportSize, {
    double padding = 100,
  }) {
    final screen = toScreen(worldPoint);
    double newOffsetDx = offset.dx;
    double newOffsetDy = offset.dy;

    if (screen.dx < padding) {
      newOffsetDx = offset.dx + (padding - screen.dx);
    } else if (screen.dx > viewportSize.width - padding) {
      newOffsetDx = offset.dx - (screen.dx - (viewportSize.width - padding));
    }

    if (screen.dy < padding) {
      newOffsetDy = offset.dy + (padding - screen.dy);
    } else if (screen.dy > viewportSize.height - padding) {
      newOffsetDy = offset.dy - (screen.dy - (viewportSize.height - padding));
    }

    return CanvasViewport(
      offset: Offset(newOffsetDx, newOffsetDy),
      scale: scale,
    );
  }

  CanvasViewport copyWith({
    Offset? offset,
    double? scale,
  }) {
    return CanvasViewport(
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
    );
  }

  @override
  String toString() =>
      'CanvasViewport(offset: ${offset.dx.toStringAsFixed(1)}, '
      '${offset.dy.toStringAsFixed(1)}, scale: ${scale.toStringAsFixed(2)})';
}
