// semantic_intent_service.dart
// 語意理解統一入口——三層瀑布架構。
// L1 規則 → (L2 embedding stub) → L3 LLM。
// feature flag 預設關閉，關閉時直接回傳 null（走既有正則 fallback）。

import '../brain_pipeline/pipeline_llm_client.dart';
import '../storage_service.dart';
import 'l1_rule_engine.dart';
import 'l3_llm_engine.dart';
import 'semantic_metrics.dart';
import 'semantic_result.dart';

class SemanticIntentService {
  final PipelineLLMClient? llmClient;
  final SemanticMetrics _metrics;
  final L1RuleEngine _l1 = L1RuleEngine();

  // [Sprint 1.3] Feature flag 快取——避免每次呼叫都讀 SharedPreferences
  bool? _cachedEnabled;
  DateTime? _cacheTimestamp;
  static const Duration _cacheTtl = Duration(seconds: 30);

  // [Sprint 1.3] A/B 模式 log——記錄 LLM 結果 vs 規則結果供比對
  final List<Map<String, dynamic>> _abLog = [];

  SemanticIntentService({
    this.llmClient,
    SemanticMetrics? metrics,
  }) : _metrics = metrics ?? SemanticMetrics();

  /// 公開 metrics（供 UI 或 debug 读取）
  SemanticMetrics get metrics => _metrics;

  /// [Sprint 1.3] A/B 模式 log——記錄 LLM vs 規則結果供比對（最近 50 筆）
  List<Map<String, dynamic>> get abLog => List.unmodifiable(_abLog);

  /// [Sprint 1.3] Feature flag 快取——30 秒 TTL，避免每次呼叫都讀 SharedPreferences。
  /// 快取過期或首次呼叫時重新讀取，SharedPreferences 異常 fallback 到 false。
  Future<bool> _isFeatureEnabled() async {
    // 快取有效
    if (_cachedEnabled != null && _cacheTimestamp != null) {
      final age = DateTime.now().difference(_cacheTimestamp!);
      if (age < _cacheTtl) return _cachedEnabled!;
    }

    // 快取過期或首次——重新讀取
    try {
      _cachedEnabled = await StorageService.isSemanticIntentEnabled();
    } catch (_) {
      _cachedEnabled = false;
    }
    _cacheTimestamp = DateTime.now();
    return _cachedEnabled!;
  }

  /// [Sprint 1.3] 手動清除 feature flag 快取（設定頁切換開關後呼叫）
  void clearFeatureFlagCache() {
    _cachedEnabled = null;
    _cacheTimestamp = null;
  }

  /// [Sprint 1.3] 記錄 A/B 比對結果。
  /// 當 LLM 和規則同時有結果時，記錄兩者差異供分析。
  void _recordABLog({
    required String method,
    required String l1Result,
    String? l3Result,
    String? winner,
  }) {
    _abLog.add({
      'method': method,
      'l1': l1Result,
      'l3': l3Result,
      'winner': winner,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_abLog.length > 50) _abLog.removeAt(0);
  }

  /// 門偵測統一入口。
  /// 流程：
  /// 1. feature flag 檢查（預設 false → 直接回 null）
  /// 2. L1 規則引擎先跑
  /// 3. L1 信心 >= 0.95 → 直接回傳
  /// 4. L1 未命中 → 呼叫 L3 LLM
  /// 5. L3 失敗 → 回傳 null（上層 fallback 到既有正則）
  Future<DoorIntentResult?> detectDoorIntent({
    required String message,
    required List<({String role, String content})> history,
    String? activeDoorTitle,
  }) async {
    // [Sprint 1.3] feature flag 快取版（30s TTL）
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.detectDoorIntent(message: message);
    if (l1Result != null && l1Result.confidence >= 0.95) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'door',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎
    final client = llmClient;
    if (client == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: 0,
        domain: 'door',
        fallbackUsed: true,
      );
      return null;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.detectDoorIntent(
      message: message,
      history: history,
      activeDoorTitle: activeDoorTitle,
    );
    stopwatch.stop();

    if (l3Result == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        domain: 'door',
        fallbackUsed: true,
      );
      return null;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'door',
      fallbackUsed: false,
    );

    // [Sprint 1.3] A/B log
    _recordABLog(
      method: 'detectDoorIntent',
      l1Result: l1Result != null
          ? '${l1Result.shouldCreateDoor} (${l1Result.confidence.toStringAsFixed(2)})'
          : 'null',
      l3Result:
          '${l3Result.shouldCreateDoor} (${l3Result.confidence.toStringAsFixed(2)})',
      winner: l1Result != null ? 'L1' : 'L3',
    );

    return l3Result;
  }

  // ============================================================
  // extractDoorTitle —— 門命名提取統一入口（Sprint 1.2）
  // ============================================================

  /// 門命名統一入口。
  /// 流程：
  /// 1. feature flag 檢查（預設 false → 直接回 null）
  /// 2. L1 規則引擎先跑
  /// 3. L1 信心 >= 0.85 → 直接回傳
  /// 4. L1 未命中 → 呼叫 L3 LLM
  /// 5. L3 失敗 → 回傳 null（上層 fallback）
  Future<DoorTitleResult?> extractDoorTitle({
    required String message,
    required List<({String role, String content})> history,
    String? activeDoorTitle,
  }) async {
    // [Sprint 1.3] feature flag 快取版（30s TTL）
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.extractDoorTitle(message: message);
    if (l1Result != null && l1Result.confidence >= 0.85) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'door_title',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎
    final client = llmClient;
    if (client == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: 0,
        domain: 'door_title',
        fallbackUsed: true,
      );
      return null;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.extractDoorTitle(
      message: message,
      history: history,
      activeDoorTitle: activeDoorTitle,
    );
    stopwatch.stop();

    if (l3Result == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        domain: 'door_title',
        fallbackUsed: true,
      );
      return null;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'door_title',
      fallbackUsed: false,
    );

    // [Sprint 1.3] A/B log
    _recordABLog(
      method: 'extractDoorTitle',
      l1Result: l1Result != null
          ? '${l1Result.title} (${l1Result.confidence.toStringAsFixed(2)})'
          : 'null',
      l3Result: '${l3Result.title} (${l3Result.confidence.toStringAsFixed(2)})',
      winner: l1Result != null ? 'L1' : 'L3',
    );

    return l3Result;
  }

  // ============================================================
  // detectDoorDrift —— 門漂移偵測統一入口（Sprint 1.3）
  // ============================================================

  /// 門漂移偵測統一入口。
  /// 流程：
  /// 1. feature flag 檢查（快取版，30s TTL）
  /// 2. L1 規則引擎先跑
  /// 3. L1 信心 >= 0.85 → 直接回傳（關鍵詞匹配 = 不漂移）
  /// 4. L1 回傳 null（門標題無關鍵詞）→ 呼叫 L3 LLM
  /// 5. L1 信心 < 0.85（報漂移）→ 仍呼叫 L3 做二次確認
  /// 6. L3 失敗 → 回傳 L1 結果（保守 fallback）
  Future<DoorDriftResult?> detectDoorDrift({
    required String doorTitle,
    required List<({String role, String content})> history,
    required String currentMessage,
    List<String>? recentMessages,
    int checkWindow = 5,
  }) async {
    // [Sprint 1.3] feature flag 快取版
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.detectDoorDrift(
      doorTitle: doorTitle,
      recentMessages: recentMessages ?? [currentMessage],
      checkWindow: checkWindow,
    );

    // L1 高信心直接回傳（關鍵詞匹配 = 確定不漂移）
    if (l1Result != null && l1Result.confidence >= 0.85 && !l1Result.isDrifting) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'door_drift',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎（L1 報漂移或 L1 無法判斷時都走 L3 二次確認）
    final client = llmClient;
    if (client == null) {
      // 無 LLM → 用 L1 結果（即使信心較低）
      if (l1Result != null) {
        _metrics.record(
          decisionPath: 'L1_fallback',
          confidence: l1Result.confidence,
          latencyMs: 0,
          domain: 'door_drift',
          fallbackUsed: true,
        );
      }
      return l1Result;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.detectDoorDrift(
      doorTitle: doorTitle,
      history: history,
      currentMessage: currentMessage,
    );
    stopwatch.stop();

    if (l3Result == null) {
      // L3 失敗 → fallback 到 L1 結果
      if (l1Result != null) {
        _metrics.record(
          decisionPath: 'L3_fallback',
          confidence: l1Result.confidence,
          latencyMs: stopwatch.elapsedMilliseconds,
          domain: 'door_drift',
          fallbackUsed: true,
        );
      }
      return l1Result;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'door_drift',
      fallbackUsed: false,
    );

    // [Sprint 1.3] A/B log
    _recordABLog(
      method: 'detectDoorDrift',
      l1Result: l1Result != null
          ? '${l1Result.isDrifting} (${l1Result.confidence.toStringAsFixed(2)})'
          : 'null',
      l3Result:
          '${l3Result.isDrifting} (${l3Result.confidence.toStringAsFixed(2)})',
      winner: l1Result != null && l1Result.isDrifting != l3Result.isDrifting
          ? 'L3'
          : 'agree',
    );

    return l3Result;
  }

  // ============================================================
  // Phase 2: classifyRoutingIntent —— 路由意圖分類統一入口
  // ============================================================

  /// 路由意圖分類統一入口（覆蓋 #4, #7, #8, #9, #10, #11）。
  /// 流程：
  /// 1. feature flag 檢查（預設 false → 回傳 null）
  /// 2. L1 關鍵字交集短路（信心 ≥0.9 直接回傳）
  /// 3. L1 未命中 → L3 LLM
  /// 4. L3 失敗 → 回傳 null（上層 fallback 到既有正則）
  Future<RoutingIntentResult?> classifyRoutingIntent({
    required String message,
    required List<({String role, String content})> history,
  }) async {
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.classifyRoutingIntent(message: message);
    if (l1Result != null && l1Result.confidence >= 0.9) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'routing',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎
    final client = llmClient;
    if (client == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: 0,
        domain: 'routing',
        fallbackUsed: true,
      );
      return null;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.classifyRoutingIntent(
      message: message,
      history: history,
    );
    stopwatch.stop();

    if (l3Result == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        domain: 'routing',
        fallbackUsed: true,
      );
      return null;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'routing',
      fallbackUsed: false,
    );

    _recordABLog(
      method: 'classifyRoutingIntent',
      l1Result: l1Result != null
          ? 'proj=${l1Result.projectDoor},reuse=${l1Result.assetReuse} (${l1Result.confidence.toStringAsFixed(2)})'
          : 'null',
      l3Result: 'proj=${l3Result.projectDoor},reuse=${l3Result.assetReuse} (${l3Result.confidence.toStringAsFixed(2)})',
      winner: l1Result != null ? 'L1' : 'L3',
    );

    return l3Result;
  }

  // ============================================================
  // Phase 2: inferBridgeAction —— 橋接行動推斷統一入口
  // ============================================================

  /// 橋接行動推斷統一入口（覆蓋 #13）。
  /// L1 橋接類型關鍵字短路（信心 ≥0.9 直接回傳），否則走 L3 LLM。
  Future<BridgeActionInferenceResult?> inferBridgeAction({
    required String message,
    required List<({String role, String content})> history,
    bool hasImage = false,
  }) async {
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.inferBridgeAction(
      message: message,
      hasImage: hasImage,
    );
    if (l1Result != null && l1Result.confidence >= 0.9) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'bridge_action',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎
    final client = llmClient;
    if (client == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: 0,
        domain: 'bridge_action',
        fallbackUsed: true,
      );
      return null;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.inferBridgeAction(
      message: message,
      history: history,
      hasImage: hasImage,
    );
    stopwatch.stop();

    if (l3Result == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        domain: 'bridge_action',
        fallbackUsed: true,
      );
      return null;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'bridge_action',
      fallbackUsed: false,
    );

    _recordABLog(
      method: 'inferBridgeAction',
      l1Result: l1Result != null
          ? '${l1Result.bridgeType} (${l1Result.confidence.toStringAsFixed(2)})'
          : 'null',
      l3Result: '${l3Result.bridgeType} (${l3Result.confidence.toStringAsFixed(2)})',
      winner: l1Result != null ? 'L1' : 'L3',
    );

    return l3Result;
  }

  // ============================================================
  // Phase 3: extractOpenIntention —— 未完成意圖偵測統一入口
  // ============================================================

  /// 未完成意圖偵測統一入口（覆蓋 #15）。
  /// L1 RegExp 短路（信心 ≥0.9 直接回傳），否則走 L3 LLM。
  /// 背景執行，不影響使用者體驗。
  Future<OpenIntentionResult?> extractOpenIntention({
    required String message,
    required List<({String role, String content})> history,
  }) async {
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.extractOpenIntention(message: message);
    if (l1Result != null && l1Result.confidence >= 0.9) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'open_intention',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎
    final client = llmClient;
    if (client == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: 0,
        domain: 'open_intention',
        fallbackUsed: true,
      );
      return null;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.extractOpenIntention(
      message: message,
      history: history,
    );
    stopwatch.stop();

    if (l3Result == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        domain: 'open_intention',
        fallbackUsed: true,
      );
      return null;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'open_intention',
      fallbackUsed: false,
    );

    return l3Result;
  }

  // ============================================================
  // Phase 3: detectEmotion —— 情緒偵測統一入口
  // ============================================================

  /// 情緒偵測統一入口（覆蓋 #16）。
  /// L1 關鍵字 map 短路（信心 ≥0.9 直接回傳），否則走 L3 LLM。
  /// 背景執行，不影響使用者體驗。
  Future<EmotionResult?> detectEmotion({
    required String message,
    required List<({String role, String content})> history,
  }) async {
    final enabled = await _isFeatureEnabled();
    if (!enabled) return null;

    // L1 規則引擎
    final l1Result = _l1.detectEmotion(message: message);
    if (l1Result != null && l1Result.confidence >= 0.9) {
      _metrics.record(
        decisionPath: 'L1',
        confidence: l1Result.confidence,
        latencyMs: 0,
        domain: 'emotion',
        fallbackUsed: false,
      );
      return l1Result;
    }

    // L3 LLM 引擎
    final client = llmClient;
    if (client == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: 0,
        domain: 'emotion',
        fallbackUsed: true,
      );
      return null;
    }

    final l3 = L3LlmEngine(client);
    final stopwatch = Stopwatch()..start();
    final l3Result = await l3.detectEmotion(
      message: message,
      history: history,
    );
    stopwatch.stop();

    if (l3Result == null) {
      _metrics.record(
        decisionPath: 'L3_fallback',
        confidence: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        domain: 'emotion',
        fallbackUsed: true,
      );
      return null;
    }

    _metrics.record(
      decisionPath: 'L3',
      confidence: l3Result.confidence,
      latencyMs: stopwatch.elapsedMilliseconds,
      domain: 'emotion',
      fallbackUsed: false,
    );

    return l3Result;
  }
}
