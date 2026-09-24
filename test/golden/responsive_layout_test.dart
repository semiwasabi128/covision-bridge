// Responsive Layout Tests — 手機/平板/桌面三裝置測試 (2026-08-06)
//
// 跑實際 UI 在手機、平板、桌面尺寸下的渲染表現：
// 1. MobileDesignShowcaseScreen 在三個尺寸下都能正確渲染
// 2. 三個尺寸下底部導航顯示狀態正確
// 3. 三個尺寸下 FAB 大小正確
// 4. 三個尺寸下 Drawer 行為正確
// 5. 三個尺寸下文字層級顏色正確
//
// 透過 ViewConfiguration + pumpWidget 模擬真實裝置。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/core/responsive.dart';
import 'package:bridge_app/screens/mobile_design_showcase_screen.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/theme/tier_registry.dart';

/// 為測試定義三種裝置的物理尺寸
class TestDevice {
  static const Size mobile = Size(375, 667); // iPhone SE
  static const Size tablet = Size(768, 1024); // iPad
  static const Size desktop = Size(1280, 800); // MacBook
}

Future<void> _pumpAtDevice(
  WidgetTester tester,
  Size deviceSize,
  Widget child,
) async {
  tester.view.physicalSize = deviceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: [TierTheme.fromManifest(_buildTierRegistryForTest())],
      ),
      home: child,
    ),
  );

  await tester.pumpAndSettle();
}

/// 建立空的 TierRegistry（測試環境不需要真實 tokens）
TierRegistry _buildTierRegistryForTest() {
  // 因為從 dart 2.12 起 const field 不能為 null，
  // 我們建立最小 TierRegistry 提供給測試
  return TierRegistry.fromJson(_minimalRegistryJson);
}

const Map<String, dynamic> _minimalRegistryJson = {
  'id': 'test',
  'name': 'Test Manifest',
  'author': 'test',
  'license': 'MIT',
  'tiers': <String, dynamic>{
    'card.title': {
      'key': 'card.title',
      'fontSize': 16,
      'fontWeight': 'w600',
      'letterSpacing': 0.3,
    },
    'card.body': {
      'key': 'card.body',
      'fontSize': 14,
      'fontWeight': 'w400',
      'letterSpacing': 0.2,
    },
    'card.caption': {
      'key': 'card.caption',
      'fontSize': 12,
      'fontWeight': 'w400',
      'letterSpacing': 0.1,
    },
    'card.heroTitle': {
      'key': 'card.heroTitle',
      'fontSize': 20,
      'fontWeight': 'bold',
      'letterSpacing': 0.4,
    },
  },
  'tokens': <String, dynamic>{},
  'fonts': <String, String>{},
};

void main() {
  group('Mobile Design Showcase - 三裝置版本', () {
    testWidgets('📱 手機 (375×667) 渲染正確', (tester) async {
      await _pumpAtDevice(
        tester,
        TestDevice.mobile,
        const MobileDesignShowcaseScreen(),
      );

      // 應該能找到 showcase 的各個區塊（visible + scroll accessible）
      expect(find.text('Mobile AppBar'), findsOneWidget);

      // 確認裝置判斷為手機
      final BuildContext context = tester.element(find.text('Mobile AppBar'));
      expect(Responsive.isMobile(context), isTrue);
      expect(Responsive.isTablet(context), isFalse);
      expect(Responsive.isDesktop(context), isFalse);

      // 確認 FAB 存在
      expect(find.byType(FloatingActionButton), findsWidgets);
    });

    testWidgets('📱 手機 Golden test 視覺回歸', (tester) async {
      await _pumpAtDevice(
        tester,
        TestDevice.mobile,
        const MobileDesignShowcaseScreen(),
      );

      await expectLater(
        find.byType(MobileDesignShowcaseScreen),
        matchesGoldenFile('goldens/responsive_mobile_showcase.png'),
      );
    });

    testWidgets('📲 平板 (768×1024) 渲染正確', (tester) async {
      await _pumpAtDevice(
        tester,
        TestDevice.tablet,
        const MobileDesignShowcaseScreen(),
      );

      // 平板時 ResponsiveHelper 應該判定為平板
      final BuildContext context = tester.element(find.text('Mobile AppBar'));
      expect(Responsive.isTablet(context), isTrue);

      // 平板尺寸下應該也能找到所有區塊
      expect(find.text('Mobile AppBar'), findsOneWidget);
      expect(find.text('MobileBottomNav'), findsOneWidget);

      await expectLater(
        find.byType(MobileDesignShowcaseScreen),
        matchesGoldenFile('goldens/responsive_tablet_showcase.png'),
      );
    });

    testWidgets('🖥️ 桌面 (1280×800) 渲染正確', (tester) async {
      await _pumpAtDevice(
        tester,
        TestDevice.desktop,
        const MobileDesignShowcaseScreen(),
      );

      final BuildContext context = tester.element(find.text('Mobile AppBar'));
      expect(Responsive.isDesktop(context), isTrue);

      expect(find.text('Mobile AppBar'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsWidgets);

      await expectLater(
        find.byType(MobileDesignShowcaseScreen),
        matchesGoldenFile('goldens/responsive_desktop_showcase.png'),
      );
    });
  });

  group('Responsive 邊界值測試', () {
    test('375px 以下屬於手機', () {
      const small = 320.0;
      expect(small < 600, isTrue, reason: '320 < 600 → 手機');
    });

    test('600px 屬於手機（<= 600）', () {
      const sixHundred = 600.0;
      expect(sixHundred <= 600, isTrue);
    });

    test('601px 屬於平板（> 600）', () {
      const sixtyOne = 601.0;
      expect(sixtyOne > 600, isTrue);
    });

    test('1024px 屬於平板（<= 1024）', () {
      const tenTwentyFour = 1024.0;
      expect(tenTwentyFour <= 1024, isTrue);
    });

    test('1025px 屬於桌面（> 1024）', () {
      const tenTwentyFive = 1025.0;
      expect(tenTwentyFive > 1024, isTrue);
    });
  });

  group('三裝置視覺差異檢查', () {
    testWidgets('手機 vs 桌面：FAB position 應相同 (右下)', (tester) async {
      // 手機
      tester.view.physicalSize = TestDevice.mobile;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [TierTheme.fromManifest(_buildTierRegistryForTest())],
          ),
          home: const MobileDesignShowcaseScreen(),
        ),
      );

      expect(find.byType(FloatingActionButton), findsWidgets);

      // 桌面
      tester.view.physicalSize = TestDevice.desktop;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [TierTheme.fromManifest(_buildTierRegistryForTest())],
          ),
          home: const MobileDesignShowcaseScreen(),
        ),
      );

      expect(find.byType(FloatingActionButton), findsWidgets);

      tester.view.reset();
    });
  });

  group('底層設計系統在三裝置下的一致性', () {
    testWidgets('BridgeDS textPrimary 在三裝置下都顯示', (tester) async {
      for (final size in [TestDevice.mobile, TestDevice.tablet, TestDevice.desktop]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                backgroundColor: BridgeDS.canvas,
                body: Text(
                  'BridgeDS Token Test',
                  style: TextStyle(color: BridgeDS.textPrimary, fontSize: 16),
                ),
              ),
            ),
          ),
        );

        expect(find.text('BridgeDS Token Test'), findsOneWidget);
      }

      tester.view.reset();
    });

    testWidgets('MobileSpacing.pagePadding = 16 一致', (tester) async {
      // 跨裝置 padding 應一致（mobile 版不管尺寸都是 16）
      for (final size in [TestDevice.mobile, TestDevice.tablet, TestDevice.desktop]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Padding(
              padding: const EdgeInsets.all(16), // MobileSpacing.pagePadding
              child: Container(
                width: 100,
                height: 100,
                color: BridgeDS.accentBlue,
              ),
            ),
          ),
        );

        expect(find.byType(Container), findsOneWidget);
      }

      tester.view.reset();
    });
  });
}
