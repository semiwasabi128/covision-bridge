import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 手機版頁面 Scaffold
///
/// 提供：
/// - AppBar（手機樣式）
/// - 可選 Drawer（從左滑出）
/// - 可選 FAB
/// - 可選底部 BottomNavigationBar
/// - 主內容區
///
/// 桌面版用一般的 Scaffold + 自訂 NavigationRail，
/// 手機版用這個一體化 widget。
class MobilePageScaffold extends StatelessWidget {
  const MobilePageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.drawerHeader,
    this.drawerItems = const [],
    this.floatingActionButton,
    this.bottomNavItems = const [],
    this.currentBottomNavIndex,
    this.onBottomNavTap,
    this.showBackButton = true,
    this.disableDesktopLayout = true,
  });

  /// 標題
  final String title;

  /// 主內容
  final Widget body;

  /// AppBar 動作
  final List<Widget> actions;

  /// Drawer header
  final Widget? drawerHeader;

  /// Drawer 項目
  final List<MobileNavItem> drawerItems;

  /// FAB
  final Widget? floatingActionButton;

  /// 底部導航
  final List<MobileNavItem> bottomNavItems;

  /// 當前底部導航 index
  final int? currentBottomNavIndex;

  /// 底部導航點擊回調
  final ValueChanged<int>? onBottomNavTap;

  /// 是否顯示返回按鈕
  final bool showBackButton;

  /// 在桌面上禁用此 layout（直接用標準 Scaffold）
  final bool disableDesktopLayout;

  @override
  Widget build(BuildContext context) {
    if (disableDesktopLayout && Responsive.isDesktop(context)) {
      // 桌面版：直接用標準 Scaffold
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
          backgroundColor: BridgeDSColors.of(context).canvas,
        ),
        drawer: drawerHeader != null && drawerItems.isNotEmpty
            ? _buildDrawer(context)
            : null,
        body: body,
        floatingActionButton: floatingActionButton,
      );
    }

    // 手機/平板版：自適應 layout
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BridgeDSColors.of(context).canvas,
        elevation: 0,
        scrolledUnderElevation: 1,
        automaticallyImplyLeading: false,
        title: Text(
          title,
          style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textPrimary,
              ),
        ),
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 24),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    GoRouter.of(context).go('/');
                  }
                },
              )
            : null,
        actions: actions.take(2).toList(),
      ),
      drawer: drawerHeader != null && drawerItems.isNotEmpty
          ? _buildDrawer(context)
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavItems.isNotEmpty && onBottomNavTap != null
          ? BottomNavigationBar(
              currentIndex: currentBottomNavIndex ?? 0,
              onTap: onBottomNavTap,
              backgroundColor: BridgeDSColors.of(context).surface,
              selectedItemColor: BridgeDSColors.of(context).accentBlue,
              unselectedItemColor: BridgeDSColors.of(context).textTertiary,
              type: BottomNavigationBarType.fixed,
              items: bottomNavItems
                  .map((item) => BottomNavigationBarItem(
                        icon: Icon(item.icon),
                        label: item.label,
                      ))
                  .toList(),
            )
          : null,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: BridgeDSColors.of(context).surface,
      child: SafeArea(
        child: Column(
          children: [
            if (drawerHeader != null)
              DrawerHeader(
                child: drawerHeader!,
                decoration: BoxDecoration(color: BridgeDSColors.of(context).surfaceElevated),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: drawerItems.length,
                itemBuilder: (ctx, index) {
                  final item = drawerItems[index];
                  return ListTile(
                    leading: Icon(
                      item.icon,
                      color: BridgeDSColors.of(ctx).accentBlue,
                    ),
                    title: Text(
                      item.label,
                      style: TierStyle.of(ctx, Tier.cardBody).toTextStyle().copyWith(
                            color: BridgeDSColors.of(ctx).textPrimary,
                          ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      if (item.route.isNotEmpty) {
                        GoRouter.of(ctx).go(item.route);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// MobilePageScaffold 用的單個 tab 項目
class MobileNavItem {
  const MobileNavItem({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

/// 手機版頁面 padding 預設值
class MobileSpacing {
  MobileSpacing._();

  static const double pagePadding = 16;
  static const double itemGap = 12;
  static const double sectionGap = 24;
}
