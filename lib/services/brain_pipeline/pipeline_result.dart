// pipeline_result.dart
// Sprint 0 — 管線最終結果容器
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// PipelineResult 包裝七層跑完後的全部產出：
// - 最終的 BrainReflection（向下相容現有 chat_controller / panel）
// - 每層的 LayerResult（供 Sprint 6 監控面板 v2 顯示）
// - 總耗時與來源分布

import '../../models/transurfing_brain.dart';
import 'layer_result.dart';

/// 管線的來源分布。
enum PipelineSource {
  /// 全部七層都走規則版
  allRule,

  /// 部分層走 AI、部分走規則
  mixed,

  /// 全部七層都走 AI
  allAi,
}

/// 七層管線的最終結果。
///
/// Sprint 1 的 TransurfingPipeline.analyzeAsync() 回傳此物件。
/// Sprint 0 只定義結構，不使用。
class PipelineResult {
  /// 最終的 BrainReflection（向下相容）。
  final BrainReflection reflection;

  /// 每層的 LayerResult，key = 層名（例如 'intent', 'attention', 'pendulum'...）。
  final Map<String, LayerResult<dynamic>> layerResults;

  /// 七層總耗時（毫秒）。
  final int totalLatencyMs;

  /// 來源分布。
  final PipelineSource source;

  const PipelineResult({
    required this.reflection,
    this.layerResults = const {},
    this.totalLatencyMs = 0,
    this.source = PipelineSource.allRule,
  });
}
