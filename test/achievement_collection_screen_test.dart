import 'package:bridge_app/screens/achievement_collection_screen.dart';
import 'package:bridge_app/services/achievement_store.dart';
import 'package:bridge_app/services/brain_progress_store.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// [Tier 整肅 2026-09-21 後] screen 內 TierStyle.of() 要求 TierTheme 已註冊，
// 否則 throw StateError。測試 host 須掛載（loadDefaultTierTheme 已記憶化，
// 跨測試安全）。
Future<void> _pumpHost(WidgetTester tester, Widget child) async {
  final tierTheme = await loadDefaultTierTheme();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [tierTheme]),
      home: child,
    ),
  );
}

void main() {
  testWidgets('renders locked SemiDAO achievement collection', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _pumpHost(tester, const AchievementCollectionScreen());
    await tester.pumpAndSettle();

    expect(find.text('山門徽章'), findsOneWidget);
    expect(find.text('山門DAO / SemiDAO'), findsOneWidget);
    expect(find.text('已解鎖 0/2 個徽章'), findsOneWidget);
    expect(find.text('山門初啟'), findsOneWidget);
    expect(find.text('第一座橋已開通'), findsOneWidget);
    expect(find.text('未解鎖'), findsNWidgets(2));
  });

  testWidgets('renders unlocked achievement and brain progress', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AchievementStore.unlockCompanionPackFirstImport();
    await BrainProgressStore.awardXp(25);

    await _pumpHost(tester, const AchievementCollectionScreen());
    await tester.pumpAndSettle();

    expect(find.text('已解鎖 1/2 個徽章'), findsOneWidget);
    expect(find.text('Bridge Brain Lv 1'), findsOneWidget);
    expect(find.text('25 XP'), findsOneWidget);
    expect(find.text('+25 XP'), findsOneWidget);
  });
}
