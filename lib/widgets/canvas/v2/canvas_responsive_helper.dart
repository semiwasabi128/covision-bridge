// V2 Canvas Responsive Helper (2026-08-06)
//
// 給 V2 Canvas (canvas_v2_workspace) 內部元件用的響應式 helper。
// 透過這個 helper 控制哪些元件在手機時顯示/隱藏，避免破壞 V2 完整 layout。
//
// 用法：
//   1. 在 widget 內引用 CanvasResponsiveHelper
//   2. 根據 isMobile / isTablet / isDesktop 分支
//
// 不改 V2 主結構，僅在組件層級套用響應式。

import 'package:flutter/widgets.dart';

import '../../../core/responsive.dart';

class CanvasResponsiveHelper {
  CanvasResponsiveHelper.of(this.context);

  final BuildContext context;

  /// 是否手機
  bool get isMobile => Responsive.isMobile(context);

  /// 是否平板
  bool get isTablet => Responsive.isTablet(context);

  /// 是否桌面
  bool get isDesktop => Responsive.isDesktop(context);

  /// 是否寬螢幕（平板 + 桌面）
  bool get isWide => isTablet || isDesktop;

  /// Canvas 工具列按鈕在手機時縮小
  double get toolbarButtonSize => Responsive.responsiveValue(
        context,
        mobile: 36,
        tablet: 40,
        desktop: 44,
      );

  /// Canvas 工具列 icon 大小
  double get toolbarIconSize => Responsive.responsiveValue(
        context,
        mobile: 16,
        tablet: 18,
        desktop: 20,
      );

  /// Sidebar 寬度（手機時可選隱藏）
  double get sidebarWidth => Responsive.responsiveValue(
        context,
        mobile: 0,    // 手機不顯示 sidebar
        tablet: 240,
        desktop: 320,
      );

  /// Detail panel 寬度
  double get detailPanelWidth => Responsive.responsiveValue(
        context,
        mobile: 0,
        tablet: 280,
        desktop: 320,
      );

  /// Canvas 節點在手機時的尺寸倍數
  double get nodeSizeMultiplier => Responsive.responsiveValue(
        context,
        mobile: 0.85,
        tablet: 1.0,
        desktop: 1.0,
      );

  /// 是否顯示完整版 chat sidebar
  bool get showFullChatSidebar => isDesktop;

  /// 是否顯示 compact chat sidebar（手機時也顯示在底部）
  bool get showCompactChatSidebar => isWide || isMobile;

  /// 是否顯示節點預覽 overlay
  bool get showNodePreviewOverlay => isDesktop || isTablet;

  /// 手機時關閉浮動提示（避免擋住節點）
  bool get hideFloatingHintsOnMobile => isMobile;
}
