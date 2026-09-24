import 'package:flutter/material.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 手機版 AppBar — 含返回按鈕 + 標題 + 動作按鈕。
///
/// 與桌面版 AppBar 的差異：
/// - 標題居左，字級 18
/// - 動作按鈕最多 2 個（桌面最多 5 個）
/// - 整個 AppBar 高度 56（桌面 64）
class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.backgroundColor,
  });

  /// 標題文字
  final String title;

  /// 動作按鈕（最多 2 個）
  final List<Widget> actions;

  /// 返回按鈕（可省略，預設為 Navigator.pop）
  final Widget? leading;

  /// 背景色
  final Color? backgroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor ?? BridgeDSColors.of(context).canvas,
      elevation: 0,
      scrolledUnderElevation: 1,
      title: Text(
        title,
        style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
              color: BridgeDSColors.of(context).textPrimary,
            ),
      ),
      leading: leading ??
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
      actions: actions.take(2).toList(),
    );
  }
}

/// 手機版 Bottom Navigation Bar — 5 個 tab（首頁 / 對話 / 記錄 / 設定 / 更多）。
///
/// 桌面版用 AppNavigationRail，手機版用 BottomNavigationBar。
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  /// 當前選中 index
  final int currentIndex;

  /// tab 點擊回調
  final ValueChanged<int> onTap;

  /// tab 列表
  final List<MobileNavItem> items;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      backgroundColor: BridgeDSColors.of(context).surface,
      selectedItemColor: BridgeDSColors.of(context).accentBlue,
      unselectedItemColor: BridgeDSColors.of(context).textTertiary,
      type: BottomNavigationBarType.fixed,
      items: items
          .map((item) => BottomNavigationBarItem(
                icon: Icon(item.icon),
                label: item.label,
              ))
          .toList(),
    );
  }
}

/// 單個 Bottom Nav tab
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

/// 手機版 Floating Action Button — 右下角浮動按鈕。
///
/// 與桌面相比縮小到 56，且只支援 mini (40) 或 default (56)。
class MobileFab extends StatelessWidget {
  const MobileFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.tooltip,
    this.mini = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label!),
        backgroundColor: BridgeDSColors.of(context).accentBlue,
        foregroundColor: BridgeDSColors.of(context).textPrimary,
        tooltip: tooltip,
      );
    }
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: BridgeDSColors.of(context).accentBlue,
      foregroundColor: BridgeDSColors.of(context).textPrimary,
      mini: mini,
      tooltip: tooltip,
      child: Icon(icon),
    );
  }
}

/// 手機版 Drawer — 從左側滑出的導航面板。
class MobileDrawer extends StatelessWidget {
  const MobileDrawer({
    super.key,
    required this.items,
    required this.header,
    required this.onItemTap,
  });

  final Widget header;
  final List<MobileDrawerItem> items;
  final void Function(int index, String route) onItemTap;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: BridgeDSColors.of(context).surface,
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              child: header,
              decoration: BoxDecoration(color: BridgeDSColors.of(context).surfaceElevated),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: Icon(item.icon, color: item.color ?? BridgeDSColors.of(context).textSecondary),
                    title: Text(
                      item.label,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                            color: BridgeDSColors.of(context).textPrimary,
                          ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(); // close drawer
                      onItemTap(index, item.route);
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

class MobileDrawerItem {
  const MobileDrawerItem({
    required this.icon,
    required this.label,
    required this.route,
    this.color,
  });

  final IconData icon;
  final String label;
  final String route;
  final Color? color;
}

/// 手機版 List Tile — 帶 chevron 指示器，可整行點擊。
class MobileListTile extends StatelessWidget {
  const MobileListTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing = const Icon(Icons.chevron_right),
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TierStyle.of(ctx, Tier.cardBody).toTextStyle().copyWith(
                          color: BridgeDSColors.of(ctx).textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TierStyle.of(ctx, Tier.cardCaption).toTextStyle().copyWith(
                            color: BridgeDSColors.of(ctx).textTertiary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

/// 手機版 SafeArea wrapper（用於底部 Tab 之上）
class MobileSafeBottom extends StatelessWidget {
  const MobileSafeBottom({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: child,
    );
  }
}
