/// 插嘴偵測（Barge-in Detection）
library;

/// Agent 在說話時（TTS 播放中），持續監聽使用者是否開口。
///
/// 這是 Phase 2 全雙工音訊層的關鍵元件 — 實現「插嘴」（barge-in）功能。
/// 當 Agent 正在朗讀時，如果使用者開口說話，立即停止 TTS 播放，
/// 讓使用者可以隨時打斷 Agent 的發言。
///
/// 偵測邏輯：
/// - TTS 開始播放時呼叫 [startMonitoring]
/// - 監聽麥克風音量，如果持續超過閾值 → 判定為使用者開口
/// - 觸發 [onInterrupt] 回調 → 呼叫方應停止 TTS
/// - TTS 播放完畢時呼叫 [stopMonitoring]
///
/// 與一般 VAD 的差異：
/// - 閾值可以不同（Agent 說話時環境音可能不同，需要更高的閾值避免 TTS 回音誤觸發）
/// - 起聲確認時間通常更短（插嘴需要快速反應）
/// - 只在 TTS 播放期間啟用
///
/// 使用方式：
///   final detector = VoiceInterruptionDetector(
///     onInterrupt: () {
///       // 停止 TTS — 通常接 ChatTtsHandler.stop()
///       ttsHandler.stop();
///       // 通知 VoiceEngine.onUserInterrupt()
///       engine.onUserInterrupt();
///     },
///   );
///
///   // TTS 開始播放時
///   detector.startMonitoring(audioStream);
///   // TTS 播放完畢時
///   detector.stopMonitoring();

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_vad.dart';

/// 插嘴偵測器
///
/// 在 Agent 說話期間監聽使用者是否開口，偵測到時觸發 [onInterrupt]。
class VoiceInterruptionDetector {
  /// 偵測到使用者插嘴時觸發
  ///
  /// 呼叫方應在此回調中：
  /// 1. 停止 TTS 播放
  /// 2. 通知 VoiceEngine.onUserInterrupt()
  final VoidCallback? onInterrupt;

  /// 插嘴偵測的靜音閾值
  ///
  /// 預設 0.12 — 比 VAD 的 0.05 更高，因為 Agent 說話時
  /// 揚聲器聲音可能回灌到麥克風，需要更高的閾值避免 TTS 回音誤觸發。
  ///
  /// 實際部署時應根據硬體環境調整：
  /// - 免持聽筒模式：0.15 ~ 0.20
  /// - 耳機模式：0.05 ~ 0.08（幾乎沒有回音）
  /// - 筆電喇叭：0.10 ~ 0.15
  final double interruptThreshold;

  /// 起聲確認時間 — 音量需持續超過閾值此長度才判定為插嘴
  ///
  /// 預設 100ms — 比一般 VAD 更短，插嘴需要快速反應。
  final Duration interruptOnsetDuration;

  /// TTS 回音抑制時間 — TTS 開始後延遲一段時間才開始監聽
  ///
  /// 預設 300ms — 避免 TTS 剛開始播放時的音量突波誤觸發。
  final Duration echoSuppressionDelay;

  /// 內部 VAD 偵測器
  ///
  /// 使用 VoiceActivityDetector 實際執行音量偵測，
  /// 但使用不同的閾值參數。
  late final VoiceActivityDetector _vad;

  /// 是否正在監聯中
  bool _isMonitoring = false;

  /// 回音抑制計時器
  Timer? _echoSuppressionTimer;

  /// 是否在回音抑制期（TTS 剛開始的延遲期）
  bool _inEchoSuppression = false;

  /// 建立插嘴偵測器
  ///
  /// [onInterrupt] — 偵測到使用者插嘴時觸發
  /// [interruptThreshold] — 插嘴偵測閾值，預設 0.12
  /// [interruptOnsetDuration] — 起聲確認時間，預設 100ms
  /// [echoSuppressionDelay] — TTS 回音抑制延遲，預設 300ms
  VoiceInterruptionDetector({
    this.onInterrupt,
    this.interruptThreshold = 0.12,
    this.interruptOnsetDuration = const Duration(milliseconds: 100),
    this.echoSuppressionDelay = const Duration(milliseconds: 300),
  }) {
    _vad = VoiceActivityDetector(
      onSpeechStart: _handleInterruptDetected,
      // 插嘴偵測只需要 onSpeechStart，不需要 onSpeechEnd
      onSpeechEnd: null,
      silenceThreshold: interruptThreshold,
      // 沉默時間不影響插嘴偵測（我們只關心 start）
      silenceDuration: const Duration(seconds: 5),
      speechOnsetDuration: interruptOnsetDuration,
    );
  }

  /// 是否正在監聽中
  bool get isMonitoring => _isMonitoring;

  /// 開始監聽插嘴
  ///
  /// 在 TTS 開始播放時呼叫。
  ///
  /// [audioStream] — 音訊振幅樣本串流（0.0 ~ 1.0）
  ///
  /// 啟動後先經過 [echoSuppressionDelay] 的回音抑制期，
  /// 之後才開始實際偵測使用者是否開口。
  void startMonitoring(Stream<List<double>> audioStream) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _inEchoSuppression = true;

    // 取消舊的回音抑制計時器（如果有）
    _echoSuppressionTimer?.cancel();

    // 回音抑制延遲 — 等待 TTS 回音消退
    _echoSuppressionTimer = Timer(echoSuppressionDelay, () {
      _inEchoSuppression = false;

      if (_isMonitoring) {
        debugPrint('[VoiceInterruptionDetector] 回音抑制期結束，開始監聽插嘴');
        // 啟動 VAD 監聽
        _vad.listenTo(audioStream);
      }
    });

    debugPrint('[VoiceInterruptionDetector] 開始監聽插嘴（回音抑制期中）');
  }

  /// 停止監聽插嘴
  ///
  /// 在 TTS 播放完畢時呼叫。
  void stopMonitoring() {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    _inEchoSuppression = false;

    _echoSuppressionTimer?.cancel();
    _echoSuppressionTimer = null;

    _vad.dispose();

    debugPrint('[VoiceInterruptionDetector] 停止監聽插嘴');
  }

  /// 處理偵測到使用者插嘴
  void _handleInterruptDetected() {
    if (!_isMonitoring || _inEchoSuppression) return;

    debugPrint('[VoiceInterruptionDetector] 偵測到使用者插嘴！');

    // 停止監聽（避免重複觸發）
    stopMonitoring();

    // 觸發插嘴回調
    onInterrupt?.call();
  }

  /// 更新插嘴偵測閾值
  ///
  /// 用於根據環境動態調整閾值。
  /// 注意：只在未監聽時才能更新，監聽中呼叫會被忽略。
  void updateThreshold(double threshold) {
    if (_isMonitoring) {
      debugPrint('[VoiceInterruptionDetector] 監聽中無法更新閾值');
      return;
    }
    // VoiceActivityDetector 的閾值是 final，需要重建
    _vad.dispose();
    _vad = VoiceActivityDetector(
      onSpeechStart: _handleInterruptDetected,
      onSpeechEnd: null,
      silenceThreshold: threshold,
      silenceDuration: const Duration(seconds: 5),
      speechOnsetDuration: interruptOnsetDuration,
    );
  }

  /// 釋放資源
  void dispose() {
    stopMonitoring();
  }
}
