// brain_layer_analyzer.dart
// Sprint 0 — 七層管線分析器介面 + 管線上下文
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// BrainLayerAnalyzer 是所有七層 analyzer 的統一介面。
// Sprint 1 的規則版 analyzer 與 Sprint 3~5 的 AI 版 analyzer 都實作此介面。
// PipelineContext 在層與層之間傳遞，讓後面的層可以讀前面的判斷結果。

import '../../models/transurfing_brain.dart';
import 'layer_result.dart';

/// 管線上下文——在七層之間傳遞的共享狀態。
///
/// 每層 analyzer 完成後，CEO pipeline 會呼叫 [copyWithPriorLayer]
/// 把結果塞進 priorLayers，下一層可以讀取。
class PipelineContext {
  /// 最近檢索到的記憶（從 BrainContainer 來）。
  final List<String> recentMemories;

  /// 目前活躍的夥伴角色名稱（例如「教練 Agent」「約瑟」）。
  final String? activeCompanionRole;

  /// 門決策上下文（專案門、卡點、待回流等）。
  final DoorDecisionContext doorContext;

  /// 前面層的判斷結果。key = layerIndex (0~6)。
  final Map<int, LayerResult<dynamic>> priorLayers;

  const PipelineContext({
    this.recentMemories = const [],
    this.activeCompanionRole,
    this.doorContext = const DoorDecisionContext(),
    this.priorLayers = const {},
  });

  /// 把第 [index] 層的結果加入，回傳新的 context（immutable）。
  PipelineContext copyWithPriorLayer(int index, LayerResult<dynamic> result) {
    final next = Map<int, LayerResult<dynamic>>.from(priorLayers);
    next[index] = result;
    return PipelineContext(
      recentMemories: recentMemories,
      activeCompanionRole: activeCompanionRole,
      doorContext: doorContext,
      priorLayers: next,
    );
  }
}

/// 七層分析器的統一介面。
///
/// 泛型 [TInput] 是該層的輸入類型，[TOutput] 是輸出類型。
/// Sprint 1 的規則版與 Sprint 3~5 的 AI 版都實作此介面。
///
/// 範例：
/// ```dart
/// class IntentClarifierRule extends BrainLayerAnalyzer<String, String> {
///   @override
///   String get layerName => 'Intent Clarifier';
///   @override
///   int get layerIndex => 0;
///   @override
///   Future<LayerResult<String>> analyze(String input, PipelineContext ctx) async { ... }
/// }
/// ```
abstract class BrainLayerAnalyzer<TInput, TOutput> {
  /// 層名稱（顯示用）。
  String get layerName;

  /// 層索引 0~6（對應七層管線的順序）。
  int get layerIndex;

  /// 執行該層判斷，回傳 [LayerResult]。
  Future<LayerResult<TOutput>> analyze(TInput input, PipelineContext context);
}
