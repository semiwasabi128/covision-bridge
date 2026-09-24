// sovereignty_import_bubble_test.dart
// [資料主權 09-15] 匯入泡泡 widget test——主權語意驗證
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/widgets/vault/sovereignty_import_bubble.dart';
import 'package:bridge_app/theme/tier_style.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SovereigntyMode?> pumpShow(WidgetTester tester) async {
    SovereigntyMode? result;
    final tierTheme = await loadDefaultTierTheme();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [tierTheme]),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await SovereigntyImportBubble.show(
                  ctx,
                  pendingCount: 42,
                  hasLocalModel: true,
                );
              },
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('GO'));
    await tester.pump(); // 讓 show() 內的 await lastMode() microtask 完成
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('首次：完整泡泡——主權語意＋雙模式數據都在畫面上', (tester) async {
    await pumpShow(tester);

    // 主權語意
    expect(find.textContaining('你的資產'), findsOneWidget);
    expect(find.textContaining('由你決定'), findsOneWidget);
    // 雙模式與實測數據
    expect(find.textContaining('雲端優先'), findsOneWidget);
    expect(find.textContaining('全本地'), findsOneWidget);
    expect(find.textContaining('20/20'), findsOneWidget); // 雲端實測
    expect(find.textContaining('17/20'), findsOneWidget); // 本地實測
    expect(find.textContaining('不出這台機器'), findsOneWidget); // 本地主權保證
    expect(find.textContaining('魔鬼辣椒'), findsOneWidget); // 資料夾提示教育
    expect(find.textContaining('42 個檔案'), findsOneWidget); // 具體數字
  });

  testWidgets('首次：選全本地 → 回傳 local 並記住', (tester) async {
    await pumpShow(tester);
    await tester.tap(find.textContaining('全本地'));
    await tester.pump();
    await tester.tap(find.text('開始嵌入'));
    await tester.pump(); // prefs 寫入 microtask
    await tester.pump(const Duration(milliseconds: 50)); // dialog pop 動畫
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sovereignty.import.mode'), equals('local'));
  });

  testWidgets('首次：取消 → 回傳 null（不嵌入）', (tester) async {
    final mode = await pumpShow(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(mode, isNull);
  });

  testWidgets('第二次：一行確認（上次模式）——不繁瑣原則', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sovereignty.import.mode', 'cloud');
    await pumpShow(tester);
    // 一行確認版：有「上次選的模式」與「換模式」按鈕
    expect(find.textContaining('上次選的模式'), findsOneWidget);
    expect(find.text('換模式'), findsOneWidget);
    expect(find.text('雲端嵌入'), findsOneWidget);
  });

  testWidgets('第二次：換模式 → 進完整泡泡可改選本地', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sovereignty.import.mode', 'cloud');
    await pumpShow(tester);
    await tester.tap(find.text('換模式'));
    await tester.pumpAndSettle();
    expect(find.textContaining('全本地'), findsOneWidget); // 完整泡泡回來了
  });
}
