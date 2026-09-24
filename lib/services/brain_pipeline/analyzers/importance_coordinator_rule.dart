// importance_coordinator_rule.dart
// Sprint 1 — Layer 4: 重要性協調（規則版）
// 原始邏輯：TransurfingBrainService._detectImportance，行為不變。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

class ImportanceCoordinatorRule
    extends BrainLayerAnalyzer<String, ImportanceLevel> {
  @override
  String get layerName => 'Importance Coordinator';

  @override
  int get layerIndex => 3;

  @override
  Future<LayerResult<ImportanceLevel>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);

    if (context.doorContext.hasActiveProject) {
      return const LayerResult<ImportanceLevel>(
        value: ImportanceLevel.elevated,
        source: LayerSource.rule,
        evidence: '有活躍專案門 → elevated',
      );
    }

    final pendulumResult = context.priorLayers[2];
    final pendulumSignals =
        pendulumResult?.value as List<PendulumSignal>? ?? [];

    var score = pendulumSignals.length;
    if (containsAny(text, ['一切都完了', '非做不可', '沒有退路'])) score += 3;
    if (containsAny(text, ['必須', '一定要', '不能失敗'])) score += 2;
    if (containsAny(text, ['趕快', '怕', '焦慮'])) score += 1;

    ImportanceLevel value;
    if (score >= 5) {
      value = ImportanceLevel.excessive;
    } else if (score >= 3) {
      value = ImportanceLevel.elevated;
    } else if (score == 0) {
      value = ImportanceLevel.low;
    } else {
      value = ImportanceLevel.balanced;
    }

    return LayerResult<ImportanceLevel>(
      value: value,
      source: LayerSource.rule,
      evidence: 'score=$score',
    );
  }
}
