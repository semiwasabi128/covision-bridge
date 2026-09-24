/// 互動決策狀態機
library;

/// 管理 Voice AI 的四個狀態之間的轉換，每個轉換觸發對應的回應層。
///
/// 這是新三層回應架構的指揮中心 — 根據使用者行為和背景運算進度，
/// 決定什麼時候播放狀態語音、什麼時候朗讀回應、什麼時候保持安靜。
///
/// 狀態流轉：
///   idle → listening（使用者開始說話）
///   listening → thinking（使用者停止說話）
///   thinking → speaking（Agent 結果出來）
///   speaking → listening（使用者插嘴）
///   speaking → idle（Agent 說完，沒人說話）
///
/// 每個狀態轉換觸發對應的回應層：
///   → listening: 安靜等待（不答腔）
///   → thinking: 層 1 狀態語音 + 啟動背景 AgentLoop
///   → speaking: 層 2 回應朗讀 TTS
///   speaking → listening（插嘴）: 停止 TTS

import 'package:flutter/foundation.dart';

/// 語音對談狀態
enum VoiceState {
  /// 閒置 — 等使用者開口
  idle,

  /// 聆聽中 — 使用者在說話
  listening,

  /// 思考中 — 使用者說完，背景運算中
  thinking,

  /// 說話中 — Agent 在說話（TTS 播放中）
  speaking,
}

/// 狀態轉換回調
///
/// 當狀態機從一個狀態轉換到另一個狀態時呼叫。
/// [from] — 前一個狀態
/// [to] — 新狀態
/// [trigger] — 觸發原因（debug 用）
typedef VoiceStateTransitionCallback = void Function({
  required VoiceState from,
  required VoiceState to,
  required String trigger,
});

/// 互動決策狀態機
///
/// 接收使用者和 Agent 的事件，決定狀態轉換，通知回調。
///
/// 事件：
/// - onUserStartedSpeaking() → idle/listening → listening
/// - onUserStoppedSpeaking() → listening → thinking
/// - onAgentResultReady() → thinking → speaking
/// - onUserInterrupted() → speaking → listening
/// - onAgentSpeakingComplete() → speaking → idle
class VoiceStateMachine {
  /// 當前狀態
  VoiceState _state = VoiceState.idle;

  /// 狀態變更回調
  final VoiceStateTransitionCallback? onTransition;

  /// 進入 listening 狀態時觸發（新架構：安靜等待，不答腔）
  final VoidCallback? onEnterListening;

  /// 離開 listening 狀態時觸發（新架構：無特殊處理）
  final VoidCallback? onExitListening;

  /// 進入 thinking 狀態時觸發（層 1 狀態語音 + 啟動 AgentLoop）
  final VoidCallback? onEnterThinking;

  /// 進入 speaking 狀態時觸發（層 2 回應朗讀 TTS）
  final VoidCallback? onEnterSpeaking;

  /// 離開 speaking 狀態時觸發（停止 TTS）
  final VoidCallback? onExitSpeaking;

  VoiceStateMachine({
    this.onTransition,
    this.onEnterListening,
    this.onExitListening,
    this.onEnterThinking,
    this.onEnterSpeaking,
    this.onExitSpeaking,
    this.onProgressReport,
    this.onClarificationTriggered,
    this.onSpokenChunk,
  });

  /// 當前狀態
  VoiceState get state => _state;

  /// 使用者開始說話
  ///
  /// 觸發：
  /// - idle → listening: 安靜等待
  /// - speaking → listening: 使用者插嘴，停止 TTS
  void onUserStartedSpeaking() {
    switch (_state) {
      case VoiceState.idle:
        _transition(VoiceState.listening, trigger: '使用者開始說話');
        break;
      case VoiceState.speaking:
        // 使用者插嘴 — 先停止 TTS
        _transition(VoiceState.listening, trigger: '使用者插嘴');
        break;
      case VoiceState.listening:
        // 已在聆聽，不重複觸發
        break;
      case VoiceState.thinking:
        // 思考中使用者又開始說話 — 回到聆聽
        _transition(VoiceState.listening, trigger: '思考中使用者又說話');
        break;
    }
  }

  /// 使用者停止說話
  ///
  /// 觸發：
  /// - listening → thinking: 層 1 狀態語音 + 啟動 AgentLoop
  void onUserStoppedSpeaking() {
    switch (_state) {
      case VoiceState.listening:
        _transition(VoiceState.thinking, trigger: '使用者停止說話');
        break;
      case VoiceState.idle:
      case VoiceState.thinking:
      case VoiceState.speaking:
        // 不在聆聽狀態，忽略
        break;
    }
  }

  /// Agent 結果就緒
  ///
  /// 觸發：
  /// - thinking → speaking: 層 2 回應朗讀 TTS
  void onAgentResultReady() {
    switch (_state) {
      case VoiceState.thinking:
        _transition(VoiceState.speaking, trigger: 'Agent 結果就緒');
        break;
      case VoiceState.listening:
        // 使用者又在說話了，不切到 speaking（等使用者說完）
        debugPrint('[VoiceStateMachine] Agent 結果就緒但使用者在說話，暫存結果');
        break;
      case VoiceState.idle:
        // 已回到 idle（可能使用者插嘴後又停止，結果才出來）
        _transition(VoiceState.speaking, trigger: 'Agent 結果就緒（從 idle）');
        break;
      case VoiceState.speaking:
        // 已在說話，不重複觸發
        break;
    }
  }

  /// 使用者插嘴
  ///
  /// 觸發：
  /// - speaking → listening: 停止 TTS，回到聆聽
  ///
  /// 等同於 onUserStartedSpeaking()，但語意上更明確。
  void onUserInterrupted() {
    onUserStartedSpeaking();
  }

  /// Agent 說話完成
  ///
  /// TTS 播放完畢時呼叫。
  ///
  /// 觸發：
  /// - speaking → idle: 回到閒置
  void onAgentSpeakingComplete() {
    switch (_state) {
      case VoiceState.speaking:
        _transition(VoiceState.idle, trigger: 'Agent 說話完成');
        break;
      case VoiceState.idle:
      case VoiceState.listening:
      case VoiceState.thinking:
        // 不在說話狀態，忽略
        break;
    }
  }

  /// 強制重置到 idle
  ///
  /// 用於 stopConversation() 或異常恢復。
  void reset() {
    if (_state != VoiceState.idle) {
      _transition(VoiceState.idle, trigger: '手動重置');
    }
  }

  /// 執行狀態轉換
  void _transition(VoiceState newState, {required String trigger}) {
    final oldState = _state;
    debugPrint('[VoiceStateMachine] $oldState → $newState ($trigger)');

    // 離開舊狀態
    switch (oldState) {
      case VoiceState.listening:
        onExitListening?.call();
        break;
      case VoiceState.speaking:
        onExitSpeaking?.call();
        break;
      case VoiceState.idle:
      case VoiceState.thinking:
        break;
    }

    _state = newState;

    // 進入新狀態
    switch (newState) {
      case VoiceState.listening:
        onEnterListening?.call();
        break;
      case VoiceState.thinking:
        onEnterThinking?.call();
        break;
      case VoiceState.speaking:
        onEnterSpeaking?.call();
        break;
      case VoiceState.idle:
        break;
    }

    // 通知狀態轉換
    onTransition?.call(from: oldState, to: newState, trigger: trigger);
  }

  /// 是否在聆聽中
  bool get isListening => _state == VoiceState.listening;

  /// 是否在思考中
  bool get isThinking => _state == VoiceState.thinking;

  /// 是否在說話中
  bool get isSpeaking => _state == VoiceState.speaking;

  /// 是否閒置
  bool get isIdle => _state == VoiceState.idle;

  // ── Phase 2 增強：全雙工事件 ──

  /// 思考中的進度回報
  ///
  /// 在 thinking 狀態下，AgentLoop 中間結果可以透過此方法通知狀態機。
  /// 狀態機不轉換狀態，但可以觸發 onProgressReport callback。
  final void Function(String intermediateText)? onProgressReport;

  /// 思考中的反問觸發
  ///
  /// 當進度報告引擎判定需要反問時呼叫。
  /// 狀態機保持 thinking，但允許暫時「說話」（反問）。
  final void Function(String question)? onClarificationTriggered;

  /// 說話中的串流 TTS 進度
  ///
  /// 在 speaking 狀態下，串流 TTS 的每一段文字完成時呼叫。
  /// 用於追蹤 Agent 說到哪裡了（被插嘴時可以記住位置）。
  final void Function(String spokenChunk)? onSpokenChunk;

  /// 記住 Agent 說到哪裡（被插嘴時用）
  String _lastSpokenPosition = '';

  /// 思考中收到中間結果
  ///
  /// 不轉換狀態，只觸發 onProgressReport。
  void onProgress(String intermediateText) {
    if (_state == VoiceState.thinking) {
      onProgressReport?.call(intermediateText);
    }
  }

  /// 思考中觸發反問
  ///
  /// 狀態保持 thinking，但暫時允許 TTS 播放反問。
  void onClarificationNeeded(String question) {
    if (_state == VoiceState.thinking) {
      onClarificationTriggered?.call(question);
    }
  }

  /// 說話中記住進度（串流 TTS 每段完成）
  void onChunkSpoken(String chunk) {
    _lastSpokenPosition = chunk;
    onSpokenChunk?.call(chunk);
  }

  /// 取得上次說到哪裡（被插嘴後可以接續）
  String get lastSpokenPosition => _lastSpokenPosition;

  /// 清除說話位置記錄
  void clearSpokenPosition() {
    _lastSpokenPosition = '';
  }
}
