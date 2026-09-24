/// Voice AI 主引擎 — 新三層回應架構
library;

/// 管理語音對談的完整生命週期，觸發三層回應：
///
///   層 1：狀態語音（thinking 時）
///     進入 thinking 時用 Kokoro 朗讀「我來查查看…」
///     深夜時段自動用 sleepiness 語氣
///
///   層 2：回應朗讀（Kokoro + 情緒）
///     Agent 結果出來後，解析 LLM 輸出的 `<emotion>` 和 `<confidence>` 標籤
///     根據敏感度判斷是否使用情緒，語速自動連動
///     Kokoro 用對應 style vector 朗讀
///
///   層 3：情緒記憶
///     記住最近 5 次情緒，下次對話有連貫性
///     深夜時段（22:00-06:00）自動用 sleepiness
///
/// 使用方式：
///   final engine = VoiceEngine(
///     onSpeak: (text) => ttsHandler.speak(text),
///     onStopSpeaking: () => ttsHandler.stop(),
///     onPlayAudioBytes: (bytes) => audioPlayer.play(bytes),
///     onAgentLoopTrigger: (userText, onProgress, onComplete) => agentLoop.run(userText),
///   );
///   await engine.startConversation();
///   // ... 使用者說話 → engine.onSpeechRecognized(text)
///   await engine.stopConversation();

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tts/kokoro_tts_service.dart';
import 'companion_voice_settings.dart'; // [教練 Agent 2026-08-03] C4
import 'voice_state_machine.dart';

/// 語音輸入結果（從 STT 傳來）
///
/// 包含辨識文字和語音特徵資料。
class VoiceInput {
  /// 辨識出的文字
  final String text;

  /// 音訊振幅樣本（0.0 ~ 1.0）— 保留欄位，新架構不使用
  final List<double> audioSamples;

  /// 總錄音時長
  final Duration duration;

  const VoiceInput({
    required this.text,
    required this.audioSamples,
    required this.duration,
  });
}

/// Kokoro TTS 朗讀回調 — 帶情緒和語速參數（fallback 用，建議改用 onPlayAudioBytes）
///
/// [text] — 要朗讀的文字
/// [emotion] — 情緒標籤（amused/neutral/sleepiness/anger/disgust）
/// [speed] — 語速倍率（1.0 = 正常）
typedef KokoroSpeakCallback = void Function(
  String text, {
  String? emotion,
  double? speed,
});

/// 音檔播放回調 — 接收 Kokoro 合成的音檔 bytes 進行播放
///
/// VoiceEngine 透過 KokoroTtsService 合成語音後，將音檔 bytes 傳給此回調播放。
/// 呼叫端應使用 audioplayers / just_audio 等套件實作實際播放邏輯。
typedef PlayAudioBytesCallback = void Function(Uint8List audioBytes);

/// AgentLoop 觸發回調
///
/// 當 VoiceEngine 需要啟動背景 AgentLoop 時呼叫。
/// [userText] — 使用者說的話
/// [onProgress] — 中間結果回調（狀態語音用）
/// [onComplete] — 最終結果回調（包含 LLM 輸出的情緒標籤）
typedef AgentLoopTrigger = void Function({
  required String userText,
  required void Function(String intermediateText) onProgress,
  required void Function(String finalReply) onComplete,
});

/// 支援的情緒標籤
const List<String> _supportedEmotions = [
  'neutral',
  'amused',
  'sleepiness',
  'anger',
  'disgust',
];

/// 情緒 → 語速調整倍率
const Map<String, double> _emotionSpeedAdjust = {
  'amused': 1.1, // 愉悅 → +10% 語速
  'neutral': 1.0, // 中性 → 正常
  'sleepiness': 0.85, // 困倦 → -15% 語速
  'anger': 1.15, // 憤怒 → +15% 語速
  'disgust': 0.9, // 厭惡 → -10% 語速
};

/// 解析 LLM 回覆中的情緒標籤和信心分數
///
/// 從回覆文字中提取 `<emotion>...</emotion>` 和 `<confidence>...</confidence>` 標籤，
/// 回傳清理後的回覆文字和解析結果。
({String reply, String? emotion, double? confidence}) parseEmotionTags(
  String rawReply,
) {
  String reply = rawReply;
  String? emotion;
  double? confidence;

  // 解析 <emotion> 標籤
  final emotionMatch = RegExp(
    r'<emotion>\s*(\w+)\s*</emotion>',
    caseSensitive: false,
  ).firstMatch(reply);
  if (emotionMatch != null) {
    final tag = emotionMatch.group(1)!.toLowerCase();
    if (_supportedEmotions.contains(tag)) {
      emotion = tag;
    }
    // 移除標籤本身
    reply = reply.replaceFirst(emotionMatch.group(0)!, '').trim();
  }

  // 解析 <confidence> 標籤
  final confMatch = RegExp(
    r'<confidence>\s*([\d.]+)\s*</confidence>',
    caseSensitive: false,
  ).firstMatch(reply);
  if (confMatch != null) {
    final value = double.tryParse(confMatch.group(1)!);
    if (value != null) {
      confidence = value.clamp(0.0, 1.0);
    }
    reply = reply.replaceFirst(confMatch.group(0)!, '').trim();
  }

  return (reply: reply, emotion: emotion, confidence: confidence);
}

/// Voice AI 主引擎 — 新三層回應架構
///
/// 協調狀態語音、Kokoro 朗讀、情緒記憶，管理語音對談的生命週期。
///
/// 狀態流轉由 VoiceStateMachine 管理，引擎在狀態轉換時觸發對應的回應層。
/// KokoroTtsService 由引擎內部管理生命週期，啟動/停止隨對談開關。
class VoiceEngine {
  /// TTS 朗讀回調（基本模式 — 不帶情緒）
  ///
  /// 當 KokoroTtsService 未啟動或合成失敗時使用此回調。
  /// 通常接 ChatTtsHandler.speak()。
  final void Function(String text) onSpeak;

  /// Kokoro TTS 朗讀回調（fallback — 帶情緒和語速）
  ///
  /// 當 Kokoro server 不可用時，作為第二層 fallback 使用。
  final KokoroSpeakCallback? onKokoroSpeak;

  /// 音檔播放回調 — 接收 Kokoro 合成的音檔 bytes 進行播放
  ///
  /// VoiceEngine 透過 KokoroTtsService 合成語音後，將 bytes 傳給此回調。
  /// 呼叫端需實作實際的音檔播放邏輯（如 audioplayers）。
  final PlayAudioBytesCallback? onPlayAudioBytes;

  /// 停止 TTS 朗讀回調
  ///
  /// 通常接 ChatTtsHandler.stop()。
  final Future<void> Function() onStopSpeaking;

  /// AgentLoop 觸發回調 — 啟動背景運算
  final AgentLoopTrigger? onAgentLoopTrigger;

  /// 語音名稱（Kokoro 聲音 ID，如 'zf_xiaoxiao'）
  final String voiceName;

  /// 基礎語速（0.5–2.0，預設 1.0）
  final double baseSpeed;

  /// 情緒表達開關
  final bool emotionEnabled;

  /// 情緒敏感度（0.0–1.0）— 值越高越容易觸發情緒
  ///
  /// 判斷閾值：confidence > (1.0 - sensitivity) 才使用 LLM 情緒標籤。
  /// sensitivity = 0.5 → confidence > 0.5 才採信。
  /// sensitivity = 0.8 → confidence > 0.2 就採信（高敏感度）。
  final double emotionSensitivity;

  /// 專案根目錄路徑（用於定位 Kokoro Python server 腳本）
  final String? projectRoot;

  /// [教練 Agent 2026-08-03] C4: 夥伴完整語音設定（優先級高於上面的建構參數）
  final CompanionVoiceSettings? settings;

  // [教練 Agent 2026-08-03] C4: 解析後的有效值（settings 優先，否則用建構參數）
  String get _effectiveVoiceName => settings?.primaryVoice ?? voiceName;
  double get _effectiveBaseSpeed => settings?.baseSpeed ?? baseSpeed;
  bool get _effectiveEmotionEnabled => settings?.emotionEnabled ?? emotionEnabled;
  double get _effectiveEmotionSensitivity => settings?.emotionSensitivity ?? emotionSensitivity;
  Set<String> get _effectiveEnabledEmotions => settings?.enabledEmotions ?? const {'amused', 'neutral', 'sleepiness'};
  String? get _effectiveSecondaryVoice => settings?.secondaryVoice;
  double get _effectiveVoiceBlend => settings?.voiceBlend ?? 1.0;
  bool get _effectiveEmotionSpeedCoupling => settings?.emotionSpeedCoupling ?? true;
  bool get _effectiveTimeAware => settings?.timeAware ?? true;
  bool get _effectiveEmotionMemory => settings?.emotionMemory ?? true;

  /// Kokoro TTS 服務實例（層 2 朗讀引擎，由引擎內部管理生命週期）
  KokoroTtsService? _kokoro;

  /// 互動決策狀態機
  late final VoiceStateMachine _stateMachine;

  /// 當前狀態（UI 訂閱用）
  final ValueNotifier<VoiceState> state =
      ValueNotifier<VoiceState>(VoiceState.idle);

  /// 是否正在對談中
  bool _conversationActive = false;

  /// 背景運算的 cancel 函數（保留欄位，未來擴充用）
  void Function()? _cancelAgentLoop;

  /// 最近 5 次情緒記錄（情緒記憶 — 層 3）
  final List<String> _emotionHistory = [];
  static const int _maxEmotionHistory = 5;

  /// 上一次使用者文字
  String _lastUserText = '';

  /// 狀態語音是否已播放（避免重複）
  bool _statusVoicePlayed = false;

  /// 是否正在合成語音（避免重複觸發）
  bool _isSynthesizing = false;

  /// 建立 Voice AI 引擎
  ///
  /// [onSpeak] — 基本 TTS 朗讀回調（Kokoro 未啟動時的 fallback）
  /// [onKokoroSpeak] — Kokoro TTS 朗讀回調（帶情緒+語速），可選 fallback
  /// [onPlayAudioBytes] — 音檔播放回調，接收 Kokoro 合成的 bytes
  /// [onStopSpeaking] — 停止 TTS 回調
  /// [onAgentLoopTrigger] — AgentLoop 啟動回調
  /// [voiceName] — Kokoro 聲音名稱（預設 'zf_xiaoxiao'）— [向後相容] 建議改用 settings
  /// [baseSpeed] — 基礎語速（預設 1.0）— [向後相容] 建議改用 settings
  /// [emotionEnabled] — 情緒表達開關（預設 true）— [向後相容] 建議改用 settings
  /// [emotionSensitivity] — 情緒敏感度 0.0–1.0（預設 0.5）— [向後相容] 建議改用 settings
  /// [projectRoot] — 專案根目錄路徑（用於定位 Kokoro server 腳本）
  /// [settings] — 夥伴完整語音設定（[教練 Agent 2026-08-03] C4 新增）
  VoiceEngine({
    required this.onSpeak,
    required this.onStopSpeaking,
    this.onAgentLoopTrigger,
    this.onKokoroSpeak,
    this.onPlayAudioBytes,
    this.voiceName = 'zf_xiaoxiao',
    this.baseSpeed = 1.0,
    this.emotionEnabled = true,
    this.emotionSensitivity = 0.5,
    this.projectRoot,
    this.settings,
  }) {
    // 建立狀態機，設定各狀態的回應層觸發
    _stateMachine = VoiceStateMachine(
      onTransition: ({required from, required to, required trigger}) {
        debugPrint('[VoiceEngine] 狀態轉換: $from → $to ($trigger)');
        state.value = to;
      },
      // 進入 listening：安靜等待，不答腔
      onEnterListening: () {
        // 新架構：聆聽時保持安靜，不啟動虛字答腔
        debugPrint('進入監聯，安靜等待使用者說話');
      },
      // 離開 listening：無特殊處理
      onExitListening: () {
        // 新架構：無需停止答腔
      },
      // 進入 thinking：層 1 狀態語音 + 啟動背景 AgentLoop
      onEnterThinking: () {
        _handleEnterThinking();
      },
      // 進入 speaking：層 2 回應朗讀已由 _handleAgentResult 準備好
      onEnterSpeaking: () {
        // TTS 已在結果就緒時觸發，這裡只做狀態標記
      },
      // 離開 speaking：停止 TTS
      onExitSpeaking: () {
        onStopSpeaking();
      },
    );
  }

  /// 當前狀態
  VoiceState get currentState => _stateMachine.state;

  /// 是否正在對談中
  bool get isConversationActive => _conversationActive;

  /// 最近 5 次情緒記錄（唯讀）
  List<String> get emotionHistory => List.unmodifiable(_emotionHistory);

  /// Kokoro TTS server 是否已就緒
  bool get isKokoroReady => _kokoro?.isRunning ?? false;

  // ─── 對談生命週期 ───

  /// 開始語音對談（toggle 模式）
  ///
  /// 啟動 Kokoro TTS server，進入 idle 狀態，等待使用者開始說話。
  Future<void> startConversation() async {
    if (_conversationActive) return;
    _conversationActive = true;
    _statusVoicePlayed = false;
    _emotionHistory.clear();
    _stateMachine.reset();
    debugPrint('[VoiceEngine] 對談已開始');

    // 啟動 Kokoro TTS server（非阻塞 — 失敗時 fallback 到 onSpeak）
    await _ensureKokoroStarted();
  }

  /// 結束語音對談（toggle 模式）
  ///
  /// 停止所有進行中的回應，關閉 Kokoro server，回到未啟動狀態。
  Future<void> stopConversation() async {
    if (!_conversationActive) return;
    _conversationActive = false;

    // 停止 TTS
    await onStopSpeaking();

    // 取消背景運算
    _cancelAgentLoop?.call();
    _cancelAgentLoop = null;

    // 停止 Kokoro server
    await _stopKokoro();

    // 重置狀態機
    _stateMachine.reset();

    debugPrint('[VoiceEngine] 對談已結束');
  }

  // ─── 語音輸入處理 ───

  /// 使用者開始說話
  ///
  /// 由 VAD 或 speech handler 的 onStatus('listening') 觸發。
  void onUserStartedSpeaking() {
    if (!_conversationActive) return;
    _stateMachine.onUserStartedSpeaking();
  }

  /// 使用者停止說話
  ///
  /// 由 VAD 或 speech handler 的 onStatus('done') 觸發。
  void onUserStoppedSpeaking() {
    if (!_conversationActive) return;
    _stateMachine.onUserStoppedSpeaking();
  }

  /// 接收語音辨識結果
  ///
  /// 由 STT 辨識完成後呼叫。包含辨識文字。
  /// 新架構不再分析情緒 — 情緒由 LLM 輸出標籤決定。
  Future<void> onSpeechRecognized(VoiceInput input) async {
    if (!_conversationActive) return;

    debugPrint(
      '[VoiceEngine] 語音辨識結果: "${input.text}" '
      '(${input.duration.inSeconds}s)',
    );

    // 儲存上下文供 thinking 狀態使用
    _lastUserText = input.text;
  }

  // ─── 三層回應觸發 ───

  /// 進入 thinking 狀態 — 層 1 狀態語音 + 啟動背景運算
  Future<void> _handleEnterThinking() async {
    _statusVoicePlayed = false;

    final userText = _lastUserText;

    // ── 層 1：狀態語音 ──
    // 進入 thinking 時用 Kokoro 朗讀「我來查查看…」
    // 深夜自動用 sleepiness 語氣，其餘用 neutral
    if (userText.isNotEmpty) {
      _playStatusVoice();
    }

    // ── 啟動背景 AgentLoop（層 2 回應朗讀的來源）──
    if (onAgentLoopTrigger != null && userText.isNotEmpty) {
      debugPrint('[VoiceEngine] 啟動背景 AgentLoop');

      onAgentLoopTrigger!(
        userText: userText,
        // 中間結果 — 如果需要可以播放進度語音
        onProgress: (intermediateText) {
          _handleAgentProgress(intermediateText);
        },
        // 最終結果 — 層 2 回應朗讀
        onComplete: (finalReply) {
          _handleAgentResult(finalReply);
        },
      );
    }
  }

  /// 播放狀態語音（層 1）
  ///
  /// 用 Kokoro 朗讀「我來查查看…」，讓使用者知道正在處理。
  /// 語氣根據時間感知調整：深夜（22:00-06:00）用 sleepiness，其餘用 neutral。
  void _playStatusVoice() {
    if (_statusVoicePlayed) return;
    _statusVoicePlayed = true;

    const statusText = '我來查查看…';
    debugPrint('[VoiceEngine] 層 1 狀態語音: "$statusText"');

    // 時間感知：深夜用 sleepiness 語氣
    final emotion = _isLateNight() ? 'sleepiness' : 'neutral';

    // 語速連動
    final speed = _computeSpeed(emotion);

    // 使用 Kokoro 合成並播放（fire-and-forget）
    unawaited(
      _synthesizeAndPlay(
        text: statusText,
        emotion: emotion,
        speed: speed,
      ),
    );
  }

  /// 中間結果處理
  ///
  /// AgentLoop 的中間結果（工具回報文字）。
  /// 新架構中保持安靜 — 不再播放中間結果，避免打斷使用者。
  void _handleAgentProgress(String intermediateText) {
    if (!_conversationActive) return;
    debugPrint('[VoiceEngine] Agent 中間結果: "$intermediateText"');
    // 新架構：thinking 中保持安靜，不播放中間結果
  }

  /// 層 2：回應朗讀（Kokoro + 情緒）
  ///
  /// AgentLoop 最終結果出來，解析情緒標籤，用 Kokoro 朗讀。
  void _handleAgentResult(String rawReply) {
    if (!_conversationActive) return;

    debugPrint('[VoiceEngine] 層 2 回應朗讀（原始）: "$rawReply"');

    // 解析 LLM 輸出的情緒標籤和信心分數
    final parsed = parseEmotionTags(rawReply);
    final reply = parsed.reply;
    final llmEmotion = parsed.emotion;
    final llmConfidence = parsed.confidence;

    // 決定最終使用的情緒（含時間感知 + 敏感度判斷 + 情緒記憶）
    final emotion = _resolveEmotion(
      llmEmotion: llmEmotion,
      confidence: llmConfidence,
    );

    debugPrint(
      '[VoiceEngine] 情緒決策: llmEmotion=$llmEmotion, '
      'confidence=$llmConfidence, '
      'sensitivity=$emotionSensitivity, '
      'final=$emotion',
    );

    // 計算語速（情緒連動）
    final speed = _computeSpeed(emotion);

    // 層 3：情緒記憶 — 記住這次情緒
    if (_effectiveEmotionMemory && emotion != null) {
      _recordEmotion(emotion);
    }

    // 通知狀態機結果就緒
    _stateMachine.onAgentResultReady();

    // 朗讀最終回覆（Kokoro 優先，fire-and-forget）
    unawaited(
      _synthesizeAndPlay(
        text: reply,
        emotion: emotion,
        speed: speed,
      ),
    );
  }

  // ─── Kokoro 合成 + 播放 ───

  /// 合成語音並播放（Kokoro 優先，fallback 到 onSpeak）
  ///
  /// [text] — 要朗讀的文字
  /// [emotion] — 情緒標籤（可選）
  /// [speed] — 語速倍率
  ///
  /// 優先路徑：KokoroTtsService.synthesize() → onPlayAudioBytes(bytes)
  /// Fallback 1：onKokoroSpeak(text, emotion, speed) — 帶情緒的回調
  /// Fallback 2：onSpeak(text) — 純文字 TTS
  Future<void> _synthesizeAndPlay({
    required String text,
    String? emotion,
    required double speed,
  }) async {
    // 防止重複觸發
    if (_isSynthesizing) {
      debugPrint('[VoiceEngine] 合成中，跳過本次請求');
      return;
    }

    final kokoro = _kokoro;
    if (kokoro != null && kokoro.isRunning && onPlayAudioBytes != null) {
      // ── Kokoro 模式：合成 → 播放 bytes ──
      _isSynthesizing = true;
      try {
        debugPrint(
          '[VoiceEngine] Kokoro 合成: emotion=$emotion, speed=$speed, '
          'text.length=${text.length}',
        );
        final result = await kokoro.synthesize(
          KokoroTtsRequest(
            text: text,
            voice: _effectiveVoiceName,
            secondaryVoice: _effectiveSecondaryVoice,
            voiceBlend: _effectiveVoiceBlend,
            speed: speed,
            emotion: _effectiveEmotionEnabled ? emotion : null,
            emotionSensitivity: _effectiveEmotionSensitivity,
          ),
        );
        onPlayAudioBytes!(result.audioBytes);
        debugPrint(
          '[VoiceEngine] ✅ Kokoro 播放: ${result.audioBytes.length} bytes',
        );
      } catch (error) {
        debugPrint('[VoiceEngine] ❌ Kokoro 合成失敗，fallback 到 onSpeak: $error');
        _fallbackSpeak(text, emotion: emotion, speed: speed);
      } finally {
        _isSynthesizing = false;
      }
    } else {
      // ── Fallback 模式 ──
      _fallbackSpeak(text, emotion: emotion, speed: speed);
    }
  }

  /// Fallback 朗讀（Kokoro 不可用時）
  ///
  /// 優先使用 onKokoroSpeak（帶情緒），其次 onSpeak（純文字）。
  void _fallbackSpeak(String text, {String? emotion, double? speed}) {
    if (onKokoroSpeak != null) {
      onKokoroSpeak!(text, emotion: emotion, speed: speed);
    } else {
      onSpeak(text);
    }
  }

  // ─── 情緒解析 + 記憶 ───

  /// 決定最終使用的情緒
  ///
  /// 優先級：
  /// 1. 時間感知 — 深夜（22:00-06:00）自動用 sleepiness（除非 LLM 高信心）
  /// 2. LLM 情緒標籤 — confidence > (1.0 - sensitivity) 時使用
  /// 3. 上次情緒記憶 — 有連貫性
  /// 4. neutral — 預設
  String? _resolveEmotion({
    required String? llmEmotion,
    required double? confidence,
  }) {
    if (!_effectiveEmotionEnabled) return null;

    // 深夜優先：如果 LLM 信心不高，強制用 sleepiness
    if (_effectiveTimeAware && _isLateNight()) {
      if (llmEmotion != null &&
          confidence != null &&
          confidence > (1.0 - _effectiveEmotionSensitivity) &&
          llmEmotion != 'neutral') {
        return llmEmotion;
      }
      return 'sleepiness';
    }

    // LLM 情緒標籤 — confidence 需大於 (1.0 - sensitivity)
    if (llmEmotion != null &&
        _effectiveEnabledEmotions.contains(llmEmotion) &&
        _supportedEmotions.contains(llmEmotion)) {
      if (confidence != null && confidence > (1.0 - _effectiveEmotionSensitivity)) {
        return llmEmotion;
      }
      // confidence 不夠但不是 neutral，參考上次情緒
      if (llmEmotion != 'neutral') {
        return llmEmotion;
      }
    }

    // 上次情緒記憶（情緒連貫性）
    if (_effectiveEmotionMemory && _emotionHistory.isNotEmpty) {
      return _emotionHistory.last;
    }

    return 'neutral';
  }

  /// 計算語速（情緒連動）
  ///
  /// 根據情緒調整語速：
  /// - amused → +10% 語速
  /// - anger → +15% 語速
  /// - sleepiness → -15% 語速
  /// - disgust → -10% 語速
  /// - neutral → 正常
  double _computeSpeed(String? emotion) {
    final baseSpeed = _effectiveBaseSpeed;
    if (_effectiveEmotionSpeedCoupling == false || emotion == null) return baseSpeed;
    final adjust = _emotionSpeedAdjust[emotion] ?? 1.0;
    return (baseSpeed * adjust).clamp(0.5, 2.0);
  }

  /// 記錄情緒到記憶（層 3）
  void _recordEmotion(String emotion) {
    _emotionHistory.add(emotion);
    if (_emotionHistory.length > _maxEmotionHistory) {
      _emotionHistory.removeAt(0);
    }
    debugPrint(
      '[VoiceEngine] 層 3 情緒記憶: $emotion '
      '(歷史: ${_emotionHistory.join(", ")})',
    );
  }

  bool _isLateNight() {
    final hour = DateTime.now().hour;
    return hour >= 22 || hour < 6;
  }

  // ─── Kokoro TTS server 管理 ───

  /// 確保 Kokoro TTS server 已啟動
  ///
  /// 若尚未建立實例則建立，若尚未啟動則啟動。
  /// 啟動失敗時靜默 fallback 到 onSpeak。
  Future<void> _ensureKokoroStarted() async {
    if (onPlayAudioBytes == null) {
      // 沒有播放回調，不需要啟動 Kokoro（直接用 fallback）
      debugPrint('[VoiceEngine] 無 onPlayAudioBytes，跳過 Kokoro 啟動');
      return;
    }

    _kokoro ??= KokoroTtsService();

    if (_kokoro!.isRunning) return;

    debugPrint('[VoiceEngine] 啟動 Kokoro TTS server...');
    final started = await _kokoro!.startServer(projectRoot: projectRoot);
    if (started) {
      debugPrint('[VoiceEngine] ✅ Kokoro TTS server 已就緒');
    } else {
      debugPrint(
        '[VoiceEngine] ❌ Kokoro TTS server 啟動失敗，將使用 fallback TTS: '
        '${_kokoro!.lastError}',
      );
    }
  }

  /// 停止 Kokoro TTS server
  Future<void> _stopKokoro() async {
    final kokoro = _kokoro;
    if (kokoro == null) return;
    await kokoro.stopServer();
    debugPrint('[VoiceEngine] Kokoro TTS server 已停止');
  }

  // ─── 插嘴處理 ───

  /// 使用者插嘴（Agent 說話時使用者開始說話）
  ///
  /// 狀態機會自動處理 speaking → listening 的轉換。
  void onUserInterrupt() {
    if (!_conversationActive) return;
    debugPrint('[VoiceEngine] 使用者插嘴');
    _stateMachine.onUserInterrupted();
  }

  /// Agent 朗讀完成
  ///
  /// 由 TTS completion handler 觸發。
  void onSpeakingComplete() {
    if (!_conversationActive) return;
    _stateMachine.onAgentSpeakingComplete();
  }

  // ─── 資源管理 ───

  /// 釋放資源
  void dispose() {
    state.dispose();
    // 停止 Kokoro server（fire-and-forget）
    unawaited(_kokoro?.dispose());
  }
}
