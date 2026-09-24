/// Agent Loop 引擎
///
/// [2026-07-19 使用者拍板] 與 Hermes 對齊——無 maxTurns 上限 + 可插嘴
///
/// 核心設計（Hermes 模式）：
/// - 不設 maxTurns 上限——LLM 自己判斷何時完成
/// - 安全閥：hardMaxTurns=200（防 LLM 真的壞掉死循環）
/// - LLM 回覆不含 tool call = 自然結束（就這麼簡單）
/// - 不需要 forceToolUse nudge——靠 system prompt 引導 LLM 用工具
/// - 不需要完成偵測關鍵詞——信任 LLM 的判斷
/// - 使用者可隨時插嘴——訊息注入 queue，每輪開始前檢查
/// - 每輪有進度回調，UI 可即時顯示
///
/// 與 Hermes agent loop 的差異：
/// - Hermes 用 OpenAI function calling（原生 tool_use）
/// - 橋樑 App 用 prompt-based JSON（ApiService 不支援 function calling）
/// - 格式與 brain pipeline L3 一致：分隔符 + safeJsonParse

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import '../storage_service.dart';
import '../causal/causal_ledger_service.dart'; // [因果引擎 L1] 介入帳本
import '../api_usage_tracker.dart'; // [小葵 2026-09-21 收尾驗收] per-task token 歸因
import '../decision/k1_gatekeeper.dart'; // [小葵 2026-09-21 R3] K1 守門員
import '../decision/decision_head.dart' show K1Labels, K1Decision; // [小葵 2026-09-22] 輕裝路徑
import '../vector_db/hybrid_search_service.dart'; // [R3] K1 need → 語意檢索
import 'compass_medic.dart'; // [軍醫 W3/W4] 羅盤出診＋傷口自癒
import 'agent_loop_tools/tool_seek_tool.dart'; // [小葵 2026-09-22] 精靈任務配備
import 'agent_safety.dart'; // [D002] 工具確認
import 'agent_tool.dart';
import 'agent_tool_call_parser.dart';
import 'agent_tool_registry.dart';
import 'production_agent_loop_llm_client.dart';

/// Agent Loop 結果
class AgentLoopResult {
  /// 最終回覆給使用者的文字
  final String reply;

  /// 每一輪的紀錄
  final List<AgentLoopTurn> turns;

  /// 是否因達到輪數上限而終止
  final bool hitTurnLimit;

  /// 是否被使用者取消
  final bool cancelled;

  /// 總耗時
  final Duration elapsed;

  const AgentLoopResult({
    required this.reply,
    required this.turns,
    required this.hitTurnLimit,
    required this.cancelled,
    required this.elapsed,
  });

  int get toolCallCount => turns.where((t) => t.toolCall != null).length;
}

/// 進度回調
/// 每輪開始/結束時呼叫，UI 可用來顯示「正在搜尋...」「正在讀取網頁...」等
typedef AgentLoopProgressCallback =
    void Function(
      int turnIndex,
      int maxTurns,
      AgentToolCall? toolCall,
      AgentToolResult? toolResult,
      String llmOutput,
    );

/// [教練 Agent 2026-08-07] 階段回調——即時進度回饋
/// 在 LLM 呼叫前、tool 執行前、timeout 時觸發，
/// 讓使用者不再看著黑箱等待。
///
/// stage 值：
/// - 'thinking'  — LLM 正在思考
/// - 'tool_start' — 即將執行工具（toolName 附帶）
/// - 'tool_done'  — 工具執行完成
/// - 'timeout'   — LLM 或 tool 超時
/// - 'error'     — 發生錯誤（detail 附帶）
typedef AgentLoopStageCallback =
    void Function(
      String stage, {
      String? toolName,
      String? detail,
    });

/// 使用者插嘴回調——當使用者在 loop 運行中發送訊息時觸發
/// UI 可以用這個顯示「使用者插嘴了：xxx」
typedef AgentLoopUserMessageCallback = void Function(String userMessage);

/// LLM 呼叫介面——AgentLoop 不直接依賴 ApiService
/// 由 chat_controller 注入實作
abstract class AgentLoopLLMClient {
  /// 發送 messages 到 LLM，回傳純文字
  /// messages 格式：[{role: 'system'|'user'|'assistant', content: '...'}]
  /// content 可以是 String（純文字）或 List（multimodal，含 image_url）
  Future<String> complete(List<Map<String, dynamic>> messages);
}

/// [2026-07-20] 工具序列重複 pattern 偵測結果
class _ToolPatternResult {
  final List<String> pattern;
  final int repetitions;
  _ToolPatternResult(this.pattern, this.repetitions);
}

/// Agent Loop 引擎
class AgentLoop {
  /// [小葵 2026-09-22] 最近一次 K1 判定——輕裝路徑判斷用
  K1Decision? _lastK1Decision;

  /// [Blue 拍板 2026-09-18] 與 Hermes（小葵）對齊——無固定輪數限制，對 agent 有信心。
  /// 剩餘空間 = 物理上限（context window、API 額度），不是人為輪數。
  /// 安全閥只留超大值，純防 LLM 真的壞掉死循環燒錢（正常 agent 永遠碰不到）。
  /// [小葵] Hermes 同款理念：臨界前的收斂靠禮儀（compass: agent.mind.turnLimitEtiquette
  /// 三級收口：150 收斂 / 180 續接工單），不靠硬閥。
  static const int hardMaxTurns = 100000;

  final AgentToolRegistry toolRegistry;
  final AgentLoopLLMClient llmClient;

  /// [D002 2026-08-10] 安全確認 callback——實例欄位，所有 run() 自動生效
  /// 設定方式：UI 層在初始化時 agentLoop.onToolConfirmation = ...
  /// 回傳 true = 確認執行；false = 拒絕
  Future<bool> Function({
    required String toolName,
    required Map<String, dynamic> args,
  })? onToolConfirmation;

  /// 使用者插嘴 message queue
  /// loop 運行中使用者發送訊息時，注入這裡，每輪 LLM 呼叫前會 drain
  final Queue<String> _userMessageQueue = Queue<String>();

  /// [因果引擎 L1] 本輪任務的情境摘要——run() 開頭由 userMessage 建立，
  /// 介入帳本記帳時作為 contextDigest（L3 反饋查詢的匹配鍵）
  String? _causalContextDigest;

  /// [軍醫 W3/W4 2026-09-17] 同工具連續失敗計數（撞牆出診觸發器）
  final Map<String, int> _medicFailStreak = {};

  /// [軍醫 W3] 待注入下一輪的救急藥卡（撞牆出診佇列）
  String? medicRescueQueued;

  AgentLoop({required this.toolRegistry, required this.llmClient});

  /// [教練 Agent 2026-08-08] 教練模式——當前 run 的 turn 列表快照
  List<AgentLoopTurn> _currentTurns = [];
  List<AgentLoopTurn> get turnsForDebug => _currentTurns;

  /// 使用者插嘴——把訊息排入 queue，下一輪 LLM 呼叫前會看到
  void injectUserMessage(String message) {
    _userMessageQueue.add(message);
    debugPrint('[AgentLoop] 使用者插嘴已排入: ${message.length} 字');
  }

  /// 執行 agent loop
  ///
  /// [systemPrompt] — 系統提示（含工具描述）
  /// [userMessage] — 使用者訊息（已做分隔符轉義）
  /// [maxTurns] — 最大輪數（預設不限制，安全閥 hardMaxTurns=200）
  /// [onProgress] — 每輪進度回調
  /// [onUserMessage] — 使用者插嘴回調
  /// [isCancelled] — 檢查是否被取消（每輪開始前檢查）
  Future<AgentLoopResult> run({
    required String systemPrompt,
    required String userMessage,
    int maxTurns = hardMaxTurns,
    AgentLoopProgressCallback? onProgress,
    AgentLoopStageCallback? onStage,
    AgentLoopUserMessageCallback? onUserMessage,
    bool Function()? isCancelled,
    // [教練 Agent 2026-08-20] 付費工具閘門——true 時 generate_image 等付費生成工具
    // 一律拒絕執行（機器訊息喚醒的輪次專用）。能力不拔：使用者親自發言的
    // 輪次為 false，照常走 confirmationRequired 確認框流程。
    bool prohibitPaidTools = false,
    // [D002 2026-08-10] onToolConfirmation 已提升為實例欄位，所有 run() 自動生效
  }) async {
    // [小葵 2026-09-21 收尾驗收] per-task 歸因 wrapper——
    // 不動內部多個 return 點，外層記帳：token 差額+時長+輪數。
    // 資料源：ApiUsageTracker（真值優先，收尾驗收刀已升級）。
    final tracker = ApiUsageTracker.instance;
    final tokenBefore = tracker.todayTotalTokens;
    final wallClockBefore = DateTime.now();
    // [小葵 2026-09-22 打鐵趁熱] 觀測——system prompt / user message 大小
    // 每輪可從 log 追蹤大戶（不需要時可移除）
    debugPrint('[AgentPerf] systemPrompt=${systemPrompt.length} chars, '
        'userMessage=${userMessage.length} chars');
    try {
      // [小葵 2026-09-22 驗屍用] 真實 prompt 落地——找出 15K tokens 大戶
      final f = File('/tmp/agent_prompt_dump.txt');
      f.writeAsStringSync(
          '===== SYSTEM (${systemPrompt.length} chars) =====\n$systemPrompt\n'
          '\n===== USER (${userMessage.length} chars) =====\n$userMessage\n');
    } catch (_) {}
    try {
      return await _runInner(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        maxTurns: maxTurns,
        onProgress: onProgress,
        onStage: onStage,
        onUserMessage: onUserMessage,
        isCancelled: isCancelled,
        prohibitPaidTools: prohibitPaidTools,
      );
    } finally {
      final tokens = tracker.todayTotalTokens - tokenBefore;
      final wallMs =
          DateTime.now().difference(wallClockBefore).inMilliseconds;
      CausalLedger.instance.record(CausalEntry(
        toolName: 'agent_perf',
        intervention: '任務效能：$tokens tokens、$wallMs ms',
        contextDigest: (userMessage.length <= 200)
            ? userMessage
            : userMessage.substring(0, 200),
        observedOutcome: '見 intervention（tokens=本次任務消耗、'
            'wallMs=牆鐘時間；真值比例見 api_usage_log.jsonl estimated 欄）',
        success: true,
        at: DateTime.now(),
      ));
    }
  }

  Future<AgentLoopResult> _runInner({
    required String systemPrompt,
    required String userMessage,
    int maxTurns = hardMaxTurns,
    AgentLoopProgressCallback? onProgress,
    AgentLoopStageCallback? onStage,
    AgentLoopUserMessageCallback? onUserMessage,
    bool Function()? isCancelled,
    bool prohibitPaidTools = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final effectiveMax = maxTurns.clamp(1, hardMaxTurns);
    final turns = <AgentLoopTurn>[];
    _currentTurns = turns; // [教練 Agent 2026-08-08] 教練模式快照

    // [因果引擎 L1] 本輪情境摘要——介入帳本的 contextDigest。
    // [修正] 頭尾各取——canvas/chat 路徑會把對話歷史包進 userMessage 前段，
    // 使用者的真實指令在末端；只取頭 300 字會漏掉真問題（ZETA-77 教訓）。
    _causalContextDigest = userMessage.length <= 320
        ? userMessage
        : '${userMessage.substring(0, 150)}…${userMessage.substring(userMessage.length - 150)}';
    unawaited(CausalLedger.instance.initialize());

    // ── [小葵 2026-09-21 R3] K1 守門員前置 ──────────────────
    // 訊息進迴圈前過三層閘門（規則→線性頭→escalate）。
    // ① 判斷入 ledger（自訓練樣本管線）
    // ② 判 need → 語意檢索搬家記憶＋大腦記憶，命中附入 user 訊息
    //    （$9 事件的根治：生日題不再靠 LLM 盲查 3-5 輪）
    // ③ escalate → 照常全推理（K1 是路由器不是法官）
    // 全部 fail-open：K1 掛了不擋任務。
    String? k1MemoryHits;
    try {
      final k1 = K1Gatekeeper.instance;
      final decision = await k1.classify(
        _causalContextDigest ?? userMessage,
        onSample: (d, msg) => k1.logSample(msg, d),
      );
      _lastK1Decision = decision;
      debugPrint('[K1] ${decision.label} '
          '(conf=${decision.confidence.toStringAsFixed(2)} '
          'src=${decision.source} esc=${decision.escalated})');
      if (decision.needMemory && !decision.escalated) {
        final results = await HybridSearchService.instance.search(
          query: _causalContextDigest ?? userMessage,
          mode: SearchMode.hybrid,
          limit: 3,
        );
        final hits = results.memoryHits;
        if (hits.isNotEmpty) {
          final buf = StringBuffer();
          buf.writeln();
          buf.writeln('〔K1 記憶命中〕回答前先看這些（語意檢索 top ${hits.length}）：');
          for (final h in hits) {
            buf.writeln('• ${(h.content.length > 160) ? h.content.substring(0, 160) : h.content}');
          }
          buf.writeln('（若與問題無關可忽略；引用時保持原意）');
          k1MemoryHits = buf.toString();
        }
      }
    } catch (e) {
      debugPrint('[K1] 前置失敗（fail-open 跳過）: $e');
    }

    // [因果引擎 L3 2026-09-12] 帳本反饋查詢——problem-solving 前置：
    // 同類情境的歷史干預記錄注入 context，不重新猜。
    // [注入位置教訓] 附在 system prompt 會沉入 33K 字海底（glm-5.2 實測
    // 注入成功但 LLM 無視）；改附在 user 訊息本體——模型必讀位置。
    // 誠實邊界：帳本空/無命中=不注入（絕不假裝查過）；檢索 fail-open。
    String? causalFeedback;
    try {
      await CausalLedger.instance.initialize();
      if (CausalLedger.instance.hasAnyEntries) {
        final recalled = await CausalLedger.instance
            .recallSimilar(_causalContextDigest ?? userMessage, limit: 3);
        causalFeedback = CausalLedger.buildFeedbackSection(recalled);
      }
    } catch (e) {
      debugPrint('[AgentLoop] 因果帳本反饋檢索失敗（fail-open 跳過注入）: $e');
    }
    if (causalFeedback != null && causalFeedback.isNotEmpty) {
      debugPrint('[AgentLoop] 因果帳本反饋附入 user 訊息（'
          '${causalFeedback.length} 字）');
    }

    // ── [小葵 2026-09-22 Blue 令] 輕裝路徑（lite path）──────────
    // 一句記憶題不該帶全套儀仗隊（8.8K tokens）。K1 判「純記憶題」
    // （needMemory 且未 escalate 且非工具任務）時，system prompt 換
    // 輕裝版：身份＋回答規則。記憶卡已由 K1 檢索附在 user 訊息。
    // 目標 ~1.5K tokens/輪。任何工具呼叫需求會自然升級回全裝
    // （LLM 可在回覆中說需要工具，下輪全裝處理）。
    String effectiveSystemPrompt = systemPrompt;
    bool isLiteEligible = false;
    if (k1MemoryHits != null &&
        _lastK1Decision != null &&
        _lastK1Decision!.needMemory &&
        !_lastK1Decision!.escalated &&
        _lastK1Decision!.label != K1Labels.directAction) {
      // [小葵 2026-09-22 Blue 令] 輕裝≠不帶工具——精靈依任務配備武器：
      // 讀 log 的題目配 read_app_log，查記憶的題目配 memory_search。
      // 打仗按任務配對的武器，不是全給或全不給。
      String? equipped;
      try {
        final toolSeek = toolRegistry.get('compass_toolseek');
        if (toolSeek is CompassToolSeekTool) {
          final kit = await toolSeek.topToolsFor(userMessage);
          if (kit.isNotEmpty) {
            final buf = StringBuffer('# 本次任務配備（精靈依任務挑選）\n');
            for (final t in kit) {
              buf.writeln(t.toFullDescription());
            }
            buf.writeln('沒有需要的工具就別用；配備外的需求說「〔需要工具〕」。');
            equipped = buf.toString();
          }
        }
      } catch (e) {
        debugPrint('[AgentLoop] 精靈配備失敗（fail-open 全裝）: $e');
      }
      if (equipped != null) {
        effectiveSystemPrompt = _buildLiteSystemPrompt(equipped);
        isLiteEligible = true;
        debugPrint('[AgentLoop] 輕裝路徑生效（K1='
            '${_lastK1Decision!.label} conf='
            '${_lastK1Decision!.confidence.toStringAsFixed(2)}）——'
            'system prompt ${systemPrompt.length}→'
            '${effectiveSystemPrompt.length} chars（含任務配備）');
      }
    }

    // [2026-07-19] 連續截圖計數器——防止 GLM-4.6v 陷入截圖迴圈
    int consecutiveScreenshots = 0;
    // [教練 Agent 2026-08-16] 截斷重試計數——連續截斷 3 次就放棄（避免無限循環）
    int consecutiveTruncations = 0;
    int statedIntentNudges = 0; // [小葵 09-15] 說了不做 nudge 計數

    // [2026-07-19] 通用循環防護——連續相同工具呼叫計數器
    // 任何工具連續呼叫 >= 5 次注入 nudge，>= 10 次強制結束
    String? lastToolName;
    int consecutiveSameTool = 0;

    // [2026-07-20] 工具序列 pattern 偵測——防 A→B→A→B 交替循環
    // consecutiveSameTool 只防同一工具連續呼叫，防不住交替循環
    final toolCallHistory = <String>[];
    int lastPatternRepsInjected = 0; // 避免同一層級重複注入 nudge

    // 組裝對話歷史
    // [因果引擎 L3] 反饋附在 user 訊息本體——模型必讀位置（system 33K 海底教訓）
    // [小葵 2026-09-21 R3] K1 記憶命中同位附入——need 判定的檢索結果直接
    // 進模型必讀位置（$9 事件根治：不靠 LLM 盲查 3-5 輪）
    var effectiveUserMessage = causalFeedback == null
        ? userMessage
        : '$userMessage\n$causalFeedback';
    if (k1MemoryHits != null) {
      effectiveUserMessage = '$effectiveUserMessage$k1MemoryHits';
    }
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': effectiveSystemPrompt},
      {'role': 'user', 'content': effectiveUserMessage},
    ];

    for (int turn = 0; turn < effectiveMax; turn++) {
      // 取消檢查
      if (isCancelled != null && isCancelled()) {
        stopwatch.stop();
        return AgentLoopResult(
          reply: _buildCancelledReply(turns),
          turns: turns,
          hitTurnLimit: false,
          cancelled: true,
          elapsed: stopwatch.elapsed,
        );
      }

      // ── 使用者插嘴 drain ──
      // Hermes 模式：使用者可以隨時發訊息，每輪 LLM 呼叫前檢查 queue
      while (_userMessageQueue.isNotEmpty) {
        final userMsg = _userMessageQueue.removeFirst();
        messages.add({'role': 'user', 'content': '〔使用者插嘴〕$userMsg'});
        onUserMessage?.call(userMsg);
        debugPrint('[AgentLoop] 使用者插嘴已注入第 $turn 輪');
      }

      // [軍醫 W3 2026-09-17] 出診注入 drain——撞牆救急藥（上一輪連敗 ≥2 產生）
      if (medicRescueQueued != null) {
        messages.add({'role': 'user', 'content': medicRescueQueued!});
        debugPrint('[軍醫] 撞牆藥卡已注入第 $turn 輪');
        medicRescueQueued = null;
      }

      // 檢查是否到最後一輪（graceful termination）
      final isLastTurn = turn == effectiveMax - 1;

      // 如果是最後一輪，注入「請直接回覆，不要再呼叫工具」提示
      if (isLastTurn && turns.isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': '已達到工具使用次數上限。請根據目前收集到的資訊，直接回覆使用者，不要再使用工具。',
        });
      }

      // [2026-07-19] Conversation history 截斷——防止 context 累積過大導致 GLM hang
      // 保留：system prompt + 最初使用者任務 + 最近 8 則訊息
      // 中間舊訊息：摘要成一行，保留工具名稱讓 LLM 知道做過什麼
      if (messages.length > 16) {
        final kept = <Map<String, dynamic>>[];
        kept.add(messages[0]); // system prompt
        kept.add(messages[1]); // 最初使用者任務
        // 中間的摘要
        final middle = messages.sublist(2, messages.length - 8);
        final summaryParts = <String>[];
        for (final m in middle) {
          final content = m['content'];
          String text = '';
          if (content is String) {
            text = content;
          } else if (content is List) {
            // image_url content——只記標記
            const text = '[含截圖]';
          }
          if (text.startsWith('工具 ') && text.contains('執行結果')) {
            // 工具結果——只留工具名和前 80 字
            final toolMatch = RegExp(r'工具 (\w+) 的執行結果').firstMatch(text);
            final toolName = toolMatch?.group(1) ?? 'unknown';
            summaryParts.add(
              '[$toolName 結果: ${text.length > 80 ? text.substring(0, 80) : text}...]',
            );
          } else if (m['role'] == 'assistant') {
            // assistant 回覆——只留前 60 字
            summaryParts.add(
              '[AI: ${text.length > 60 ? text.substring(0, 60) : text}...]',
            );
          }
        }
        if (summaryParts.isNotEmpty) {
          kept.add({
            'role': 'user',
            'content': '〔歷史摘要〕之前做過：\n${summaryParts.join('\n')}',
          });
        }
        // 保留最近 8 則
        kept.addAll(messages.sublist(messages.length - 8));
        messages.clear();
        messages.addAll(kept);
        debugPrint(
          '[AgentLoop] History 截斷：${middle.length + 10} → ${kept.length} 則',
        );
      }

      // 呼叫 LLM
      onStage?.call('thinking', detail: '第 ${turn + 1}/$effectiveMax 輪思考中');
      
      // [教練 Agent 2026-08-08] 體感時間延長——讓使用者在等待時有更多線索
      // [教練 Agent 2026-08-09] 第一條 hint 立即顯示（不等 5 秒）
      final hints = <String>[
        '正在理解你的需求…',
        '整理思路中，快要好了…',
        '想到幾個方向了，讓我再想想…',
        '快完成了，正在組織回覆…',
      ];
      Timer? hintTimer;
      int hintIdx = 0;
      final hintStart = DateTime.now();
      // 立即顯示第一條 hint
      onStage?.call('thinking', detail: hints[0]);
      hintIdx = 1;
      hintTimer = Timer.periodic(const Duration(seconds: 5), (t) {
        if (hintIdx < hints.length) {
          final elapsed = DateTime.now().difference(hintStart).inSeconds;
          onStage?.call('thinking', detail: '${hints[hintIdx]}（${elapsed}s）');
          hintIdx++;
        } else {
          t.cancel();
        }
      });
      
      String llmOutput;
      try {
        // [教練 Agent 2026-08-09] 統一 90 秒 timeout——Agent Loop 一律走雲端
        final llmTimeout = const Duration(seconds: 90);
        
        llmOutput = await llmClient
            .complete(messages)
            .timeout(
              llmTimeout,
              onTimeout: () {
                throw TimeoutException('LLM ${llmTimeout.inSeconds}s 超時');
              },
            );
      } on TimeoutException catch (_) {
        hintTimer.cancel();
        onStage?.call('timeout', detail: 'LLM 思考超時，正在調整策略...');
        // [教練 Agent 2026-07-19 使用者洞察] glm-4.6v vision model 不穩定會 hang。
        // timeout 時若 messages 有截圖，evict 掉讓下一輪回到 glm-5.2，
        // 然後注入「截圖分析超時，請用文字描述你在截圖中看到的問題」繼續 loop，
        // 而不是直接結束——讓原生 Agent的大腦（glm-5.2）接手推理。
        // [2026-07-20] 加強：連續截圖計數器 +2（懲罰性），讓後續截圖直接被 nudge 攔截
        debugPrint('[AgentLoop] LLM timeout，evict 截圖讓下一輪回到 glm-5.2');
        _evictOldScreenshots(messages);
        consecutiveScreenshots += 2; // 懲罰性計數——下次截圖直接觸發 nudge
        messages.add({
          'role': 'assistant',
          'content': '〔視覺模型分析截圖超時。請改用你在截圖前讀過的原始碼內容，用文字描述問題並繼續。不要再截圖，直接用文字推理。〕',
        });
        continue;
      } catch (e) {
        hintTimer.cancel();
        // 其他 LLM 錯誤 = 直接結束，回報錯誤
        onStage?.call('error', detail: 'LLM 呼叫失敗：$e');
        debugPrint('[AgentLoop] LLM 呼叫失敗: $e');
        stopwatch.stop();
        return AgentLoopResult(
          reply: '抱歉，發生了問題：$e',
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      hintTimer.cancel();

      // 解析 tool call
      final toolCalls = AgentToolCallParser.parse(llmOutput);

      // [教練 Agent 2026-08-16 使用者 抓包] 截斷防護——
      // 症狀：原生 Agent輸出「啊，是我的指令少了 -r...重跑一次：」就停了。
      // 根因：串流中途被斷，tool call 有頭無尾，parser 配對不到
      // → 誤判「沒有工具呼叫 = 自主結束」→ loop 退出，遺言停在冒號。
      // 修法：偵測截斷（有 start 無 end / 結尾懸空冒號）→ 注入提示重試，
      // 不讓任務死在斷線手裡。
      final truncated = AgentToolCallParser.hasTruncatedToolCall(llmOutput) ||
          (toolCalls.isEmpty &&
              AgentToolCallParser.endsWithDanglingColon(llmOutput));
      if (toolCalls.isEmpty && truncated) {
        consecutiveTruncations++;
        if (consecutiveTruncations >= 3) {
          debugPrint('[AgentLoop] 連續 3 次截斷，放棄重試並回報');
          final replyText = AgentToolCallParser.extractText(llmOutput);
          return AgentLoopResult(
            reply: replyText.isEmpty
                ? '抱歉，我的輸出連續被截斷，無法完成任務。請再試一次。'
                : '$replyText\n\n（後續工具呼叫連續被截斷，任務中斷）',
            turns: turns,
            hitTurnLimit: false,
            cancelled: false,
            elapsed: stopwatch.elapsed,
          );
        }
        debugPrint('[AgentLoop] 偵測到截斷的 tool call，注入重試提示');
        onStage?.call('retry', detail: '上次輸出被截斷，重新輸出工具呼叫...');
        messages.add({'role': 'assistant', 'content': llmOutput});
        messages.add({
          'role': 'user',
          'content': '〔你上一則回覆在輸出工具呼叫時被截斷了（內容不完整）。'
              '請直接重新輸出完整的工具呼叫，格式：'
              '<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>。'
              '不要重複解釋，直接給工具呼叫。〕',
        });
        continue;
      }
      // [教練 Agent 2026-08-16] 成功解析到完整 tool call → 重置截斷計數
      if (toolCalls.isNotEmpty) consecutiveTruncations = 0;

      // [小葵 2026-09-16 Blue 令] 結構性續跑——取代詞表式「說了不做」防護。
      // 病例史：詞表（先看/再動手/找…）永遠追不完新句式；nudge 2 次太少；
      // 且「進行中談話」式回覆讓使用者無法分辨「工作中」與「停了」。
      // 新規則（不猜句子，看結構）：
      //   沒有 tool call 且 回覆沒有 [[TASK_DONE]] 標記 且 未達 nudge 上限（5）
      //   → 注入結構性 nudge：要嘛給下一個 tool call，要嘛打 [[TASK_DONE]] 收工。
      // 完成宣告的唯一可靠訊號 = [[TASK_DONE]]（prompt 鐵則已要求收工必打）。
      if (toolCalls.isEmpty &&
          turn < effectiveMax - 1 &&
          !llmOutput.contains('[[TASK_DONE]]') &&
          statedIntentNudges < 5) {
        statedIntentNudges++;
        debugPrint('[AgentLoop] 結構性續跑 nudge（第 $statedIntentNudges/5 次）');
        // [小葵 2026-09-18 僵局喚醒] nudge >= 3 換強措辭——明確告知後果
        // （病例：09:23 小橋連吃 2 個 nudge 無效，看起來像當機）
        messages.add({'role': 'assistant', 'content': llmOutput});
        // [小葵 2026-09-18 僵局喚醒] 第 3 次起升級措辭：講後果＋收斂選項
        final urgent = statedIntentNudges >= 3;
        messages.add({
          'role': 'user',
          'content': urgent
              ? '〔最後提醒〕這是第 $statedIntentNudges 次沒有工具呼叫也沒有 [[TASK_DONE]]。'
                  '再這樣下去本輪會被視為僵局結束，你的任務將停在此處。'
                  '立刻二選一：① 下一個工具呼叫 '
                  '（<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>）；'
                  '② 收工報告＋[[TASK_DONE]]。沒有第三個選項。〕'
              : '〔系統提醒〕你的回覆沒有工具呼叫，也沒有 [[TASK_DONE]] 收工標記——'
                  '對使用者來說這看起來像「停了」。請立刻二選一：'
                  '① 繼續執行：輸出下一個工具呼叫 '
                  '（格式：<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>）；'
                  '② 任務已完成：輸出結構化收工報告（已完成清單＋證據引用），'
                  '並在報告結尾加上 [[TASK_DONE]]。'
                  '不要回覆「我接下來要…」這種未來式——直接做，或明確收工。〕',
        });
        continue;
      }
      statedIntentNudges = 0; // 有行動或明確收工都重置

      // 沒有 tool call = LLM 自主結束（Hermes 模式——信任 LLM 判斷）
      // [小葵 2026-09-18] 但若因 nudge 耗盡被結束（僵局），reply 必須標記僵局而非假裝自主收工
      // [小葵 2026-09-22 Blue 令] 輕裝升級出口——模型說〔需要工具〕時
      // 自動重進全裝 loop（K1 誤判的自癒路徑，零人工）：
      // 輕裝只花 ~2K tokens 試答；試完發現要工具 → 全裝接手完成任務。
      // 誤判成本封頂（一輪輕裝），任務必達（全裝收尾）。
      if (toolCalls.isEmpty) {
        final reply = AgentToolCallParser.extractText(llmOutput);
        if (isLiteEligible && _liteNeedsTool.hasMatch(llmOutput)) {
          debugPrint('[AgentLoop] 輕裝→全裝升級：模型表明需要工具，'
              '重進全裝 loop');
          return _runInner(
            systemPrompt: systemPrompt, // 全裝原版
            userMessage: '$userMessage\n〔系統註記：此任務需要工具，已為你切換全裝配備。直接開始執行。〕',
            maxTurns: maxTurns,
            onProgress: onProgress,
            onStage: onStage,
            onUserMessage: onUserMessage,
            isCancelled: isCancelled,
            prohibitPaidTools: prohibitPaidTools,
          );
        }
        final finalTurn = AgentLoopTurn(
          turnIndex: turn,
          llmRawOutput: llmOutput,
          finalReply: reply,
        );
        turns.add(finalTurn);
        onProgress?.call(turn, effectiveMax, null, null, llmOutput);
        stopwatch.stop();
        return AgentLoopResult(
          reply: reply,
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      // 有 tool call = 執行第一個（v1 一次只執行一個）
      final toolCall = toolCalls.first;
      final tool = toolRegistry.get(toolCall.name);
      onStage?.call('tool_start', toolName: toolCall.name, detail: '正在執行：${toolCall.name}');
      debugPrint('[AgentLoop] 執行工具: ${toolCall.name} args=${toolCall.args}');

      // [2026-07-19] 連續截圖追蹤 + nudge
      // [2026-07-20] 加入 canvas_screenshot——原生 Agent的 canvas MCP 截圖工具也要追蹤
      if (toolCall.name == 'screen_capture' ||
          toolCall.name == 'screenshot' ||
          toolCall.name == 'canvas_screenshot') {
        consecutiveScreenshots++;
        if (consecutiveScreenshots >= 2) {
          debugPrint('[AgentLoop] 連續截圖 $consecutiveScreenshots 次，注入推進 nudge');
          messages.add({
            'role': 'user',
            'content':
                '〔系統提醒〕你已連續截圖 $consecutiveScreenshots 次。'
                '如果畫面沒有變化，繼續截圖不會得到新資訊。'
                '考慮改用 read_source_file 讀取相關程式碼，或用 ui_get_state 確認 UI 結構，'
                '然後直接給出分析或修復方案。',
          });
        }
      } else {
        consecutiveScreenshots = 0;
      }

      // [2026-07-19] 通用循環防護——連續相同工具呼叫追蹤
      if (toolCall.name == lastToolName) {
        consecutiveSameTool++;
      } else {
        consecutiveSameTool = 1;
        lastToolName = toolCall.name;
      }
      if (consecutiveSameTool >= 5 && consecutiveSameTool < 10) {
        debugPrint(
          '[AgentLoop] 連續呼叫 $lastToolName $consecutiveSameTool 次，注入推進 nudge',
        );
        messages.add({
          'role': 'user',
          'content':
              '〔系統提醒〕你已連續呼叫 $lastToolName $consecutiveSameTool 次。'
              '如果這個工具沒有給你新資訊，重複呼叫不會有幫助。'
              '請換一個工具，或根據目前收集到的資訊直接回覆使用者。',
        });
      } else if (consecutiveSameTool >= 10) {
        debugPrint(
          '[AgentLoop] 連續呼叫 $lastToolName $consecutiveSameTool 次，強制結束 loop',
        );
        messages.add({
          'role': 'user',
          'content': '已達連續相同工具呼叫上限。請根據目前收集到的資訊，直接回覆使用者，不要再使用工具。',
        });
      }

      // [2026-07-20] 工具序列 pattern 偵測——防 A→B→A→B 交替循環
      // consecutiveSameTool 只防「同一工具連續呼叫」，防不住交替循環。
      // 偵測最近工具序列是否有重複 pattern（長度 2-4）：
      // 例如 [A,B,A,B,A,B] = pattern [A,B] 重複 3 次 → 卡住
      //
      // 注意：同一工具的連續呼叫（[A,A,A,A]）由 consecutiveSameTool 處理，
      // pattern 偵測只管 A→B→A→B 真正的交替循環。
      // 如果 pattern 裡所有工具都相同（如 [A,A]），跳過——交給 consecutiveSameTool。
      toolCallHistory.add(toolCall.name);
      final patternResult = _detectRepeatingPattern(toolCallHistory);
      if (patternResult != null) {
        final pattern = patternResult.pattern;
        final reps = patternResult.repetitions;
        // pattern 裡所有工具都相同 = 不是交替循環，是 consecutiveSameTool 的工作
        final isAlternating = pattern.toSet().length > 1;

        if (isAlternating) {
          debugPrint(
            '[AgentLoop] 偵測到工具交替序列重複: $pattern ×$reps (歷史 ${toolCallHistory.length} 步)',
          );

          if (reps >= 4) {
            // 4 次以上交替重複 = 強制結束，直接回覆使用者
            debugPrint('[AgentLoop] 工具交替循環 ×$reps，強制結束 loop');
            messages.add({
              'role': 'user',
              'content':
                  '你正在重複相同的工具序列（${pattern.join(' → ')}）已 $reps 次。'
                  '畫面狀態很可能沒有變化，繼續查看不會得到新資訊。'
                  '請根據目前收集到的資訊，直接回覆使用者你的分析和建議，不要再呼叫工具。',
            });
          } else if (reps >= 2 && reps > lastPatternRepsInjected) {
            // 2-3 次交替重複 = 注入 nudge，只在升級時注入一次
            lastPatternRepsInjected = reps;
            debugPrint('[AgentLoop] 工具交替循環 ×$reps，注入推進 nudge');
            messages.add({
              'role': 'user',
              'content':
                  '〔系統提醒〕你正在重複相同的工具序列（${pattern.join(' → ')}）$reps 次。'
                  '如果狀態沒有變化，重複查看不會帶來新資訊。'
                  '請根據已有資訊直接回覆使用者，或換一個你還沒用過的工具。',
            });
          }
        }
      }

      AgentToolResult? toolResult;
      // [軍醫 W3 2026-09-17] 出診①動手前——高風險工具執行前注入羅盤卡。
      // fail-open：medic 掛了不擋任務（內部全 try-catch）。
      String? medicBrief;
      if (tool != null) {
        try {
          medicBrief = CompassMedic.instance.preFlight(toolCall.name, toolCall.args);
          if (medicBrief != null) {
            debugPrint('[軍醫] 出診：${toolCall.name} 注入 ${medicBrief.length} chars');
          }
        } catch (_) {}
      }
      if (tool == null) {
        // 未註冊的工具名 = 回報錯誤給 LLM
        toolResult = AgentToolResult.failure(
          '工具「${toolCall.name}」不存在。可用工具：${toolRegistry.all.map((t) => t.name).join(', ')}',
        );
      } else if (prohibitPaidTools &&
          AgentSafetyConstraints.paidGenerativeTools.contains(toolCall.name)) {
        // [教練 Agent 2026-08-20] 機器訊息輪次的付費工具閘門——直接拒絕，不執行、
        // 不跳確認框。LLM 會收到這個說明並改用文字回覆。
        debugPrint('[AgentLoop] 機器輪次禁用付費工具 ${toolCall.name}');
        toolResult = AgentToolResult.failure(
          '此輪對話由系統事件（節點結果/畫布狀態）觸發，不是使用者親自請求。'
          '付費生成工具（${toolCall.name}）只在使用者親自發言時可用。'
          '請用文字總結目前工作流的進度與結果即可。',
        );
      } else {
        // [D002 2026-08-09] 破壞性操作確認——在執行前檢查
        // [D002 2026-08-10] 改用實例欄位，所有 run() 呼叫（含 NativeAgentLoop）自動生效
        if (onToolConfirmation != null &&
            AgentSafetyConstraints.needsToolConfirmation(toolCall.name, toolCall.args)) {
          final isDestructive =
              AgentSafetyConstraints.isToolDestructive(toolCall.name, toolCall.args);
          debugPrint('[AgentLoop] 工具 ${toolCall.name} 需要確認${isDestructive ? '（破壞性）' : ''}，暫停等待使用者');

          final confirmed = await onToolConfirmation!(
            toolName: toolCall.name,
            args: toolCall.args,
          );

          if (!confirmed) {
            debugPrint('[AgentLoop] 使用者拒絕了 ${toolCall.name}，跳過');
            toolResult = AgentToolResult.failure(
              '使用者拒絕了此操作（${toolCall.name}）。',
            );
          } else {
            debugPrint('[AgentLoop] 使用者確認了 ${toolCall.name}，繼續執行');
            try {
              toolResult = await tool.execute(toolCall.args);
            } catch (e) {
              toolResult = AgentToolResult.failure(e.toString());
            }
          }
        } else {
          try {
            toolResult = await tool.execute(toolCall.args);
          } catch (e) {
            toolResult = AgentToolResult.failure(e.toString());
          }
        }
      }

      final loopTurn = AgentLoopTurn(
        turnIndex: turn,
        toolCall: toolCall,
        toolResult: toolResult,
        llmRawOutput: llmOutput,
      );
      turns.add(loopTurn);
      onStage?.call('tool_done', toolName: toolCall.name, detail: toolResult?.success == true ? '完成' : '失敗');
      onProgress?.call(turn, effectiveMax, toolCall, toolResult, llmOutput);

      // [因果引擎 L1 2026-09-11] 介入帳本——所有工具執行的咽喉點記帳。
      // 執行即記（不靠 agent 自覺）：do(工具+參數摘要) @ 情境 → 觀測(結果摘要)。
      // fail-open：record 內部吞錯留痕，絕不影響 loop。
      if (tool != null) {
        CausalLedger.instance.record(CausalEntry(
          toolName: toolCall.name,
          intervention: CausalLedger.digestArgs(toolCall.args),
          contextDigest: _causalContextDigest ?? toolCall.name,
          observedOutcome:
              CausalLedger.digestResult(toolResult.content, toolResult.success),
          success: toolResult.success,
          companionId: CausalLedger.instance.ambientCompanionId,
          at: DateTime.now(),
        ));
      }

      // [軍醫 W3/W4 2026-09-17] 撞牆出診＋傷口自癒——掛因果帳本同址。
      // ①失敗計數：同工具連續失敗 ≥2 → 送藥注入下一輪
      // ②失敗自動立案 pending pitfall；之後同工具成功 → 自動草擬藥方
      // 全部 fail-open，絕不影響 loop。
      if (tool != null) {
        try {
          final toolOk = toolResult.success;
          if (!toolOk) {
            _medicFailStreak[toolCall.name] =
                (_medicFailStreak[toolCall.name] ?? 0) + 1;
            CompassMedic.instance
                .fileWoundCase(toolCall.name, toolResult.content);
            if ((_medicFailStreak[toolCall.name] ?? 0) >= 2) {
              final rescue = CompassMedic.instance
                  .onWallHit(toolCall.name, toolResult.content);
              if (rescue != null) {
                medicRescueQueued = rescue;
                debugPrint('[軍醫] 撞牆出診：${toolCall.name} 連敗 ${_medicFailStreak[toolCall.name]} 次，送藥');
              }
            }
          } else {
            // 成功：結算 pending 傷口（失敗→成功對照=藥方）
            if ((_medicFailStreak[toolCall.name] ?? 0) > 0) {
              CompassMedic.instance
                  .closeWoundCase(toolCall.name, toolResult.content);
              debugPrint('[軍醫] 傷口結算：${toolCall.name} pending→藥方入庫');
            }
            _medicFailStreak[toolCall.name] = 0;
          }
        } catch (_) {}
      }

      // ── 媒體短路：生成型媒體工具（generate_image 等）成功後直接結束 loop ──
      // screen_capture 是感知工具，不短路——原生 Agent還需要看截圖結果繼續做事
      // [教練 Agent 2026-07-18] 修復：screen_capture 被誤短路導致原生 Agent無法繼續後續步驟
      final isGenerativeMediaTool = toolCall.name == 'generate_image';
      if (isGenerativeMediaTool &&
          toolResult.success &&
          toolResult.mediaUrl != null &&
          toolResult.mediaUrl!.isNotEmpty) {
        final replyText = AgentToolCallParser.extractText(llmOutput);
        stopwatch.stop();
        return AgentLoopResult(
          reply: replyText.isEmpty ? '圖片已生成完成！' : replyText,
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      // 圖片生成失敗也立即結束：使用者指定的 provider 若沒有 adapter、
      // token 或遠端服務失敗，不能自動偏航去截圖／vision／猜測設定。
      if (isGenerativeMediaTool && !toolResult.success) {
        stopwatch.stop();
        return AgentLoopResult(
          reply: toolResult.content,
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      // 把 LLM 回覆加入對話歷史
      messages.add({'role': 'assistant', 'content': llmOutput});

      // [2026-07-19 使用者洞察] 截圖看完就清——讓後續推理回到 GLM-5.2
      // 問題：messages 裡只要有 image_url，ApiService 就走 vision fallback (glm-4.6v)。
      // 截圖嵌入後，即使 LLM 已看完圖並回覆，舊 base64 還在 messages 裡 →
      // hasImages 永遠 true → 讀碼、分析、寫碼全部用 glm-4.6v 跑（慢且弱）。
      // Hermes 模式：vision_analyze 看圖→得文字描述→後續純文字推理。
      // 原生 Agent對齊：截圖→glm-4.6v 看一次→LLM 回覆後清掉圖→回到 glm-5.2。
      _evictOldScreenshots(messages);

      // 把工具結果加入對話歷史（讓 LLM 下一輪看到結果）
      // [2026-07-18] multimodal vision：screen_capture 等工具的截圖
      // 不再只回傳檔案路徑字串，而是讀檔轉 base64 嵌入 image_url content block
      // 讓 LLM 真正「看到」畫面像素，實現視覺美感審查
      // [軍醫 W3 2026-09-17] 動手前藥卡附在工具結果前——LLM 下一輪
      // 同時看到「藥卡＋執行結果」，直接對照學習。
      if (medicBrief != null && medicBrief!.isNotEmpty) {
        messages.add({'role': 'user', 'content': medicBrief!});
      }
      if (toolResult.success &&
          toolResult.mediaUrl != null &&
          toolResult.mediaUrl!.isNotEmpty &&
          _isImageMediaUrl(toolResult.mediaUrl!) &&
          toolCall.name != 'generate_image') {
        // 嘗試把圖片嵌入 message
        final imageContent = await _buildImageContent(
          toolResult.content,
          toolResult.mediaUrl!,
          toolCall.name,
        );
        if (imageContent != null) {
          messages.add({'role': 'user', 'content': imageContent});
        } else {
          // 圖片讀取失敗，fallback 到純文字
          messages.add({
            'role': 'user',
            'content':
                '工具 ${toolCall.name} 的執行結果：\n${toolResult.content}\n（圖片嵌入失敗，路徑：${toolResult.mediaUrl}）',
          });
        }
      } else if (toolResult.success) {
        final resultParts = <String>[];
        resultParts.add(toolResult.content);
        if (toolResult.mediaUrl != null && toolResult.mediaUrl!.isNotEmpty) {
          resultParts.add('媒體檔案路徑：${toolResult.mediaUrl}');
          resultParts.add('（這是本機檔案路徑，圖片已成功儲存。請在回覆中告知使用者圖片已生成，不需要再提供連結。）');
        }
        final resultText = resultParts.join('\n');
        messages.add({
          'role': 'user',
          'content': '工具 ${toolCall.name} 的執行結果：\n$resultText',
        });
      } else {
        messages.add({
          'role': 'user',
          'content': '工具 ${toolCall.name} 的執行結果：\n[錯誤] ${toolResult.content}',
        });
      }
    }

    // 跑到這裡 = 到了上限但 LLM 仍在呼叫工具
    // 做一次 final LLM call 強制回覆
    stopwatch.stop();
    return AgentLoopResult(
      reply: _buildGracefulReply(turns),
      turns: turns,
      hitTurnLimit: true,
      cancelled: false,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Graceful termination 回覆——把目前累積的工具結果摘要給使用者
  String _buildGracefulReply(List<AgentLoopTurn> turns) {
    if (turns.isEmpty) return '我完成了任務。';

    final toolCount = turns.where((t) => t.toolCall != null).length;
    final lastToolTurns = turns.where((t) => t.toolCall != null).takeLast(3);

    final summary = StringBuffer();
    summary.write('我進行了 $toolCount 次工具操作，以下是最近的结果：\n\n');
    for (final turn in lastToolTurns) {
      if (turn.toolCall != null && turn.toolResult != null) {
        final status = turn.toolResult!.success ? '成功' : '失敗';
        summary.write('• ${turn.toolCall!.name}（$status）\n');
      }
    }
    summary.write('\n由於達到工具使用次數上限，以上是目前收集到的資訊。');

    return summary.toString();
  }


  /// [小葵 2026-09-22 Blue 令] 輕裝 system prompt——純記憶題用。
  /// 身份＋誠實鐵則，不帶工具/人格卡/畫布/預算眼（~500 chars）。
  /// 記憶卡由 K1 檢索附在 user 訊息，模型必讀。
  /// [升級出口] 若問題其實需要工具，模型說「需要查/讀/執行」——
  /// loop 偵測到此跡象自動重進全裝（見 lite 重跑邏輯）。
  String _buildLiteSystemPrompt(String toolKit) {
    return """# 你的身份
你是橋樑 App 的原生 Agent，與使用者同一台機器上對話。用繁體中文回答。

# 回答規則（記憶題）
1. 使用者訊息中〔K1 記憶命中〕的內容是檢索到的記憶卡——優先依它回答，引用時保持原意。
2. 記憶卡沒有的資訊就誠實說「記憶中沒有這個紀錄」，禁止編造或腦補。
3. 直接回答問題本身，簡潔自然。
4. 若配備的工具不足以完成任務，在回覆開頭說「〔需要工具〕」加一句說明需要什麼，系統會自動為你升級。
5. 【白話鐵則】回答用一般人看得懂的白話——你是跟「人」對話，不是跟工程師 code review。
   - 技術名詞必須翻譯成人話。例：不寫「k1_gatekeeper conf=0.7」，寫「守門員覺得有七成把握才去查記憶」。
   - 證據引用說「出處」，不貼記憶卡 ID（mem_123...）或內部參數——技術細節放到文末【技術細節】區。
   - 回覆結構：白話正文在上；開發者需要的技術細節（工具名、ID、參數、原始輸出）一律放在最後，
     用「【技術細節】」一行獨立標記開頭，之後的內容 UI 會自動摺疊成可點開的區塊。
   - 一句話自檢：國高中生看得懂才算合格。

$toolKit
""";
  }

  /// [小葵 2026-09-22] 輕裝誤判偵測——模型表明需要工具時的重跑訊號
  static final RegExp _liteNeedsTool = RegExp(r'〔需要工具〕');

  String _buildCancelledReply(List<AgentLoopTurn> turns) {
    if (turns.isEmpty) return '操作已取消。';
    final toolCount = turns.where((t) => t.toolCall != null).length;
    return '操作已取消。之前完成了 $toolCount 次工具操作。';
  }

  /// [2026-07-20] 偵測工具序列中的重複 pattern
  ///
  /// 檢查最近 N 次工具呼叫是否形成重複循環（如 A→B→A→B→A→B）。
  /// 嘗試 pattern 長度 2~4，回傳最先匹配到的 pattern 和重複次數。
  /// 只看歷史尾部——中間曾經用過同工具不算循環。
  ///
  /// 回傳 null = 沒有偵測到重複 pattern。
  static _ToolPatternResult? _detectRepeatingPattern(List<String> history) {
    if (history.length < 4) return null; // 至少要 4 步才能形成 2×2 重複

    for (int plen = 2; plen <= 4; plen++) {
      // 從尾部取整數倍的段落來檢查
      final maxReps = history.length ~/ plen;
      if (maxReps < 2) continue;

      // 取最後 maxReps*plen 步
      final tail = history.sublist(history.length - maxReps * plen);
      final pattern = tail.sublist(0, plen);

      bool allMatch = true;
      for (int r = 1; r < maxReps; r++) {
        for (int i = 0; i < plen; i++) {
          if (tail[r * plen + i] != pattern[i]) {
            allMatch = false;
            break;
          }
        }
        if (!allMatch) break;
      }

      if (allMatch && maxReps >= 2) {
        return _ToolPatternResult(pattern, maxReps);
      }
    }

    return null;
  }

  /// 判斷 mediaUrl 是否為可嵌入的圖片
  /// 支援：本機 .png/.jpg/.jpeg 檔案路徑、data:image/ base64 URI
  bool _isImageMediaUrl(String url) {
    if (url.startsWith('data:image/')) return true;
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  /// [2026-07-19 使用者洞察] 截圖 eviction——LLM 看完圖後清掉所有 image_url
  ///
  /// 核心問題：messages 裡只要有 image_url，ApiService 就走 vision fallback (glm-4.6v)。
  /// 截圖嵌入 → glm-4.6v 看圖 → LLM 回覆 → 舊 base64 還在 messages → hasImages=true
  /// → 讀碼/分析/寫碼全用 glm-4.6v 跑（慢且弱）。
  ///
  /// Hermes 模式：vision_analyze 看圖 → 得文字描述 → 後續純文字推理。
  /// 原生 Agent對齊：截圖 → glm-4.6v 看一次 → LLM 回覆後清掉圖 → 回到 glm-5.2。
  ///
  /// 策略：LLM 回覆加入 messages 後，把所有 image_url content 換成文字佔位符。
  /// LLM 的文字分析（assistant messages）完整保留——它記得「看到什麼」，
  /// 但後續輪次不再帶 base64 像素，回到 glm-5.2 做推理。
  void _evictOldScreenshots(List<Map<String, dynamic>> messages) {
    int evictedCount = 0;

    for (int i = 0; i < messages.length; i++) {
      final content = messages[i]['content'];
      if (content is List) {
        final hasImage = content.any(
          (part) =>
              part is Map<String, dynamic> && part.containsKey('image_url'),
        );
        if (hasImage) {
          // 保留文字部分，image_url 換成佔位符
          final textParts = <Map<String, dynamic>>[];
          for (final part in content) {
            if (part is Map<String, dynamic> && part['type'] == 'text') {
              textParts.add(part);
            }
          }
          textParts.add({
            'type': 'text',
            'text': '〔截圖已由 vision 模型分析完畢，已移除 base64 以節省 context。你的文字分析仍保留在上方。〕',
          });
          messages[i] = {'role': messages[i]['role'], 'content': textParts};
          evictedCount++;
        }
      }
    }

    if (evictedCount > 0) {
      debugPrint(
        '[AgentLoop] 截圖 eviction: 清除 $evictedCount 張截圖 base64，後續回到文字模型',
      );
    }
  }

  /// 把截圖檔案讀取轉 base64，組成 OpenAI vision multimodal content
  ///
  /// 回傳 List<Map> 格式：
  /// [
  ///   {type: 'text', text: '工具結果文字...'},
  ///   {type: 'image_url', image_url: {url: 'data:image/png;base64,...'}},
  /// ]
  /// 回傳 null = 圖片讀取失敗
  Future<List<Map<String, dynamic>>?> _buildImageContent(
    String textResult,
    String mediaUrl,
    String toolName,
  ) async {
    try {
      // [2026-07-20] 統一壓縮路徑——data URI 和檔案路徑都走同一套壓縮
      // 之前 data URI（canvas_screenshot 回傳的）直接跳過壓縮，
      // 全解析度 PNG 送 glm-4.6v 導致反覆 timeout
      Uint8List bytes;
      String? sourceMimeType;

      if (mediaUrl.startsWith('data:image/')) {
        // data URI — 解出 base64 bytes
        final commaIdx = mediaUrl.indexOf(',');
        if (commaIdx < 0) {
          debugPrint('[AgentLoop] data URI 格式錯誤：$mediaUrl');
          return null;
        }
        final header = mediaUrl.substring(
          0,
          commaIdx,
        ); // e.g. "data:image/png;base64"
        sourceMimeType =
            header.contains('image/jpeg') || header.contains('image/jpg')
            ? 'image/jpeg'
            : header.contains('image/webp')
            ? 'image/webp'
            : 'image/png';
        bytes = base64Decode(mediaUrl.substring(commaIdx + 1));
        if (bytes.isEmpty) {
          debugPrint('[AgentLoop] data URI base64 解出 0 bytes — 空截圖');
          return null;
        }
      } else {
        // 本機檔案路徑
        final file = File(mediaUrl);
        if (!await file.exists()) {
          debugPrint('[AgentLoop] 截圖檔案不存在：$mediaUrl');
          return null;
        }
        bytes = await file.readAsBytes();
        final lower = mediaUrl.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
          sourceMimeType = 'image/jpeg';
        else if (lower.endsWith('.webp'))
          sourceMimeType = 'image/webp';
        else
          sourceMimeType = 'image/png';
      }

      // [2026-07-18] 截圖壓縮：大圖片會讓 vision API 超時
      // 縮小到最大 1024px 寬，轉 JPEG 品質 85
      // [2026-07-20] data URI 也走這條路——canvas_screenshot 全解析度 PNG 同樣會 timeout
      String mimeType = sourceMimeType;
      try {
        final decoded = image.decodeImage(bytes);
        if (decoded != null) {
          int targetWidth = decoded.width;
          int targetHeight = decoded.height;
          if (decoded.width > 1024 || decoded.height > 1024) {
            final ratio = decoded.width > decoded.height
                ? 1024 / decoded.width
                : 1024 / decoded.height;
            targetWidth = (decoded.width * ratio).round();
            targetHeight = (decoded.height * ratio).round();
          }
          final resized = (targetWidth != decoded.width)
              ? image.copyResize(
                  decoded,
                  width: targetWidth,
                  height: targetHeight,
                )
              : decoded;
          bytes = image.encodeJpg(resized, quality: 85);
          mimeType = 'image/jpeg';
          debugPrint(
            '[AgentLoop] 截圖壓縮：${decoded.width}x${decoded.height} → ${targetWidth}x${targetHeight}, ${bytes.length} bytes',
          );
        }
      } catch (e) {
        debugPrint('[AgentLoop] 截圖壓縮失敗（用原圖）：$e');
      }

      final base64Data = base64Encode(bytes);
      final dataUrl = 'data:$mimeType;base64,$base64Data';
      debugPrint(
        '[AgentLoop] 圖片嵌入 message：$mimeType, ${bytes.length} bytes → ${base64Data.length} chars base64',
      );

      return [
        {
          'type': 'text',
          'text': '工具 $toolName 的執行結果：\n$textResult\n\n以下是截圖畫面，請用視覺分析：',
        },
        {
          'type': 'image_url',
          'image_url': {'url': dataUrl},
        },
      ];
    } catch (e) {
      debugPrint('[AgentLoop] 圖片嵌入失敗：$e');
      return null;
    }
  }

  // [2026-07-19] _looksLikeCompletion 已移除
  // Hermes 模式：信任 LLM 判斷——回覆不含 tool call = 自然結束
  // 不需要關鍵詞猜測，完成偵測造成誤判（工作中途被當完成）
}

/// 取 list 最後 N 個元素（Dart 標準庫沒有 takeLast）
extension TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}
