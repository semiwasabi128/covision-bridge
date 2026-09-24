// attention_gate_rule.dart
// Sprint 1 — Layer 2: 注意力閘門（規則版）
// 原始邏輯：TransurfingBrainService._detectAttention，行為不變。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

class AttentionGateRule
    extends BrainLayerAnalyzer<String, AttentionState> {
  @override
  String get layerName => 'Attention Gate';

  @override
  int get layerIndex => 1;

  @override
  Future<LayerResult<AttentionState>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);

    // 從 priorLayers 拿 pendulum 結果（layer 2 的 pendulumSignals）
    final pendulumResult = context.priorLayers[2];
    final pendulumSignals = pendulumResult?.value as List<PendulumSignal>? ?? [];

    final hasPlatformPull = pendulumSignals.any(
      (signal) => signal.type == PendulumSignalType.platformPull,
    );
    AttentionState value;

    if (hasPlatformPull &&
        containsAny(text, ['新聞', '看到', '很多', '一堆', '不知道怎麼用'])) {
      value = AttentionState.captured;
    } else if (containsAny(
      text,
      ['好多', '一堆', '每個都', '不知道從哪裡', '一直看'],
    )) {
      value = AttentionState.scattered;
    } else {
      value = AttentionState.clear;
    }

    return LayerResult<AttentionState>(
      value: value,
      source: LayerSource.rule,
      evidence: value == AttentionState.captured
          ? '平台拉力 + 資訊量標記'
          : value == AttentionState.scattered
              ? '散亂標記命中'
              : '注意力清晰',
    );
  }
}
