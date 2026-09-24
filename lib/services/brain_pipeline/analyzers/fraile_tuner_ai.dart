// fraile_tuner_ai.dart
// Sprint 4 — Layer 5b: 頻率共振（AI 版）
// 根據心腦對齊 + 擺錘訊號 + 近期行動評估頻率，輸出趨勢說明。
// 規則版只能靠關鍵字判斷 strong/present/weak/obscured，AI 版能綜合評估。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';

const _systemPrompt = '''你是一個頻率共振分析器。在 Reality Transurfing 的框架中，「頻率」是指一個人是否活在自己的本真狀態。

頻率等級：
- strong: 使用者明確在做自己想做的事，有自己的風格和節奏
- present: 有一些自己的聲音，但還不夠堅定
- weak: 大部分在回應外部需求，自己的聲音很微弱
- obscured: 被比較、平台拉力或外部結構完全蓋過，看不到自己的頻率

你會收到使用者的訊息、心腦對齊狀態、擺錘訊號、和近期記憶。
請綜合評估頻率等級，並用一句話寫出 evidence，說明為什麼。

請輸出一行 JSON，不要加 markdown code block：
{"resonance": "strong|present|weak|obscured", "evidence": "一句話說明頻率趨勢"}''';

class FraileTunerAI extends BrainLayerAnalyzer<String, FraileResonance> {
  final PipelineLLMClient llmClient;

  FraileTunerAI(this.llmClient);

  @override
  String get layerName => 'Fraile Tuner (AI)';

  @override
  int get layerIndex => 5;

  @override
  Future<LayerResult<FraileResonance>> analyze(
    String input,
    PipelineContext context,
  ) async {
    if (!llmClient.isAvailable) {
      return LayerResult<FraileResonance>(
        value: FraileResonance.weak,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 不可用，fallback to weak',
      );
    }

    // 組裝 context
    final alignmentResult = context.priorLayers[4];
    final alignment = alignmentResult?.value as HeartMindAlignment? ??
        HeartMindAlignment.unknown;

    final pendulumResult = context.priorLayers[2];
    final pendulumSignals =
        pendulumResult?.value as List<PendulumSignal>? ?? [];
    final pendulumSummary = pendulumSignals.isEmpty
        ? '無'
        : pendulumSignals.map((s) => s.label).join(', ');

    final recentMemories = context.recentMemories.isEmpty
        ? '無近期記憶'
        : context.recentMemories.take(5).join(' / ');

    final userPrompt = '使用者訊息：$input\n'
        '心腦對齊：${alignment.name}\n'
        '擺錘訊號：$pendulumSummary\n'
        '近期記憶：$recentMemories';

    final response = await llmClient.complete(
      systemPrompt: _systemPrompt,
      userPrompt: userPrompt,
    );

    if (!response.succeeded) {
      return LayerResult<FraileResonance>(
        value: FraileResonance.weak,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 呼叫失敗，fallback to weak',
      );
    }

    final json = safeJsonParse(response.content) as Map<String, dynamic>?;
    if (json == null) {
      return LayerResult<FraileResonance>(
        value: FraileResonance.weak,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 回應無法解析 JSON',
      );
    }

    final resonanceStr = json['resonance'] as String? ?? 'weak';
    final evidence = json['evidence'] as String? ?? '';

    FraileResonance resonance;
    switch (resonanceStr.toLowerCase().trim()) {
      case 'strong':
        resonance = FraileResonance.strong;
      case 'present':
        resonance = FraileResonance.present;
      case 'obscured':
        resonance = FraileResonance.obscured;
      default:
        resonance = FraileResonance.weak;
    }

    return LayerResult<FraileResonance>(
      value: resonance,
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: evidence,
      latencyMs: response.latencyMs,
      metadata: {
        if (evidence.isNotEmpty) 'fraileEvidence': evidence,
      },
    );
  }
}
