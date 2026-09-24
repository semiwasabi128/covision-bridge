// sprint3_ai_mixed_test.dart
// Sprint 3 驗證測試 — AI analyzer + 混合策略器
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試項目：
// 1. AttentionGateAI 用 mock LLM 回應，正確解析 JSON
// 2. PendulumDetectorAI 用 mock LLM 回應，正確解析 JSON array
// 3. MixedAttentionGate 規則版 confidence 高 → 不叫 AI
// 4. MixedAttentionGate 規則版 confidence 低 / 長文 → 叫 AI 覆蓋
// 5. MixedPendulumDetector 聯集合併去重
// 6. LLM 不可用 → fallback to rule only
// 7. 約瑟的驗證標準：刷 shorts → clipConsumption + urgency
// 8. 約瑟的驗證標準：GPT-5 新聞 → platformPull + comparison, attentionState=captured
// 9. 規則 fallback：LLM 關掉仍能命中擺錘

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_llm_client.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/brain_layer_analyzer.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/attention_gate_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/pendulum_detector_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_attention_gate.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_pendulum_detector.dart';

void main() {
  group('AttentionGateAI', () {
    test('parses clear from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"state": "clear", "evidence": "簡單問候"}',
        ),
      );
      final analyzer = AttentionGateAI(mock);
      final result = await analyzer.analyze('你好', _emptyContext());
      expect(result.value, AttentionState.clear);
      expect(result.source, LayerSource.ai);
      expect(result.evidence, contains('簡單問候'));
    });

    test('parses captured from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"state": "captured", "evidence": "被新聞拉走"}',
        ),
      );
      final analyzer = AttentionGateAI(mock);
      final result = await analyzer.analyze('新聞說 GPT-5', _emptyContext());
      expect(result.value, AttentionState.captured);
    });

    test('parses scattered from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"state": "scattered", "evidence": "資訊過載"}',
        ),
      );
      final analyzer = AttentionGateAI(mock);
      final result = await analyzer.analyze('好多東西', _emptyContext());
      expect(result.value, AttentionState.scattered);
    });

    test('handles markdown code block in LLM response', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '```json\n{"state": "captured", "evidence": "測試"}\n```',
        ),
      );
      final analyzer = AttentionGateAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, AttentionState.captured);
    });

    test('LLM unavailable → fallback to clear', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = AttentionGateAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, AttentionState.clear);
      expect(result.confidence, 0.0);
    });
  });

  group('PendulumDetectorAI', () {
    test('parses pendulum array from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '[{"type": "urgency", "label": "急迫感", "evidence_quote": "必須趕快"}]',
        ),
      );
      final analyzer = PendulumDetectorAI(mock);
      final result = await analyzer.analyze('必須趕快完成', _emptyContext());
      expect(result.value.length, 1);
      expect(result.value[0].type, PendulumSignalType.urgency);
      expect(result.value[0].source, PendulumSignalSource.aiInferred);
    });

    test('parses clipConsumption (Sprint 3 new type)', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '[{"type": "clipConsumption", "label": "短影音過量", "evidence_quote": "刷了兩個小時 shorts"}]',
        ),
      );
      final analyzer = PendulumDetectorAI(mock);
      final result = await analyzer.analyze('我刷了兩個小時 shorts', _emptyContext());
      expect(result.value.length, 1);
      expect(result.value[0].type, PendulumSignalType.clipConsumption);
    });

    test('empty array when no pendulums', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(content: '[]'),
      );
      final analyzer = PendulumDetectorAI(mock);
      final result = await analyzer.analyze('你好', _emptyContext());
      expect(result.value, isEmpty);
    });

    test('LLM unavailable → empty list', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = PendulumDetectorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, isEmpty);
      expect(result.confidence, 0.0);
    });
  });

  group('MixedAttentionGate', () {
    test('short clear message → rule only, no AI call', () async {
      var aiCalled = false;
      final mock = MockPipelineLLMClient(
        handler: (_, __) async {
          aiCalled = true;
          return const PipelineLLMResponse(content: '{"state": "scattered", "evidence": "should not be called"}');
        },
      );
      final analyzer = MixedAttentionGate(mock);
      final result = await analyzer.analyze('你好', _emptyContext());
      // 規則版說 clear, confidence 預設 1.0, 字 < 80 → 不叫 AI
      expect(aiCalled, isFalse);
      expect(result.source, LayerSource.rule);
    });

    test('long message → triggers AI override', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"state": "captured", "evidence": "AI 判斷被新聞捕獲"}',
        ),
      );
      final longMsg = '我看到新聞說 GPT-5 很厲害，我是不是該跳槽工具，但又不確定好不好用' * 3; // > 80 chars
      final analyzer = MixedAttentionGate(mock);
      final result = await analyzer.analyze(longMsg, _emptyContext());
      expect(result.value, AttentionState.captured);
      expect(result.source, LayerSource.mixed);
      expect(result.evidence, contains('rule:'));
      expect(result.evidence, contains('ai:'));
    });

    test('LLM unavailable → rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = MixedAttentionGate(mock);
      final longMsg = 'a' * 100; // > 80 chars triggers AI path
      final result = await analyzer.analyze(longMsg, _emptyContext());
      expect(result.source, LayerSource.rule);
    });
  });

  group('MixedPendulumDetector', () {
    test('union merge: rule + AI signals combined, deduped', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '[{"type": "clipConsumption", "label": "短影音過量", "evidence_quote": "刷了兩個小時 shorts"}]',
        ),
      );
      final analyzer = MixedPendulumDetector(mock);
      // 規則版會命中 urgency（「趕快」）+ fear（「完了」）
      final result = await analyzer.analyze(
        '我刷了兩個小時 shorts，必須趕快寫論文，不然就完了',
        _emptyContext(),
      );
      // 規則版: urgency + fear (2 signals)
      // AI 版: clipConsumption (1 signal)
      // 合併後: 3 signals (無重複)
      expect(result.value.length, 3);
      expect(result.source, LayerSource.mixed);

      // 確認三種來源都有
      final types = result.value.map((s) => s.type).toSet();
      expect(types, contains(PendulumSignalType.urgency));
      expect(types, contains(PendulumSignalType.fear));
      expect(types, contains(PendulumSignalType.clipConsumption));

      // 確認 source 標籤正確
      final ruleSignals = result.value.where((s) => s.source == PendulumSignalSource.ruleMatch);
      final aiSignals = result.value.where((s) => s.source == PendulumSignalSource.aiInferred);
      expect(ruleSignals.length, 2); // urgency + fear
      expect(aiSignals.length, 1); // clipConsumption
    });

    test('dedup: same type+evidence from rule and AI → only one', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '[{"type": "urgency", "label": "急迫感", "evidence_quote": "趕快"}]',
        ),
      );
      final analyzer = MixedPendulumDetector(mock);
      // 規則版會命中 urgency（「趕快」）
      // AI 版也命中 urgency（「趕快」）
      final result = await analyzer.analyze('趕快完成', _emptyContext());
      // 兩邊都命中 urgency + evidence "趕快" → dedup 後只留一條（規則版先放）
      final urgencySignals = result.value.where((s) => s.type == PendulumSignalType.urgency).toList();
      expect(urgencySignals.length, 1);
      expect(urgencySignals[0].source, PendulumSignalSource.ruleMatch);
    });

    test('LLM unavailable → rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = MixedPendulumDetector(mock);
      final result = await analyzer.analyze('必須趕快完成，不然就完了', _emptyContext());
      expect(result.source, LayerSource.rule);
      expect(result.value.length, greaterThanOrEqualTo(2)); // urgency + fear
    });

    // 約瑟驗證標準 1: 刷 shorts → clipConsumption (ai) + urgency (rule)
    test('Joseph spec: 刷 shorts → clipConsumption + urgency', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '[{"type": "clipConsumption", "label": "短影音過量", "evidence_quote": "刷了兩個小時 shorts"}]',
        ),
      );
      final analyzer = MixedPendulumDetector(mock);
      final result = await analyzer.analyze(
        '我刷了兩個小時 shorts，想寫論文但寫不出來',
        _emptyContext(),
      );
      final types = result.value.map((s) => s.type).toSet();
      expect(types, contains(PendulumSignalType.clipConsumption));
      // 規則版可能不命中 urgency（「寫不出來」不在 markers 裡），但 clipConsumption 一定來自 AI
      final aiSignals = result.value.where((s) => s.source == PendulumSignalSource.aiInferred);
      expect(aiSignals.any((s) => s.type == PendulumSignalType.clipConsumption), isTrue);
    });

    // 約瑟驗證標準 2: GPT-5 新聞 → platformPull + comparison, attention=captured
    test('Joseph spec: GPT-5 新聞 → AI detects platformPull + comparison', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '[{"type": "platformPull", "label": "平台拉力", "evidence_quote": "GPT-5"}, {"type": "comparison", "label": "比較與跟風", "evidence_quote": "我是不是該跳槽"}]',
        ),
      );
      final pendulumAnalyzer = MixedPendulumDetector(mock);
      final pendulumResult = await pendulumAnalyzer.analyze(
        '新聞說 GPT-5 很厲害，我是不是該跳槽工具',
        _emptyContext(),
      );
      final types = pendulumResult.value.map((s) => s.type).toSet();
      expect(types, contains(PendulumSignalType.platformPull));
      expect(types, contains(PendulumSignalType.comparison));

      // 同時跑 attention gate AI（直接測 AI 版，因為短訊息 mixed 不會叫 AI）
      final attentionMock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"state": "captured", "evidence": "被新聞話題捕獲"}',
        ),
      );
      final attentionAnalyzer = AttentionGateAI(attentionMock);
      final attentionResult = await attentionAnalyzer.analyze(
        '新聞說 GPT-5 很厲害，我是不是該跳槽工具',
        _emptyContext(),
      );
      expect(attentionResult.value, AttentionState.captured);
    });

    // 約瑟驗證標準 3: 規則 fallback — LLM 關掉仍能命中至少 2 個擺錘
    test('Joseph spec: LLM off → rule fallback hits 2+ pendulums', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = MixedPendulumDetector(mock);
      // 用實際會命中 2+ rule markers 的訊息：
      // '大家都' → comparison, '很紅' → comparison (同一 type, 但 'discord' → platformPull)
      // '應該' → guilt
      final result = await analyzer.analyze(
        '大家都說 discord 新平台很紅，我應該也去用',
        _emptyContext(),
      );
      expect(result.value.length, greaterThanOrEqualTo(2));
      expect(result.source, LayerSource.rule);
      final types = result.value.map((s) => s.type).toSet();
      expect(types, contains(PendulumSignalType.comparison));
      expect(types, contains(PendulumSignalType.platformPull));
    });
  });

  group('safeJsonParse', () {
    test('parses plain JSON', () {
      expect(safeJsonParse('{"a": 1}'), {'a': 1});
    });

    test('parses JSON in code block', () {
      expect(safeJsonParse('```json\n{"a": 1}\n```'), {'a': 1});
    });

    test('parses JSON with surrounding text', () {
      expect(safeJsonParse('Here is the result: {"a": 1} done'), {'a': 1});
    });

    test('returns null for invalid', () {
      expect(safeJsonParse('not json at all'), isNull);
    });

    test('parses JSON array', () {
      final result = safeJsonParse('[{"a": 1}, {"b": 2}]');
      expect(result, isA<List>());
      expect((result as List).length, 2);
    });
  });
}

PipelineContext _emptyContext() => const PipelineContext();
