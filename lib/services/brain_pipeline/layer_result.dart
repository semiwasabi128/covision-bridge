// layer_result.dart
// Sprint 0 — 七層管線的通用層結果容器
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 每一層 analyzer 的 analyze() 都回傳 LayerResult<T>，
// 攜帶 source / confidence / evidence / latencyMs 供監控面板與 fallback 決策使用。

/// 層結果的來源標記。
enum LayerSource {
  /// LLM 驅動判斷
  ai,

  /// 規則版（關鍵字比對）
  rule,

  /// 快取命中（同一輪已跑過）
  cached,

  /// AI + 規則混合策略
  mixed,
}

/// 通用層結果容器。
///
/// 泛型 [T] 是該層判斷的輸出類型，例如：
/// - Layer 1 Intent → `LayerResult<String>`
/// - Layer 2 Attention → `LayerResult<AttentionState>`
/// - Layer 3 Pendulum → `LayerResult<List<PendulumSignal>>`
class LayerResult<T> {
  /// 該層的判斷結果值。
  final T value;

  /// 結果來源（AI / 規則 / 快取 / 混合）。
  final LayerSource source;

  /// 信心分數 0.0 ~ 1.0。規則版預設 1.0，AI 版由 LLM 回傳。
  final double confidence;

  /// 一句話依據（例如「命中關鍵字：急迫感」或 LLM 的 evidence_quote）。
  final String evidence;

  /// 該層執行耗時（毫秒）。
  final int latencyMs;

  /// Sprint 4 新增：可選的中繼資料，供 AI analyzer 傳遞 hint 等附加資訊。
  /// 規則版不填（預設空 Map），AI 版可塞 humorHint / mindStatement 等。
  /// Pipeline 會從這裡收集 GuidanceHint。
  final Map<String, dynamic> metadata;

  const LayerResult({
    required this.value,
    required this.source,
    this.confidence = 1.0,
    this.evidence = '',
    this.latencyMs = 0,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'LayerResult($source, conf=$confidence, ${latencyMs}ms, evidence="$evidence")';
}
