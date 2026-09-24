// mixed_door_flow_detector.dart
// Sprint 5 — Layer 6: 門與水流偵測（混合策略）
//
// 約瑟鐵則：contextDriven 一律後補，不可被 AI 移除。
//
// 策略：
// 1. 規則版與 AI 版並跑
// 2. 合併門候選：ruleMatch 先放（確保不漏），AI 補充（aiInferred），去重 by (kind, label)
// 3. contextDriven 門（從 DoorDecisionContext.activeProjectTitle 來的）永遠保留，不可被覆蓋
// 4. DoorDecision：規則版優先（有真實 DoorDecisionContext），AI 版不產生
// 5. FlowState：AI 版優先（語意判斷較準），LLM 不可用時 fallback 規則版

import '../../../../../models/transurfing_brain.dart';
import '../../brain_layer_analyzer.dart';
import '../../layer_result.dart';
import '../../pipeline_llm_client.dart';
import '../door_flow_detector_rule.dart';
import '../door_flow_detector_ai.dart';

class MixedDoorFlowDetector
    extends BrainLayerAnalyzer<String, DoorFlowResult> {
  final DoorFlowDetectorRule _rule = DoorFlowDetectorRule();
  final PipelineLLMClient llmClient;

  MixedDoorFlowDetector(this.llmClient);

  @override
  String get layerName => 'Door & Flow Detector (Mixed)';

  @override
  int get layerIndex => 6;

  @override
  Future<LayerResult<DoorFlowResult>> analyze(
    String input,
    PipelineContext context,
  ) async {
    // 1. 同時跑規則版和 AI 版
    final ruleFuture = _rule.analyze(input, context);

    // AI 版需要 LLM client，如果不可用就只回規則版
    if (!llmClient.isAvailable) {
      return ruleFuture;
    }

    final aiAnalyzer = DoorFlowDetectorAI(llmClient);
    final results = await Future.wait([
      ruleFuture,
      aiAnalyzer.analyze(input, context),
    ]);

    final ruleResult = results[0];
    final aiResult = results[1];

    final ruleValue = ruleResult.value;
    final aiValue = aiResult.value;

    // 2. 合併門候選——去重 by (kind, label)
    final seen = <String>{};
    final mergedDoors = <DoorCandidate>[];

    // 規則版先放（含 ruleMatch 和 contextDriven）
    for (final door in ruleValue.doors) {
      final key = '${door.kind.name}|${door.label}';
      if (seen.add(key)) {
        mergedDoors.add(door);
      }
    }

    // AI 版後放（aiInferred），去重
    for (final door in aiValue.doors) {
      final key = '${door.kind.name}|${door.label}';
      if (seen.add(key)) {
        mergedDoors.add(door);
      }
    }

    // 3. contextDriven 門保護：確保 contextDriven 門一定在最終清單裡
    // （規則版已經把它們放進來了，這裡只是做二次確認）
    final contextDrivenDoors = ruleValue.doors
        .where((d) => d.source == DoorCandidateSource.contextDriven)
        .toList();
    for (final cdDoor in contextDrivenDoors) {
      final key = '${cdDoor.kind.name}|${cdDoor.label}';
      final exists = mergedDoors.any(
        (d) => '${d.kind.name}|${d.label}' == key,
      );
      if (!exists) {
        mergedDoors.add(cdDoor);
      }
    }

    // 4. DoorDecision：規則版優先（有真實 DoorDecisionContext）
    final doorDecision = ruleValue.doorDecision ?? aiValue.doorDecision;

    // 5. FlowState：AI 版優先（語意判斷較準），但規則版的 againstFlow/stalled
    //    如果是因為 importance/excessive 或明確關鍵字觸發的，保留規則版
    FlowState flowState;
    if (aiResult.confidence > 0 && aiValue.flowState != FlowState.unknown) {
      flowState = aiValue.flowState;
    } else {
      flowState = ruleValue.flowState;
    }

    return LayerResult<DoorFlowResult>(
      value: DoorFlowResult(
        doors: mergedDoors,
        doorDecision: doorDecision,
        flowState: flowState,
      ),
      source: LayerSource.mixed,
      confidence: 0.85,
      evidence: 'rule.doors=${ruleValue.doors.length}, '
          'ai.doors=${aiValue.doors.length}, '
          'merged=${mergedDoors.length}, '
          'flow=${flowState.name}',
      latencyMs: ruleResult.latencyMs + aiResult.latencyMs,
    );
  }
}
