// voice_handoff.dart — 人機移交設計
//
// Phase 4: 信任治理 — 人機移交流暢度
//
// 影片中的關鍵觀點：
// 「把移交設計成一個產品功能，而不是一個失敗後的兜底方案。」
// 「人機移交的流暢程度，是信任建立還是被摧毀的關鍵時刻。」
//
// Agent 遇到無法處理的情況時：
// 1. 不是靜默失敗，而是明確告知使用者
// 2. 提供選項
// 3. 移交時帶上下文
// 4. 使用者可以隨時接管

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 人機移交原因
enum HandoffReason {
  /// Agent 不確定使用者意圖
  ambiguousIntent,

  /// 操作需要人工確認（dangerous 等級）
  requiresConfirmation,

  /// Agent 能力不足
  capabilityLimit,

  /// 使用者主動要求接管
  userRequested,

  /// 多次嘗試失敗
  repeatedFailure,
}

/// 移交選項
class HandoffOption {
  final String id;
  final String label;
  final String description;
  final bool isTakeOver; // true = 使用者自己來，false = Agent 換方式做

  const HandoffOption({
    required this.id,
    required this.label,
    required this.description,
    this.isTakeOver = false,
  });
}

/// 人機移交事件
class HandoffEvent {
  final DateTime timestamp;
  final HandoffReason reason;
  final String context; // 之前對話的摘要
  final List<HandoffOption> options;
  final String? agentSuggestion; // Agent 建議的選項 id

  const HandoffEvent({
    required this.timestamp,
    required this.reason,
    required this.context,
    required this.options,
    this.agentSuggestion,
  });
}

/// 人機移交管理器
///
/// 當 Agent 遇到無法處理的情況時，流暢地移交給使用者。
///
/// 使用方式：
///   final handoff = VoiceHandoffManager(
///     onSpeak: ttsHandler.speak,
///     onWaitUserChoice: (event) => showHandoffUI(event),
///   );
///   handoff.requestHandoff(
///     reason: HandoffReason.ambiguousIntent,
///     context: '使用者要修一個 bug，但不確定是哪個檔案',
///     options: [...],
///   );
class VoiceHandoffManager {
  VoiceHandoffManager({
    required this.onSpeak,
    this.onWaitUserChoice,
  });

  /// TTS 朗讀回調
  final void Function(String text) onSpeak;

  /// 等待使用者選擇的回調
  final void Function(HandoffEvent event)? onWaitUserChoice;

  /// 當前移交事件
  HandoffEvent? _currentEvent;

  /// 移交歷史
  final List<HandoffEvent> _history = [];

  /// 請求人機移交
  ///
  /// Agent 遇到無法處理的情況時呼叫。
  /// 會用 TTS 念出移交訊息，然後等待使用者選擇。
  Future<void> requestHandoff({
    required HandoffReason reason,
    required String context,
    required List<HandoffOption> options,
    String? suggestion,
  }) async {
    final event = HandoffEvent(
      timestamp: DateTime.now(),
      reason: reason,
      context: context,
      options: options,
      agentSuggestion: suggestion,
    );

    _currentEvent = event;
    _history.add(event);

    // 根據原因生成不同的移交話術
    final message = _buildHandoffMessage(event);
    debugPrint('[HandoffManager] 移交: ${reason.name} — $message');
    onSpeak(message);

    // 通知 UI 顯示選項
    onWaitUserChoice?.call(event);
  }

  /// 生成移交話術
  String _buildHandoffMessage(HandoffEvent event) {
    switch (event.reason) {
      case HandoffReason.ambiguousIntent:
        final options = event.options.map((o) => '「${o.label}」').join(' 還是 ');
        return '我不太確定你的意思。是 $options？你告訴我，我來處理。';

      case HandoffReason.requiresConfirmation:
        return '這個操作會改動系統，我需要你確認。要我繼續嗎？說「好」或「不要」。';

      case HandoffReason.capabilityLimit:
        return '這個我可能處理不好，需要你來看一下。我先把目前的情況告訴你。';

      case HandoffReason.userRequested:
        return '好，我停下來。你要接手嗎？我可以把目前做到的告訴你。';

      case HandoffReason.repeatedFailure:
        return '我試了幾次都沒成功，可能需要你來看看。我先說明一下我遇到什麼問題。';
    }
  }

  /// 使用者選擇了某個選項
  ///
  /// 返回 true 如果使用者選擇自己接管，false 如果讓 Agent 換方式繼續。
  bool onUserChoice(String optionId) {
    if (_currentEvent == null) return false;

    final option = _currentEvent!.options.where((o) => o.id == optionId).firstOrNull;
    if (option == null) return false;

    _currentEvent = null;
    return option.isTakeOver;
  }

  /// 使用者語音確認（「好」「確認」「不要」等）
  ///
  /// 用於 requiresConfirmation 場景。
  /// 返回 true = 確認，false = 拒絕。
  bool onVoiceConfirmation(String spoken) {
    final lower = spoken.toLowerCase();
    final confirmed = lower.contains('好') ||
        lower.contains('確認') ||
        lower.contains('可以') ||
        lower.contains('對') ||
        lower.contains('yes') ||
        lower.contains('ok');

    _currentEvent = null;
    return confirmed;
  }

  /// 取得移交歷史
  List<HandoffEvent> get history => List.unmodifiable(_history);

  /// 是否正在等待使用者選擇
  bool get isWaitingForChoice => _currentEvent != null;

  /// 取得當前移交事件
  HandoffEvent? get currentEvent => _currentEvent;
}
