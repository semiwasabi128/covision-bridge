import 'storage_service.dart';
import '../models/transurfing_brain.dart';
import '../models/second_brain_trace.dart';
import 'dart:convert';

class ContextCompressionResult {
  final String? systemNote;
  final List<Map<String, String>> messages;
  final int compressedCount;
  final String strategy;

  const ContextCompressionResult({
    required this.systemNote,
    required this.messages,
    required this.compressedCount,
    this.strategy = 'none',
  });

  bool get didCompress => compressedCount > 0;
}

class ContextCompressionDraft {
  final List<Map<String, String>> olderMessages;
  final List<Map<String, String>> recentMessages;

  const ContextCompressionDraft({
    required this.olderMessages,
    required this.recentMessages,
  });

  int get compressedCount => olderMessages.length;
  bool get shouldCompress => olderMessages.isNotEmpty;
}

class ContextCompressor {
  static const int defaultRecentMessageLimit = 12;
  static const int _maxSummaryChars = 1800;
  static const int _maxMessageChars = 220;
  static const int _maxSemanticTranscriptChars = 8000;

  static Future<ContextCompressionResult> compressMessages(
    List<Map<String, String>> messages, {
    int recentMessageLimit = defaultRecentMessageLimit,
  }) async {
    final enabled = await StorageService.isContextCompressionEnabled();
    return compressMessagesSync(
      messages,
      enabled: enabled,
      recentMessageLimit: recentMessageLimit,
    );
  }

  static ContextCompressionResult compressMessagesSync(
    List<Map<String, String>> messages, {
    required bool enabled,
    int recentMessageLimit = defaultRecentMessageLimit,
  }) {
    final draft = createDraft(
      messages,
      enabled: enabled,
      recentMessageLimit: recentMessageLimit,
    );

    if (!draft.shouldCompress) {
      return ContextCompressionResult(
        systemNote: null,
        messages: draft.recentMessages,
        compressedCount: 0,
      );
    }

    return buildResultFromDraft(
      draft,
      systemNote: _summarizeOlderMessages(draft.olderMessages),
      strategy: 'local',
    );
  }

  static ContextCompressionDraft createDraft(
    List<Map<String, String>> messages, {
    required bool enabled,
    int recentMessageLimit = defaultRecentMessageLimit,
  }) {
    final conversational = messages
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .toList();

    if (!enabled || conversational.length <= recentMessageLimit) {
      return ContextCompressionDraft(
        olderMessages: const [],
        recentMessages: conversational,
      );
    }

    final splitAt = conversational.length - recentMessageLimit;
    return ContextCompressionDraft(
      olderMessages: conversational.take(splitAt).toList(),
      recentMessages: conversational.skip(splitAt).toList(),
    );
  }

  static ContextCompressionResult buildResultFromDraft(
    ContextCompressionDraft draft, {
    required String systemNote,
    required String strategy,
  }) {
    return ContextCompressionResult(
      systemNote: systemNote,
      messages: draft.recentMessages,
      compressedCount: draft.compressedCount,
      strategy: strategy,
    );
  }

  static String buildSemanticSystemNote(String summary) {
    final trimmed = summary.trim();
    return [
      '【語意壓縮上下文 v2】',
      '以下是較早對話的任務狀態摘要。請把它當作背景脈絡，但優先遵循最近訊息。',
      '',
      trimmed.isEmpty ? '尚無可用摘要。' : trimmed,
    ].join('\n');
  }

  static String buildTransurfingBrainNotes(BrainReflection reflection) {
    final pendulums = reflection.pendulumSignals.isEmpty
        ? '無'
        : reflection.pendulumSignals
              .map((signal) => '${signal.label}(${signal.evidence})')
              .join('、');
    final doors = reflection.doorCandidates.isEmpty
        ? '未明'
        : reflection.doorCandidates
              .map((door) => '${_doorLabel(door.kind)}：${door.reason}')
              .join('；');

    return [
      '【Transurfing Brain Notes】',
      '這是橋樑大腦對最近使用者輸入的方向判斷。請把它當成意圖與狀態背景，不要把它當作絕對事實，也不要替使用者做最終決定。',
      '- 使用者意圖：${reflection.userIntent}',
      '- 注意力：${_attentionLabel(reflection.attentionState)}',
      '- 鐘擺：$pendulums',
      '- 重要性：${_importanceLabel(reflection.importanceLevel)}',
      '- 心腦狀態：${_alignmentLabel(reflection.heartMindAlignment)}',
      '- Fraile：${_fraileLabel(reflection.fraileResonance)}',
      '- 門：$doors',
      '- 水流：${_flowLabel(reflection.flowState)}',
      '- 建議：${_moveLabel(reflection.recommendedMove)}',
      '- 引導：${reflection.guidance}',
    ].join('\n');
  }

  static String? buildTransurfingInsightRecallNotes(List<String> insights) {
    if (insights.isEmpty) return null;

    return [
      '【Transurfing Insight Recall】',
      '以下是橋樑大腦從長期記憶中回收、且與當前狀態相符的洞察。請把它們當作可參考的使用者模式，不要僵硬套用。',
      ...insights.take(5).map((insight) => '- $insight'),
    ].join('\n');
  }

  static String? buildSecondBrainMemoryNotes(
    List<SecondBrainMemoryTrace> memories,
  ) {
    if (memories.isEmpty) return null;

    final lines = <String>[
      '【第二大腦索引回收】',
      '以下是使用者第二大腦中與本輪意圖相關的檔案內容節錄，請優先引用：',
    ];
    for (final memory in memories.take(5)) {
      final excerpt = memory.sourcePreview.isNotEmpty
          ? memory.sourcePreview
          : memory.content;
      final trimmed = excerpt.length > 300
          ? '${excerpt.substring(0, 300)}...'
          : excerpt;
      lines.add('- ${memory.sourceLabel}（${memory.room}）：$trimmed');
    }
    return lines.join('\n');
  }

  static String buildSemanticTranscript(List<Map<String, String>> messages) {
    final lines = <String>[];
    for (final message in messages) {
      final role = message['role'] == 'user' ? '使用者' : '助理';
      final content = (message['content'] ?? '').trim();
      if (content.isNotEmpty) {
        lines.add('$role：$content');
      }
    }

    final transcript = lines.join('\n\n');
    if (transcript.length <= _maxSemanticTranscriptChars) return transcript;
    return transcript.substring(
      transcript.length - _maxSemanticTranscriptChars,
    );
  }

  static String _summarizeOlderMessages(List<Map<String, String>> messages) {
    final lines = <String>[
      '【已壓縮的較早上下文】',
      '以下是本輪對話較早內容的壓縮摘要。請把它當作背景脈絡，但優先遵循最近訊息。',
    ];

    for (final message in messages) {
      final role = message['role'] == 'user' ? '使用者' : '助理';
      final content = _compactContent(message['content'] ?? '');
      if (content.isNotEmpty) {
        lines.add('- $role：$content');
      }
    }

    final summary = lines.join('\n');
    if (summary.length <= _maxSummaryChars) return summary;
    return '${summary.substring(0, _maxSummaryChars).trimRight()}\n- 摘要已截短。';
  }

  static String _compactContent(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= _maxMessageChars) return normalized;
    return '${normalized.substring(0, _maxMessageChars).trimRight()}...';
  }

  static String _attentionLabel(AttentionState state) {
    switch (state) {
      case AttentionState.clear:
        return '清醒';
      case AttentionState.captured:
        return '被捕獲';
      case AttentionState.scattered:
        return '分散';
    }
  }

  static String _importanceLabel(ImportanceLevel level) {
    switch (level) {
      case ImportanceLevel.low:
        return '低';
      case ImportanceLevel.balanced:
        return '平衡';
      case ImportanceLevel.elevated:
        return '偏高';
      case ImportanceLevel.excessive:
        return '過高';
    }
  }

  static String _alignmentLabel(HeartMindAlignment alignment) {
    switch (alignment) {
      case HeartMindAlignment.aligned:
        return '一致';
      case HeartMindAlignment.mixed:
        return '混合';
      case HeartMindAlignment.conflicted:
        return '衝突';
      case HeartMindAlignment.unknown:
        return '未知';
    }
  }

  static String _fraileLabel(FraileResonance resonance) {
    switch (resonance) {
      case FraileResonance.strong:
        return '強共振';
      case FraileResonance.present:
        return '有共振';
      case FraileResonance.weak:
        return '弱';
      case FraileResonance.obscured:
        return '被遮蔽';
    }
  }

  static String _doorLabel(DoorKind kind) {
    switch (kind) {
      case DoorKind.ownDoor:
        return '自己的門';
      case DoorKind.foreignDoor:
        return '外部門';
      case DoorKind.falseDoor:
        return '假門';
      case DoorKind.currentLink:
        return '下一環';
    }
  }

  static String _flowLabel(FlowState state) {
    switch (state) {
      case FlowState.withFlow:
        return '順流';
      case FlowState.againstFlow:
        return '逆流';
      case FlowState.stalled:
        return '停滯';
      case FlowState.unknown:
        return '觀察中';
    }
  }

  static String _moveLabel(RecommendedMove move) {
    switch (move) {
      case RecommendedMove.answerDirectly:
        return '直接回應';
      case RecommendedMove.askClarifyingQuestion:
        return '先釐清';
      case RecommendedMove.reduceImportance:
        return '降重要性';
      case RecommendedMove.convertToOutput:
        return '轉成輸出';
      case RecommendedMove.takeNextAction:
        return '推進下一步';
      case RecommendedMove.routeBridge:
        return '接橋';
      case RecommendedMove.declareIntention:
        return '宣告意圖';
      case RecommendedMove.recordWaterAction:
        return '記錄行動';
    }
  }
}

// [小葵 2026-09-21] ConversationCompressor — 對話級 context 壓縮器
// 設計稿 docs/CONTEXT_COMPRESSION_STRATEGY.md 的 L1/L2/L3 實作。
// 緣起：9/19 gpt-6-astra cache writes 燒 $35 事件。
//
// ⚠️ 與同檔的 ContextCompressor（舊，服務 api_service 的訊息壓縮）互不取代。
//   - ContextCompressor（舊）：Map<String,String> 訊息 + Transurfing notes
//   - ConversationCompressor（新）：CompressibleMessage + 三層壓縮架構
//
// 三層架構：
//   L1 靜態分段（永遠開啟，零成本）—— system + initial_task 鎖 prefix，
//       中間可壓縮，最近 K 輪保留原文。
//   L2 語義摘要（LLM 壓縮）—— 中間段摘要成 1 則 user 訊息。
//       壓縮模型 = 階梯最便宜階（由呼叫端注入，本庫不綁定任何 provider）。
//   L3 粗暴截斷（fallback）—— 無 LLM / L2 失敗時保留頭尾、丟中間。
//
// 本檔是純函式庫：無 IO、無網路、不 import App 其他 service。
// 測試入口：test/compression_round_trip_test.dart

class CompressibleMessage {
  final String role;
  final String content;
  final Map<String, dynamic>? raw;

  const CompressibleMessage({required this.role, required this.content, this.raw});

  factory CompressibleMessage.fromJson(Map<String, dynamic> j) =>
      CompressibleMessage(
        role: (j['role'] ?? 'user') as String,
        content: (j['content'] ?? '') as String,
        raw: j,
      );

  Map<String, dynamic> toJson() => {'role': role, 'content': content, ...?raw};
}

/// L2 摘要函式簽名：把多則訊息摘要成一段文字。
/// 由呼叫端注入（App 內接 ApiService；測試接 fake / 真實 API）。
typedef ConversationSummarizer =
    Future<String> Function(List<CompressibleMessage> middle);

class ConversationCompressionResult {
  final List<CompressibleMessage> messages;
  final bool usedLlmSummary; // L2 成功？
  final int originalCount;
  final int compressedCount;

  const ConversationCompressionResult({
    required this.messages,
    required this.usedLlmSummary,
    required this.originalCount,
    required this.compressedCount,
  });

  int get savedCount => originalCount - compressedCount;
}

class ConversationCompressor {
  /// 中間段超過 [middleThreshold] 則時觸發壓縮
  final int middleThreshold;

  /// 永遠保留原文的最近輪數
  final int keepRecentTurns;

  /// 壓縮摘要標記（round-trip 測試可憑此辨識壓縮過的 context）
  static const String summaryMarker = '[歷史摘要]';

  ConversationCompressor({
    this.middleThreshold = 10,
    this.keepRecentTurns = 8,
  });

  /// L1 靜態分段：locked（system + initial task）/ middle（可壓縮）/ recent（保留原文）
  ({List<CompressibleMessage> lockedPrefix, List<CompressibleMessage> middle,
    List<CompressibleMessage> recent}) segment(List<CompressibleMessage> msgs) {
    if (smsgIsEmpty(msgs)) {
      return (lockedPrefix: const [], middle: const [], recent: const []);
    }
    final locked = <CompressibleMessage>[];
    var i = 0;
    if (msgs.first.role == 'system') {
      locked.add(msgs[0]);
      i = 1;
    }
    if (i < msgs.length) {
      locked.add(msgs[i]); // initial user task
      i++;
    }
    final recentStart = (msgs.length - keepRecentTurns).clamp(i, msgs.length);
    return (
      lockedPrefix: locked,
      middle: msgs.sublist(i, recentStart),
      recent: msgs.sublist(recentStart),
    );
  }

  /// 完整壓縮流程（L1 → L2，L2 失敗退 L3）
  Future<ConversationCompressionResult> compress(
    List<CompressibleMessage> msgs, {
    ConversationSummarizer? summarizer,
  }) async {
    final seg = segment(msgs);
    final middle = seg.middle;

    // 中間段沒超過門檻 → 不壓，原樣回傳（省壓縮自身成本）
    if (middle.length <= middleThreshold) {
      return ConversationCompressionResult(
        messages: msgs,
        usedLlmSummary: false,
        originalCount: msgs.length,
        compressedCount: msgs.length,
      );
    }

    // L3 baseline：頭尾保留、中間丟棄（比較組 + fallback）
    final l3 = <CompressibleMessage>[
      ...seg.lockedPrefix,
      CompressibleMessage(
          role: 'user',
          content: '$summaryMarker（截斷模式：前 ${middle.length} 則中間歷史已省略）'),
      ...seg.recent,
    ];

    if (summarizer == null) return _result(l3, false, msgs.length);

    // L2：LLM 摘要
    try {
      final summary = await summarizer(middle);
      if (summary.trim().isEmpty) return _result(l3, false, msgs.length);
      final l2 = <CompressibleMessage>[
        ...seg.lockedPrefix,
        CompressibleMessage(role: 'user', content: '$summaryMarker\n$summary'),
        ...seg.recent,
      ];
      return _result(l2, true, msgs.length);
    } catch (_) {
      return _result(l3, false, msgs.length);
    }
  }

  ConversationCompressionResult _result(
          List<CompressibleMessage> out, bool llm, int orig) =>
      ConversationCompressionResult(
        messages: out,
        usedLlmSummary: llm,
        originalCount: orig,
        compressedCount: out.length,
      );

  static bool smsgIsEmpty(List<CompressibleMessage> msgs) => msgs.isEmpty;

  /// 從 conversations.json 的 messages 陣列載入（純解析；檔案讀取由呼叫端）
  static List<CompressibleMessage> parseMessages(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => CompressibleMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
