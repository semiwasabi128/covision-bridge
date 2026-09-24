import 'package:flutter/material.dart';

import '../core/responsive.dart';

/// 自適應 Scaffold — 在標準 [Scaffold] 之上加入：
///
/// - 自動 [SafeArea]
/// - 平板 / 桌面時 body 加最大寬度約束（maxContentWidth = 600），手機滿版
/// - 鍵盤避讓（resizeToAvoidBottomInset: true）
///
/// 所有參數皆 optional，未提供時使用合理預設值。
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.maxContentWidth = 600,
  });

  /// 頂部 AppBar，可不提供。
  final PreferredSizeWidget? appBar;

  /// 主體內容。
  final Widget body;

  /// 浮動按鈕。
  final Widget? floatingActionButton;

  /// 背景顏色。
  final Color? backgroundColor;

  /// 底部導航列。
  final Widget? bottomNavigationBar;

  /// 平板 / 桌面時 body 的最大寬度。手機不受此限制。
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isTablet(context) || Responsive.isDesktop(context);

    Widget effectiveBody = SafeArea(child: body);

    if (isWide) {
      // 平板 / 桌面：置中 + 最大寬度約束
      effectiveBody = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: effectiveBody,
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: effectiveBody,
      floatingActionButton: floatingActionButton,
      backgroundColor: backgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      resizeToAvoidBottomInset: true,
    );
  }
}
