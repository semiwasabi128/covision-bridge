// intent_clarifier_rule.dart
// Sprint 1 — Layer 1: 意圖澄清（規則版）
// 原始邏輯：TransurfingBrainService._clarifyIntent，行為不變。

import '../../../models/intent_spine.dart';
import '../../intent_spine_service.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

class IntentClarifierRule extends BrainLayerAnalyzer<String, String> {
  @override
  String get layerName => 'Intent Clarifier';

  @override
  int get layerIndex => 0;

  @override
  Future<LayerResult<String>> analyze(String input, PipelineContext context) async {
    final text = normalize(input);
    final role = context.activeCompanionRole == null
        ? ''
        : '${context.activeCompanionRole}：';
    final intentSpine = const IntentSpineService().analyze(text);
    String value;

    if (intentSpine.mode != IntentSpineMode.casual) {
      value = '$role${intentSpine.userFacingSummary}';
    } else if (containsAny(text, aiServiceMarkers)) {
      value = '$role想把外部 AI 服務轉成自己的可用能力。';
    } else if (containsAny(text, ['繼續', '下一步', '開始做', '執行'])) {
      value = '$role想推進目前橋樑計畫的下一個可交付切片。';
    } else if (containsAny(text, ['值得', '審視', '評估', '判斷'])) {
      value = '$role想重新判斷方向是否符合真正目標。';
    } else if (containsAny(text, ['卡住', '不知道', '不懂', '複雜'])) {
      value = '$role想降低阻力，找到能走進去的門。';
    } else {
      value = '$role想獲得回應並維持目前對話水流。';
    }

    return LayerResult<String>(
      value: value,
      source: LayerSource.rule,
      evidence: 'IntentSpine mode=${intentSpine.mode.name}',
    );
  }
}
