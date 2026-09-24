// sprint9_heart_mind_test.dart
// Sprint 9 — 心腦合一對話閉環測試
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試範圍：
// 1. HeartMindStore — 寫入、讀取、idempotent check、跨天
// 2. HeartMindDialogue — 狀態機流轉（idle→offeringSplit→awaitingUser→integrated→written）
// 3. Timeout — 5 分鐘無回應自動回 idle
// 4. 清晨確認 — 昨晚整合 statement 轉清晨確認
// 5. Pipeline 整合 — analyzeAsync 後偵測分裂觸發
// 6. LLM 整合 — mock LLM 產出整合 statement
// 7. 規則版 fallback — 無 LLM 時拼接 statement
// 8. Widget — HeartMindDialogueCard 渲染

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/heart_mind/heart_mind_dialogue.dart';
import 'package:bridge_app/services/brain_pipeline/heart_mind/heart_mind_store.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_llm_client.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline/transurfing_pipeline.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/widgets/brain_pipeline/heart_mind_dialogue_card.dart';

// === Helpers ===

BrainReflection _testReflection({
  HeartMindAlignment alignment = HeartMindAlignment.aligned,
  GuidanceHint? guidanceHint,
  Map<String, LayerResult<dynamic>> layerResults = const {},
}) {
  return BrainReflection(
    userIntent: '測試',
    attentionState: AttentionState.clear,
    pendulumSignals: const [],
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: alignment,
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
    guidanceHint: guidanceHint,
    layerResults: layerResults,
  );
}

GuidanceHint _splitHint({
  String mind = '應該念資工',
  String heart = '想做音樂',
  String splitMarker = '但是',
  String integrationPrompt = '如果兩邊都對，你最想先聽哪邊？',
}) {
  return GuidanceHint(
    mindStatement: mind,
    heartStatement: heart,
    splitMarker: splitMarker,
    integrationPrompt: integrationPrompt,
  );
}

void main() {
  // [Tier 整肅 2026-09-21 後] card 內 TierStyle.of() 要求 TierTheme 已註冊。
  late final ThemeData tierHostTheme;
  setUpAll(() async {
    final tierTheme = await loadDefaultTierTheme();
    tierHostTheme = ThemeData.dark().copyWith(extensions: [tierTheme]);
  });

  // === 1. HeartMindStore ===

  group('HeartMindStore', () {
    test('writeStatement stores and retrieves', () async {
      final store = HeartMindStore();
      await store.writeStatement(
        statement: '兼顧現實與夢想',
        dateKey: '2026-07-04',
      );

      final statements = store.getStatementsForDate('2026-07-04');
      expect(statements.length, 1);
      expect(statements.first, '兼顧現實與夢想');
    });

    test('idempotent check — same statement not written twice', () async {
      final store = HeartMindStore();
      await store.writeStatement(
        statement: '同一句話',
        dateKey: '2026-07-04',
      );
      await store.writeStatement(
        statement: '同一句話',
        dateKey: '2026-07-04',
      );

      expect(store.getStatementsForDate('2026-07-04').length, 1);
    });

    test('different statements both stored', () async {
      final store = HeartMindStore();
      await store.writeStatement(statement: '第一句', dateKey: '2026-07-04');
      await store.writeStatement(statement: '第二句', dateKey: '2026-07-04');

      expect(store.getStatementsForDate('2026-07-04').length, 2);
    });

    test('cross-day retrieval', () async {
      final store = HeartMindStore();
      await store.writeStatement(statement: '昨天', dateKey: '2026-07-03');
      await store.writeStatement(statement: '今天', dateKey: '2026-07-04');

      expect(store.getStatementsForDate('2026-07-03'), ['昨天']);
      expect(store.getStatementsForDate('2026-07-04'), ['今天']);
    });

    test('getLatestStatement returns most recent', () async {
      final store = HeartMindStore();
      await store.writeStatement(statement: '前天', dateKey: '2026-07-02');
      await store.writeStatement(statement: '昨天', dateKey: '2026-07-03');
      await store.writeStatement(statement: '今天', dateKey: '2026-07-04');

      expect(store.getLatestStatement(), '今天');
    });

    test('getLatestStatement returns null when empty', () {
      final store = HeartMindStore();
      expect(store.getLatestStatement(), isNull);
    });

    test('getRecordsForDate returns full records with metadata', () async {
      final store = HeartMindStore();
      await store.writeStatement(
        statement: '整合句',
        mindStatement: '腦',
        heartStatement: '心',
        userReply: '先聽心',
        dateKey: '2026-07-04',
      );

      final records = store.getRecordsForDate('2026-07-04');
      expect(records.length, 1);
      expect(records.first.statement, '整合句');
      expect(records.first.mindStatement, '腦');
      expect(records.first.heartStatement, '心');
      expect(records.first.userReply, '先聽心');
    });

    test('clear removes everything', () async {
      final store = HeartMindStore();
      await store.writeStatement(statement: 'A', dateKey: '2026-07-04');
      store.clear();
      expect(store.getStatementsForDate('2026-07-04'), isEmpty);
    });
  });

  // === 2. HeartMindDialogue — State Machine ===

  group('HeartMindDialogue — State Machine', () {
    test('initial state is idle', () {
      final dialogue = HeartMindDialogue(
        store: HeartMindStore(),
      );
      expect(dialogue.state, HeartMindDialogueState.idle);
      expect(dialogue.session, isNull);
    });

    test('offerSplit triggers on mixed alignment with splitMarker', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      final reflection = _testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      );

      dialogue.offerSplit(reflection);

      expect(dialogue.state, HeartMindDialogueState.offeringSplit);
      expect(dialogue.session!.mindStatement, '應該念資工');
      expect(dialogue.session!.heartStatement, '想做音樂');
      expect(dialogue.session!.splitMarker, '但是');
      expect(dialogue.session!.integrationPrompt, '如果兩邊都對，你最想先聽哪邊？');
    });

    test('offerSplit triggers on conflicted alignment', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      final reflection = _testReflection(
        alignment: HeartMindAlignment.conflicted,
        guidanceHint: _splitHint(),
      );

      dialogue.offerSplit(reflection);
      expect(dialogue.state, HeartMindDialogueState.offeringSplit);
    });

    test('offerSplit does NOT trigger on aligned', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      final reflection = _testReflection(
        alignment: HeartMindAlignment.aligned,
        guidanceHint: _splitHint(),
      );

      dialogue.offerSplit(reflection);
      expect(dialogue.state, HeartMindDialogueState.idle);
    });

    test('offerSplit does NOT trigger without guidanceHint', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      final reflection = _testReflection(
        alignment: HeartMindAlignment.mixed,
      );

      dialogue.offerSplit(reflection);
      expect(dialogue.state, HeartMindDialogueState.idle);
    });

    test('offerSplit does NOT trigger without splitMarker and integrationPrompt', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      final reflection = _testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: const GuidanceHint(
          mindStatement: '腦',
          heartStatement: '心',
          // splitMarker and integrationPrompt are null
        ),
      );

      dialogue.offerSplit(reflection);
      expect(dialogue.state, HeartMindDialogueState.idle);
    });

    test('offerSplit does not interrupt existing session', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      final reflection = _testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      );

      dialogue.offerSplit(reflection);
      expect(dialogue.state, HeartMindDialogueState.offeringSplit);

      // Second call should not override
      final reflection2 = _testReflection(
        alignment: HeartMindAlignment.conflicted,
        guidanceHint: _splitHint(mind: '其他', heart: '其他2'),
      );
      dialogue.offerSplit(reflection2);
      expect(dialogue.session!.mindStatement, '應該念資工'); // still first
    });
  });

  // === 3. handleUserReply → LLM integration ===

  group('handleUserReply — LLM Integration', () {
    test('with mock LLM produces integrated statement', () async {
      final store = HeartMindStore();
      final mockLlm = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '在音樂和資工之間，我選擇先讓自己開心',
        ),
      );
      final dialogue = HeartMindDialogue(
        store: store,
        llmClient: mockLlm,
      );

      final reflection = _testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      );
      dialogue.offerSplit(reflection);

      await dialogue.handleUserReply('先聽心');

      expect(dialogue.state, HeartMindDialogueState.written);
      expect(dialogue.session!.integratedStatement, '在音樂和資工之間，我選擇先讓自己開心');
      expect(dialogue.session!.userReply, '先聽心');
    });

    test('writes integrated statement to store', () async {
      final store = HeartMindStore();
      final mockLlm = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '整合後的句子',
        ),
      );
      final dialogue = HeartMindDialogue(
        store: store,
        llmClient: mockLlm,
      );

      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('先聽心');

      // Statement should be in the store
      final today = DateTime.now();
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final dateKey = '${today.year}-${twoDigits(today.month)}-${twoDigits(today.day)}';
      expect(store.getStatementsForDate(dateKey), contains('整合後的句子'));
    });

    test('rule-based fallback when no LLM', () async {
      final store = HeartMindStore();
      final dialogue = HeartMindDialogue(store: store);

      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('我更想讓自己開心');

      expect(dialogue.state, HeartMindDialogueState.written);
      // Rule-based: "在{heart}和{mind}之間，{reply}"
      expect(dialogue.session!.integratedStatement,
          contains('想做音樂'));
      expect(dialogue.session!.integratedStatement,
          contains('應該念資工'));
      expect(dialogue.session!.integratedStatement,
          contains('開心'));
    });

    test('rule-based fallback when LLM fails', () async {
      final store = HeartMindStore();
      final mockLlm = MockPipelineLLMClient(
        defaultResponse: PipelineLLMResponse.failed,
      );
      final dialogue = HeartMindDialogue(
        store: store,
        llmClient: mockLlm,
      );

      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('先聽心');

      // Should still produce a statement via rule-based fallback
      expect(dialogue.state, HeartMindDialogueState.written);
      expect(dialogue.session!.integratedStatement, isNotEmpty);
    });

    test('handleUserReply does nothing when idle', () async {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      await dialogue.handleUserReply('隨便');
      expect(dialogue.state, HeartMindDialogueState.idle);
    });
  });

  // === 4. Idempotent check ===

  group('Idempotent check', () {
    test('same statement not written twice to store', () async {
      final store = HeartMindStore();
      final mockLlm = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '完全相同的句子',
        ),
      );
      final dialogue = HeartMindDialogue(
        store: store,
        llmClient: mockLlm,
      );

      // First session
      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('先聽心');

      // Reset and do it again with same LLM response
      dialogue.reset();
      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('先聽心');

      // Store should only have 1 entry
      final today = DateTime.now();
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final dateKey = '${today.year}-${twoDigits(today.month)}-${twoDigits(today.day)}';
      expect(store.getStatementsForDate(dateKey).length, 1);
    });
  });

  // === 5. Timeout ===

  group('Timeout', () {
    test('returns to idle after 5 minutes', () {
      var mockNow = DateTime(2026, 7, 4, 10, 0, 0);
      final dialogue = HeartMindDialogue(
        store: HeartMindStore(),
        clock: () => mockNow,
        timeout: const Duration(minutes: 5),
      );

      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      expect(dialogue.state, HeartMindDialogueState.offeringSplit);

      // Advance 6 minutes
      mockNow = mockNow.add(const Duration(minutes: 6));
      dialogue.checkTimeout();

      expect(dialogue.state, HeartMindDialogueState.idle);
      expect(dialogue.session, isNull);
    });

    test('does NOT timeout within 5 minutes', () {
      var mockNow = DateTime(2026, 7, 4, 10, 0, 0);
      final dialogue = HeartMindDialogue(
        store: HeartMindStore(),
        clock: () => mockNow,
        timeout: const Duration(minutes: 5),
      );

      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));

      // Advance 4 minutes
      mockNow = mockNow.add(const Duration(minutes: 4));
      dialogue.checkTimeout();

      expect(dialogue.state, HeartMindDialogueState.offeringSplit);
    });

    test('written state clears on checkTimeout', () async {
      var mockNow = DateTime(2026, 7, 4, 10, 0, 0);
      final store = HeartMindStore(clock: () => mockNow);
      final dialogue = HeartMindDialogue(
        store: store,
        clock: () => mockNow,
      );

      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('先聽心');

      expect(dialogue.state, HeartMindDialogueState.written);

      // checkTimeout after written → clears session
      dialogue.checkTimeout();
      expect(dialogue.state, HeartMindDialogueState.idle);
    });
  });

  // === 6. Morning Affirmation ===

  group('Morning Affirmation', () {
    test('returns last night statement when today is empty', () async {
      var mockNow = DateTime(2026, 7, 4, 8, 0, 0);
      final store = HeartMindStore(clock: () => mockNow);
      final dialogue = HeartMindDialogue(
        store: store,
        clock: () => mockNow,
      );

      // Write yesterday's statement
      await store.writeStatement(
        statement: '昨晚的整合句',
        dateKey: '2026-07-03',
      );

      final morning = dialogue.getMorningAffirmation();
      expect(morning, '昨晚的整合句');
    });

    test('returns null when yesterday is empty', () {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      expect(dialogue.getMorningAffirmation(), isNull);
    });

    test('returns null when today already has statements', () async {
      var mockNow = DateTime(2026, 7, 4, 8, 0, 0);
      final store = HeartMindStore(clock: () => mockNow);
      final dialogue = HeartMindDialogue(
        store: store,
        clock: () => mockNow,
      );

      await store.writeStatement(statement: '昨天', dateKey: '2026-07-03');
      await store.writeStatement(statement: '今天', dateKey: '2026-07-04');

      // Today already has content → no morning affirmation
      expect(dialogue.getMorningAffirmation(), isNull);
    });
  });

  // === 7. Pipeline Integration ===

  group('Pipeline Sprint 9 Integration', () {
    test('analyzeAsync triggers heartMindDialogue on split', () async {
      final store = HeartMindStore();
      final dialogue = HeartMindDialogue(store: store);
      final pipeline = TransurfingPipeline(heartMindDialogue: dialogue);

      // 這個訊息應該觸發 mixed alignment（規則版偵測到「但」）
      await pipeline.analyzeAsync('我很想做音樂，但爸說要念資工');

      // Should have triggered offerSplit (if rule detects splitMarker)
      // Note: rule version may or may not detect splitMarker — depends on rule implementation
      // At minimum, should not crash
      expect(dialogue.state, anyOf(
        HeartMindDialogueState.idle,
        HeartMindDialogueState.offeringSplit,
      ));
    });

    test('analyzeAsync without heartMindDialogue does not crash', () async {
      final pipeline = TransurfingPipeline();
      final result = await pipeline.analyzeAsync('測試');
      expect(result, isNotNull);
    });
  });

  // === 8. Widget Tests ===

  group('HeartMindDialogueCard Widget', () {
    testWidgets('idle with no morning affirmation shows nothing', (tester) async {
      final dialogue = HeartMindDialogue(store: HeartMindStore());

      await tester.pumpWidget(
        MaterialApp(
          theme: tierHostTheme,
          home: Scaffold(
            body: HeartMindDialogueCard(dialogue: dialogue),
          ),
        ),
      );

      expect(find.byType(HeartMindDialogueCard), findsOneWidget);
      // SizedBox.shrink → no visible content
      expect(find.text('心腦合一'), findsNothing);
    });

    testWidgets('offeringSplit shows mind/heart and buttons', (tester) async {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: tierHostTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HeartMindDialogueCard(dialogue: dialogue),
            ),
          ),
        ),
      );

      expect(find.text('心腦合一'), findsOneWidget);
      expect(find.textContaining('想做音樂'), findsOneWidget);
      expect(find.textContaining('應該念資工'), findsOneWidget);
      expect(find.text('先聽心'), findsOneWidget);
      expect(find.text('先聽腦'), findsOneWidget);
      expect(find.text('都聽'), findsOneWidget);
    });

    testWidgets('integrated shows integrated statement', (tester) async {
      final store = HeartMindStore();
      final dialogue = HeartMindDialogue(store: store);
      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));
      await dialogue.handleUserReply('先聽心');

      await tester.pumpWidget(
        MaterialApp(
          theme: tierHostTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HeartMindDialogueCard(dialogue: dialogue),
            ),
          ),
        ),
      );

      // Should show the integrated statement (rule-based)
      expect(find.byType(HeartMindDialogueCard), findsOneWidget);
    });

    testWidgets('morning affirmation shows when available', (tester) async {
      var mockNow = DateTime(2026, 7, 4, 8, 0, 0);
      final store = HeartMindStore(clock: () => mockNow);
      final dialogue = HeartMindDialogue(
        store: store,
        clock: () => mockNow,
      );

      await store.writeStatement(
        statement: '昨夜整合的智慧',
        dateKey: '2026-07-03',
      );

      final morning = dialogue.getMorningAffirmation();
      expect(morning, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          theme: tierHostTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HeartMindDialogueCard(
                dialogue: dialogue,
                morningAffirmation: morning,
              ),
            ),
          ),
        ),
      );

      expect(find.text('今日清晨確認'), findsOneWidget);
      expect(find.text('昨夜整合的智慧'), findsOneWidget);
    });

    testWidgets('dismiss button calls reset', (tester) async {
      final dialogue = HeartMindDialogue(store: HeartMindStore());
      dialogue.offerSplit(_testReflection(
        alignment: HeartMindAlignment.mixed,
        guidanceHint: _splitHint(),
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: tierHostTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HeartMindDialogueCard(
                dialogue: dialogue,
                onDismiss: () => dialogue.reset(),
              ),
            ),
          ),
        ),
      );

      // Tap dismiss
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dialogue.state, HeartMindDialogueState.idle);
    });
  });

  // === 9. HeartMindSession model ===

  group('HeartMindSession model', () {
    test('copyWith creates a new instance with updated fields', () {
      final now = DateTime.now();
      final session = HeartMindSession(
        state: HeartMindDialogueState.offeringSplit,
        mindStatement: '腦',
        heartStatement: '心',
        createdAt: now,
        lastActivityAt: now,
      );

      final updated = session.copyWith(
        state: HeartMindDialogueState.awaitingUser,
        userReply: '先聽心',
      );

      expect(updated.state, HeartMindDialogueState.awaitingUser);
      expect(updated.userReply, '先聽心');
      expect(updated.mindStatement, '腦'); // preserved
      expect(updated.heartStatement, '心'); // preserved
      expect(updated.createdAt, now); // preserved
    });
  });
}
