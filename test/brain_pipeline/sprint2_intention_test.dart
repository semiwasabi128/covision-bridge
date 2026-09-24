// sprint2_intention_test.dart
// Sprint 2 驗證測試 — IntentionRouter 狀態機 + ActionRouterAI + 混合策略 + 零回歸
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試項目：
// 1. IntentionRecord 建立與狀態轉換
// 2. IntentionRouter 偵測宣告觸發詞 → declareIntention + recordIntention
// 3. IntentionRouter 偵測確認觸發詞 → open → confirmed
// 4. IntentionRouter 偵測完成觸發詞 → confirmed → acted
// 5. IntentionRouter 無觸發詞 → 不覆寫 move
// 6. ActionRouterAI 用 mock LLM 回應，正確解析 declareIntention
// 7. ActionRouterAI LLM 失敗 → fallback to rule
// 8. MixedActionRouter 無觸發詞 → 回規則版（省 token）
// 9. MixedActionRouter 有觸發詞 + LLM 可用 → AI 覆蓋
// 10. MixedActionRouter LLM 不可用 → 回規則版
// 11. Pipeline LLM 關 → Layer 7 走規則版（零回歸）
// 12. RecommendedMove 新 enum 值存在且 switch 窮舉
// 13. 約瑟驗證標準：宣告 → 確認 → 完成三步閉環

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/intention_record.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/brain_container.dart';
import 'package:bridge_app/services/brain_pipeline/intention_router.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/brain_layer_analyzer.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_llm_client.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/action_router_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/action_router_rule.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_action_router.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline/transurfing_pipeline.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_result.dart';

/// 測試用 Mock BrainContainer — 不碰 BrainContainerService
class _MockBrainContainer implements BrainContainer {
  final List<Map<String, String>> records = [];

  @override
  Future<void> recordIntention({
    required String userMessage,
    String? contextSnapshot,
  }) async {
    records.add({
      'type': 'intention',
      'content': userMessage,
    });
  }

  @override
  Future<void> recordConfirmation({
    required String intentionId,
    String? userReply,
  }) async {
    records.add({
      'type': 'confirmation',
      'content': intentionId,
      'reply': userReply ?? '',
    });
  }

  @override
  Future<void> recordAction({
    required String intentionId,
    String? actionSummary,
  }) async {
    records.add({
      'type': 'action',
      'content': intentionId,
      'summary': actionSummary ?? '',
    });
  }

  @override
  Future<List<String>> searchRecent({
    required String query,
    int limit = 5,
  }) async {
    return records
        .where((r) => r['content']!.contains(query))
        .take(limit)
        .map((r) => r['content']!)
        .toList();
  }
}

PipelineContext _emptyContext() => const PipelineContext();

void main() {
  group('IntentionRecord', () {
    test('create sets status to open', () {
      final record = IntentionRecord.create(
        userMessage: '我要做完 Sprint 2',
        now: DateTime(2026, 7, 4, 10, 0),
      );
      expect(record.status, IntentionStatus.open);
      expect(record.isOpen, true);
      expect(record.userMessage, '我要做完 Sprint 2');
      expect(record.id, isNotEmpty);
    });

    test('confirm transitions to confirmed', () {
      final record = IntentionRecord.create(userMessage: 'test');
      final confirmed = record.confirm('確認');
      expect(confirmed.status, IntentionStatus.confirmed);
      expect(confirmed.isConfirmed, true);
      expect(confirmed.confirmationReply, '確認');
    });

    test('markActed transitions to acted', () {
      final record = IntentionRecord.create(userMessage: 'test');
      final confirmed = record.confirm('確認');
      final acted = confirmed.markActed('做完了');
      expect(acted.status, IntentionStatus.acted);
      expect(acted.isActed, true);
      expect(acted.actionSummary, '做完了');
    });

    test('cancel transitions to cancelled', () {
      final record = IntentionRecord.create(userMessage: 'test');
      final cancelled = record.cancel();
      expect(cancelled.status, IntentionStatus.cancelled);
      expect(cancelled.isCancelled, true);
    });
  });

  group('IntentionRouter', () {
    late _MockBrainContainer mockContainer;
    late IntentionRouter router;

    setUp(() {
      mockContainer = _MockBrainContainer();
      router = IntentionRouter(mockContainer);
    });

    test('declare trigger creates IntentionRecord + writes to container', () async {
      final result = await router.handleMove(
        message: '我宣告：今晚八點把 Sprint 2 寫完',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(result.move, RecommendedMove.declareIntention);
      expect(result.newIntentionId, isNotNull);
      expect(router.intentions.length, 1);
      expect(router.intentions.first.isOpen, true);
      expect(mockContainer.records.length, 1);
      expect(mockContainer.records.first['type'], 'intention');
    });

    test('confirm trigger transitions open → confirmed', () async {
      // 先宣告
      await router.handleMove(
        message: '我要做完 Sprint 2',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(router.intentions.first.isOpen, true);

      // 確認
      final result = await router.handleMove(
        message: '確認，現在開始',
        pipelineMove: RecommendedMove.takeNextAction,
      );
      expect(router.intentions.first.isConfirmed, true);
      expect(result.affectedIntentionId, isNotNull);
      expect(result.statusMessage, contains('已確認'));
      expect(mockContainer.records.any((r) => r['type'] == 'confirmation'), true);
    });

    test('act trigger transitions confirmed → acted', () async {
      // 宣告 → 確認 → 完成
      await router.handleMove(
        message: '我要做完 Sprint 2',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      await router.handleMove(
        message: '確認',
        pipelineMove: RecommendedMove.takeNextAction,
      );
      expect(router.intentions.first.isConfirmed, true);

      final result = await router.handleMove(
        message: '做完了',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(router.intentions.first.isActed, true);
      expect(result.move, RecommendedMove.recordWaterAction);
      expect(result.statusMessage, contains('已記錄行動'));
      expect(mockContainer.records.any((r) => r['type'] == 'action'), true);
    });

    test('no trigger words → no override', () async {
      final result = await router.handleMove(
        message: '那個任務很重要',
        pipelineMove: RecommendedMove.takeNextAction,
      );
      expect(result.move, RecommendedMove.takeNextAction);
      expect(result.newIntentionId, isNull);
      expect(result.statusMessage, isNull);
      expect(router.intentions.length, 0);
    });

    test('confirm without open intention → no effect', () async {
      final result = await router.handleMove(
        message: '確認',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(result.move, RecommendedMove.answerDirectly);
      expect(result.affectedIntentionId, isNull);
    });

    test('full declare → confirm → act cycle', () async {
      // Step 1: 宣告
      final r1 = await router.handleMove(
        message: '我宣告：今晚八點把橋樑計畫 1C sprint 2 寫完',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(r1.move, RecommendedMove.declareIntention);
      expect(router.openIntentions.length, 1);

      // Step 2: 確認
      final r2 = await router.handleMove(
        message: '確認，八點開始',
        pipelineMove: RecommendedMove.takeNextAction,
      );
      expect(router.intentions.first.isConfirmed, true);

      // Step 3: 完成
      final r3 = await router.handleMove(
        message: '完成',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(r3.move, RecommendedMove.recordWaterAction);
      expect(router.intentions.first.isActed, true);
      expect(router.todayActions.length, 1);
    });

    test('multiple declare → multiple intentions', () async {
      await router.handleMove(
        message: '我要做 A',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      await router.handleMove(
        message: '我決定做 B',
        pipelineMove: RecommendedMove.answerDirectly,
      );
      expect(router.intentions.length, 2);
      expect(router.openIntentions.length, 2);
    });
  });

  group('ActionRouterAI', () {
    test('parses declareIntention from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"move": "declareIntention", "reason": "使用者明確宣告意圖", "intentionText": "今晚八點完成 Sprint 2"}',
        ),
      );
      final analyzer = ActionRouterAI(mock);
      final result = await analyzer.analyze(
        '我宣告：今晚八點完成 Sprint 2',
        _emptyContext(),
      );
      expect(result.value.move, RecommendedMove.declareIntention);
      expect(result.source, LayerSource.ai);
      expect(result.metadata['intentionText'], '今晚八點完成 Sprint 2');
    });

    test('parses recordWaterAction from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"move": "recordWaterAction", "reason": "使用者表示完成", "intentionText": ""}',
        ),
      );
      final analyzer = ActionRouterAI(mock);
      final result = await analyzer.analyze(
        '我做完了',
        _emptyContext(),
      );
      expect(result.value.move, RecommendedMove.recordWaterAction);
      expect(result.source, LayerSource.ai);
    });

    test('LLM failed → fallback to rule', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: PipelineLLMResponse.failed,
      );
      final analyzer = ActionRouterAI(mock);
      final result = await analyzer.analyze(
        '那個任務很重要',
        _emptyContext(),
      );
      expect(result.source, LayerSource.rule);
      expect(result.evidence, contains('ai_fallback'));
    });

    test('invalid JSON → fallback to rule', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: 'this is not json',
        ),
      );
      final analyzer = ActionRouterAI(mock);
      final result = await analyzer.analyze(
        '測試',
        _emptyContext(),
      );
      expect(result.source, LayerSource.rule);
    });
  });

  group('MixedActionRouter', () {
    test('no trigger words → rule only (save tokens)', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"move": "declareIntention", "reason": "should not be called", "intentionText": ""}',
        ),
      );
      final analyzer = MixedActionRouter(mock);
      final result = await analyzer.analyze(
        '那個任務很重要',
        _emptyContext(),
      );
      // Should NOT call LLM
      expect(result.source, LayerSource.rule);
      expect(result.value.move, isNot(RecommendedMove.declareIntention));
    });

    test('trigger word + LLM available → AI overrides', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"move": "declareIntention", "reason": "明確宣告", "intentionText": "完成 Sprint 2"}',
        ),
      );
      final analyzer = MixedActionRouter(mock);
      final result = await analyzer.analyze(
        '我宣告要完成 Sprint 2',
        _emptyContext(),
      );
      expect(result.value.move, RecommendedMove.declareIntention);
      expect(result.source, LayerSource.mixed);
      expect(result.metadata['intentionText'], '完成 Sprint 2');
    });

    test('trigger word + LLM unavailable → rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = MixedActionRouter(mock);
      final result = await analyzer.analyze(
        '我宣告要完成 Sprint 2',
        _emptyContext(),
      );
      expect(result.source, LayerSource.rule);
      expect(result.value.move, isNot(RecommendedMove.declareIntention));
    });

    test('trigger word + LLM returns non-declare move → keeps rule move', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"move": "answerDirectly", "reason": "not a declaration", "intentionText": ""}',
        ),
      );
      final analyzer = MixedActionRouter(mock);
      final result = await analyzer.analyze(
        '我宣告要完成 Sprint 2',
        _emptyContext(),
      );
      // AI said answerDirectly, but rule also said answerDirectly → keep rule
      expect(result.value.move, isNot(RecommendedMove.declareIntention));
    });
  });

  group('Pipeline integration (zero regression)', () {
    test('LLM off → Layer 7 walks rule (allRule)', () async {
      final pipeline = TransurfingPipeline(); // no llmClient
      final result = await pipeline.analyzeAsync('那個任務很重要');
      expect(result.source, PipelineSource.allRule);
      // move should be one of the original 6 (not declareIntention/recordWaterAction)
      expect(
        result.reflection.recommendedMove,
        isIn([
          RecommendedMove.answerDirectly,
          RecommendedMove.askClarifyingQuestion,
          RecommendedMove.reduceImportance,
          RecommendedMove.convertToOutput,
          RecommendedMove.takeNextAction,
          RecommendedMove.routeBridge,
        ]),
      );
    });

    test('LLM on + no trigger → Layer 7 walks rule (mixed but no AI call for L7)', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"attention_state": "clear", "evidence": "test"}',
        ),
      );
      final pipeline = TransurfingPipeline(llmClient: mock);
      final result = await pipeline.analyzeAsync('那個任務很重要');
      // Other layers use AI, but L7 shouldn't call AI (no trigger word)
      expect(result.source, PipelineSource.mixed);
    });
  });

  group('RecommendedMove enum', () {
    test('has 8 values (6 original + 2 new)', () {
      expect(RecommendedMove.values.length, 8);
    });

    test('declareIntention exists', () {
      expect(RecommendedMove.values.contains(RecommendedMove.declareIntention), true);
    });

    test('recordWaterAction exists', () {
      expect(RecommendedMove.values.contains(RecommendedMove.recordWaterAction), true);
    });
  });
}
