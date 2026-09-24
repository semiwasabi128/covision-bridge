import 'package:flutter/widgets.dart';

/// 螢幕寬度 breakpoint 常數（pt）
class ResponsiveBreakpoints {
  ResponsiveBreakpoints._();

  /// 手機：寬度 < 600
  static const double mobile = 600;

  /// 平板：600 ≤ 寬度 < 1024
  static const double tablet = 1024;

  /// 桌面：寬度 ≥ 1024
  static const double desktop = 1024;
}

/// Responsive helper — 透過 BuildContext 判讀目前裝置類型與尺寸。
///
/// 用法：
/// ```dart
/// if (Responsive.isMobile(context)) { ... }
/// final padding = Responsive.responsiveValue(
///   context,
///   mobile: 16.0,
///   tablet: 24.0,
///   desktop: 32.0,
/// );
/// ```
class Responsive {
  Responsive._();

  /// 取得螢幕寬度
  static double screenWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width;
  }

  /// 取得螢幕高度
  static double screenHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height;
  }

  /// 是否為手機（寬度 < 600）
  static bool isMobile(BuildContext context) {
    return screenWidth(context) < ResponsiveBreakpoints.mobile;
  }

  /// 是否為平板（600 ≤ 寬度 < 1024）
  static bool isTablet(BuildContext context) {
    final w = screenWidth(context);
    return w >= ResponsiveBreakpoints.mobile && w < ResponsiveBreakpoints.tablet;
  }

  /// 是否為桌面（寬度 ≥ 1024）
  static bool isDesktop(BuildContext context) {
    return screenWidth(context) >= ResponsiveBreakpoints.desktop;
  }

  /// 依螢幕寬度回傳對應值。
  ///
  /// - [mobile] 為必填，手機時使用。
  /// - [tablet] 若未提供則 fallback 到 [mobile]。
  /// - [desktop] 若未提供則 fallback 到 [tablet]（再 fallback 到 [mobile]）。
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) {
      return desktop ?? tablet ?? mobile;
    }
    if (isTablet(context)) {
      return tablet ?? mobile;
    }
    return mobile;
  }
}

/// BuildContext extension — 讓呼叫端可以直接 context.isMobile() 等。
extension ResponsiveContext on BuildContext {
  bool get isMobile => Responsive.isMobile(this);
  bool get isTablet => Responsive.isTablet(this);
  bool get isDesktop => Responsive.isDesktop(this);

  double get screenWidth => Responsive.screenWidth(this);
  double get screenHeight => Responsive.screenHeight(this);

  T responsiveValue<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) =>
      Responsive.responsiveValue(
        this,
        mobile: mobile,
        tablet: tablet,
        desktop: desktop,
      );
}
