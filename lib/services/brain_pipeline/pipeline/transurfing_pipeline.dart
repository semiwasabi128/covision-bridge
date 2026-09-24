// transurfing_pipeline.dart
// Sprint 1 — 七層管線調度器
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 依序跑 8 個 rule analyzer，每層結果塞進 PipelineContext.priorLayers。
// 最終組裝成 BrainReflection + PipelineResult。
//
// 行為與原 TransurfingBrainService.analyze() 完全一致——
// 只是換成管線架構跑，邏輯全部從原 service 剪下貼上。

import '../../../models/transurfing_brain.dart';
import '../analyzer_config.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../companion_broadcaster.dart';
import '../companion_mood_mapper.dart';
import '../pipeline_result.dart';
import '../pipeline_llm_client.dart';
// Sprint 8：擺錘審計 + clip 消費計數
import '../audit/audit_store.dart';
import '../audit/pendulum_auditor.dart';
import '../audit/clip_consumption_counter.dart';
// Sprint 9：心腦合一對話閉環
import '../heart_mind/heart_mind_dialogue.dart';
import '../heart_mind/heart_mind_store.dart';
// Sprint 10：Router + Cache + CostTracker
import '../analyzer_router.dart';
import '../layer_cache.dart';
import '../cost_tracker.dart';
import '../analyzers/intent_clarifier_rule.dart';
import '../analyzers/attention_gate_rule.dart';
import '../analyzers/pendulum_detector_rule.dart';
import '../analyzers/importance_coordinator_rule.dart';
import '../analyzers/heart_mind_tuner_rule.dart';
import '../analyzers/fraile_tuner_rule.dart';
import '../analyzers/door_flow_detector_rule.dart';
import '../analyzers/action_router_rule.dart';
// Sprint 3 混合策略
import '../analyzers/mixtures/mixed_attention_gate.dart';
import '../analyzers/mixtures/mixed_pendulum_detector.dart';
// Sprint 4 混合策略
import '../analyzers/mixtures/mixed_importance_coordinator.dart';
import '../analyzers/mixtures/mixed_heart_mind_tuner.dart';
import '../analyzers/mixtures/mixed_fraile_tuner.dart';
// Sprint 5 混合策略
import '../analyzers/mixtures/mixed_door_flow_detector.dart';
// Sprint 2 混合策略
import '../analyzers/mixtures/mixed_action_router.dart';

class TransurfingPipeline {
  final AnalyzerConfig config;
  final CompanionBroadcaster? broadcaster;

  /// Sprint 4 新增：可選的 LLM client。
  /// 傳入且 isAvailable 時，層 1~6 走混合策略（rule + AI），並收集 GuidanceHint。
  /// 不傳或不可用時，全部走規則版（與原 analyze() 行為一致，零回歸）。
  final PipelineLLMClient? llmClient;

  /// Sprint 8 新增：擺錘審計 store。
  /// 傳入時，每輪分析後自動記錄擺錘計數 + 偵測 clip 消費。
  /// 不傳時不審計（零回歸）。
  final AuditStore? auditStore;

  /// Sprint 9 新增：心腦合一對話狀態機。
  /// 傳入時，每輪分析後偵測心腦分裂，觸發對話流程。
  /// 不傳時不啟動心腦對話（零回歸）。
  final HeartMindDialogue? heartMindDialogue;

  /// Sprint 10 新增：層結果快取。
  /// 傳入時，同訊息第二次走快取（source=cached, latency=0）。
  final LayerCache? layerCache;

  /// Sprint 10 新增：LLM 成本追蹤。
  /// 傳入時，每次 LLM 呼叫記 token + latency，超額自動切規則版。
  final CostTracker? costTracker;

  TransurfingPipeline({
    this.config = const AnalyzerConfig(),
    this.broadcaster,
    this.llmClient,
    this.auditStore,
    this.heartMindDialogue,
    this.layerCache,
    this.costTracker,
  });

  /// 是否使用 AI 混合策略
  bool get _useAi => llmClient != null && llmClient!.isAvailable;

  /// Sprint 8：是否啟用審計
  bool get _useAudit => auditStore != null;

  /// Sprint 9：是否啟用心腦對話
  bool get _useHeartMind => heartMindDialogue != null;

  /// Sprint 10：是否啟用快取
  bool get _useCache => layerCache != null;

  /// Sprint 10：構建 AnalyzerRouter（結合 config + costTracker）
  AnalyzerRouter get _router => AnalyzerRouter(
        config: config,
        costTracker: costTracker,
      );

  /// Sprint 10：快取 key
  String? _cacheKey;

  /// Sprint 10：用 Router 決定某層是否走 AI。
  /// 先檢查 _useAi（llmClient 可用），再檢查 Router 的 costTracker/override。
  /// 注意：globalAiEnabled 不在此判斷——既有測試不傳 config 但期望走 AI，
  /// globalAiEnabled 的語意是「全域明確關閉」，預設 false 不代表「不允許」。
  bool _shouldUseAiForLayer(int layerIndex) {
    if (!_useAi) return false;
    // CostTracker 超額 → 規則版
    if (costTracker != null && costTracker!.isOverLimit) return false;
    // 每層覆寫
    final kind = config.kindForLayer(layerIndex);
    if (kind == AnalyzerKind.rule) return false;
    return true;
  }

  /// 跑完整七層管線，回傳 PipelineResult。
  Future<PipelineResult> analyzeAsync(
    String message, {
    List<String> recentMemories = const [],
    String? activeCompanionRole,
    DoorDecisionContext doorContext = const DoorDecisionContext(),
  }) async {
    final stopwatch = Stopwatch()..start();

    // 管線順序：pendulum(2) → attention(1) → importance(3) → heartMind(4)
    // → fraile(5) → doorFlow(6) → intent(0) → actionRouter(7)
    //
    // 注意：原 service 的執行順序是 pendulum → attention → importance →
    // alignment → fraile → doors → doorDecision → flow → move → intent
    // 管線用 layerIndex 標記但不代表執行順序——執行順序在這裡控制。
    // intent(0) 可以最後跑（它只依賴 text + role，不依賴其他層），
    // 但為了與原 service 一致，我們在 actionRouter 之前跑。

    var ctx = PipelineContext(
      recentMemories: recentMemories,
      activeCompanionRole: activeCompanionRole,
      doorContext: doorContext,
    );

    // Sprint 10：生成快取 key
    _cacheKey = _useCache ? layerCache!.keyFor(message) : null;

    // Sprint 10：追蹤是否有任何層嘗試走 AI
    var anyAiAttempted = false;

    // Layer 2: Pendulum Detector（必須先跑，attention 和 importance 依賴它）
    final useAiL2 = _shouldUseAiForLayer(2);
    if (useAiL2) anyAiAttempted = true;
    LayerResult<dynamic>? pendulumResult;
    if (_useCache && _cacheKey != null) {
      pendulumResult = layerCache!.get(layerIndex: 2, key: _cacheKey!);
    }
    if (pendulumResult == null) {
      final pendulumAnalyzer = useAiL2
          ? MixedPendulumDetector(llmClient!)
          : PendulumDetectorRule();
      pendulumResult = await pendulumAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 2, key: _cacheKey!, result: pendulumResult);
      }
      if (useAiL2 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'pendulum',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: pendulumResult.latencyMs,
          succeeded: pendulumResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(2, pendulumResult);

    // Layer 1: Attention Gate（依賴 pendulum）
    final useAiL1 = _shouldUseAiForLayer(1);
    if (useAiL1) anyAiAttempted = true;
    LayerResult<dynamic>? attentionResult;
    if (_useCache && _cacheKey != null) {
      attentionResult = layerCache!.get(layerIndex: 1, key: _cacheKey!);
    }
    if (attentionResult == null) {
      final attentionAnalyzer = useAiL1
          ? MixedAttentionGate(llmClient!)
          : AttentionGateRule();
      attentionResult = await attentionAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 1, key: _cacheKey!, result: attentionResult);
      }
      if (useAiL1 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'attention',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: attentionResult.latencyMs,
          succeeded: attentionResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(1, attentionResult);

    // Layer 3: Importance Coordinator（依賴 pendulum + doorContext）
    final useAiL3 = _shouldUseAiForLayer(3);
    if (useAiL3) anyAiAttempted = true;
    LayerResult<dynamic>? importanceResult;
    if (_useCache && _cacheKey != null) {
      importanceResult = layerCache!.get(layerIndex: 3, key: _cacheKey!);
    }
    if (importanceResult == null) {
      final importanceAnalyzer = useAiL3
          ? MixedImportanceCoordinator(llmClient!)
          : ImportanceCoordinatorRule();
      importanceResult = await importanceAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 3, key: _cacheKey!, result: importanceResult);
      }
      if (useAiL3 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'importance',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: importanceResult.latencyMs,
          succeeded: importanceResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(3, importanceResult);

    // Layer 4: Heart-Mind Tuner（只依賴 text）
    final useAiL4 = _shouldUseAiForLayer(4);
    if (useAiL4) anyAiAttempted = true;
    LayerResult<dynamic>? heartMindResult;
    if (_useCache && _cacheKey != null) {
      heartMindResult = layerCache!.get(layerIndex: 4, key: _cacheKey!);
    }
    if (heartMindResult == null) {
      final heartMindAnalyzer = useAiL4
          ? MixedHeartMindTuner(llmClient!)
          : HeartMindTunerRule();
      heartMindResult = await heartMindAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 4, key: _cacheKey!, result: heartMindResult);
      }
      if (useAiL4 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'heartMind',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: heartMindResult.latencyMs,
          succeeded: heartMindResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(4, heartMindResult);

    // Layer 5: Fraile Tuner（依賴 alignment + pendulum）
    final useAiL5 = _shouldUseAiForLayer(5);
    if (useAiL5) anyAiAttempted = true;
    LayerResult<dynamic>? fraileResult;
    if (_useCache && _cacheKey != null) {
      fraileResult = layerCache!.get(layerIndex: 5, key: _cacheKey!);
    }
    if (fraileResult == null) {
      final fraileAnalyzer = useAiL5
          ? MixedFraileTuner(llmClient!)
          : FraileTunerRule();
      fraileResult = await fraileAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 5, key: _cacheKey!, result: fraileResult);
      }
      if (useAiL5 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'fraile',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: fraileResult.latencyMs,
          succeeded: fraileResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(5, fraileResult);

    // Layer 6: Door & Flow Detector（依賴 attention + importance + fraile + doorContext）
    final useAiL6 = _shouldUseAiForLayer(6);
    if (useAiL6) anyAiAttempted = true;
    LayerResult<dynamic>? doorFlowResult;
    if (_useCache && _cacheKey != null) {
      doorFlowResult = layerCache!.get(layerIndex: 6, key: _cacheKey!);
    }
    if (doorFlowResult == null) {
      final doorFlowAnalyzer = useAiL6
          ? MixedDoorFlowDetector(llmClient!)
          : DoorFlowDetectorRule();
      doorFlowResult = await doorFlowAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 6, key: _cacheKey!, result: doorFlowResult);
      }
      if (useAiL6 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'doorFlow',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: doorFlowResult.latencyMs,
          succeeded: doorFlowResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(6, doorFlowResult);

    // Layer 0: Intent Clarifier（只依賴 text + role，永遠規則版）
    LayerResult<dynamic>? intentResult;
    if (_useCache && _cacheKey != null) {
      intentResult = layerCache!.get(layerIndex: 0, key: _cacheKey!);
    }
    if (intentResult == null) {
      final intentAnalyzer = IntentClarifierRule();
      intentResult = await intentAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 0, key: _cacheKey!, result: intentResult);
      }
    }
    ctx = ctx.copyWithPriorLayer(0, intentResult);

    // Layer 7: Action Router（依賴 attention + importance + alignment + doors + flow）
    final useAiL7 = _shouldUseAiForLayer(7);
    if (useAiL7) anyAiAttempted = true;
    LayerResult<dynamic>? actionRouterResult;
    if (_useCache && _cacheKey != null) {
      actionRouterResult = layerCache!.get(layerIndex: 7, key: _cacheKey!);
    }
    if (actionRouterResult == null) {
      final actionRouterAnalyzer = useAiL7
          ? MixedActionRouter(llmClient!)
          : ActionRouterRule();
      actionRouterResult = await actionRouterAnalyzer.analyze(message, ctx);
      if (_useCache && _cacheKey != null) {
        layerCache!.put(layerIndex: 7, key: _cacheKey!, result: actionRouterResult);
      }
      if (useAiL7 && costTracker != null) {
        costTracker!.recordCall(
          layerName: 'actionRouter',
          tokens: CostTracker.estimateTokens('', message),
          latencyMs: actionRouterResult.latencyMs,
          succeeded: actionRouterResult.source == LayerSource.ai,
        );
      }
    }
    ctx = ctx.copyWithPriorLayer(7, actionRouterResult);

    stopwatch.stop();

    // Sprint 4：從各層 metadata 收集 GuidanceHint
    GuidanceHint? guidanceHint;
    if (_useAi) {
      final hints = <GuidanceHint>[
        GuidanceHint(
          humorHint: importanceResult.metadata['humorHint'] as String?,
        ),
        GuidanceHint(
          mindStatement: heartMindResult.metadata['mindStatement'] as String?,
          heartStatement: heartMindResult.metadata['heartStatement'] as String?,
          splitMarker: heartMindResult.metadata['splitMarker'] as String?,
          integrationPrompt:
              heartMindResult.metadata['integrationPrompt'] as String?,
        ),
        GuidanceHint(
          fraileEvidence: fraileResult.metadata['fraileEvidence'] as String?,
        ),
      ];
      // 合併所有 partial hint
      guidanceHint = hints.fold<GuidanceHint>(
        const GuidanceHint(),
        (acc, h) => acc.merge(h),
      );
      // 全部 null → 不設
      if (!guidanceHint.hasAny) guidanceHint = null;
    }

    // 組裝 BrainReflection
    final doorFlow = doorFlowResult.value;
    final actionRouter = actionRouterResult.value;

    final reflection = BrainReflection(
      userIntent: intentResult.value,
      attentionState: attentionResult.value,
      pendulumSignals: pendulumResult.value,
      importanceLevel: importanceResult.value,
      heartMindAlignment: heartMindResult.value,
      fraileResonance: fraileResult.value,
      doorCandidates: doorFlow.doors,
      doorDecision: doorFlow.doorDecision,
      flowState: doorFlow.flowState,
      recommendedMove: actionRouter.move,
      companionExpression: actionRouter.expression,
      guidance: actionRouter.guidance,
      guidanceHint: guidanceHint,
      layerResults: {
        'intent': intentResult,
        'attention': attentionResult,
        'pendulum': pendulumResult,
        'importance': importanceResult,
        'heartMind': heartMindResult,
        'fraile': fraileResult,
        'doorFlow': doorFlowResult,
        'actionRouter': actionRouterResult,
      },
    );

    // Sprint 7：用 CompanionMoodMapper 豐富 companionExpression（補上 gait / voiceTone）
    const moodMapper = CompanionMoodMapper();
    final moodMapping = moodMapper.mapFromReflection(reflection);
    final enrichedReflection = BrainReflection(
      userIntent: reflection.userIntent,
      attentionState: reflection.attentionState,
      pendulumSignals: reflection.pendulumSignals,
      importanceLevel: reflection.importanceLevel,
      heartMindAlignment: reflection.heartMindAlignment,
      fraileResonance: reflection.fraileResonance,
      doorCandidates: reflection.doorCandidates,
      doorDecision: reflection.doorDecision,
      flowState: reflection.flowState,
      recommendedMove: reflection.recommendedMove,
      companionExpression: reflection.companionExpression.withCompanionFields(
        gait: moodMapping.gait,
        voiceTone: moodMapping.voiceTone,
      ),
      guidance: reflection.guidance,
      guidanceHint: reflection.guidanceHint,
      layerResults: reflection.layerResults,
    );

    // 廣播（Sprint 7 的 LocalCompanionBroadcaster 會通知所有訂閱者）
    broadcaster?.broadcast(enrichedReflection);

    // Sprint 8：擺錘審計 + clip 消費偵測
    if (_useAudit) {
      PendulumAuditor(auditStore!).record(enrichedReflection);
      ClipConsumptionCounter(auditStore!).detectAndRecord(message);
    }

    // Sprint 9：心腦合一對話——偵測分裂觸發狀態機
    if (_useHeartMind) {
      heartMindDialogue!.checkTimeout();
      heartMindDialogue!.offerSplit(enrichedReflection);
    }

    // Sprint 10：從實際 layer results + AI 嘗試 flag 判斷 source
    final allSources = [
      pendulumResult.source,
      attentionResult.source,
      importanceResult.source,
      heartMindResult.source,
      fraileResult.source,
      doorFlowResult.source,
      actionRouterResult.source,
    ];
    final hasAi = allSources.any((s) => s == LayerSource.ai);
    final hasCached = allSources.any((s) => s == LayerSource.cached);
    final pipelineSource = hasAi
        ? PipelineSource.mixed
        : (anyAiAttempted || hasCached)
            ? PipelineSource.mixed
            : PipelineSource.allRule;

    return PipelineResult(
      reflection: enrichedReflection,
      layerResults: {
        'intent': intentResult,
        'attention': attentionResult,
        'pendulum': pendulumResult,
        'importance': importanceResult,
        'heartMind': heartMindResult,
        'fraile': fraileResult,
        'doorFlow': doorFlowResult,
        'actionRouter': actionRouterResult,
      },
      totalLatencyMs: stopwatch.elapsedMilliseconds,
      source: pipelineSource,
    );
  }
}
