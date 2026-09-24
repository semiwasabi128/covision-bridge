// sprint5_door_flow_test.dart
// Sprint 5 驗證測試 — Door & Flow AI 升級 + 混合策略
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 測試項目：
// 1. DoorFlowDetectorAI 用 mock LLM 回應，正確解析 JSON（門候選 + 水流狀態）
// 2. DoorFlowDetectorAI 處理 markdown code block
// 3. DoorFlowDetectorAI LLM 不可用 → fallback
// 4. MixedDoorFlowDetector 規則版 + AI 版合併去重
// 5. 約瑟鐵則：contextDriven 門不被 AI 覆蓋
// 6. 約瑟驗證標準：activeProject + 「下一步」→ 即使 AI 沒產出 ownDoor，規則版也補上
// 7. LLM 不可用 → fallback to rule only

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_llm_client.dart';
import 'package:bridge_app/services/brain_pipeline/layer_result.dart';
import 'package:bridge_app/services/brain_pipeline/brain_layer_analyzer.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/door_flow_detector_ai.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/door_flow_detector_rule.dart';
import 'package:bridge_app/services/brain_pipeline/analyzers/mixtures/mixed_door_flow_detector.dart';

void main() {
  group('DoorFlowDetectorAI', () {
    test('parses doors + flowState from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "ownDoor", "label": "橋樑計畫", "reason": "使用者明確提到自己的專案"}, {"kind": "currentLink", "label": "下一個 sprint", "reason": "推進已確認的下一步"}], "flowState": "withFlow"}',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('我想把橋樑計畫的下一個 sprint 做完', _emptyContext());

      expect(result.value.doors.length, 2);
      expect(result.value.doors[0].kind, DoorKind.ownDoor);
      expect(result.value.doors[0].label, '橋樑計畫');
      expect(result.value.doors[0].source, DoorCandidateSource.aiInferred);
      expect(result.value.doors[1].kind, DoorKind.currentLink);
      expect(result.value.flowState, FlowState.withFlow);
      expect(result.source, LayerSource.ai);
    });

    test('parses foreignDoor from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "foreignDoor", "label": "新 AI 工具", "reason": "注意力被外部工具吸引"}], "flowState": "unknown"}',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('我看到一個新的 AI 工具', _emptyContext());

      expect(result.value.doors.length, 1);
      expect(result.value.doors[0].kind, DoorKind.foreignDoor);
      expect(result.value.doors[0].source, DoorCandidateSource.aiInferred);
      expect(result.value.flowState, FlowState.unknown);
    });

    test('parses falseDoor from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "falseDoor", "label": "保證獲利投資", "reason": "不合理承諾"}], "flowState": "unknown"}',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('保證月賺30%', _emptyContext());

      expect(result.value.doors.length, 1);
      expect(result.value.doors[0].kind, DoorKind.falseDoor);
    });

    test('parses againstFlow from LLM JSON', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [], "flowState": "againstFlow"}',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('卡住了', _emptyContext());

      expect(result.value.doors, isEmpty);
      expect(result.value.flowState, FlowState.againstFlow);
    });

    test('handles markdown code block in LLM response', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '```json\n{"doors": [{"kind": "ownDoor", "label": "音樂創作", "reason": "使用者提到自己的興趣"}], "flowState": "withFlow"}\n```',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('我想做音樂', _emptyContext());

      expect(result.value.doors.length, 1);
      expect(result.value.doors[0].label, '音樂創作');
      expect(result.value.flowState, FlowState.withFlow);
    });

    test('LLM unavailable → fallback to empty + unknown', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());

      expect(result.value.doors, isEmpty);
      expect(result.value.flowState, FlowState.unknown);
      expect(result.confidence, 0.0);
    });

    test('LLM failed → fallback to empty + unknown', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: PipelineLLMResponse.failed,
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());

      expect(result.value.doors, isEmpty);
      expect(result.value.flowState, FlowState.unknown);
      expect(result.confidence, 0.0);
    });

    test('invalid JSON → fallback to empty + unknown', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(content: 'not json at all'),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());

      expect(result.value.doors, isEmpty);
      expect(result.value.flowState, FlowState.unknown);
      expect(result.confidence, 0.0);
    });

    test('AI doors always have aiInferred source', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "ownDoor", "label": "A", "reason": "x"}, {"kind": "foreignDoor", "label": "B", "reason": "y"}], "flowState": "unknown"}',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());

      for (final door in result.value.doors) {
        expect(door.source, DoorCandidateSource.aiInferred);
      }
    });

    test('AI version does not produce doorDecision', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [], "flowState": "withFlow"}',
        ),
      );
      final analyzer = DoorFlowDetectorAI(mock);
      final result = await analyzer.analyze('test', _emptyContext());

      expect(result.value.doorDecision, isNull);
    });
  });

  group('MixedDoorFlowDetector', () {
    test('rule + AI doors merged, deduped by (kind, label)', () async {
      // 規則版會產生 ownDoor "自己的門"（因為 fraile=present 需要前層結果，這裡用空 context）
      // AI 版產生 ownDoor "橋樑計畫" + currentLink "下一個 sprint"
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "ownDoor", "label": "橋樑計畫", "reason": "使用者提到專案"}, {"kind": "currentLink", "label": "下一個 sprint", "reason": "推進下一步"}], "flowState": "withFlow"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('我想把橋樑計畫的下一個 sprint 做完', _emptyContext());

      expect(result.source, LayerSource.mixed);
      // 規則版可能產生 0 個門（空 context 沒有 fraile/attention），AI 產生 2 個
      expect(result.value.doors.length, greaterThanOrEqualTo(2));

      // AI 的門應該都在
      final labels = result.value.doors.map((d) => d.label).toSet();
      expect(labels, contains('橋樑計畫'));
      expect(labels, contains('下一個 sprint'));
    });

    test('dedup: same (kind, label) from rule and AI → only one', () async {
      // 規則版產生 currentLink "目前 transfer chain 的下一環"（命中「下一步」）
      // AI 版也產生 currentLink "目前 transfer chain 的下一環"
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "currentLink", "label": "目前 transfer chain 的下一環", "reason": "推進已確認路徑"}], "flowState": "unknown"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('下一步', _emptyContext());

      final currentLinkDoors = result.value.doors
          .where((d) => d.kind == DoorKind.currentLink)
          .toList();
      // 去重後應該只有一個
      final labels = currentLinkDoors.map((d) => d.label).toSet();
      expect(labels.contains('目前 transfer chain 的下一環'), isTrue);
      final count = currentLinkDoors
          .where((d) => d.label == '目前 transfer chain 的下一環')
          .length;
      expect(count, 1);
    });

    test('contextDriven door is never removed by AI', () async {
      // 給一個有 activeProjectTitle 的 context
      // 規則版會產生 ownDoor source=contextDriven（activeProjectTitle）
      // AI 版產生不同的 ownDoor，不應該覆蓋 contextDriven
      const ctx = DoorDecisionContext(
        activeProjectTitle: '1C sprint 5',
      );
      final context = const PipelineContext(doorContext: ctx);

      // AI 回應一個完全不同的 ownDoor
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "ownDoor", "label": "音樂創作", "reason": "使用者想做音樂"}], "flowState": "withFlow"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('我想做音樂', context);

      // contextDriven 門「1C sprint 5」必須還在
      final projectDoors = result.value.doors
          .where((d) => d.label == '1C sprint 5')
          .toList();
      expect(projectDoors.length, 1);
      expect(projectDoors[0].source, DoorCandidateSource.contextDriven);

      // AI 的門也應該在
      final aiDoors = result.value.doors
          .where((d) => d.source == DoorCandidateSource.aiInferred)
          .toList();
      expect(aiDoors.any((d) => d.label == '音樂創作'), isTrue);
    });

    // 約瑟驗證標準：DoorDecisionContext.activeProjectTitle = "1C sprint 5"，
    // 輸入「下一步是什麼」→ 即使 AI 沒產出 ownDoor，規則版也補上 contextDriven 專案門
    test('Joseph spec: activeProject + "下一步" → contextDriven door present even if AI misses it', () async {
      const ctx = DoorDecisionContext(
        activeProjectTitle: '1C sprint 5',
      );
      final context = const PipelineContext(doorContext: ctx);

      // AI 回應空 doors（沒偵測到 ownDoor）
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [], "flowState": "unknown"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('下一步是什麼', context);

      // 規則版補上 contextDriven ownDoor
      final ownDoors = result.value.doors
          .where((d) => d.kind == DoorKind.ownDoor)
          .toList();
      expect(ownDoors.any((d) => d.label == '1C sprint 5'), isTrue);

      // 規則版也命中 currentLink（「下一步」）
      final currentLinkDoors = result.value.doors
          .where((d) => d.kind == DoorKind.currentLink)
          .toList();
      expect(currentLinkDoors.isNotEmpty, isTrue);
    });

    test('FlowState: AI preferred when available', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [], "flowState": "withFlow"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('很棒，繼續', _emptyContext());

      // 規則版也會說 withFlow（命中「很棒」「繼續」），AI 也說 withFlow
      expect(result.value.flowState, FlowState.withFlow);
    });

    test('FlowState: AI againstFlow overrides rule unknown', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [], "flowState": "againstFlow"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('感覺很卡', _emptyContext());

      // AI 說 againstFlow，規則版可能說 unknown
      expect(result.value.flowState, FlowState.againstFlow);
    });

    test('LLM unavailable → rule only', () async {
      final mock = MockPipelineLLMClient(isAvailable: false);
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('下一步', _emptyContext());

      expect(result.source, LayerSource.rule);
      // 規則版命中「下一步」→ currentLink
      expect(result.value.doors.any((d) => d.kind == DoorKind.currentLink), isTrue);
    });

    test('rule produces doorDecision, AI does not override it', () async {
      // 給一個有 pendingBridgeTask + requestedCapability 的 context → 規則版會產生 doorDecision
      const ctx = DoorDecisionContext(
        pendingBridgeTaskTitle: '音樂生成能力',
        pendingBridgeTaskMissing: '需要設定音樂 API',
        requestedCapabilityLabel: '影片生成',
      );
      final context = const PipelineContext(doorContext: ctx);

      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [], "flowState": "unknown"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('下一步', context);

      // 規則版的 doorDecision 應該保留
      expect(result.value.doorDecision, isNotNull);
      expect(result.value.doorDecision!.title, contains('能力支線門'));
    });

    test('mixed evidence contains rule and AI counts', () async {
      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "ownDoor", "label": "test door", "reason": "test"}], "flowState": "withFlow"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('test', _emptyContext());

      expect(result.evidence, contains('rule.doors='));
      expect(result.evidence, contains('ai.doors='));
      expect(result.evidence, contains('merged='));
    });

    test('all three source types can coexist', () async {
      // context: 有 activeProject → contextDriven ownDoor
      // rule: 命中「下一步」→ ruleMatch currentLink
      // AI: 產生 foreignDoor
      const ctx = DoorDecisionContext(
        activeProjectTitle: '測試專案',
      );
      final context = const PipelineContext(doorContext: ctx);

      final mock = MockPipelineLLMClient(
        defaultResponse: const PipelineLLMResponse(
          content: '{"doors": [{"kind": "foreignDoor", "label": "外部工具", "reason": "注意力被拉走"}], "flowState": "unknown"}',
        ),
      );
      final analyzer = MixedDoorFlowDetector(mock);
      final result = await analyzer.analyze('下一步', context);

      final sources = result.value.doors.map((d) => d.source).toSet();
      // 應該同時有 contextDriven, ruleMatch, aiInferred
      expect(sources, contains(DoorCandidateSource.contextDriven));
      expect(sources, contains(DoorCandidateSource.ruleMatch));
      expect(sources, contains(DoorCandidateSource.aiInferred));
    });
  });

  group('DoorFlowDetectorRule (regression)', () {
    test('rule still works: activeProject → ownDoor', () async {
      const ctx = DoorDecisionContext(
        activeProjectTitle: '測試專案',
      );
      final context = const PipelineContext(doorContext: ctx);
      final analyzer = DoorFlowDetectorRule();
      final result = await analyzer.analyze('你好', context);

      expect(result.value.doors.any((d) => d.label == '測試專案'), isTrue);
      expect(result.source, LayerSource.rule);
    });

    test('rule still works: falseDoor keywords', () async {
      final analyzer = DoorFlowDetectorRule();
      final result = await analyzer.analyze('快速致富不是夢', _emptyContext());

      expect(result.value.doors.any((d) => d.kind == DoorKind.falseDoor), isTrue);
    });

    test('rule still works: flow withFlow from keywords', () async {
      const ctx = DoorDecisionContext(
        activeProjectTitle: '測試專案',
      );
      final context = const PipelineContext(doorContext: ctx);
      final analyzer = DoorFlowDetectorRule();
      final result = await analyzer.analyze('繼續', context);

      expect(result.value.flowState, FlowState.withFlow);
    });
  });
}

PipelineContext _emptyContext() => const PipelineContext();
