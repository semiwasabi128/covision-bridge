// pendulum_detector_rule.dart
// Sprint 1 — Layer 3: 擺錘偵測（規則版）
// 原始邏輯：TransurfingBrainService._detectPendulums，行為不變。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../text_utils.dart';

class PendulumDetectorRule
    extends BrainLayerAnalyzer<String, List<PendulumSignal>> {
  @override
  String get layerName => 'Pendulum Detector';

  @override
  int get layerIndex => 2;

  @override
  Future<LayerResult<List<PendulumSignal>>> analyze(
    String input,
    PipelineContext context,
  ) async {
    final text = normalize(input);
    final signals = <PendulumSignal>[];

    _addSignalIfAny(signals, text, PendulumSignalType.urgency, '急迫感', [
      '趕快', '立刻', '馬上', '來不及', '錯過', '一定要', '必須',
    ]);
    _addSignalIfAny(signals, text, PendulumSignalType.fear, '恐懼與焦慮', [
      '怕', '焦慮', '完了', '失敗', '不安', '怎麼辦', '撐不住',
    ]);
    _addSignalIfAny(
      signals,
      text,
      PendulumSignalType.comparison,
      '比較與跟風',
      ['大家都', '別人', '新聞說', '很紅', '流行', '巨頭', '最新'],
    );
    _addSignalIfAny(signals, text, PendulumSignalType.proving, '證明自己', [
      '證明', '不輸', '贏過', '看得起', '我是不是不懂',
    ]);
    _addSignalIfAny(signals, text, PendulumSignalType.guilt, '義務與愧疚', [
      '應該', '對不起', '愧疚', '都是我的錯', '不得不',
    ]);
    _addSignalIfAny(
      signals,
      text,
      PendulumSignalType.platformPull,
      '平台拉力',
      aiServiceMarkers,
    );

    return LayerResult<List<PendulumSignal>>(
      value: signals,
      source: LayerSource.rule,
      evidence: signals.isEmpty
          ? '無擺錘訊號'
          : '偵測到 ${signals.length} 個擺錘：${signals.map((s) => s.label).join(', ')}',
    );
  }

  void _addSignalIfAny(
    List<PendulumSignal> signals,
    String text,
    PendulumSignalType type,
    String label,
    List<String> markers,
  ) {
    final marker = firstMarker(text, markers);
    if (marker == null) return;
    signals.add(PendulumSignal(type: type, label: label, evidence: marker));
  }
}
