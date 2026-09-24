// pendulum_detector_ai.dart
// Sprint 3 — Layer 2: 擺錘偵測（AI 版）
// 用 LLM 做語意判斷，能偵測規則版看不到的 infoPoisoning / platformCapture / clipConsumption。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';

/// PendulumDetector 的 AI prompt 模板。
const _systemPrompt = '''你是一個「擺錘」偵測器。在 Reality Transurfing 的框架中，「擺錘」是那些會消耗使用者能量、把注意力拉離真正目標的外部結構性力量。

九種擺錘類型：
1. urgency（急迫感）：訊息含有「非現在不可」的壓力，但不是真正的緊急。
2. fear（恐懼與焦慮）：訊息反映恐懼、焦慮、完蛋了的心態。
3. comparison（比較與跟風）：訊息顯示使用者正在跟別人比較或盲目跟風。
4. proving（證明自己）：訊息顯示使用者試圖證明自己不輸人。
5. guilt（義務與愧疚）：訊息含有應該、不得不、愧疚的語調。
6. platformPull（平台拉力）：訊息提到 AI 服務/平台/工具，注意力被工具本身拉走。
7. infoPoisoning（資訊中毒）：吸收大量互相矛盾的資訊源，不知道該信誰。
8. platformCapture（平台捕獲）：被特定平台演算法拉住，如社群媒體無意識滑動。
9. clipConsumption（短影音過量）：刷短影音/shorts/TikTok/Reels 過量，消耗注意力。

請輸出 JSON 陣列，每個元素代表一個偵測到的擺錘。如果沒有偵測到任何擺錘，輸出空陣列 []。
不要加 markdown code block。每個 evidence_quote 必須是使用者訊息中的真實片段。

格式：
[{"type": "urgency", "label": "急迫感", "evidence_quote": "使用者訊息中的原文片段"}]

擺錘 label 對照：
- urgency → 急迫感
- fear → 恐懼與焦慮
- comparison → 比較與跟風
- proving → 證明自己
- guilt → 義務與愧疚
- platformPull → 平台拉力
- infoPoisoning → 資訊中毒
- platformCapture → 平台捕獲
- clipConsumption → 短影音過量''';

class PendulumDetectorAI
    extends BrainLayerAnalyzer<String, List<PendulumSignal>> {
  final PipelineLLMClient llmClient;

  PendulumDetectorAI(this.llmClient);

  @override
  String get layerName => 'Pendulum Detector (AI)';

  @override
  int get layerIndex => 2;

  @override
  Future<LayerResult<List<PendulumSignal>>> analyze(
    String input,
    PipelineContext context,
  ) async {
    if (!llmClient.isAvailable) {
      return LayerResult<List<PendulumSignal>>(
        value: const [],
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 不可用',
      );
    }

    final response = await llmClient.complete(
      systemPrompt: _systemPrompt,
      userPrompt: '使用者訊息：$input',
    );

    if (!response.succeeded) {
      return LayerResult<List<PendulumSignal>>(
        value: const [],
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 呼叫失敗',
      );
    }

    final json = safeJsonParse(response.content);
    if (json == null) {
      return LayerResult<List<PendulumSignal>>(
        value: const [],
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 回應無法解析 JSON',
      );
    }

    final List<dynamic> items = json is List ? json : [];
    final signals = <PendulumSignal>[];

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final typeStr = item['type'] as String? ?? '';
      final label = item['label'] as String? ?? '';
      final evidence = item['evidence_quote'] as String? ??
          item['evidence'] as String? ??
          '';

      final type = _parseType(typeStr);
      if (type == null) continue;

      signals.add(PendulumSignal(
        type: type,
        label: label.isNotEmpty ? label : _defaultLabel(type),
        evidence: evidence,
        source: PendulumSignalSource.aiInferred,
      ));
    }

    return LayerResult<List<PendulumSignal>>(
      value: signals,
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: signals.isEmpty
          ? 'AI 未偵測到擺錘'
          : 'AI 偵測到 ${signals.length} 個擺錘',
      latencyMs: response.latencyMs,
    );
  }

  PendulumSignalType? _parseType(String s) {
    switch (s.toLowerCase().trim()) {
      case 'urgency':
        return PendulumSignalType.urgency;
      case 'fear':
        return PendulumSignalType.fear;
      case 'comparison':
        return PendulumSignalType.comparison;
      case 'proving':
        return PendulumSignalType.proving;
      case 'guilt':
        return PendulumSignalType.guilt;
      case 'platformpull':
        return PendulumSignalType.platformPull;
      case 'infopoisoning':
        return PendulumSignalType.infoPoisoning;
      case 'platformcapture':
        return PendulumSignalType.platformCapture;
      case 'clipconsumption':
        return PendulumSignalType.clipConsumption;
      default:
        return null;
    }
  }

  String _defaultLabel(PendulumSignalType type) {
    switch (type) {
      case PendulumSignalType.urgency:
        return '急迫感';
      case PendulumSignalType.fear:
        return '恐懼與焦慮';
      case PendulumSignalType.comparison:
        return '比較與跟風';
      case PendulumSignalType.proving:
        return '證明自己';
      case PendulumSignalType.guilt:
        return '義務與愧疚';
      case PendulumSignalType.platformPull:
        return '平台拉力';
      case PendulumSignalType.infoPoisoning:
        return '資訊中毒';
      case PendulumSignalType.platformCapture:
        return '平台捕獲';
      case PendulumSignalType.clipConsumption:
        return '短影音過量';
    }
  }
}
