// door_flow_detector_ai.dart
// Sprint 5 — Layer 6: 門與水流偵測（AI 版）
// 用 LLM 做語意判斷，能偵測規則版看不到的門候選。
// AI 版產生的門候選 source 為 aiInferred；contextDriven 來自規則版的 DoorDecisionContext。

import '../../../models/transurfing_brain.dart';
import '../brain_layer_analyzer.dart';
import '../layer_result.dart';
import '../pipeline_llm_client.dart';
import 'door_flow_detector_rule.dart';

/// DoorFlowDetector 的 AI prompt 模板（硬編碼，不讀 .md 檔——管線不需要 I/O）。
const _systemPrompt = '''你是一個「門與水流」偵測器。在 Reality Transurfing 的框架中，「門」是使用者面前真實存在的選擇路徑，「水流」是使用者目前行動的順暢程度。

四種門類型：
1. ownDoor（自己的門）：使用者自己的目標、專案、創作方向。訊息中反映使用者的真實需求或長期方向。
2. foreignDoor（外部門）：外部平台、新聞、工具的門。注意力被外部資訊拉走，不是使用者自己的目標。
3. falseDoor（假門）：不合理的承諾、捷徑、快速致富。看起來像機會但實際上是陷阱。
4. currentLink（當前鏈結）：目前工作鏈的下一環。使用者正在要求推進已確認的路徑。

水流狀態：
- withFlow：順流——使用者感覺順暢、自然、有進展。
- againstFlow：逆流——使用者感覺卡住、複雜、一直失敗。
- stalled：停滯——沒有進展、空轉。
- unknown：無法判斷。

請輸出 JSON 物件，不要加 markdown code block：
{"doors": [{"kind": "ownDoor", "label": "門的名稱", "reason": "為什麼這是一扇門"}], "flowState": "withFlow"}

如果沒有偵測到任何門，doors 為空陣列 []。每個 reason 必須是一句繁體中文解釋。

範例：
使用者：「我想把橋樑計畫的下一個 sprint 做完」
回應：{"doors": [{"kind": "ownDoor", "label": "橋樑計畫", "reason": "使用者明確提到自己的專案方向"}, {"kind": "currentLink", "label": "下一個 sprint", "reason": "使用者要推進已確認的下一步"}], "flowState": "withFlow"}

使用者：「我看到一個新的 AI 工具可以自動寫程式，好像很厲害」
回應：{"doors": [{"kind": "foreignDoor", "label": "新 AI 工具", "reason": "注意力被外部工具吸引，不是使用者自己的目標"}], "flowState": "unknown"}

使用者：「這個投資保證月賺 30%，不用做什麼」
回應：{"doors": [{"kind": "falseDoor", "label": "保證獲利投資", "reason": "不合理承諾與捷徑誘惑"}], "flowState": "unknown"}

使用者：「卡住了，不知道怎麼往下走」
回應：{"doors": [], "flowState": "againstFlow"}

使用者：「你好」
回應：{"doors": [], "flowState": "unknown"}''';

class DoorFlowDetectorAI
    extends BrainLayerAnalyzer<String, DoorFlowResult> {
  final PipelineLLMClient llmClient;

  DoorFlowDetectorAI(this.llmClient);

  @override
  String get layerName => 'Door & Flow Detector (AI)';

  @override
  int get layerIndex => 6;

  @override
  Future<LayerResult<DoorFlowResult>> analyze(
    String input,
    PipelineContext context,
  ) async {
    if (!llmClient.isAvailable) {
      return LayerResult<DoorFlowResult>(
        value: const DoorFlowResult(
          doors: [],
          doorDecision: null,
          flowState: FlowState.unknown,
        ),
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
      return LayerResult<DoorFlowResult>(
        value: const DoorFlowResult(
          doors: [],
          doorDecision: null,
          flowState: FlowState.unknown,
        ),
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 呼叫失敗',
      );
    }

    final json = safeJsonParse(response.content) as Map<String, dynamic>?;
    if (json == null) {
      return LayerResult<DoorFlowResult>(
        value: const DoorFlowResult(
          doors: [],
          doorDecision: null,
          flowState: FlowState.unknown,
        ),
        source: LayerSource.ai,
        confidence: 0.0,
        evidence: 'LLM 回應無法解析 JSON',
      );
    }

    // 解析 doors
    final doors = <DoorCandidate>[];
    final doorsJson = json['doors'] as List<dynamic>? ?? [];
    for (final item in doorsJson) {
      if (item is! Map<String, dynamic>) continue;
      final kindStr = item['kind'] as String? ?? '';
      final label = item['label'] as String? ?? '';
      final reason = item['reason'] as String? ?? '';
      final kind = _parseDoorKind(kindStr);
      if (kind == null || label.isEmpty) continue;
      doors.add(DoorCandidate(
        kind: kind,
        label: label,
        reason: reason,
        source: DoorCandidateSource.aiInferred,
      ));
    }

    // 解析 flowState
    final flowStr = json['flowState'] as String? ?? 'unknown';
    final flowState = _parseFlowState(flowStr);

    return LayerResult<DoorFlowResult>(
      value: DoorFlowResult(
        doors: doors,
        doorDecision: null, // AI 版不產生 doorDecision——規則版的 contextual decision 更可靠
        flowState: flowState,
      ),
      source: LayerSource.ai,
      confidence: 0.8,
      evidence: doors.isEmpty
          ? 'AI 偵測到 0 門, flow=${flowState.name}'
          : 'AI 偵測到 ${doors.length} 門 (${doors.map((d) => d.kind.name).join(", ")}), flow=${flowState.name}',
      latencyMs: response.latencyMs,
    );
  }

  DoorKind? _parseDoorKind(String s) {
    switch (s.toLowerCase().trim()) {
      case 'owndoor':
        return DoorKind.ownDoor;
      case 'foreigndoor':
        return DoorKind.foreignDoor;
      case 'falsedoor':
        return DoorKind.falseDoor;
      case 'currentlink':
        return DoorKind.currentLink;
      default:
        return null;
    }
  }

  FlowState _parseFlowState(String s) {
    switch (s.toLowerCase().trim()) {
      case 'withflow':
        return FlowState.withFlow;
      case 'againstflow':
        return FlowState.againstFlow;
      case 'stalled':
        return FlowState.stalled;
      default:
        return FlowState.unknown;
    }
  }
}
