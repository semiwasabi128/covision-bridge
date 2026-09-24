// fraile_tuner_rule.dart
// Sprint 1 — Layer 5b: 頻率共振（規則版）
// 原始邏輯：TransurfingBrainService._detectFraileResonance，行為不變。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

class FraileTunerRule extends BrainLayerAnalyzer<String, FraileResonance> {
  @override
  String get layerName => 'Fraile Tuner';

  @override
  int get layerIndex => 5;

  @override
  Future<LayerResult<FraileResonance>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);

    final alignmentResult = context.priorLayers[4];
    final alignment = alignmentResult?.value as HeartMindAlignment? ??
        HeartMindAlignment.unknown;

    final pendulumResult = context.priorLayers[2];
    final pendulumSignals =
        pendulumResult?.value as List<PendulumSignal>? ?? [];

    FraileResonance value;

    if (alignment == HeartMindAlignment.aligned &&
        containsAny(text, ['自己', '我的', '喜歡', '創作', '夥伴', '風格'])) {
      value = FraileResonance.strong;
    } else if (containsAny(
      text,
      ['我的需求', '我的喜好', '自己取', '自己的名字'],
    )) {
      value = FraileResonance.present;
    } else if (pendulumSignals.any(
      (signal) =>
          signal.type == PendulumSignalType.comparison ||
          signal.type == PendulumSignalType.platformPull,
    )) {
      value = FraileResonance.obscured;
    } else {
      value = FraileResonance.weak;
    }

    return LayerResult<FraileResonance>(
      value: value,
      source: LayerSource.rule,
      evidence: 'alignment=$alignment',
    );
  }
}
