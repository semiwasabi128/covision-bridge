// voice_progress_reporter.dart — 第三層現況回報 + 第四層聰明反問
//
// Phase 2: 背景運算的中間文字先讀出來 + 結果沒出來時反問
//
// 第三層（現況回報）：
//   AgentLoop 運算過程中產生的中間文字（工具回報、讀檔結果）
//   不丟掉，先讀出來讓使用者聽
//   例：「我先看看你的檔案... 好，我找到了這個問題...」
//
// 第四層（聰明反問）：
//   如果最終結果還沒出來，Agent 反問關鍵釐清問題
//   反問夠聰明 → 使用者自己把想法全部說完 → 賺到時間 + 更多上下文
//   例：「你說的是 lib/services/ 還是 lib/widgets/ 底的？」

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_persona_responses.dart';
import 'voice_streaming_tts.dart';

/// 現況回報 + 聰明反問引擎
///
/// 在背景 AgentLoop 運算期間：
/// 1. 把中間結果讀出來（第三層）
/// 2. 如果結果還沒出來，反問關鍵問題（第四層）
///
/// 使用方式：
///   final reporter = VoiceProgressReporter(
///     streamingTts: streamingTts,
///     onClarificationNeeded: (question) => engine.onUserInputNeeded(question),
///   );
///   reporter.start();
///   // AgentLoop 中間結果：
///   reporter.onProgress('正在讀取檔案...');
///   reporter.onProgress('找到 3 個候選檔案');
///   // 如果 3 秒後還沒最終結果：
///   //   reporter 自動觸發第四層反問
///   reporter.onComplete('問題找到了...');
class VoiceProgressReporter {
  VoiceProgressReporter({
    required this.streamingTts,
    this.onClarificationNeeded,
    this.clarificationDelay = const Duration(seconds: 3),
    this.maxProgressReports = 3,
  });

  /// 串流 TTS — 用來念現況回報
  final VoiceStreamingTts streamingTts;

  /// 第四層反問回調 — 當需要使用者釐清時呼叫
  final void Function(String question)? onClarificationNeeded;

  /// 多久沒最終結果就觸發反問
  final Duration clarificationDelay;

  /// 最多念幾次現況回報（避免太吵）
  final int maxProgressReports;

  /// 計數
  int _progressCount = 0;

  /// 是否已完成
  bool _completed = false;

  /// 反問計時器
  Timer? _clarificationTimer;

  /// 反問是否已觸發
  bool _clarificationTriggered = false;

  /// 啟動現況回報 + 反問計時器
  void start() {
    _progressCount = 0;
    _completed = false;
    _clarificationTriggered = false;
    _startClarificationTimer();
  }

  /// 第三層：AgentLoop 中間結果
  ///
  /// 把中間文字念出來，讓使用者知道 Agent 在做事。
  /// 限制最多念 maxProgressReports 次，避免太吵。
  void onProgress(String intermediateText) {
    if (_completed) return;
    if (_progressCount >= maxProgressReports) return;

    _progressCount++;
    debugPrint('[ProgressReporter] 第三層現況回報 (#$_progressCount): $intermediateText');

    // 用串流 TTS 念出來
    streamingTts.feed(intermediateText);
  }

  /// 第五層：AgentLoop 最終結果
  ///
  /// 取消反問計時器，標記完成。
  void onComplete(String finalReply) {
    _completed = true;
    _clarificationTimer?.cancel();
    _clarificationTimer = null;
    debugPrint('[ProgressReporter] 最終結果: $finalReply');
  }

  /// 啟動反問計時器
  ///
  /// 如果 clarificationDelay 後還沒收到 onComplete，就觸發第四層反問。
  void _startClarificationTimer() {
    _clarificationTimer?.cancel();
    _clarificationTimer = Timer(clarificationDelay, () {
      if (!_completed && !_clarificationTriggered) {
        _triggerClarification();
      }
    });
  }

  /// 觸發第四層聰明反問
  ///
  /// 根據已有的中間結果，生成一個精準的反問。
  /// 這裡用簡單的邏輯 — 實際整合時可以呼叫 delegate_subagent 生成更聰明的反問。
  void _triggerClarification() {
    _clarificationTriggered = true;
    debugPrint('[ProgressReporter] 第四層聰明反問觸發');

    // 用本地模型生成反問（0 雲端 token）
    // 這裡先用簡單的預設反問，實際整合時可以更聰明
    final question = _generateClarificationQuestion();

    // 念出反問
    streamingTts.feed(question);

    // 通知引擎需要使用者輸入
    onClarificationNeeded?.call(question);
  }

  /// 生成反問問題
  ///
  /// Phase 2 先用簡單邏輯，Phase 3 可以呼叫 delegate_subagent 生成更精準的反問。
  String _generateClarificationQuestion() {
    // 根據 progressCount 給不同的反問
    if (_progressCount == 0) {
      return '你說的具體是什麼呢？';
    } else if (_progressCount == 1) {
      return '我找到了一些線索，你能再說清楚一點嗎？';
    } else {
      return '你想要的是哪一個方向？';
    }
  }

  /// 使用者回答了反問 — 重新啟動計時器
  ///
  /// 使用者回答的過程中，背景運算繼續跑，賺到時間。
  void onUserResponded() {
    if (!_completed) {
      _clarificationTriggered = false;
      _startClarificationTimer();
    }
  }

  /// 停止
  void stop() {
    _clarificationTimer?.cancel();
    _clarificationTimer = null;
    _completed = true;
  }

  /// 重置
  void reset() {
    _progressCount = 0;
    _completed = false;
    _clarificationTriggered = false;
    _clarificationTimer?.cancel();
    _clarificationTimer = null;
  }
}
