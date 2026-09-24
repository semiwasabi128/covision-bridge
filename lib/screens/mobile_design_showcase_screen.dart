// Mobile Design System Showcase (2026-08-06)
//
// 演示 / 教學頁，列出所有 lib/widgets/mobile/ 提供的 widget 與 pattern。
// 用 MobilePageScaffold + 各個 mobile widget 示範。
//
// 入口：/mobile-showcase
//
// 用法：
// 1. 給設計師/PM 看 mobile UI 看起來怎樣
// 2. 給開源貢獻者當 reference
// 3. 給 QA 在不同裝置（手機/平板/桌面）看 layout 切換

import 'package:flutter/material.dart';

import '../core/responsive.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/mobile/app_bar_mobile.dart' as appbar;
import '../widgets/mobile/mobile_navigation.dart' as nav;

class MobileDesignShowcaseScreen extends StatefulWidget {
  const MobileDesignShowcaseScreen({super.key});

  @override
  State<MobileDesignShowcaseScreen> createState() =>
      _MobileDesignShowcaseScreenState();
}

class _MobileDesignShowcaseScreenState
    extends State<MobileDesignShowcaseScreen> {
  int _selectedBottomNavIndex = 0;

  void _onBottomNavTap(int index) {
    setState(() => _selectedBottomNavIndex = index);
    final items = _bottomNavItems;
    if (index < items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('切換到 ${items[index].label}'),
          duration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      maxContentWidth: 600,
      body: Column(
        children: [
          // 手機版 AppBar 示範
          _buildSectionTitle('Mobile AppBar'),
          appbar.MobileAppBar(
            title: 'Mobile Demo',
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _showSnack('搜尋點擊'),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showSnack('更多選項'),
              ),
            ],
          ),

          // 內容（可滾動）
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(nav.MobileSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 當前裝置資訊
                  _buildDeviceInfoCard(),
                  const SizedBox(height: nav.MobileSpacing.sectionGap),

                  // 示範 1: ListTile
                  _buildSectionTitle('appbar.MobileListTile'),
                  const SizedBox(height: nav.MobileSpacing.itemGap),
                  _buildListTileDemo(),
                  const SizedBox(height: nav.MobileSpacing.sectionGap),

                  // 示範 2: FAB
                  _buildSectionTitle('appbar.MobileFab'),
                  const SizedBox(height: nav.MobileSpacing.itemGap),
                  _buildFabDemo(),
                  const SizedBox(height: nav.MobileSpacing.sectionGap),

                  // 示範 3: Drawer
                  _buildSectionTitle('MobileDrawer'),
                  const SizedBox(height: nav.MobileSpacing.itemGap),
                  _buildDrawerTrigger(),
                  const SizedBox(height: nav.MobileSpacing.sectionGap),

                  // 示範 4: Bottom Nav
                  _buildSectionTitle('MobileBottomNav'),
                  const SizedBox(height: nav.MobileSpacing.itemGap),
                  _buildBottomNavPreview(),
                  const SizedBox(height: 80), // FAB room
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: appbar.MobileFab(
        onPressed: () => _showSnack('FAB 點擊'),
        icon: Icons.add,
        tooltip: '新增',
        label: '新增',
        mini: false,
      ),
    );
  }

  Widget _buildSectionTitle(String label) {
    return Text(
      label,
      style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
            color: BridgeDSColors.of(context).textPrimary,
          ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Container(
      padding: EdgeInsets.all(nav.MobileSpacing.pagePadding),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.devices,
                color: BridgeDSColors.of(context).accentBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '當前裝置',
                style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
                      color: BridgeDSColors.of(context).textPrimary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '類型: ${Responsive.isMobile(context) ? "手機" : Responsive.isTablet(context) ? "平板" : "桌面"}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                ),
          ),
          Text(
            '寬度: ${MediaQuery.sizeOf(context).width.toStringAsFixed(0)} px',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                ),
          ),
          Text(
            '高度: ${MediaQuery.sizeOf(context).height.toStringAsFixed(0)} px',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildListTileDemo() {
    return Column(
      children: [
        appbar.MobileListTile(
          leading: CircleAvatar(
            backgroundColor: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15),
            child: Icon(Icons.person, color: BridgeDSColors.of(context).accentBlue, size: 20),
          ),
          title: '夥伴',
          subtitle: 'AI 助理 · 在線',
          onTap: () => _showSnack('點擊 夥伴'),
        ),
        const Divider(height: 1),
        appbar.MobileListTile(
          leading: CircleAvatar(
            backgroundColor: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.15),
            child: Icon(Icons.code, color: BridgeDSColors.of(context).accentGreen, size: 20),
          ),
          title: 'Code Assistant',
          subtitle: '撰寫程式碼',
          onTap: () => _showSnack('點擊 Code Assistant'),
        ),
        const Divider(height: 1),
        appbar.MobileListTile(
          leading: CircleAvatar(
            backgroundColor: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
            child: Icon(Icons.brush, color: BridgeDSColors.of(context).accentPurple, size: 20),
          ),
          title: 'Design Assistant',
          subtitle: '視覺設計',
          onTap: () => _showSnack('點擊 Design Assistant'),
        ),
      ],
    );
  }

  Widget _buildFabDemo() {
    return Row(
      children: [
        appbar.MobileFab(
          onPressed: () => _showSnack('Default FAB'),
          icon: Icons.add,
          tooltip: '預設 FAB',
        ),
        const SizedBox(width: 16),
        appbar.MobileFab(
          onPressed: () => _showSnack('Mini FAB'),
          icon: Icons.edit,
          tooltip: 'Mini FAB',
          mini: true,
        ),
        const SizedBox(width: 16),
        appbar.MobileFab(
          onPressed: () => _showSnack('Extended FAB'),
          icon: Icons.rocket_launch,
          label: '啟動',
          tooltip: 'Extended FAB',
        ),
      ],
    );
  }

  Widget _buildDrawerTrigger() {
    return Builder(
      builder: (context) => ElevatedButton.icon(
        onPressed: () => Scaffold.of(context).openDrawer(),
        icon: const Icon(Icons.menu),
        label: const Text('打開 Drawer (從左滑出)'),
        style: ElevatedButton.styleFrom(
          backgroundColor: BridgeDSColors.of(context).accentBlue,
          foregroundColor: BridgeDSColors.of(context).textPrimary,
        ),
      ),
    );
  }

  Widget _buildBottomNavPreview() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surfaceElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedBottomNavIndex,
            onTap: _onBottomNavTap,
            backgroundColor: Colors.transparent,
            selectedItemColor: BridgeDSColors.of(context).accentBlue,
            unselectedItemColor: BridgeDSColors.of(context).textTertiary,
            type: BottomNavigationBarType.fixed,
            items: _bottomNavItems
                .map((item) => BottomNavigationBarItem(
                      icon: Icon(item.icon),
                      label: item.label,
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '當前選中：${_bottomNavItems[_selectedBottomNavIndex].label}',
          style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textMuted,
              ),
        ),
      ],
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }
}

// 共用 Bottom Navigation Bar 數據
class _DemoNavItem {
  const _DemoNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

const List<_DemoNavItem> _bottomNavItems = [
  _DemoNavItem(Icons.home, '首頁'),
  _DemoNavItem(Icons.chat, '對話'),
  _DemoNavItem(Icons.history, '記錄'),
  _DemoNavItem(Icons.settings, '設定'),
  _DemoNavItem(Icons.more_horiz, '更多'),
];

/// MobilePageScaffold 整合示範頁
/// 展示完整 MobilePageScaffold 使用方式（Drawer + BottomNav + FAB）
class MobilePageScaffoldDemo extends StatelessWidget {
  const MobilePageScaffoldDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return nav.MobilePageScaffold(
      title: 'Page Demo',
      body: Center(
        child: Text(
          '完整 MobilePageScaffold 演示',
          style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textPrimary,
              ),
        ),
      ),
      drawerHeader: Container(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bridge App',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Adaptive Design System',
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).textSecondary,
                  ),
            ),
          ],
        ),
      ),
      drawerItems: const [
        nav.MobileNavItem(icon: Icons.home, label: '首頁', route: '/'),
        nav.MobileNavItem(icon: Icons.account_circle, label: '我的', route: '/account'),
        nav.MobileNavItem(icon: Icons.folder, label: '專案', route: '/projects'),
        nav.MobileNavItem(icon: Icons.help, label: '說明', route: '/help'),
      ],
      bottomNavItems: const [
        nav.MobileNavItem(icon: Icons.home, label: '首頁', route: '/'),
        nav.MobileNavItem(icon: Icons.chat, label: '對話', route: '/chat'),
        nav.MobileNavItem(icon: Icons.history, label: '記錄', route: '/history'),
        nav.MobileNavItem(icon: Icons.settings, label: '設定', route: '/settings'),
        nav.MobileNavItem(icon: Icons.more_horiz, label: '更多', route: '/more'),
      ],
      currentBottomNavIndex: 0,
      onBottomNavTap: (i) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切換到 ${_bottomNavItems[i].label}')),
      ),
      floatingActionButton: appbar.MobileFab(
        onPressed: () {},
        icon: Icons.add,
      ),
    );
  }
}
