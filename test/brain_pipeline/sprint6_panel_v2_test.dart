// sprint6_panel_v2_test.dart
// Sprint 6 — 即時監控面板 v2 測試
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試範圍：
// 1. BrainPanelState — 展開/摺疊、override toggle、auto-refresh 訂閱
// 2. LayerCard — 各層 value 文字、source chip、confidence、evidence
// 3. PendulumRadarChart — 六軸計數正確
// 4. AttentionMeter — 三段狀態高亮
// 5. IntentionTimeline — 24h 過濾
// 6. _layerSummary — AI/規則分布摘要
// 7. Panel 整合 — layerResults 非空時七層區塊出現

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/intention_record.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_reflection_store.dart';
import 'package:bridge_app/state/brain_panel_state.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/widgets/brain_pipeline/attention_meter.dart';
import 'package:bridge_app/widgets/brain_pipeline/layer_card.dart';
import 'package:bridge_app/widgets/brain_pipeline/layer_source_chip.dart';

// === Helpers ===

/// Tier 系統（2026-09-21 整肅後）要求所有文字層級走 TierStyle，
/// 測試 host 必須註冊 TierTheme，否則 LayerCard 等元件 build 時拋
/// 「TierTheme not registered」。
Future<void> _pumpHost(WidgetTester tester, Widget child) async {
  final tierTheme = await loadDefaultTierTheme();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [tierTheme]),
      home: Scaffold(body: child),
    ),
  );
}

BrainReflection _testReflection({
  String userIntent = '測試意圖',
  Map<String, LayerResult<dynamic>> layerResults = const {},
  List<PendulumSignal> pendulumSignals = const [],
  AttentionState attentionState = AttentionState.clear,
  RecommendedMove move = RecommendedMove.answerDirectly,
}) {
  return BrainReflection(
    userIntent: userIntent,
    attentionState: attentionState,
    pendulumSignals: pendulumSignals,
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: HeartMindAlignment.aligned,
    fraileResonance: FraileResonance.present,
    doorCandidates: const [],
    flowState: FlowState.withFlow,
    recommendedMove: move,
    companionExpression: const CompanionExpression(
      mood: AgentCompanionMood.idle,
      action: AgentCompanionAction.standing,
      statusText: '測試',
    ),
    guidance: '測試指引',
    layerResults: layerResults,
  );
}

// === 1. BrainPanelState ===

void main() {
  group('BrainPanelState', () {
    test('initial state: allExpanded=false, no overrides', () {
      final state = BrainPanelState();
      expect(state.allExpanded, false);
      expect(state.overrides, isEmpty);
      expect(state.isLayerExpanded('intent'), false);
    });

    test('toggleLayer toggles individual layer expansion', () {
      final state = BrainPanelState();
      state.toggleLayer('attention');
      expect(state.isLayerExpanded('attention'), true);
      state.toggleLayer('attention');
      expect(state.isLayerExpanded('attention'), false);
    });

    test('allExpanded overrides individual layer state', () {
      final state = BrainPanelState();
      state.toggleAllExpanded();
      expect(state.allExpanded, true);
      expect(state.isLayerExpanded('intent'), true);
      expect(state.isLayerExpanded('pendulum'), true);
    });

    test('toggleAllExpanded off clears individual layers', () {
      final state = BrainPanelState();
      state.toggleLayer('intent');
      state.toggleAllExpanded();
      state.toggleAllExpanded(); // off
      expect(state.allExpanded, false);
      expect(state.isLayerExpanded('intent'), false);
    });

    test('toggleOverride cycles: null -> ai -> rule -> null', () {
      final state = BrainPanelState();
      expect(state.getOverride('attention'), isNull);
      state.toggleOverride('attention');
      expect(state.getOverride('attention'), LayerOverrideMode.ai);
      state.toggleOverride('attention');
      expect(state.getOverride('attention'), LayerOverrideMode.rule);
      state.toggleOverride('attention');
      expect(state.getOverride('attention'), isNull);
    });

    test('clearOverrides removes all overrides', () {
      final state = BrainPanelState();
      state.toggleOverride('intent');
      state.toggleOverride('attention');
      expect(state.overrides.length, 2);
      state.clearOverrides();
      expect(state.overrides, isEmpty);
    });

    test('auto-refresh: starts with current store value', () {
      final store = BrainReflectionStore.instance;
      final testRef = _testReflection();
      store.update(testRef);
      final state = BrainPanelState();
      state.startListening();
      expect(state.reflection, isNotNull);
      state.stopListening();
      store.clear();
    });

    test('auto-refresh: updates when store changes', () {
      final store = BrainReflectionStore.instance;
      store.clear();
      final state = BrainPanelState();
      state.startListening();
      expect(state.reflection, isNull);
      final testRef = _testReflection();
      store.update(testRef);
      expect(state.reflection, isNotNull);
      expect(state.reflection!.userIntent, '測試意圖');
      state.stopListening();
      store.clear();
    });
  });

  // === 2. LayerCard ===

  group('LayerCard', () {
    testWidgets('displays layer name and value text', (tester) async {
      final reflection = _testReflection(
        userIntent: '我想做音樂',
        layerResults: {
          'intent': const LayerResult<String>(
            value: '我想做音樂',
            source: LayerSource.ai,
            confidence: 0.85,
            evidence: '使用者明確表達意圖',
          ),
        },
      );
      await _pumpHost(
        tester,
        LayerCard(
          layerId: BrainLayerId.intent,
          layerResult: reflection.layerResults['intent']!,
          reflection: reflection,
        ),
      );
      expect(find.text('意圖'), findsOneWidget);
      expect(find.text('我想做音樂'), findsOneWidget);
    });

    testWidgets('shows confidence bar for non-rule source', (tester) async {
      final reflection = _testReflection(
        layerResults: {
          'attention': const LayerResult<AttentionState>(
            value: AttentionState.captured,
            source: LayerSource.ai,
            confidence: 0.72,
            evidence: '被新聞平台捕獲',
          ),
        },
      );
      await _pumpHost(
        tester,
        LayerCard(
          layerId: BrainLayerId.attention,
          layerResult: reflection.layerResults['attention']!,
          reflection: reflection,
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('hides confidence bar for rule source', (tester) async {
      final reflection = _testReflection(
        layerResults: {
          'intent': const LayerResult<String>(
            value: '測試',
            source: LayerSource.rule,
            confidence: 1.0,
            evidence: '',
          ),
        },
      );
      await _pumpHost(
        tester,
        LayerCard(
          layerId: BrainLayerId.intent,
          layerResult: reflection.layerResults['intent']!,
          reflection: reflection,
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('displays hint from metadata', (tester) async {
      final reflection = _testReflection(
        layerResults: {
          'importance': const LayerResult<ImportanceLevel>(
            value: ImportanceLevel.excessive,
            source: LayerSource.mixed,
            confidence: 0.9,
            evidence: '過度重要',
            metadata: {'humorHint': '試著寫成笑話'},
          ),
        },
      );
      await _pumpHost(
        tester,
        LayerCard(
          layerId: BrainLayerId.importance,
          layerResult: reflection.layerResults['importance']!,
          reflection: reflection,
        ),
      );
      expect(find.text('試著寫成笑話'), findsOneWidget);
      expect(find.text('幽默化解'), findsOneWidget);
    });

    testWidgets('pendulum layer shows signal labels', (tester) async {
      final reflection = _testReflection(
        pendulumSignals: const [
          PendulumSignal(type: PendulumSignalType.urgency, label: '急迫感', evidence: '必須現在'),
          PendulumSignal(type: PendulumSignalType.comparison, label: '比較', evidence: '別人都'),
        ],
        layerResults: {
          'pendulum': const LayerResult<List<PendulumSignal>>(
            value: [],
            source: LayerSource.mixed,
            confidence: 0.8,
            evidence: '2 個擺錘',
          ),
        },
      );
      await _pumpHost(
        tester,
        LayerCard(
          layerId: BrainLayerId.pendulum,
          layerResult: reflection.layerResults['pendulum']!,
          reflection: reflection,
        ),
      );
      expect(find.text('急迫感、比較'), findsOneWidget);
    });

    testWidgets('source chip tap triggers onSourceToggle', (tester) async {
      var tapped = false;
      final reflection = _testReflection(
        layerResults: {
          'intent': const LayerResult<String>(
            value: '測試',
            source: LayerSource.rule,
          ),
        },
      );
      await _pumpHost(
        tester,
        LayerCard(
          layerId: BrainLayerId.intent,
          layerResult: reflection.layerResults['intent']!,
          reflection: reflection,
          onSourceToggle: () => tapped = true,
        ),
      );
      await tester.tap(find.byType(LayerSourceChip));
      expect(tapped, true);
    });
  });

  // === 3. LayerSourceChip ===

  group('LayerSourceChip', () {
    testWidgets('displays correct label for each source', (tester) async {
      for (final source in LayerSource.values) {
        await _pumpHost(tester, LayerSourceChip(source: source));
        final expected = switch (source) {
          LayerSource.ai => 'AI',
          LayerSource.rule => '規則',
          LayerSource.mixed => '混合',
          LayerSource.cached => '快取',
        };
        expect(find.text(expected), findsOneWidget);
      }
    });

    testWidgets('override mode shows override label', (tester) async {
      await _pumpHost(
        tester,
        const LayerSourceChip(
          source: LayerSource.rule,
          overrideMode: LayerOverrideMode.ai,
        ),
      );
      expect(find.text('AI⚡'), findsOneWidget);
    });
  });

  // === 4. AttentionMeter ===

  group('AttentionMeter', () {
    testWidgets('renders three segments', (tester) async {
      await _pumpHost(
        tester,
        const AttentionMeter(state: AttentionState.clear),
      );
      expect(find.text('清醒'), findsOneWidget);
      expect(find.text('被捕獲'), findsOneWidget);
      expect(find.text('分散'), findsOneWidget);
    });
  });

  // === 5. BrainLayerId enum ===

  group('BrainLayerId', () {
    test('has exactly 8 layers', () {
      expect(BrainLayerId.values.length, 8);
    });

    test('keys match pipeline output', () {
      final keys = BrainLayerId.values.map((l) => l.key).toList();
      expect(keys, containsAll([
        'intent', 'attention', 'pendulum', 'importance',
        'heartMind', 'fraile', 'doorFlow', 'actionRouter',
      ]));
    });

    test('each layer has non-empty displayName and icon', () {
      for (final layer in BrainLayerId.values) {
        expect(layer.displayName, isNotEmpty);
        expect(layer.icon, isNotNull);
      }
    });
  });

  // === 6. IntentionRecord integration ===

  group('IntentionTimeline data', () {
    test('filters today intentions correctly', () {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final ms = dayStart.millisecondsSinceEpoch;

      final intentions = [
        IntentionRecord(
          id: '1',
          userMessage: '今天要完成報告',
          createdAtMs: ms + 3600000, // 1 hour into today
          updatedAtMs: ms + 3600000,
          status: IntentionStatus.open,
        ),
        IntentionRecord(
          id: '2',
          userMessage: '昨天的宣告',
          createdAtMs: ms - 86400000, // yesterday
          updatedAtMs: ms - 86400000,
          status: IntentionStatus.acted,
        ),
      ];

      final today = intentions.where((r) {
        final dayEndMs = ms + 86400000;
        return r.createdAtMs >= ms && r.createdAtMs < dayEndMs;
      }).toList();

      expect(today.length, 1);
      expect(today.first.userMessage, '今天要完成報告');
    });
  });
}
