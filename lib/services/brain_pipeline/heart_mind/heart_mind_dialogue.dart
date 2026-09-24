// heart_mind_dialogue.dart
// Sprint 9 — 心腦合一對話閉環狀態機
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 狀態流：idle → offeringSplit → awaitingUser → integrated → written
//
// 觸發條件：pipeline 偵測到 alignment == mixed/conflicted 且有 splitMarker
// user 回覆後呼叫 LLM 把 mindStatement + heartStatement + user回應壓縮為整合 statement
// 寫入 HeartMindStore（idempotent check：同句不重複寫）
// 5 分鐘無回應自動回 idle（防卡死）
//
// 早晚節奏：每日第一輪若 alignment == aligned → 撈昨晚整合 statement 轉清晨確認

import 'dart:async';

import '../../../models/transurfing_brain.dart';
import '../pipeline_llm_client.dart';
import 'heart_mind_store.dart';

/// 心腦對話狀態機的狀態。
enum HeartMindDialogueState {
  /// 無活動
  idle,

  /// 偵測到分裂，向使用者提出引導句
  offeringSplit,

  /// 等待使用者選邊或回覆
  awaitingUser,

  /// LLM 已產出整合 statement
  integrated,

  /// 整合 statement 已寫入 store
  written,
}

/// 心腦對話的一次完整會話快照。
class HeartMindSession {
  final HeartMindDialogueState state;

  /// 觸發本次對話的 mindStatement（AI 抽取的理智立場）
  final String? mindStatement;

  /// 觸發本次對話的 heartStatement（AI 抽取的心立場）
  final String? heartStatement;

  /// 分裂標記（原文中的「可是」「但是」等）
  final String? splitMarker;

  /// 引導句（如「如果兩邊都對，你最想先聽哪邊？」）
  final String? integrationPrompt;

  /// 使用者回覆
  final String? userReply;

  /// LLM 產出的整合 statement
  final String? integratedStatement;

  /// 本次會話建立時間
  final DateTime createdAt;

  /// 最後活動時間（用於 timeout 判斷）
  final DateTime lastActivityAt;

  const HeartMindSession({
    this.state = HeartMindDialogueState.idle,
    this.mindStatement,
    this.heartStatement,
    this.splitMarker,
    this.integrationPrompt,
    this.userReply,
    this.integratedStatement,
    required this.createdAt,
    required this.lastActivityAt,
  });

  HeartMindSession copyWith({
    HeartMindDialogueState? state,
    String? mindStatement,
    String? heartStatement,
    String? splitMarker,
    String? integrationPrompt,
    String? userReply,
    String? integratedStatement,
    DateTime? lastActivityAt,
  }) {
    return HeartMindSession(
      state: state ?? this.state,
      mindStatement: mindStatement ?? this.mindStatement,
      heartStatement: heartStatement ?? this.heartStatement,
      splitMarker: splitMarker ?? this.splitMarker,
      integrationPrompt: integrationPrompt ?? this.integrationPrompt,
      userReply: userReply ?? this.userReply,
      integratedStatement: integratedStatement ?? this.integratedStatement,
      createdAt: createdAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    );
  }
}

/// 心腦合一對話閉環狀態機。
///
/// 生命週期：
/// 1. pipeline 偵測到 mixed/conflicted + splitMarker → [offerSplit]
/// 2. user 點選或輸入回覆 → [handleUserReply] → 呼叫 LLM 整合 → [integrate]
/// 3. 整合 statement 寫入 store → [writeToStore]
/// 4. 5 分鐘無回應 → [checkTimeout] 自動回 idle
/// 5. 隔天早上 alignment == aligned → [getMorningAffirmation]
class HeartMindDialogue {
  final HeartMindStore _store;
  final PipelineLLMClient? _llmClient;

  /// 可注入的時鐘
  final DateTime Function() _clock;

  /// 無回應 timeout（預設 5 分鐘）
  final Duration timeout;

  /// 目前會話
  HeartMindSession? _session;

  HeartMindDialogue({
    required HeartMindStore store,
    PipelineLLMClient? llmClient,
    DateTime Function()? clock,
    this.timeout = const Duration(minutes: 5),
  })  : _store = store,
        _llmClient = llmClient,
        _clock = clock ?? DateTime.now;

  /// 目前會話狀態（null = idle）
  HeartMindSession? get session => _session;

  /// 目前狀態
  HeartMindDialogueState get state => _session?.state ?? HeartMindDialogueState.idle;

  /// 從 reflection 的 GuidanceHint 觸發分裂對話。
  /// 只在 alignment == mixed/conflicted 且有 splitMarker 時觸發。
  /// 如果已經有進行中的會話，不覆蓋。
  void offerSplit(BrainReflection reflection) {
    // 已有進行中會話 → 不打斷
    if (_session != null && _session!.state != HeartMindDialogueState.idle) {
      return;
    }

    final hint = reflection.guidanceHint;
    if (hint == null) return;

    final alignment = reflection.heartMindAlignment;
    if (alignment != HeartMindAlignment.mixed &&
        alignment != HeartMindAlignment.conflicted) {
      return;
    }

    // 需要有 splitMarker 或 integrationPrompt 才觸發
    if ((hint.splitMarker == null || hint.splitMarker!.isEmpty) &&
        (hint.integrationPrompt == null || hint.integrationPrompt!.isEmpty)) {
      return;
    }

    final now = _clock();
    _session = HeartMindSession(
      state: HeartMindDialogueState.offeringSplit,
      mindStatement: hint.mindStatement,
      heartStatement: hint.heartStatement,
      splitMarker: hint.splitMarker,
      integrationPrompt: hint.integrationPrompt,
      createdAt: now,
      lastActivityAt: now,
    );
  }

  /// 使用者回覆（點選或輸入）。
  /// 回覆後呼叫 LLM 把 mindStatement + heartStatement + userReply 壓縮為整合 statement。
  /// LLM 不可用時用規則版 fallback（直接拼接）。
  Future<void> handleUserReply(String reply) async {
    if (_session == null || _session!.state == HeartMindDialogueState.idle) {
      return;
    }

    final now = _clock();
    _session = _session!.copyWith(
      state: HeartMindDialogueState.awaitingUser,
      userReply: reply,
      lastActivityAt: now,
    );

    // 呼叫 LLM 整合
    final integratedStatement = await _callLlmForIntegration(
      mindStatement: _session!.mindStatement ?? '',
      heartStatement: _session!.heartStatement ?? '',
      userReply: reply,
    );

    _session = _session!.copyWith(
      state: HeartMindDialogueState.integrated,
      integratedStatement: integratedStatement,
      lastActivityAt: _clock(),
    );

    // 自動寫入 store
    await writeToStore();
  }

  /// 把整合 statement 寫入 store（含 idempotent check）。
  Future<void> writeToStore() async {
    if (_session == null || _session!.state != HeartMindDialogueState.integrated) {
      return;
    }

    final statement = _session!.integratedStatement;
    if (statement == null || statement.isEmpty) return;

    // Idempotent check：同句不重複寫
    final existing = _store.getStatementsForDate(_todayKey());
    if (existing.contains(statement)) {
      _session = _session!.copyWith(
        state: HeartMindDialogueState.written,
        lastActivityAt: _clock(),
      );
      return;
    }

    await _store.writeStatement(
      statement: statement,
      mindStatement: _session!.mindStatement,
      heartStatement: _session!.heartStatement,
      userReply: _session!.userReply,
      dateKey: _todayKey(),
    );

    _session = _session!.copyWith(
      state: HeartMindDialogueState.written,
      lastActivityAt: _clock(),
    );
  }

  /// 檢查 timeout——如果超過 [timeout] 沒有活動，回到 idle。
  void checkTimeout() {
    if (_session == null || _session!.state == HeartMindDialogueState.idle) {
      return;
    }
    if (_session!.state == HeartMindDialogueState.written) {
      // written 是終態——直接清空
      _session = null;
      return;
    }

    final now = _clock();
    if (now.difference(_session!.lastActivityAt) > timeout) {
      _session = null; // 回 idle
    }
  }

  /// 取得今日清晨確認（昨晚的整合 statement）。
  /// 只在今天還沒有新整合、且昨天有整合 statement 時回傳。
  String? getMorningAffirmation() {
    final yesterday = _yesterdayKey();
    final yesterdayStatements = _store.getStatementsForDate(yesterday);
    if (yesterdayStatements.isEmpty) return null;

    // 今天已經有自己的整合 → 不需要清晨確認
    final todayStatements = _store.getStatementsForDate(_todayKey());
    if (todayStatements.isNotEmpty) return null;

    return yesterdayStatements.last;
  }

  /// 手動重置（測試 / panel 按鈕用）
  void reset() {
    _session = null;
  }

  // === LLM 整合 ===

  Future<String> _callLlmForIntegration({
    required String mindStatement,
    required String heartStatement,
    required String userReply,
  }) async {
    if (_llmClient == null || !_llmClient!.isAvailable) {
      // 規則版 fallback：直接拼接
      return _ruleBasedIntegration(mindStatement, heartStatement, userReply);
    }

    final systemPrompt = _integrationSystemPrompt;
    final userPrompt = '''
心智立場：$mindStatement
心立場：$heartStatement
使用者回覆：$userReply

請把這三段壓縮為一句整合後的 statement（繁體中文，不超過 50 字）。
只輸出 statement 本身，不要加引號或說明。''';

    final response = await _llmClient!.complete(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );

    if (!response.succeeded || response.content.trim().isEmpty) {
      return _ruleBasedIntegration(mindStatement, heartStatement, userReply);
    }

    return response.content.trim();
  }

  /// 規則版 fallback：簡單拼接
  String _ruleBasedIntegration(
    String mindStatement,
    String heartStatement,
    String userReply,
  ) {
    if (heartStatement.isNotEmpty && userReply.isNotEmpty) {
      return '在$heartStatement和$mindStatement之間，$userReply';
    }
    if (heartStatement.isNotEmpty) {
      return '兼顧$mindStatement的同時，也讓$heartStatement';
    }
    return userReply;
  }

  static const _integrationSystemPrompt = '''你是一個心腦合一整合器。
使用者的心智立場和心立場發生了分裂，現在使用者已經回覆了引導句。

你要把三段內容（心智立場、心立場、使用者回覆）壓縮為一句整合後的 statement。
這句 statement 應該：
- 反映使用者回覆中的選擇方向
- 同時承認心智和心的兩個立場
- 用自然、溫暖的繁體中文
- 不超過 50 字
- 不加引號、不加編號、不加說明文字''';

  // === 日期 helpers ===

  String _todayKey() => _formatDateKey(_clock());
  String _yesterdayKey() => _formatDateKey(_clock().subtract(const Duration(days: 1)));

  static String _formatDateKey(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)}';
  }
}
