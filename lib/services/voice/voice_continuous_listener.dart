/// 持續監聽模式 — 全雙工音訊層
library;

/// 持續錄音 + VAD + 定期送 Whisper 轉文字。
///
/// 這是 Phase 2 全雙工音訊層的核心元件 — 麥克風持續開著，
/// 透過 VAD 自動偵測使用者何時開始/停止說話，
/// 並在偵測到說話時自動啟動聽寫（speech_to_text），
/// 偵測到停止時結束聽寫並送出辨識結果。
///
/// 運作流程：
/// 1. start() → 初始化 STT，開始監聽音訊振幅
/// 2. VAD 偵測到使用者開始說話 → 啟動 STT 聽寫
/// 3. VAD 偵測到使用者停止說話 → 停止 STT 聽寫
/// 4. STT 回傳辨識結果 → 透過 onRecognized 送出
/// 5. 重複 2-4，直到 stop() 被呼叫
///
/// 使用方式：
///   final listener = VoiceContinuousListener(
///     onRecognized: (text, audioSamples, duration) {
///       debugPrint('辨識結果: $text');
///       // 將結果送給 VoiceEngine.onSpeechRecognized()
///     },
///     onSpeechStart: () {
///       // 通知 VoiceEngine.onUserStartedSpeaking()
///     },
///     onSpeechEnd: () {
///       // 通知 VoiceEngine.onUserStoppedSpeaking()
///     },
///   );
///   await listener.start();
///   // ... 持續監聯中
///   await listener.stop();
///
/// 注意事項：
/// - speech_to_text 套件在 iOS/Android 上有不同的行為，實際使用時需測試
/// - 音訊振幅取樣使用 STT 的 onSoundLevelChange 回調
/// - 這是全雙工的基礎 — 麥克風持續開著，不會因為 TTS 播放而停止

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'voice_vad.dart';

/// 辨識結果回調
///
/// [text] — 辨識出的文字
/// [audioSamples] — 音訊振幅樣本（0.0 ~ 1.0）
/// [duration] — 本次聽寫的時長
typedef ContinuousListenerCallback = void Function({
  required String text,
  required List<double> audioSamples,
  required Duration duration,
});

/// 持續監聽器
///
/// 結合 VAD 和 speech_to_text 實現全雙工持續監聽。
class VoiceContinuousListener {
  /// 辨識結果回調 — 傳回文字 + 音訊樣本 + 時長
  final ContinuousListenerCallback? onRecognized;

  /// 偵測到使用者開始說話時觸發
  final VoidCallback? onSpeechStart;

  /// 偵測到使用者停止說話時觸發
  final VoidCallback? onSpeechEnd;

  /// 錯誤回調
  final void Function(String message)? onError;

  /// STT 引擎
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  /// 語音活動偵測器
  ///
  /// 接收 STT 的 sound level 事件，轉換為振幅樣本串流供 VAD 使用。
  /// late final 讓我們在建構子 body 中設定回調（可存取 this）。
  late final VoiceActivityDetector _vad;

  /// VAD 參數（建構子中儲存，_vad 初始化時使用）
  final double _silenceThreshold;
  final Duration _silenceDuration;

  /// 音訊振幅串流控制器
  ///
  /// 接收 STT 的 sound level 事件，轉換為振幅樣本串流供 VAD 使用。
  final StreamController<List<double>> _amplitudeController =
      StreamController<List<double>>.broadcast();

  /// [教練 Agent 2026-08-03] 對外暴露振幅串流（normalized 0.0~1.0）
  /// 給 UI（麥克風按鈕波形）訂閱真實音量
  Stream<double> get amplitudeStream =>
      _amplitudeController.stream.map((samples) => samples.isNotEmpty ? samples.first : 0.0);

  /// 是否已初始化
  bool _initialized = false;

  /// STT 是否可用
  bool _available = false;

  /// 是否正在監聽
  bool _isListening = false;

  /// STT 是否正在聽寫中
  bool _isDictating = false;

  /// 本次聽寫的開始時間
  DateTime? _dictationStartTime;

  /// 本次聽寫累積的音訊樣本
  final List<double> _currentSamples = [];

  /// 目前累積的辨識文字（partial results）
  String _currentText = '';

  /// 音量電平串流訂閱
  StreamSubscription<List<double>>? _amplitudeSubscription;

  /// 建立持續監聽器
  ///
  /// [onRecognized] — 辨識完成回調
  /// [onSpeechStart] — 偵測到使用者開始說話
  /// [onSpeechEnd] — 偵測到使用者停止說話
  /// [onError] — 錯誤回調
  /// [silenceThreshold] — VAD 靜音閾值，預設 0.05
  /// [silenceDuration] — VAD 沉默判定時間，預設 1.5 秒
  VoiceContinuousListener({
    this.onRecognized,
    this.onSpeechStart,
    this.onSpeechEnd,
    this.onError,
    double silenceThreshold = 0.05,
    Duration silenceDuration = const Duration(milliseconds: 1500),
  })  : _silenceThreshold = silenceThreshold,
        _silenceDuration = silenceDuration {
    // 在建構子 body 中初始化 VAD，才能在回調中存取 this
    _vad = VoiceActivityDetector(
      onSpeechStart: () {
        debugPrint('[VoiceContinuousListener] VAD: 開始說話');
        onSpeechStart?.call();
        _startDictation();
      },
      onSpeechEnd: () {
        debugPrint('[VoiceContinuousListener] VAD: 停止說話');
        onSpeechEnd?.call();
        _finalizeDictation();
      },
      silenceThreshold: _silenceThreshold,
      silenceDuration: _silenceDuration,
    );
  }

  /// 是否正在監聽中
  bool get isListening => _isListening;

  /// STT 是否正在聽寫中
  bool get isDictating => _isDictating;

  /// 開始持續監聽
  ///
  /// 初始化 STT 引擎，啟動 VAD 監聽音訊振幅串流。
  /// 啟動後麥克風持續開著，等待 VAD 偵測到使用者說話。
  Future<void> start() async {
    if (_isListening) return;

    // 初始化 STT
    if (!_initialized) {
      _available = await _speechToText.initialize(
        debugLogging: kDebugMode,
        onError: _handleSttError,
        onStatus: _handleSttStatus,
      );
      _initialized = true;
    }

    if (!_available) {
      onError?.call('無法啟用語音辨識，請確認麥克風與語音辨識權限。');
      return;
    }

    _isListening = true;
    _currentSamples.clear();
    _currentText = '';

    // 啟動 VAD — 監聽振幅串流
    _amplitudeSubscription = _amplitudeController.stream.listen(null);
    _vad.listenTo(_amplitudeController.stream);

    debugPrint('[VoiceContinuousListener] 持續監聽已啟動');
  }

  /// 停止持續監聯
  ///
  /// 停止 VAD、取消 STT 聽寫、釋放資源。
  Future<void> stop() async {
    if (!_isListening) return;

    _isListening = false;

    // 停止 VAD
    _vad.dispose();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    // 停止 STT
    if (_isDictating) {
      await _speechToText.stop();
      _isDictating = false;
    }

    // 如果有未送出的結果，送出
    if (_currentText.isNotEmpty) {
      _emitResult();
    }

    _currentSamples.clear();
    _currentText = '';

    debugPrint('[VoiceContinuousListener] 持續監聽已停止');
  }

  /// 啟動聽寫
  ///
  /// 由 VAD 的 onSpeechStart 觸發。開始 STT 聽寫並收集音訊樣本。
  Future<void> _startDictation() async {
    if (_isDictating || !_isListening || !_available) return;

    _isDictating = true;
    _dictationStartTime = DateTime.now();
    _currentSamples.clear();
    _currentText = '';

    try {
      await _speechToText.listen(
        onResult: _handleSttResult,
        onSoundLevelChange: _handleSoundLevel,
        listenOptions: stt.SpeechListenOptions(
          localeId: 'zh_TW',
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
      debugPrint('[VoiceContinuousListener] 聽寫已啟動');
    } catch (error) {
      _isDictating = false;
      onError?.call('聽寫啟動失敗：$error');
    }
  }

  /// 結束聽寫並送出結果
  ///
  /// 由 VAD 的 onSpeechEnd 觸發。停止 STT 聽寫，送出辨識結果。
  Future<void> _finalizeDictation() async {
    if (!_isDictating) return;

    _isDictating = false;

    try {
      await _speechToText.stop();
    } catch (error) {
      debugPrint('[VoiceContinuousListener] 停止聽寫時發生錯誤: $error');
    }

    // 送出結果
    if (_currentText.isNotEmpty) {
      _emitResult();
    }

    debugPrint('[VoiceContinuousListener] 聽寫已結束');
  }

  /// 送出辨識結果
  void _emitResult() {
    if (_currentText.isEmpty) return;

    final duration = _dictationStartTime != null
        ? DateTime.now().difference(_dictationStartTime!)
        : Duration.zero;

    // 複製樣本避免外部修改
    final samples = List<double>.from(_currentSamples);

    debugPrint('[VoiceContinuousListener] 辨識結果: "$_currentText" '
        '(${duration.inSeconds}s, ${samples.length} samples)');

    onRecognized?.call(
      text: _currentText,
      audioSamples: samples,
      duration: duration,
    );

    _currentText = '';
    _currentSamples.clear();
    _dictationStartTime = null;
  }

  /// 處理 STT 辨識結果
  void _handleSttResult(SpeechRecognitionResult result) {
    final recognizedWords = result.recognizedWords.trim();
    if (recognizedWords.isNotEmpty) {
      _currentText = recognizedWords;
    }

    // 最終結果時自動送出（如果 VAD 沒有先觸發的話）
    if (result.finalResult && _isDictating && _currentText.isNotEmpty) {
      // VAD 會負責觸發 _finalizeDictation，這裡不重複
      // 但如果 STT 自己結束了，也要處理
      _finalizeDictation();
    }
  }

  /// 處理 STT 音量電平變化
  ///
  /// 將 STT 的 sound level（dBFS）轉換為 0.0~1.0 的振幅值，
  /// 推入振幅串流供 VAD 使用。
  void _handleSoundLevel(double level) {
    // STT 的 sound level 是 dBFS（通常為負值，如 -40.0 ~ 0.0）
    // 轉換為 0.0 ~ 1.0 的振幅值
    // -60 dBFS 以下 → 0.0（靜音）
    // 0 dBFS → 1.0（最大音量）
    final normalizedAmplitude = ((level + 60) / 60).clamp(0.0, 1.0);

    _currentSamples.add(normalizedAmplitude);

    // 推入串流給 VAD 處理
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add([normalizedAmplitude]);
    }
  }

  /// 處理 STT 狀態變化
  void _handleSttStatus(String status) {
    debugPrint('[VoiceContinuousListener] STT 狀態: $status');

    if (status == 'done' || status == 'notListening') {
      if (_isDictating && _currentText.isNotEmpty) {
        _finalizeDictation();
      }
    } else if (status == 'listening') {
      // STT 開始聽了，如果 VAD 還沒觸發 startDictation，在這裡啟動
      if (!_isDictating) {
        _startDictation();
      }
    }
  }

  /// 處理 STT 錯誤
  void _handleSttError(SpeechRecognitionError error) {
    debugPrint('[VoiceContinuousListener] STT 錯誤: ${error.errorMsg}');
    _isDictating = false;

    // 如果有部分結果，仍然送出
    if (_currentText.isNotEmpty) {
      _emitResult();
    }

    onError?.call('語音辨識錯誤：${error.errorMsg}');

    // 持續監聽模式下，錯誤後自動重新開始監聯
    if (_isListening && _available) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isListening && !_isDictating) {
          debugPrint('[VoiceContinuousListener] 錯誤後重新啟動聽寫');
          // VAD 會在下一次偵測到說話時重新啟動聽寫
        }
      });
    }
  }

  /// 釋放資源
  void dispose() {
    _vad.dispose();
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _amplitudeController.close();
  }
}
