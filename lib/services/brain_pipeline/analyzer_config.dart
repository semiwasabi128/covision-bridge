// analyzer_config.dart
// Sprint 0 — 管線分析器全域配置
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 控制每層要走 AI 還是規則版、AI 逾時、最低信心覆寫門檻等。
// Sprint 10 的 AnalyzerRouter 會讀這份配置決定每層實際呼叫哪個 analyzer。

/// 每層可選擇的判斷路徑。
enum AnalyzerKind {
  /// 強制走規則版
  rule,

  /// 強制走 AI 版
  ai,

  /// 自動：信心夠高走規則版省成本，不夠才呼叫 AI
  auto,
}

/// 管線全域配置。
///
/// 預設 `globalAiEnabled = false`——在 Sprint 3~5 的 AI analyzer 落地前，
/// 所有層都走規則版。Sprint 10 的 CostTracker 可以在運行時翻轉此旗標。
class AnalyzerConfig {
  /// 每層獨立的路徑覆寫。key = layerIndex (0~6)，value = 強制模式。
  /// 未指定者預設 `AnalyzerKind.auto`。
  final Map<int, AnalyzerKind> layerOverrides;

  /// AI 呼叫逾時（毫秒）。逾時自動降級到規則版。
  final int aiTimeoutMs;

  /// AI 版信心低於此值時，不改覆規則版結果。
  final double aiMinConfidenceForOverride;

  /// 全域 AI 開關。false 時所有層強制走規則版。
  final bool globalAiEnabled;

  const AnalyzerConfig({
    this.layerOverrides = const {},
    this.aiTimeoutMs = 3000,
    this.aiMinConfidenceForOverride = 0.6,
    this.globalAiEnabled = false,
  });

  /// 取得指定層的路徑模式。
  AnalyzerKind kindForLayer(int layerIndex) {
    return layerOverrides[layerIndex] ?? AnalyzerKind.auto;
  }

  /// 複製並修改配置（用於 Sprint 10 的動態切換）。
  AnalyzerConfig copyWith({
    Map<int, AnalyzerKind>? layerOverrides,
    int? aiTimeoutMs,
    double? aiMinConfidenceForOverride,
    bool? globalAiEnabled,
  }) {
    return AnalyzerConfig(
      layerOverrides: layerOverrides ?? this.layerOverrides,
      aiTimeoutMs: aiTimeoutMs ?? this.aiTimeoutMs,
      aiMinConfidenceForOverride:
          aiMinConfidenceForOverride ?? this.aiMinConfidenceForOverride,
      globalAiEnabled: globalAiEnabled ?? this.globalAiEnabled,
    );
  }
}
