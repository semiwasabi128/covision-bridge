/// 語音活動偵測（Voice Activity Detection）
library;

/// 使用音量閾值偵測使用者何時開始/停止說話。
///
/// 這是 Phase 2 全雙工音訊層的基礎元件 — 接收音訊振幅串流，
/// 即時判斷使用者是否在說話，並透過回調通知上下層。
///
/// 偵測邏輯：
/// 1. 音量持續超過 [silenceThreshold] → 判定為「開始說話」
/// 2. 音量持續低於 [silenceThreshold] 超過 [silenceDuration] → 判定為「停止說話」
///
/// 使用方式：
///   final vad = VoiceActivityDetector(
///     onSpeechStart: () => debugPrint('使用者開始說話'),
///     onSpeechEnd: () => debugPrint('使用者停止說話'),
///   );
///   vad.listenTo(audioAmplitudeStream);
///   // ... 不需要時
///   vad.dispose();
///
/// 音訊振幅樣本應為 0.0 ~ 1.0 的浮點數，取樣頻率建議 100Hz
///（每 10ms 一個樣本），與 VoiceEmotionAnalyzer 的格式一致。

import 'dart:async';

/// 語音活動偵測器
///
/// 透過 [StreamTransformer] 將原始音訊振幅串流轉換為語音活動事件。
/// 當偵測到使用者開始說話時觸發 [onSpeechStart]，
/// 偵測到使用者停止說話（沉默超過 [silenceDuration]）時觸發 [onSpeechEnd]。
class VoiceActivityDetector {
  /// 偵測到使用者開始說話時觸發
  final void Function()? onSpeechStart;

  /// 偵測到使用者停止說話時觸發
  final void Function()? onSpeechEnd;

  /// 靜音閾值 — 音量低於此值視為沉默（0.0 ~ 1.0）
  ///
  /// 預設 0.05，與 VoiceEmotionAnalyzer 的沉默閾值一致。
  /// 環境噪音較大時可調高，安靜環境可調低。
  final double silenceThreshold;

  /// 沉默持續時間 — 超過此長度的連續沉默才判定為「停止說話」
  ///
  /// 預設 1.5 秒，適合一般對話節奏。
  /// 語速快的場景可調短（如 1.0 秒），長句場景可調長（如 2.0 秒）。
  final Duration silenceDuration;

  /// 起聲確認時間 — 音量需持續超過閾值此長度才判定為「開始說話」
  ///
  /// 避免單一噪音脈衝誤觸發。預設 150ms。
  final Duration speechOnsetDuration;

  /// 目前是否正在說話
  bool _isSpeaking = false;

  /// 目前是否正在監聽
  bool _isActive = false;

  /// 串流訂閱（用於取消監聽）
  StreamSubscription<List<double>>? _subscription;

  /// 音量持續超過閾值的累積時間
  Duration _speechOnsetAccumulator = Duration.zero;

  /// 音量持續低於閾值的累積時間（沉默計時）
  Duration _silenceAccumulator = Duration.zero;

  /// 每個樣本代表的時間長度（由取樣頻率推算）
  Duration _sampleInterval = const Duration(milliseconds: 10);

  /// 建立語音活動偵測器
  ///
  /// [onSpeechStart] — 偵測到使用者開始說話時觸發
  /// [onSpeechEnd] — 偵測到使用者停止說話時觸發
  /// [silenceThreshold] — 靜音閾值（0.0 ~ 1.0），預設 0.05
  /// [silenceDuration] — 沉默判定時間，預設 1.5 秒
  /// [speechOnsetDuration] — 起聲確認時間，預設 150ms
  VoiceActivityDetector({
    this.onSpeechStart,
    this.onSpeechEnd,
    this.silenceThreshold = 0.05,
    this.silenceDuration = const Duration(milliseconds: 1500),
    this.speechOnsetDuration = const Duration(milliseconds: 150),
  });

  /// 目前是否偵測到使用者正在說話
  bool get isSpeaking => _isSpeaking;

  /// 目前是否正在監聽中
  bool get isActive => _isActive;

  /// 開始監聽音訊振幅串流
  ///
  /// [audioStream] — 音訊振幅樣本串流，每筆資料為一組 0.0~1.0 的振幅值
  /// [sampleInterval] — 每個樣本之間的時間間隔，預設 10ms（100Hz）
  ///
  /// 呼叫後開始偵測語音活動。重複呼叫會先取消舊的訂閱再重新開始。
  void listenTo(
    Stream<List<double>> audioStream, {
    Duration sampleInterval = const Duration(milliseconds: 10),
  }) {
    // 取消舊的監聽
    dispose();

    _sampleInterval = sampleInterval;
    _isActive = true;
    _isSpeaking = false;
    _speechOnsetAccumulator = Duration.zero;
    _silenceAccumulator = Duration.zero;

    _subscription = audioStream.listen(
      _processSamples,
      onError: (Object error) {
        // 串流錯誤時停止監聽
        _isActive = false;
      },
      onDone: () {
        // 串流結束時，如果在說話中，觸發停止
        if (_isSpeaking) {
          _isSpeaking = false;
          onSpeechEnd?.call();
        }
        _isActive = false;
      },
    );
  }

  /// 處理一批音訊振幅樣本
  void _processSamples(List<double> samples) {
    if (!_isActive) return;

    for (final sample in samples) {
      _processSample(sample);
    }
  }

  /// 處理單一音訊振幅樣本
  void _processSample(double amplitude) {
    final isLoud = amplitude >= silenceThreshold;

    if (_isSpeaking) {
      // ── 正在說話中：偵測沉默 ──
      if (isLoud) {
        // 使用者還在說話，重置沉默計時
        _silenceAccumulator = Duration.zero;
      } else {
        // 沉默累積
        _silenceAccumulator += _sampleInterval;

        // 沉默超過閾值 → 判定停止說話
        if (_silenceAccumulator >= silenceDuration) {
          _isSpeaking = false;
          _silenceAccumulator = Duration.zero;
          _speechOnsetAccumulator = Duration.zero;
          onSpeechEnd?.call();
        }
      }
    } else {
      // ── 未在說話：偵測起聲 ──
      if (isLoud) {
        _speechOnsetAccumulator += _sampleInterval;
        _silenceAccumulator = Duration.zero;

        // 音量持續超過起聲確認時間 → 判定開始說話
        if (_speechOnsetAccumulator >= speechOnsetDuration) {
          _isSpeaking = true;
          _speechOnsetAccumulator = Duration.zero;
          onSpeechStart?.call();
        }
      } else {
        // 沒有聲音，重置起聲確認
        _speechOnsetAccumulator = Duration.zero;
      }
    }
  }

  /// 停止監聽並釋放資源
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isActive = false;
    _isSpeaking = false;
    _speechOnsetAccumulator = Duration.zero;
    _silenceAccumulator = Duration.zero;
  }
}

/// 將音訊振幅串流轉換為語音活動事件的 StreamTransformer
///
/// 此 transformer 將 `Stream<List<double>>`（原始振幅）轉換為
/// `Stream<VadEvent>`（語音活動事件），可用於串流組合。
///
/// 使用方式：
///   final transformer = VadTransformer(silenceThreshold: 0.05);
///   final eventStream = audioStream.transform(transformer);
///   eventStream.listen((event) {
///     if (event.isSpeechStart) { ... }
///     if (event.isSpeechEnd) { ... }
///   });
class VadTransformer
    extends StreamTransformerBase<List<double>, VadEvent> {
  /// 靜音閾值
  final double silenceThreshold;

  /// 沉默判定時間
  final Duration silenceDuration;

  /// 起聲確認時間
  final Duration speechOnsetDuration;

  /// 每個樣本的時間間隔
  final Duration sampleInterval;

  /// 建立 VAD 串流轉換器
  VadTransformer({
    this.silenceThreshold = 0.05,
    this.silenceDuration = const Duration(milliseconds: 1500),
    this.speechOnsetDuration = const Duration(milliseconds: 150),
    this.sampleInterval = const Duration(milliseconds: 10),
  });

  @override
  Stream<VadEvent> bind(Stream<List<double>> stream) {
    bool isSpeaking = false;
    Duration speechOnsetAcc = Duration.zero;
    Duration silenceAcc = Duration.zero;

    return stream.expand((samples) {
      final events = <VadEvent>[];

      for (final sample in samples) {
        final isLoud = sample >= silenceThreshold;

        if (isSpeaking) {
          if (isLoud) {
            silenceAcc = Duration.zero;
          } else {
            silenceAcc += sampleInterval;
            if (silenceAcc >= silenceDuration) {
              isSpeaking = false;
              silenceAcc = Duration.zero;
              speechOnsetAcc = Duration.zero;
              events.add(const VadEvent.speechEnd());
            }
          }
        } else {
          if (isLoud) {
            speechOnsetAcc += sampleInterval;
            silenceAcc = Duration.zero;
            if (speechOnsetAcc >= speechOnsetDuration) {
              isSpeaking = true;
              speechOnsetAcc = Duration.zero;
              events.add(const VadEvent.speechStart());
            }
          } else {
            speechOnsetAcc = Duration.zero;
          }
        }
      }

      return events;
    });
  }
}

/// VAD 事件
class VadEvent {
  /// 是否為「開始說話」事件
  final bool isSpeechStart;

  /// 是否為「停止說話」事件
  final bool isSpeechEnd;

  /// 事件發生時間戳（相對於開始監聽）
  final Duration timestamp;

  /// 建立開始說話事件
  const VadEvent.speechStart({this.timestamp = Duration.zero})
      : isSpeechStart = true,
        isSpeechEnd = false;

  /// 建立停止說話事件
  const VadEvent.speechEnd({this.timestamp = Duration.zero})
      : isSpeechStart = false,
        isSpeechEnd = true;

  @override
  String toString() {
    if (isSpeechStart) return 'VadEvent(speechStart)';
    if (isSpeechEnd) return 'VadEvent(speechEnd)';
    return 'VadEvent(none)';
  }
}
