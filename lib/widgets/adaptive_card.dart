import 'package:flutter/material.dart';

import '../core/spacing.dart';

/// 防溢卡片容器 — 自動套用 [AppSpacing] padding，可選 margin 與 onTap。
///
/// 內部使用 [Column] 搭配 [MainAxisSize.min]，適合放在清單或有限空間中。
/// 搭配 [AdaptiveText] 可確保文字不溢出。
class AdaptiveCard extends StatelessWidget {
  const AdaptiveCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    this.elevation,
    this.borderRadius,
  });

  /// 卡片內容。
  final Widget child;

  /// 內邊距，預設 [AppSpacing.md]。
  final EdgeInsets? padding;

  /// 外邊距，預設零。
  final EdgeInsets? margin;

  /// 點擊回調，提供時卡片變為可點擊（含 ripple）。
  final VoidCallback? onTap;

  /// 卡片背景色。
  final Color? color;

  /// 陰影高度，預設 1。
  final double? elevation;

  /// 圓角半徑，預設 12。
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? 12;

    return Card(
      color: color,
      elevation: elevation ?? 1,
      margin: margin ?? EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [child],
          ),
        ),
      ),
    );
  }
}

/// 自適應文字 — 預設帶 [maxLines] 與 [TextOverflow.ellipsis]，
/// 防止長文字在有限寬度中溢出。
///
/// 用法：
/// ```dart
/// AdaptiveText('一段可能很長的文字', style: theme.textTheme.bodyMedium)
/// AdaptiveText('標題', maxLines: 1, style: theme.textTheme.titleLarge)
/// ```
class AdaptiveText extends StatelessWidget {
  const AdaptiveText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.softWrap = true,
  });

  /// 文字內容。
  final String data;

  /// 文字樣式。
  final TextStyle? style;

  /// 最大行數，預設 2。
  final int maxLines;

  /// 溢出處理，預設 [TextOverflow.ellipsis]。
  final TextOverflow overflow;

  /// 對齊方式。
  final TextAlign? textAlign;

  /// 是否換行，預設 true。
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
}
