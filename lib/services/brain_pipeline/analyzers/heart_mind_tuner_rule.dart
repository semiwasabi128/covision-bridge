// heart_mind_tuner_rule.dart
// Sprint 1 — Layer 5a: 心腦合一（規則版）
// 原始邏輯：TransurfingBrainService._detectHeartMindAlignment，行為不變。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

class HeartMindTunerRule
    extends BrainLayerAnalyzer<String, HeartMindAlignment> {
  @override
  String get layerName => 'Heart-Mind Tuner';

  @override
  int get layerIndex => 4;

  @override
  Future<LayerResult<HeartMindAlignment>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);

    final hasContrast = containsAny(text, ['可是', '但是', '但', '不過']);
    final hasWant = containsAny(text, ['想', '希望', '喜歡', '需要']);
    final hasDiscomfort =
        containsAny(text, ['不想', '壓力', '痛苦', '勉強', '卡住']);
    final hasEnergy =
        containsAny(text, ['喜歡', '太棒', '興奮', '有感覺', '自然']);

    HeartMindAlignment value;
    if (hasDiscomfort && (hasWant || hasContrast)) {
      value = HeartMindAlignment.conflicted;
    } else if (hasContrast && hasWant) {
      value = HeartMindAlignment.mixed;
    } else if (hasEnergy) {
      value = HeartMindAlignment.aligned;
    } else {
      value = HeartMindAlignment.unknown;
    }

    return LayerResult<HeartMindAlignment>(
      value: value,
      source: LayerSource.rule,
      evidence: 'contrast=$hasContrast, want=$hasWant, discomfort=$hasDiscomfort, energy=$hasEnergy',
    );
  }
}
