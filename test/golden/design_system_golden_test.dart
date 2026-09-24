// Golden Tests — 視覺回歸測試 (階段 C/D 收斂保護)
//
// 用途：把關鍵 widget 渲染成圖片，跟 baseline 比對。
// 防止未來修改 BridgeDS token 時破壞視覺。
//
// 執行：
//   flutter test --update-goldens test/golden/  # 更新 baseline
//   flutter test test/golden/                    # 比對（失敗即回歸）
//
// 注意：golden test 在不同平台/螢幕尺寸可能會有微小差異，
// 建議在 macOS 上建立 baseline，所有平台共用。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/theme/bridge_design_system.dart';

void main() {
  group('Golden Tests - BridgeDS Surface Palette', () {
    testWidgets('Surface palette swatches', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: BridgeDS.canvas,
            body: _ColorPalette(
              title: 'Surface Palette',
              colors: [
                BridgeDS.canvas,
                BridgeDS.surface,
                BridgeDS.surfaceElevated,
                BridgeDS.surfaceHover,
                BridgeDS.darkPanel,
                BridgeDS.darkCanvas,
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/palette_surface.png'),
      );
    });

    testWidgets('Status palette swatches', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: BridgeDS.canvas,
            body: _ColorPalette(
              title: 'Status Palette',
              colors: const [
                Color(0xFF81C784), // softGreen
                Color(0xFF6B8E6B), // successGreen
                Color(0xFF2E7D32), // successDark
                Color(0xFFEF5350), // errorRed
                Color(0xFFFF1744), // alertRed
                Color(0xFF388E3C), // green700
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/palette_status.png'),
      );
    });

    testWidgets('Accent palette swatches', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: BridgeDS.canvas,
            body: _ColorPalette(
              title: 'Accent Palette',
              colors: const [
                Color(0xFFFF6363), // accentRed
                Color(0xFF55B3FF), // accentBlue
                Color(0xFF5FC992), // accentGreen
                Color(0xFFFFBC33), // accentYellow
                Color(0xFF533AFD), // accentPurple
                Color(0xFFF96BEE), // accentMagenta
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/palette_accent.png'),
      );
    });

    testWidgets('Node palette swatches', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: BridgeDS.canvas,
            body: _ColorPalette(
              title: 'Node Palette',
              colors: const [
                Color(0xFF4A9EFF), // fileBlue
                Color(0xFFFFB454), // sopOrange
                Color(0xFFFF6B9D), // pinkAccent
                Color(0xFF8E9AAF), // slate
                Color(0xFF4ECDC4), // teal
                Color(0xFF7C89FF), // deepPurple
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/palette_node.png'),
      );
    });

    testWidgets('Text colors hierarchy', (tester) async {
      tester.view.physicalSize = const Size(600, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: BridgeDS.canvas,
            body: _TextHierarchy(),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/text_hierarchy.png'),
      );
    });
  });
}

/// 簡單的顏色 palette widget，用於 golden test
class _ColorPalette extends StatelessWidget {
  const _ColorPalette({
    required this.title,
    required this.colors,
  });

  final String title;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: BridgeDS.canvas,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors
                .map((c) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// 文字層級展示 widget，用於 golden test
class _TextHierarchy extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: BridgeDS.canvas,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Primary Text (textPrimary)',
            style: TextStyle(
              color: Color(0xFFF9F9F9),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Secondary Text (textSecondary)',
            style: TextStyle(color: Color(0xFFCECECE), fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Tertiary Text (textTertiary)',
            style: TextStyle(color: Color(0xFF9C9C9D), fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            'Muted Text (textMuted)',
            style: TextStyle(color: Color(0xFF6A6B6C), fontSize: 12),
          ),
          SizedBox(height: 8),
          Text(
            'Quaternary Text (textQuaternary)',
            style: TextStyle(color: Color(0xFF434345), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
