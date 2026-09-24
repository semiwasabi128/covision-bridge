// sprint8_audit_test.dart
// Sprint 8 — 擺錘審計 + clip 消費計數器測試
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試範圍：
// 1. AuditStore — 擺錘計數、跨日切換、7 天摘要
// 2. PendulumAuditor — 從 reflection 提取 pendulumSignals 寫入 store
// 3. ClipConsumptionCounter — 各種短影音消費訊息偵測
// 4. Pipeline 整合 — analyzeAsync 後 auditStore 自動記錄
// 5. PendulumAuditChart widget — 渲染測試
// 6. Panel — 擺錘週報區塊出現條件

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/audit/audit_store.dart';
import 'package:bridge_app/services/brain_pipeline/audit/pendulum_auditor.dart';
import 'package:bridge_app/services/brain_pipeline/audit/clip_consumption_counter.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline/transurfing_pipeline.dart';
import 'package:bridge_app/widgets/brain_pipeline/pendulum_audit_chart.dart';

// === Helpers ===

BrainReflection _testReflection({
  List<PendulumSignal> pendulumSignals = const [],
  Map<String, LayerResult<dynamic>> layerResults = const {},
}) {
  return BrainReflection(
    userIntent: '測試',
    attentionState: AttentionState.clear,
    pendulumSignals: pendulumSignals,
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: HeartMindAlignment.aligned,
    fraileResonance: FraileResonance.present,
    doorCandidates: const [],
    flowState: FlowState.withFlow,
    recommendedMove: RecommendedMove.answerDirectly,
    companionExpression: const CompanionExpression(
      mood: AgentCompanionMood.idle,
      action: AgentCompanionAction.standing,
      statusText: '測試',
    ),
    guidance: '測試指引',
    layerResults: layerResults,
  );
}

PendulumSignal _signal(
  PendulumSignalType type, {
  String evidence = '測試證據',
  PendulumSignalSource source = PendulumSignalSource.ruleMatch,
}) {
  return PendulumSignal(
    type: type,
    label: type.name,
    evidence: evidence,
    source: source,
  );
}

void main() {
  // === 1. AuditStore — Pendulum Audit ===

  group('AuditStore — Pendulum Audit', () {
    test('recordPendulums increments counts for detected types', () {
      final store = AuditStore();
      store.recordPendulums([
        _signal(PendulumSignalType.urgency, evidence: '必須現在'),
        _signal(PendulumSignalType.fear, evidence: '怕失敗'),
        _signal(PendulumSignalType.urgency, evidence: '急著完成'),
      ]);

      final summary = store.getAuditLast7Days();
      final today = summary.days.last; // index 6 = today

      expect(today.totalCount(PendulumSignalType.urgency), 2);
      expect(today.totalCount(PendulumSignalType.fear), 1);
      expect(today.totalCount(PendulumSignalType.comparison), 0);
    });

    test('rule and ai counts are separate', () {
      final store = AuditStore();
      store.recordPendulums([
        _signal(PendulumSignalType.urgency, source: PendulumSignalSource.ruleMatch),
        _signal(PendulumSignalType.urgency, source: PendulumSignalSource.aiInferred),
        _signal(PendulumSignalType.urgency, source: PendulumSignalSource.aiInferred),
      ]);

      final today = store.getAuditLast7Days().days.last;
      expect(today.ruleCounts['urgency'], 1);
      expect(today.aiCounts['urgency'], 2);
      expect(today.totalCount(PendulumSignalType.urgency), 3);
    });

    test('evidence quotes are saved (max 5)', () {
      final store = AuditStore();
      // Record 7 signals of same type
      for (int i = 0; i < 7; i++) {
        store.recordPendulums([
          _signal(PendulumSignalType.urgency, evidence: '證據 $i'),
        ]);
      }

      final today = store.getAuditLast7Days().days.last;
      final quotes = today.evidenceQuotes['urgency']!;
      expect(quotes.length, 5); // capped at 5
      expect(quotes.first, '證據 0');
      expect(quotes.last, '證據 4');
    });

    test('grandTotal sums all types', () {
      final store = AuditStore();
      store.recordPendulums([
        _signal(PendulumSignalType.urgency),
        _signal(PendulumSignalType.fear),
        _signal(PendulumSignalType.comparison),
        _signal(PendulumSignalType.proving),
      ]);

      final today = store.getAuditLast7Days().days.last;
      expect(today.grandTotal, 4);
    });

    test('7-day summary returns 7 entries', () {
      final store = AuditStore();
      final summary = store.getAuditLast7Days();
      expect(summary.days.length, 7);
      // All empty initially
      for (final day in summary.days) {
        expect(day.grandTotal, 0);
      }
    });

    test('7-day summary totalForType aggregates across days', () {
      var mockNow = DateTime(2026, 7, 4, 10, 0, 0);
      final store = AuditStore(clock: () => mockNow);

      // Day 1: 2 urgency
      store.recordPendulums([
        _signal(PendulumSignalType.urgency),
        _signal(PendulumSignalType.urgency),
      ]);

      // Advance to next day
      mockNow = mockNow.add(const Duration(days: 1));

      // Day 2: 3 urgency
      store.recordPendulums([
        _signal(PendulumSignalType.urgency),
        _signal(PendulumSignalType.urgency),
        _signal(PendulumSignalType.urgency),
      ]);

      final summary = store.getAuditLast7Days();
      expect(summary.totalForType(PendulumSignalType.urgency), 5);
      expect(summary.grandTotal, 5);
    });
  });

  // === 2. AuditStore — Day Rollover ===

  group('AuditStore — Day Rollover', () {
    test('counts reset on new day', () {
      var mockNow = DateTime(2026, 7, 4, 23, 0, 0);
      final store = AuditStore(clock: () => mockNow);

      // Day 1: record some pendulums
      store.recordPendulums([
        _signal(PendulumSignalType.urgency),
        _signal(PendulumSignalType.fear),
      ]);

      // Next day
      mockNow = DateTime(2026, 7, 5, 8, 0, 0);

      // Day 2: record different pendulum
      store.recordPendulums([
        _signal(PendulumSignalType.comparison),
      ]);

      final summary = store.getAuditLast7Days();
      // Today (day 2) should only have comparison
      final today = summary.days.last;
      expect(today.totalCount(PendulumSignalType.urgency), 0);
      expect(today.totalCount(PendulumSignalType.fear), 0);
      expect(today.totalCount(PendulumSignalType.comparison), 1);

      // Yesterday should have urgency + fear
      final yesterday = summary.days[5];
      expect(yesterday.totalCount(PendulumSignalType.urgency), 1);
      expect(yesterday.totalCount(PendulumSignalType.fear), 1);
    });

    test('clip consumption resets on new day', () {
      var mockNow = DateTime(2026, 7, 4, 23, 0, 0);
      final store = AuditStore(clock: () => mockNow);

      store.addClipConsumptionSeconds(3600);
      expect(store.clipConsumptionSecondsToday, 3600);

      // Next day
      mockNow = DateTime(2026, 7, 5, 8, 0, 0);
      expect(store.clipConsumptionSecondsToday, 0);
    });
  });

  // === 3. AuditStore — Clip Consumption ===

  group('AuditStore — Clip Consumption', () {
    test('addClipConsumptionSeconds accumulates', () {
      final store = AuditStore();
      store.addClipConsumptionSeconds(1800);
      store.addClipConsumptionSeconds(900);

      expect(store.clipConsumptionSecondsToday, 2700);
    });

    test('negative seconds are ignored', () {
      final store = AuditStore();
      store.addClipConsumptionSeconds(-100);
      expect(store.clipConsumptionSecondsToday, 0);
    });

    test('clipOverLimit triggers at 3600 seconds', () {
      final store = AuditStore();
      store.addClipConsumptionSeconds(3599);
      expect(store.getAuditLast7Days().clipOverLimit, false);

      store.addClipConsumptionSeconds(1);
      expect(store.getAuditLast7Days().clipOverLimit, true);
    });

    test('clear resets everything', () {
      final store = AuditStore();
      store.recordPendulums([_signal(PendulumSignalType.urgency)]);
      store.addClipConsumptionSeconds(1800);

      store.clear();

      final summary = store.getAuditLast7Days();
      expect(summary.grandTotal, 0);
      expect(summary.clipConsumptionSecondsToday, 0);
    });
  });

  // === 4. PendulumAuditor ===

  group('PendulumAuditor', () {
    test('record extracts pendulumSignals from reflection', () {
      final store = AuditStore();
      final auditor = PendulumAuditor(store);

      final reflection = _testReflection(
        pendulumSignals: [
          _signal(PendulumSignalType.urgency, evidence: '必須'),
          _signal(PendulumSignalType.fear, evidence: '怕'),
        ],
      );

      auditor.record(reflection);

      final today = store.getAuditLast7Days().days.last;
      expect(today.totalCount(PendulumSignalType.urgency), 1);
      expect(today.totalCount(PendulumSignalType.fear), 1);
    });

    test('record with empty signals does nothing', () {
      final store = AuditStore();
      final auditor = PendulumAuditor(store);

      auditor.record(_testReflection(pendulumSignals: const []));

      expect(store.getAuditLast7Days().grandTotal, 0);
    });
  });

  // === 5. ClipConsumptionCounter ===

  group('ClipConsumptionCounter', () {
    test('detects "刷了 2 小時 shorts"', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      final seconds = counter.detectAndRecord('我今天刷了 2 小時 shorts');
      expect(seconds, 7200);
      expect(store.clipConsumptionSecondsToday, 7200);
    });

    test('detects "看了 30 分鐘 TikTok"', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      final seconds = counter.detectAndRecord('又看了 30 分鐘 TikTok');
      expect(seconds, 1800);
    });

    test('detects Chinese "刷了 1 小時" (no platform keyword)', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      final seconds = counter.detectAndRecord('刷了 1 小時');
      expect(seconds, 3600);
    });

    test('detects "刷手機 2 小時"', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      final seconds = counter.detectAndRecord('刷手機 2 小時');
      expect(seconds, 7200);
    });

    test('accumulates across multiple messages', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      counter.detectAndRecord('刷了 2 小時 shorts');
      counter.detectAndRecord('又刷了 30 分鐘');
      counter.detectAndRecord('再看 15 分鐘 reels');

      expect(store.clipConsumptionSecondsToday, 7200 + 1800 + 900);
    });

    test('returns 0 for non-clip messages', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      expect(counter.detect('你好'), 0);
      expect(counter.detect('今天天氣不錯'), 0);
      expect(counter.detect('我想寫論文'), 0);
    });

    test('returns 0 for time without scroll verb or platform', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      // "花了 2 小時寫程式" — 有時間但不是刷手機
      expect(counter.detect('花了 2 小時寫程式'), 0);
    });

    test('detects English formats', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      expect(counter.detect('watched shorts for 2 hours'), 7200);
      expect(counter.detect('browsed TikTok for 45 minutes'), 2700);
    });

    test('isOverLimit after 60 minutes', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      expect(counter.isOverLimit, false);
      counter.detectAndRecord('刷了 1 小時 shorts');
      expect(counter.isOverLimit, true);
    });

    test('detect only does not write to store', () {
      final store = AuditStore();
      final counter = ClipConsumptionCounter(store);

      counter.detect('刷了 2 小時 shorts');
      expect(store.clipConsumptionSecondsToday, 0);
    });
  });

  // === 6. Pipeline Integration ===

  group('Pipeline Sprint 8 Integration', () {
    test('analyzeAsync records pendulums to auditStore', () async {
      final auditStore = AuditStore();
      final pipeline = TransurfingPipeline(auditStore: auditStore);

      // 這個訊息應該觸發 urgency 擺錘（規則版命中「必須」）
      await pipeline.analyzeAsync('我必須現在完成這件事，不然就完了');

      final summary = auditStore.getAuditLast7Days();
      final today = summary.days.last;

      // 規則版應該至少偵測到 1 個擺錘
      expect(today.grandTotal, greaterThan(0));
    });

    test('analyzeAsync records clip consumption to auditStore', () async {
      final auditStore = AuditStore();
      final pipeline = TransurfingPipeline(auditStore: auditStore);

      await pipeline.analyzeAsync('我今天刷了 2 小時 shorts');

      expect(auditStore.clipConsumptionSecondsToday, 7200);
    });

    test('analyzeAsync without auditStore does not crash', () async {
      final pipeline = TransurfingPipeline();

      // Should complete without error
      final result = await pipeline.analyzeAsync('測試訊息');
      expect(result, isNotNull);
    });

    test('multiple rounds accumulate in auditStore', () async {
      final auditStore = AuditStore();
      final pipeline = TransurfingPipeline(auditStore: auditStore);

      await pipeline.analyzeAsync('我必須現在完成');
      await pipeline.analyzeAsync('怕做不好，別人都做得很好');
      await pipeline.analyzeAsync('刷了 1 小時 shorts');

      final summary = auditStore.getAuditLast7Days();
      final today = summary.days.last;

      // At least 2 rounds of pendulum signals + clip consumption
      expect(today.grandTotal, greaterThanOrEqualTo(2));
      expect(summary.clipConsumptionSecondsToday, 3600);
    });

    test('clip over limit after 2 hours of shorts', () async {
      final auditStore = AuditStore();
      final pipeline = TransurfingPipeline(auditStore: auditStore);

      await pipeline.analyzeAsync('刷了 2 小時 shorts');

      final summary = auditStore.getAuditLast7Days();
      expect(summary.clipOverLimit, true);
    });
  });

  // === 7. PendulumAuditChart Widget ===

  group('PendulumAuditChart Widget', () {
    testWidgets('renders empty state when no data', (tester) async {
      const summary = PendulumAuditSummary(days: []);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PendulumAuditChart(summary: summary),
          ),
        ),
      );

      expect(find.text('過去 7 天無擺錘紀錄'), findsOneWidget);
    });

    testWidgets('renders chart when data exists', (tester) async {
      final store = AuditStore();
      store.recordPendulums([
        _signal(PendulumSignalType.urgency),
        _signal(PendulumSignalType.fear),
      ]);
      final summary = store.getAuditLast7Days();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PendulumAuditChart(summary: summary),
            ),
          ),
        ),
      );

      // Should have a CustomPaint (the bar chart)
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      // Should have legend items
      expect(find.textContaining('急迫'), findsOneWidget);
    });

    testWidgets('renders clip consumption bar when seconds > 0', (tester) async {
      final store = AuditStore();
      store.addClipConsumptionSeconds(3600);
      final summary = store.getAuditLast7Days();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PendulumAuditChart(summary: summary),
            ),
          ),
        ),
      );

      expect(find.textContaining('今日短影音消費'), findsOneWidget);
      expect(find.textContaining('超過 60 分鐘警示'), findsOneWidget);
    });
  });

  // === 8. DailyPendulumAudit model ===

  group('DailyPendulumAudit model', () {
    test('totalCount sums rule + ai', () {
      const audit = DailyPendulumAudit(
        dateKey: '2026-07-04',
        ruleCounts: {'urgency': 2},
        aiCounts: {'urgency': 3, 'fear': 1},
      );

      expect(audit.totalCount(PendulumSignalType.urgency), 5);
      expect(audit.totalCount(PendulumSignalType.fear), 1);
      expect(audit.totalCount(PendulumSignalType.comparison), 0);
    });

    test('grandTotal sums all types', () {
      const audit = DailyPendulumAudit(
        dateKey: '2026-07-04',
        ruleCounts: {'urgency': 2, 'fear': 1},
        aiCounts: {'urgency': 3},
      );

      expect(audit.grandTotal, 6);
    });

    test('empty audit has zero totals', () {
      const audit = DailyPendulumAudit(dateKey: '2026-07-04');

      expect(audit.grandTotal, 0);
      for (final type in PendulumSignalType.values) {
        expect(audit.totalCount(type), 0);
      }
    });
  });

  // === 9. PendulumAuditSummary ===

  group('PendulumAuditSummary', () {
    test('totalForType aggregates across 7 days', () {
      final days = List.generate(7, (i) => DailyPendulumAudit(
        dateKey: '2026-07-0${i + 1}',
        ruleCounts: {'urgency': i + 1},
      ));

      final summary = PendulumAuditSummary(days: days);

      // 1+2+3+4+5+6+7 = 28
      expect(summary.totalForType(PendulumSignalType.urgency), 28);
      expect(summary.grandTotal, 28);
    });

    test('clipOverLimit is true when seconds >= 3600', () {
      const summary = PendulumAuditSummary(
        days: [],
        clipConsumptionSecondsToday: 3600,
      );
      expect(summary.clipOverLimit, true);
    });

    test('clipOverLimit is false when seconds < 3600', () {
      const summary = PendulumAuditSummary(
        days: [],
        clipConsumptionSecondsToday: 3599,
      );
      expect(summary.clipOverLimit, false);
    });
  });
}
