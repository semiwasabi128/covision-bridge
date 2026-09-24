// sprint4_ai_mixed_test.dart
// Sprint 4 驗證測試 — AI analyzer + 混合策略器 + GuidanceHint 收集
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試項目：
// 1. ImportanceCoordinatorAI 用 mock LLM 回應，正確解析 level + humorHint
// 2. HeartMindTunerAI 用 mock LLM 回應，正確解析 alignment + mindStatement/heartStatement/splitMarker/integrationPrompt
// 3. FraileTunerAI 用 mock LLM 回應，正確解析 resonance + fraileEvidence
// 4. MixedImportanceCoordinator 規則版先跑 → AI 覆蓋 → metadata 帶 humorHint
// 5. MixedHeartMindTuner 規則版先跑 → AI 覆蓋 → metadata 帶 hint
// 6. MixedFraileTuner 規則版先跑 → AI 覆蓋 → metadata 帶 fraileEvidence
// 7. LLM 不可用 → 全部 fallback to rule only
// 8. 約瑟的驗證標準：心腦衝突 → alignment=mixed, integrationPrompt 非空
// 9. 約瑟的驗證標準：過度重要 → level=excessive, humorHint 非空
// 10. Pipeline 完整跑：LLM 開 → guidanceHint 收集正確
// 11. Pipeline 完整跑：LLM 關 → guidanceHint 為 null（零回歸）
// 12. GuidanceHint.merge() 正確合併
// 13. GuidanceHint.hasAny 正確判斷

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_llm_client.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/brain_layer_analyzer.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/importance_coordinator_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/heart_mind_tuner_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/fraile_tuner_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_importance_coordinator.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_heart_mind_tuner.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_fraile_tuner.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline/transurfing_pipeline.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_result.dart';

void main() {
  group('ImportanceCoordinatorAI', () {
    test('parses excessive + humorHint from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"level": "excessive", "humor_hint": "試著把這件事寫成笑話給朋友聽", "evidence": "災難化心態"}',
        ),
      );
      final analyzer = ImportanceCoordinatorAI(mock);
      final result = await analyzer.analyze(
        '我必須現在完成這個，否則我會被看笑話',
        _emptyContext(),
      );
      expect(result.value, ImportanceLevel.excessive);
      expect(result.source, LayerSource.ai);
      expect(result.metadata['humorHint'], '試著把這件事寫成笑話給朋友聽');
    });

    test('parses balanced with empty humorHint', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"level": "balanced", "humor_hint": "", "evidence": "正常重視"}',
        ),
      );
      final analyzer = ImportanceCoordinatorAI(mock);
      final result = await analyzer.analyze('今天天氣不錯', _emptyContext());
      expect(result.value, ImportanceLevel.balanced);
      expect(result.metadata.containsKey('humorHint'), isFalse);
    });

    test('LLM unavailable → fallback to balanced', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = ImportanceCoordinatorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, ImportanceLevel.balanced);
      expect(result.confidence, 0.0);
    });

    test('handles markdown code block in LLM response', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '```json\n{"level": "elevated", "humor_hint": "深呼吸", "evidence": "有壓力"}\n```',
        ),
      );
      final analyzer = ImportanceCoordinatorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, ImportanceLevel.elevated);
    });
  });

  group('HeartMindTunerAI', () {
    test('parses mixed alignment with mind/heart/splitMarker/integrationPrompt',
        () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"alignment": "mixed", "mind_statement": "應該念資工", "heart_statement": "想做音樂", "split_marker": "但", "integration_prompt": "如果兩邊都成立，你想先讓誰聽到？"}',
        ),
      );
      final analyzer = HeartMindTunerAI(mock);
      final result = await analyzer.analyze(
        '我很想做音樂，但我爸說應該念資工',
        _emptyContext(),
      );
      expect(result.value, HeartMindAlignment.mixed);
      expect(result.metadata['mindStatement'], '應該念資工');
      expect(result.metadata['heartStatement'], '想做音樂');
      expect(result.metadata['splitMarker'], '但');
      expect(result.metadata['integrationPrompt'],
          '如果兩邊都成立，你想先讓誰聽到？');
    });

    test('parses conflicted alignment', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"alignment": "conflicted", "mind_statement": "要賺錢", "heart_statement": "想旅行", "split_marker": "可是", "integration_prompt": "兩邊都需要你，先聽哪邊？"}',
        ),
      );
      final analyzer = HeartMindTunerAI(mock);
      final result =
          await analyzer.analyze('想旅行可是要賺錢', _emptyContext());
      expect(result.value, HeartMindAlignment.conflicted);
    });

    test('parses aligned with empty statements', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"alignment": "aligned", "mind_statement": "", "heart_statement": "", "split_marker": "", "integration_prompt": ""}',
        ),
      );
      final analyzer = HeartMindTunerAI(mock);
      final result = await analyzer.analyze('今天好開心', _emptyContext());
      expect(result.value, HeartMindAlignment.aligned);
      expect(result.metadata.containsKey('mindStatement'), isFalse);
    });

    test('LLM unavailable → fallback to unknown', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = HeartMindTunerAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, HeartMindAlignment.unknown);
      expect(result.confidence, 0.0);
    });
  });

  group('FraileTunerAI', () {
    test('parses strong resonance with evidence', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"resonance": "strong", "evidence": "明確在做自己想做的事，有自己的風格"}',
        ),
      );
      final analyzer = FraileTunerAI(mock);
      final result =
          await analyzer.analyze('我喜歡我的創作風格', _emptyContext());
      expect(result.value, FraileResonance.strong);
      expect(result.metadata['fraileEvidence'],
          '明確在做自己想做的事，有自己的風格');
    });

    test('parses obscured resonance', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"resonance": "obscured", "evidence": "被比較和平台拉力蓋過"}',
        ),
      );
      final analyzer = FraileTunerAI(mock);
      final result =
          await analyzer.analyze('大家都買了我也要買', _emptyContext());
      expect(result.value, FraileResonance.obscured);
    });

    test('LLM unavailable → fallback to weak', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = FraileTunerAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());
      expect(result.value, FraileResonance.weak);
      expect(result.confidence, 0.0);
    });
  });

  group('MixedImportanceCoordinator', () {
    test('LLM available → AI overrides rule, metadata carries humorHint',
        () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"level": "excessive", "humor_hint": "放輕鬆", "evidence": "災難化"}',
        ),
      );
      final mixed = MixedImportanceCoordinator(mock);
      final result = await mixed.analyze(
        '我必須現在完成這個，否則我會被看笑話',
        _emptyContext(),
      );
      expect(result.source, LayerSource.mixed);
      expect(result.value, ImportanceLevel.excessive);
      expect(result.metadata['humorHint'], '放輕鬆');
      // evidence 同時包含 rule 和 ai
      expect(result.evidence, contains('rule:'));
      expect(result.evidence, contains('ai:'));
    });

    test('LLM unavailable → fallback to rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final mixed = MixedImportanceCoordinator(mock);
      final result = await mixed.analyze('必須完成', _emptyContext());
      expect(result.source, LayerSource.rule);
      expect(result.metadata['humorHint'], isNull);
    });
  });

  group('MixedHeartMindTuner', () {
    test('LLM available → AI overrides rule, metadata carries hints',
        () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"alignment": "mixed", "mind_statement": "應該念資工", "heart_statement": "想做音樂", "split_marker": "但", "integration_prompt": "先聽哪邊？"}',
        ),
      );
      final mixed = MixedHeartMindTuner(mock);
      final result = await mixed.analyze(
        '我很想做音樂，但我爸說應該念資工',
        _emptyContext(),
      );
      expect(result.source, LayerSource.mixed);
      expect(result.value, HeartMindAlignment.mixed);
      expect(result.metadata['integrationPrompt'], '先聽哪邊？');
    });

    test('LLM unavailable → fallback to rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final mixed = MixedHeartMindTuner(mock);
      final result = await mixed.analyze('想可是不要', _emptyContext());
      expect(result.source, LayerSource.rule);
      expect(result.metadata['integrationPrompt'], isNull);
    });
  });

  group('MixedFraileTuner', () {
    test('LLM available → AI overrides rule, metadata carries evidence',
        () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"resonance": "strong", "evidence": "做自己想做的事"}',
        ),
      );
      final mixed = MixedFraileTuner(mock);
      final result =
          await mixed.analyze('我喜歡創作', _emptyContext());
      expect(result.source, LayerSource.mixed);
      expect(result.value, FraileResonance.strong);
      expect(result.metadata['fraileEvidence'], '做自己想做的事');
    });

    test('LLM unavailable → fallback to rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final mixed = MixedFraileTuner(mock);
      final result = await mixed.analyze('自己', _emptyContext());
      expect(result.source, LayerSource.rule);
    });
  });

  group('GuidanceHint', () {
    test('hasAny returns false for all-null', () {
      const hint = GuidanceHint();
      expect(hint.hasAny, isFalse);
    });

    test('hasAny returns true when any field is non-null', () {
      const hint = GuidanceHint(humorHint: 'test');
      expect(hint.hasAny, isTrue);
    });

    test('merge combines non-null fields from both', () {
      const a = GuidanceHint(humorHint: '哈哈');
      const b = GuidanceHint(mindStatement: '心智', integrationPrompt: '引導');
      final merged = a.merge(b);
      expect(merged.humorHint, '哈哈');
      expect(merged.mindStatement, '心智');
      expect(merged.integrationPrompt, '引導');
    });

    test('merge prefers left side on conflict', () {
      const a = GuidanceHint(humorHint: 'left');
      const b = GuidanceHint(humorHint: 'right');
      final merged = a.merge(b);
      expect(merged.humorHint, 'left');
    });
  });

  group('Pipeline GuidanceHint collection', () {
    test('LLM on → guidanceHint collected from all 3 layers', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content:
              '{"level": "excessive", "humor_hint": "放鬆點", "evidence": "測試"}',
        ),
        handler: (systemPrompt, userPrompt) async {
          // 根據 prompt 內容決定回應
          if (systemPrompt.contains('重要性判斷器')) {
            return const PipelineLLMResponse(
              content:
                  '{"level": "excessive", "humor_hint": "試著笑一笑", "evidence": "災難化"}',
            );
          }
          if (systemPrompt.contains('心腦合一分析器')) {
            return const PipelineLLMResponse(
              content:
                  '{"alignment": "conflicted", "mind_statement": "應該工作", "heart_statement": "想休息", "split_marker": "可是", "integration_prompt": "先聽心的聲音？"}',
            );
          }
          if (systemPrompt.contains('頻率共振分析器')) {
            return const PipelineLLMResponse(
              content:
                  '{"resonance": "present", "evidence": "有自己的聲音但不夠堅定"}',
            );
          }
          // Attention gate / pendulum / door flow 的回應
          return const PipelineLLMResponse(
            content: '{"state": "clear", "evidence": "測試"}',
          );
        },
      );

      final pipeline = TransurfingPipeline(llmClient: mock);
      final result = await pipeline.analyzeAsync(
        '我必須完成這個否則完蛋，可是我好累',
      );

      expect(result.source, PipelineSource.mixed);
      expect(result.reflection.guidanceHint, isNotNull);
      expect(result.reflection.guidanceHint!.humorHint, '試著笑一笑');
      expect(result.reflection.guidanceHint!.mindStatement, '應該工作');
      expect(result.reflection.guidanceHint!.heartStatement, '想休息');
      expect(result.reflection.guidanceHint!.splitMarker, '可是');
      expect(result.reflection.guidanceHint!.integrationPrompt,
          '先聽心的聲音？');
      expect(result.reflection.guidanceHint!.fraileEvidence,
          '有自己的聲音但不夠堅定');
    });

    test('LLM off → guidanceHint is null (zero regression)', () async {
      final pipeline = TransurfingPipeline(); // 不傳 llmClient
      final result = await pipeline.analyzeAsync('你好');

      expect(result.source, PipelineSource.allRule);
      expect(result.reflection.guidanceHint, isNull);
    });

    test('LLM off → all layers are rule source', () async {
      final pipeline = TransurfingPipeline();
      final result = await pipeline.analyzeAsync('你好');

      for (final entry in result.layerResults.entries) {
        expect(
          entry.value.source,
          anyOf(LayerSource.rule, LayerSource.cached),
          reason: '${entry.key} should be rule-based when LLM is off',
        );
      }
    });
  });
}

PipelineContext _emptyContext() => const PipelineContext();
