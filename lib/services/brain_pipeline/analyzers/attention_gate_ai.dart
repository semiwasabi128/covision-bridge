// attention_gate_ai.dart
// Sprint 3 — Layer 1: 注意力閘門（AI 版）
// 用 LLM 做語意判斷，區分 clear / captured / scattered。
// 規則版只能靠關鍵字，AI 版能理解「我被新聞拉走了」這種沒有命中關鍵字的語意。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';

/// AttentionGate 的 AI prompt 模板（硬編碼，不讀 .md 檔——管線不需要 I/O）。
const _systemPrompt = '''你是一個注意力狀態分析器。你會收到使用者的一句話，判斷他的注意力處於什麼狀態。

狀態定義：
- clear: 注意力清醒，意圖明確，知道自己在做什麼。
- captured: 注意力被某則新聞、平台貼文、或外部資訊捕獲，注意力被拉走但聚焦在單一外部來源。
- scattered: 注意力散亂，資訊流過載，不知道從哪裡開始，感覺 overwhelmed。

請輸出一行 JSON，不要加 markdown code block：
{"state": "clear|captured|scattered", "evidence": "一句話解釋為什麼"}''';

class AttentionGateAI extends BrainLayerAnalyzer<String, AttentionState> {
  final PipelineLLMClient llmClient;

  AttentionGateAI(this.llmClient);

  @override
  String get layerName => 'Attention Gate (AI)';

  @override
  int get layerIndex => 1;

  @override
  Future<LayerResult<AttentionState>> analyze(
    String input,
    PipelineContext context,
  ) async {
    if (!llmClient.isAvailable) {
      return LayerResult<AttentionState>(
        value: AttentionState.clear,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 不可用，fallback to clear',
      );
    }

    final response = await llmClient.complete(
      systemPrompt: _systemPrompt,
      userPrompt: '使用者訊息：$input',
    );

    if (!response.succeeded) {
      return LayerResult<AttentionState>(
        value: AttentionState.clear,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 呼叫失敗，fallback to clear',
      );
    }

    final json = safeJsonParse(response.content) as Map<String, dynamic>?;
    if (json == null) {
      return LayerResult<AttentionState>(
        value: AttentionState.clear,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 回應無法解析 JSON',
      );
    }

    final stateStr = json['state'] as String? ?? 'clear';
    final evidence = json['evidence'] as String? ?? '';

    AttentionState state;
    switch (stateStr.toLowerCase()) {
      case 'captured':
        state = AttentionState.captured;
      case 'scattered':
        state = AttentionState.scattered;
      default:
        state = AttentionState.clear;
    }

    return LayerResult<AttentionState>(
      value: state,
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: evidence,
      latencyMs: response.latencyMs,
    );
  }
}
