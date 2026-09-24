// cost_tracker.dart
// Sprint 10 — LLM 成本追蹤
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 每輪 LLM 呼叫記 token + latency，
// 當日累計超過設定 → 自動切到規則版。
//
// 設計：
// - in-memory（重啟歸零）
// - 可注入 Clock 做跨日測試
// - threshold 可自訂（預設 10000 tokens/day）
// - 超額後 isOverLimit = true，AnalyzerRouter 據此切規則版

import 'pipeline_llm_client.dart';

/// 一筆 LLM 呼叫紀錄。
class LlmCallRecord {
  final String layerName;
  final int estimatedTokens;
  final int latencyMs;
  final bool succeeded;
  final String dateKey;
  final DateTime timestamp;

  const LlmCallRecord({
    required this.layerName,
    required this.estimatedTokens,
    required this.latencyMs,
    required this.succeeded,
    required this.dateKey,
    required this.timestamp,
  });
}

/// LLM 成本追蹤器。
///
/// 使用方式：
/// ```dart
/// final tracker = CostTracker(dailyTokenLimit: 10000);
/// // 每次 LLM 呼叫後：
/// tracker.recordCall(layerName: 'attention', tokens: 350, latencyMs: 800);
/// if (tracker.isOverLimit) {
///   // 切到規則版
/// }
/// ```
class CostTracker {
  /// 每日 token 上限
  final int dailyTokenLimit;

  /// 每日 latency 上限（毫秒，可選）
  final int? dailyLatencyLimitMs;

  /// dateKey → List<LlmCallRecord>
  final Map<String, List<LlmCallRecord>> _records = {};

  /// 可注入的時鐘
  final DateTime Function() _clock;

  /// 是否已觸發超額警示
  bool _limitNotified = false;

  CostTracker({
    this.dailyTokenLimit = 10000,
    this.dailyLatencyLimitMs,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 今天的 dateKey
  String get _todayKey => _formatDateKey(_clock());

  static String _formatDateKey(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)}';
  }

  /// 記錄一次 LLM 呼叫。
  void recordCall({
    required String layerName,
    required int tokens,
    required int latencyMs,
    required bool succeeded,
  }) {
    final dateKey = _todayKey;
    _records.putIfAbsent(dateKey, () => []);
    _records[dateKey]!.add(LlmCallRecord(
      layerName: layerName,
      estimatedTokens: tokens,
      latencyMs: latencyMs,
      succeeded: succeeded,
      dateKey: dateKey,
      timestamp: _clock(),
    ));
  }

  /// 今天的累計 token 數。
  int get todayTokenCount {
    final records = _records[_todayKey];
    if (records == null) return 0;
    return records.fold(0, (sum, r) => sum + r.estimatedTokens);
  }

  /// 今天的累計 latency（毫秒）。
  int get todayLatencyMs {
    final records = _records[_todayKey];
    if (records == null) return 0;
    return records.fold(0, (sum, r) => sum + r.latencyMs);
  }

  /// 今天的 LLM 呼叫次數。
  int get todayCallCount {
    final records = _records[_todayKey];
    return records?.length ?? 0;
  }

  /// 是否超過限制。
  bool get isOverLimit {
    if (todayTokenCount >= dailyTokenLimit) return true;
    if (dailyLatencyLimitMs != null && todayLatencyMs >= dailyLatencyLimitMs!) {
      return true;
    }
    return false;
  }

  /// 剩餘 token 額度。
  int get remainingTokens {
    final remaining = dailyTokenLimit - todayTokenCount;
    return remaining > 0 ? remaining : 0;
  }

  /// 取得今天的所有呼叫紀錄。
  List<LlmCallRecord> get todayRecords {
    return _records[_todayKey] ?? [];
  }

  /// 取得今天的 per-layer 統計。
  Map<String, int> get todayTokensByLayer {
    final records = _records[_todayKey] ?? [];
    final result = <String, int>{};
    for (final r in records) {
      result[r.layerName] = (result[r.layerName] ?? 0) + r.estimatedTokens;
    }
    return result;
  }

  /// 清除所有紀錄。
  void clear() {
    _records.clear();
    _limitNotified = false;
  }

  /// 粗估 token 數（從 prompt 字數估算）。
  /// 中文約 1 字 ≈ 1.5 token，英文約 4 字 ≈ 1 token。
  /// 這只是粗估，不需要精確。
  static int estimateTokens(String systemPrompt, String userPrompt) {
    final combined = '$systemPrompt$userPrompt';
    int cjkCount = 0;
    int otherCount = 0;
    for (final codeUnit in combined.codeUnits) {
      if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) {
        cjkCount++;
      } else {
        otherCount++;
      }
    }
    return (cjkCount * 1.5 + otherCount / 4).round();
  }
}
