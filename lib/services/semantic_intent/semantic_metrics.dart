// semantic_metrics.dart
// 語意理解決策的 in-memory metrics 記錄。
// 記錄每次決策的路徑（L1/L3/fallback）、信心、延遲等，供未來分析用。
// 不持久化，僅保留最近 100 筆。

/// 單筆語意理解決策記錄。
class SemanticMetricEntry {
  /// 決策路徑：'L1', 'L3', 'L3_fallback'
  final String decisionPath;

  /// 信心分數 0-1
  final double confidence;

  /// 延遲毫秒
  final int latencyMs;

  /// domain 名稱（如 'door'）
  final String domain;

  /// 是否使用了 fallback（回到既有正則）
  final bool fallbackUsed;

  /// 使用者是否事後修正（未來接線用，Sprint 1.1 恆為 false）
  final bool userCorrection;

  /// 時間戳
  final DateTime timestamp;

  const SemanticMetricEntry({
    required this.decisionPath,
    required this.confidence,
    required this.latencyMs,
    required this.domain,
    required this.fallbackUsed,
    this.userCorrection = false,
    required this.timestamp,
  });
}

/// 語意理解 metrics 收集器（in-memory）。
class SemanticMetrics {
  final List<SemanticMetricEntry> _entries = [];

  /// 最近 100 筆記錄（唯讀）
  List<SemanticMetricEntry> get entries => List.unmodifiable(_entries);

  /// 記錄一筆決策。
  void record({
    required String decisionPath,
    required double confidence,
    required int latencyMs,
    required String domain,
    required bool fallbackUsed,
    bool userCorrection = false,
  }) {
    _entries.add(SemanticMetricEntry(
      decisionPath: decisionPath,
      confidence: confidence,
      latencyMs: latencyMs,
      domain: domain,
      fallbackUsed: fallbackUsed,
      userCorrection: userCorrection,
      timestamp: DateTime.now(),
    ));
    // 只保留最近 100 筆
    if (_entries.length > 100) {
      _entries.removeAt(0);
    }
  }

  /// 清除所有記錄。
  void clear() => _entries.clear();
}
