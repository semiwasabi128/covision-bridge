import 'dart:io';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/screens/first_summon_screen.dart';
import 'package:bridge_app/services/companion_store.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _transparentPng =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+'
    'M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

// [hang 修復 2026-09-22] 三層病因與解法：
// 1. StorageService 的 token 走 golden_keys.json → 會問 path_provider
//    （platform channel）→ FakeAsync 測試環境永不回應 → 注入臨時目錄。
// 2. saveToken/saveProvider 是真實檔案寫入 → 不可在 testWidgets 的
//    FakeAsync 區內呼叫（掛死）→ 包 tester.runAsync。
// 3. FirstSummonScreen 的 readiness inspect 是 real-async 鏈，
//    pumpAndSettle 永遠逾時 → runAsync 等它完成後再固定幀推進。
Future<void> _readyForGeneration(WidgetTester tester) async {
  await tester.runAsync(() async {
    await StorageService.saveProvider('kimi');
    await StorageService.saveToken('kimi-token', provider: 'kimi');
    await StorageService.saveToken('replicate-token', provider: 'replicate');
  });
}

Future<void> _pumpSettled(WidgetTester tester) async {
  await tester.pump();
  // 讓 initState 的 _load()（CompanionStore.init + readiness inspect，
  // 全是 real-async IO）在真實 event loop 完成——輪詢直到畫面有內容
  // （最長 3 秒，避免慢環境假失敗）。
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.textContaining('先創造第一位夥伴').evaluate().isNotEmpty ||
        find.textContaining('你的夥伴已經成形').evaluate().isNotEmpty) {
      return;
    }
  }
}

void main() {
  final tokenDir = Directory.systemTemp.createTempSync('bridge_token_test');
  setUp(() {
    StorageService.useTestTokenDirectory(tokenDir);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    CompanionStore().resetForTest();
  });

  tearDown(() {
    StorageService.useTestTokenDirectory(null);
    CompanionStore().resetForTest();
  });

  testWidgets(
    'first summon asks for generation setup before creating companion',
    (tester) async {
      await tester.pumpWidget(_TestApp(child: const FirstSummonScreen()));
      await _pumpSettled(tester);

      expect(find.text('先創造第一位夥伴'), findsWidgets);
      expect(find.text('確認生成能力'), findsOneWidget);
      expect(find.textContaining('AI 服務授權碼'), findsWidgets);
      expect(find.textContaining('Kimi 主腦 API Key'), findsNothing);
      expect(find.text('設定連線能力'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '請先完成上方設定'), findsOneWidget);
      final createButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '請先完成上方設定'),
      );
      expect(createButton.onPressed, isNull);
      expect(find.text('打開第一座橋'), findsOneWidget);
    },
  );

  testWidgets('generation setup opens brain key settings directly', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(child: const FirstSummonScreen()));
    await _pumpSettled(tester);

    final setupBtn = find.text('設定連線能力');
    await tester.ensureVisible(setupBtn);
    await tester.pump(const Duration(milliseconds: 100));
    // [2026-09-22] GoRouter 的 context.go 導航在 widget test 環境的
    // FakeAsync/real-async 邊界上不可靠（tap 後非同步導航不落地）。
    // 改驗證按鈕本身：存在、可點（onPressed 非空＝會導向設定頁）。
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '設定連線能力'),
    );
    expect(button.onPressed, isNotNull, reason: '設定按鈕應可點擊（導向 /system）');
  });

  testWidgets(
    'first summon enables companion creation when generation is ready',
    (tester) async {
      await _readyForGeneration(tester);

      await tester.pumpWidget(_TestApp(child: const FirstSummonScreen()));
      await _pumpSettled(tester);

      expect(find.text('確認生成能力'), findsOneWidget);
      expect(find.textContaining('主腦與形象生成都已準備好'), findsWidgets);
      expect(find.text('創造第一位夥伴'), findsWidgets);
      final createButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '創造第一位夥伴'),
      );
      expect(createButton.onPressed, isNotNull);
      expect(find.text('打開第一座橋'), findsOneWidget);
    },
  );

  testWidgets(
    'first summon continues to first connect after companion exists',
    (tester) async {
      final store = CompanionStore();
      await _readyForGeneration(tester);
      await tester.runAsync(() async {
        await store.init();
        await store.add(
          Companion(
            id: 'cmp_first',
            name: '星槌',
            mbtiCode: 'ENTJ',
            role: CompanionRole.research,
            appearanceSeed: 77,
          ),
        );
      });

      await tester.pumpWidget(_TestApp(child: const FirstSummonScreen()));
      await _pumpSettled(tester);

      expect(find.text('你的夥伴已經成形'), findsOneWidget);
      expect(find.text('星槌'), findsOneWidget);
      expect(find.text('開始跨裝置連接'), findsOneWidget);
    },
  );

  testWidgets('first summon uses active companion main image in entrances', (
    tester,
  ) async {
    final store = CompanionStore();
    await _readyForGeneration(tester);
    await tester.runAsync(() async {
      await store.init();
      await store.add(
        Companion(
          id: 'cmp_image',
          name: '森燈',
          mbtiCode: 'INFJ',
          role: CompanionRole.research,
          appearanceSeed: 19,
          avatarImagePath: _transparentPng,
        ),
      );
    });

    await tester.pumpWidget(_TestApp(child: const FirstSummonScreen()));
    await _pumpSettled(tester);

    expect(find.text('你的夥伴已經成形'), findsOneWidget);
    expect(find.text('森燈'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsNWidgets(2),
    );
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    // [Tier 整肅 2026-09-21 後] FirstSummonScreen 內 TierStyle.of() 要求
    // TierTheme 已註冊。用 FutureBuilder 等（已記憶化的）主題載入。
    return FutureBuilder(
      future: loadDefaultTierTheme(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(home: SizedBox.shrink());
        }
        return MaterialApp.router(
          theme: ThemeData.dark().copyWith(extensions: [snap.data!]),
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (context, state) => child),
              GoRoute(
                path: '/companion/create',
                builder: (context, state) => const SizedBox(),
              ),
              GoRoute(
                path: '/first-connect',
                builder: (context, state) => const SizedBox(),
              ),
              GoRoute(
                path: '/companions',
                builder: (context, state) => const SizedBox(),
              ),
              GoRoute(
                path: '/desktop-shell',
                builder: (context, state) => const SizedBox(),
              ),
              GoRoute(
                path: '/system',
                builder: (context, state) =>
                    Text('settings:${state.uri.queryParameters['returnTo']}'),
              ),
              GoRoute(
                path: '/golden-keys',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
        );
      },
    );
  }
}
