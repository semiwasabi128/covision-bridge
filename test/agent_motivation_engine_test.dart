import 'package:bridge_app/services/agent_motivation_engine.dart';
import 'package:bridge_app/services/brain_progress_store.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const insight = 'Transurfing洞察：此類議題出現自己的門訊號，與使用者需求、喜好或創作方向有共振。';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BrainProgressStore.clear();
    await AgentMotivationEngine.clear();
  });

  test(
    'accurate feedback increases agent drive and keeps insight usable',
    () async {
      const engine = AgentMotivationEngine();

      final change = await engine.applyInsightFeedback(
        agentName: '約瑟',
        insight: insight,
        feedback: TransurfingInsightFeedback.accurate,
      );

      expect(change.after.agentName, '約瑟');
      expect(change.after.driveXp, 15);
      expect(change.after.usefulFeedbackCount, 1);
      expect(
        change.after.accuracyScore,
        greaterThan(change.before.accuracyScore),
      );
      expect(change.after.lastSignal, contains('更常引用'));
      expect(
        await MemoryStore.getTransurfingInsightFeedback(insight),
        TransurfingInsightFeedback.accurate,
      );
    },
  );

  test(
    'inaccurate feedback lowers accuracy and becomes correction signal',
    () async {
      const engine = AgentMotivationEngine();

      await engine.applyInsightFeedback(
        agentName: '約瑟',
        insight: insight,
        feedback: TransurfingInsightFeedback.accurate,
      );
      final beforeCorrection = await engine.getSnapshot('約瑟');
      final change = await engine.applyInsightFeedback(
        agentName: '約瑟',
        insight: insight,
        feedback: TransurfingInsightFeedback.inaccurate,
      );

      expect(change.before.accuracyScore, beforeCorrection.accuracyScore);
      expect(change.after.correctionCount, 1);
      expect(change.after.accuracyScore, lessThan(change.before.accuracyScore));
      expect(change.after.learningFocus, contains('降低誤判'));
      expect(
        await MemoryStore.getTransurfingInsightFeedback(insight),
        TransurfingInsightFeedback.inaccurate,
      );
    },
  );

  test('repeated corrections create a recovery route shortcut', () async {
    const engine = AgentMotivationEngine();

    await engine.applyInsightFeedback(
      agentName: '約瑟',
      insight: '$insight 第一次',
      feedback: TransurfingInsightFeedback.inaccurate,
    );
    final first = await engine.getSnapshot('約瑟');

    expect(first.correctionStreak, 1);
    expect(first.hasRecoveryRoute, isFalse);

    final change = await engine.applyInsightFeedback(
      agentName: '約瑟',
      insight: '$insight 第二次',
      feedback: TransurfingInsightFeedback.inaccurate,
    );

    expect(change.after.correctionStreak, 2);
    expect(change.after.hasRecoveryRoute, isTrue);
    expect(change.after.recoveryRouteCount, 1);
    expect(change.after.activeRecoveryRoute, contains('通關路線'));
  });
}
