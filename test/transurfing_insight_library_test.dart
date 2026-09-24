import 'package:bridge_app/services/brain_progress_store.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/widgets/transurfing_insight_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // [Tier 整肅 2026-09-21 後] widget 內 TierStyle.of() 要求 TierTheme。
  late final ThemeData tierHostTheme;
  setUpAll(() async {
    tierHostTheme = ThemeData.dark().copyWith(
      extensions: [await loadDefaultTierTheme()],
    );
  });

  const accurateInsight = 'Transurfing洞察：使用者注意力容易被外部平台或新 AI 服務捕獲，需要先轉成自己的輸出。';
  const mutedInsight = 'Transurfing洞察：此類議題出現逆流訊號，需要檢查是否過度控制、焦慮或走進外部目標。';

  testWidgets('renders insight cards and triggers feedback actions', (
    tester,
  ) async {
    String? tappedInsight;
    TransurfingInsightFeedback? tappedFeedback;

    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: TransurfingInsightLibrary(
            progress: BrainProgressStore.snapshotForXp(125),
            records: const [
              TransurfingInsightRecord(
                insight: accurateInsight,
                feedback: TransurfingInsightFeedback.accurate,
                inMemory: true,
                trustScore: 85,
              ),
              TransurfingInsightRecord(
                insight: mutedInsight,
                feedback: TransurfingInsightFeedback.muted,
                inMemory: true,
                trustScore: 35,
              ),
            ],
            onFeedback: (insight, feedback) async {
              tappedInsight = insight;
              tappedFeedback = feedback;
            },
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('洞察卡片庫'), findsOneWidget);
    expect(find.text('Bridge Brain Lv 2'), findsOneWidget);
    expect(find.text('同步率 25/150 XP'), findsOneWidget);
    expect(find.textContaining('注意力容易被外部平台'), findsOneWidget);
    expect(find.textContaining('逆流訊號'), findsOneWidget);
    expect(find.text('Lv 5'), findsOneWidget);
    expect(find.text('高信任 85%'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '不準').first);
    await tester.pump();

    expect(tappedInsight, accurateInsight);
    expect(tappedFeedback, TransurfingInsightFeedback.inaccurate);
  });

  testWidgets('filters insight cards by status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: TransurfingInsightLibrary(
            records: const [
              TransurfingInsightRecord(
                insight: accurateInsight,
                feedback: TransurfingInsightFeedback.accurate,
                inMemory: true,
                trustScore: 85,
              ),
              TransurfingInsightRecord(
                insight: mutedInsight,
                feedback: TransurfingInsightFeedback.muted,
                inMemory: true,
                trustScore: 35,
              ),
            ],
            onFeedback: (_, _) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('暫停').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('逆流訊號'), findsOneWidget);
    expect(find.textContaining('注意力容易被外部平台'), findsNothing);
  });
}
