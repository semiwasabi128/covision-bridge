// importance_coordinator_ai.dart
// Sprint 4 — Layer 4: 重要性協調（AI 版）
// 用 LLM 判斷過度重要 vs 平衡 vs 偏低，並輸出幽默化解句 humorHint。
// 規則版只能靠關鍵字計分，AI 版能理解「被看笑話」這種語意上的過度重要。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';

const _systemPrompt = '''你是一個重要性判斷器。在 Reality Transurfing 的框架中，過度重要（excessive importance）是最大的能量消耗來源。

判斷等級：
- excessive: 使用者把這件事看得太重，附帶「非做不可」「否則完蛋」「被看笑話」等災難化心態。
- elevated: 比正常重視多一點，有壓力但不到災難化。
- balanced: 正常的重視程度。
- low: 顯得無所謂或敷衍。

同時輸出一個幽默化解句 humorHint——用一句話幫使用者把過度重要的感覺鬆開。
範例：「試試看把這件事寫成笑話給朋友聽，看看是否還那麼嚴重」
如果等級是 low 或 balanced，humorHint 可以為空字串。

請輸出一行 JSON，不要加 markdown code block：
{"level": "excessive|elevated|balanced|low", "humor_hint": "一句幽默化解句或空字串", "evidence": "一句話解釋為什麼"}''';

class ImportanceCoordinatorAI
    extends BrainLayerAnalyzer<String, ImportanceLevel> {
  final PipelineLLMClient llmClient;

  ImportanceCoordinatorAI(this.llmClient);

  @override
  String get layerName => 'Importance Coordinator (AI)';

  @override
  int get layerIndex => 3;

  @override
  Future<LayerResult<ImportanceLevel>> analyze(
    String input,
    PipelineContext context,
  ) async {
    if (!llmClient.isAvailable) {
      return LayerResult<ImportanceLevel>(
        value: ImportanceLevel.balanced,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 不可用，fallback to balanced',
      );
    }

    // 組裝 context：把擺錘訊號和門上下文傳給 LLM
    final pendulumResult = context.priorLayers[2];
    final pendulumSignals =
        pendulumResult?.value as List<PendulumSignal>? ?? [];
    final pendulumSummary = pendulumSignals.isEmpty
        ? '無擺錘訊號'
        : pendulumSignals.map((s) => '${s.label}(${s.type.name})').join(', ');
    final hasActiveProject = context.doorContext.hasActiveProject;

    final userPrompt = '使用者訊息：$input\n'
        '擺錘訊號：$pendulumSummary\n'
        '有活躍專案門：${hasActiveProject ? "是" : "否"}';

    final response = await llmClient.complete(
      systemPrompt: _systemPrompt,
      userPrompt: userPrompt,
    );

    if (!response.succeeded) {
      return LayerResult<ImportanceLevel>(
        value: ImportanceLevel.balanced,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 呼叫失敗，fallback to balanced',
      );
    }

    final json = safeJsonParse(response.content) as Map<String, dynamic>?;
    if (json == null) {
      return LayerResult<ImportanceLevel>(
        value: ImportanceLevel.balanced,
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 回應無法解析 JSON',
      );
    }

    final levelStr = json['level'] as String? ?? 'balanced';
    final humorHint = json['humor_hint'] as String? ?? '';
    final evidence = json['evidence'] as String? ?? '';

    ImportanceLevel level;
    switch (levelStr.toLowerCase().trim()) {
      case 'excessive':
        level = ImportanceLevel.excessive;
      case 'elevated':
        level = ImportanceLevel.elevated;
      case 'low':
        level = ImportanceLevel.low;
      default:
        level = ImportanceLevel.balanced;
    }

    return LayerResult<ImportanceLevel>(
      value: level,
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: evidence,
      latencyMs: response.latencyMs,
      metadata: {
        if (humorHint.isNotEmpty) 'humorHint': humorHint,
      },
    );
  }
}
