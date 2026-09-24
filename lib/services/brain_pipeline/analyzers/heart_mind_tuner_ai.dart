// heart_mind_tuner_ai.dart
// Sprint 4 — Layer 5a: 心腦合一（AI 版）
// 用 LLM 抽取心智立場、心立場、分裂標記，並輸出整合引導句。
// 規則版只能判斷 aligned/mixed/conflicted/unknown，AI 版能輸出具體引導。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';

const _systemPrompt = '''你是一個心腦合一分析器。你要從使用者的訊息中，分別找出「心智的立場」和「心的立場」。

- mindStatement：使用者理智上認為應該做的事或應該遵從的立場（一句話）
- heartStatement：使用者內心真正想做的事或感受（一句話）
- splitMarker：兩者最尖銳對立的那個詞或短語（從使用者原文中提取，例如「可是」「但是」「不過」）
- integrationPrompt：一句幫助使用者整合兩邊的引導句（例如「如果兩邊都對，你最想先聽哪邊？」）

alignment 判斷：
- aligned: 心和心智方向一致
- mixed: 有一些不一致但不到尖銳衝突
- conflicted: 明顯的內心撕裂，心和心智對立
- unknown: 訊息太短或不明確，無法判斷

如果使用者的訊息沒有明顯的心腦分裂，mindStatement/heartStatement/splitMarker 可以為空字串，alignment 設為 aligned 或 unknown。

請輸出一行 JSON，不要加 markdown code block：
{"alignment": "aligned|mixed|conflicted|unknown", "mind_statement": "...", "heart_statement": "...", "split_marker": "...", "integration_prompt": "..."}''';

class HeartMindTunerAI
    extends BrainLayerAnalyzer<String, HeartMindAlignment> {
  final PipelineLLMClient llmClient;

  HeartMindTunerAI(this.llmClient);

  @override
  String get layerName => 'Heart-Mind Tuner (AI)';

  @override
  int get layerIndex => 4;

  @override
  Future<LayerResult<HeartMindAlignment>> analyze(
    String input,
    PipelineContext context,
  ) async {
    if (!llmClient.isAvailable) {
      return LayerResult<HeartMindAlignment>(
        value: HeartMindAlignment.unknown,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 不可用，fallback to unknown',
      );
    }

    final response = await llmClient.complete(
      systemPrompt: _systemPrompt,
      userPrompt: '使用者訊息：$input',
    );

    if (!response.succeeded) {
      return LayerResult<HeartMindAlignment>(
        value: HeartMindAlignment.unknown,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 呼叫失敗，fallback to unknown',
      );
    }

    final json = safeJsonParse(response.content) as Map<String, dynamic>?;
    if (json == null) {
      return LayerResult<HeartMindAlignment>(
        value: HeartMindAlignment.unknown,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 回應無法解析 JSON',
      );
    }

    final alignmentStr = json['alignment'] as String? ?? 'unknown';
    final mindStatement = json['mind_statement'] as String? ?? '';
    final heartStatement = json['heart_statement'] as String? ?? '';
    final splitMarker = json['split_marker'] as String? ?? '';
    final integrationPrompt = json['integration_prompt'] as String? ?? '';

    HeartMindAlignment alignment;
    switch (alignmentStr.toLowerCase().trim()) {
      case 'aligned':
        alignment = HeartMindAlignment.aligned;
      case 'mixed':
        alignment = HeartMindAlignment.mixed;
      case 'conflicted':
        alignment = HeartMindAlignment.conflicted;
      default:
        alignment = HeartMindAlignment.unknown;
    }

    return LayerResult<HeartMindAlignment>(
      value: alignment,
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: 'mind="$mindStatement", heart="$heartStatement"',
      latencyMs: response.latencyMs,
      metadata: {
        if (mindStatement.isNotEmpty) 'mindStatement': mindStatement,
        if (heartStatement.isNotEmpty) 'heartStatement': heartStatement,
        if (splitMarker.isNotEmpty) 'splitMarker': splitMarker,
        if (integrationPrompt.isNotEmpty) 'integrationPrompt': integrationPrompt,
      },
    );
  }
}
