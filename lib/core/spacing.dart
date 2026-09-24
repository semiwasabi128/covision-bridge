import 'package:flutter/widgets.dart';

/// 統一間距常數。
///
/// 所有 UI 間距應優先使用這裡的值，避免散落 magic number。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// 間距 helper — 回傳 [SizedBox]，用於 Column / Row 中的固定間距。
///
/// 垂直間距（Column 內）：
/// ```dart
/// AppGap.v(AppSpacing.md)   // 垂直 16
/// AppGap.vMd()              // 垂直 16（快捷版）
/// ```
///
/// 水平間距（Row 內）：
/// ```dart
/// AppGap.h(AppSpacing.sm)   // 水平 8
/// AppGap.hSm()              // 水平 8（快捷版）
/// ```
class AppGap {
  AppGap._();

  // ── 通用（指定大小） ──────────────────────────────

  /// 垂直間距
  static SizedBox v(double height) => SizedBox(height: height);

  /// 水平間距
  static SizedBox h(double width) => SizedBox(width: width);

  // ── 快捷版本（對應 AppSpacing 常數） ───────────────

  /// 垂直 xs（4）
  static SizedBox vXs() => const SizedBox(height: AppSpacing.xs);

  /// 垂直 sm（8）
  static SizedBox vSm() => const SizedBox(height: AppSpacing.sm);

  /// 垂直 md（16）
  static SizedBox vMd() => const SizedBox(height: AppSpacing.md);

  /// 垂直 lg（24）
  static SizedBox vLg() => const SizedBox(height: AppSpacing.lg);

  /// 垂直 xl（32）
  static SizedBox vXl() => const SizedBox(height: AppSpacing.xl);

  /// 垂直 xxl（48）
  static SizedBox vXxl() => const SizedBox(height: AppSpacing.xxl);

  /// 水平 xs（4）
  static SizedBox hXs() => const SizedBox(width: AppSpacing.xs);

  /// 水平 sm（8）
  static SizedBox hSm() => const SizedBox(width: AppSpacing.sm);

  /// 水平 md（16）
  static SizedBox hMd() => const SizedBox(width: AppSpacing.md);

  /// 水平 lg（24）
  static SizedBox hLg() => const SizedBox(width: AppSpacing.lg);

  /// 水平 xl（32）
  static SizedBox hXl() => const SizedBox(width: AppSpacing.xl);

  /// 水平 xxl（48）
  static SizedBox hXxl() => const SizedBox(width: AppSpacing.xxl);
}
