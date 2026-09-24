/// 語氣/情緒分析引擎
library;

/// 分析使用者的語音特徵（語速、停頓位置），推斷情緒狀態。
/// 這是五層回應架構中第二層（情緒短回應）的資料來源。
///
/// 分析維度：
/// - 語速（字/秒）— 快 = 急迫、慢 = 思考中
/// - 停頓位置 — 哪個問題猶豫了
/// - 音量變化 — 情緒起伏
/// - 情緒分類 — urgent / confused / happy / angry / calm
///
/// 使用方式：
///   final analyzer = VoiceEmotionAnalyzer();
///   final result = analyzer.analyze(audioSamples, duration, text: '幫我看看這個');
///   // result.emotion → Emotion.urgent
///   // result.speechRate → 5.2（字/秒）
///   // result.pauses → [Duration(seconds: 2), ...]

import 'dart:math' as math;

/// 情緒分類列舉
///
/// 對應設計方案中的情緒感知與回應策略：
/// - urgent: 急迫/焦慮 → 先安撫，快速給方案
/// - confused: 猶豫/困惑 → 主動引導，拆解問題
/// - happy: 興奮/開心 → 共鳴回應
/// - angry: 憤怒/不滿 → 誠懇道歉，立即修正
/// - calm: 平靜/正常 → 正常節奏
enum VoiceEmotion {
  urgent('急迫'),
  confused('困惑'),
  happy('開心'),
  angry('憤怒'),
  calm('平靜');

  const VoiceEmotion(this.label);
  final String label;
}

/// 停頓資訊
///
/// 記錄一次停頓的位置與長度，用於判斷使用者在哪個話題猶豫了。
class VoicePause {
  /// 停頓開始時間（相對於發聲起點）
  final Duration start;

  /// 停頓長度
  final Duration duration;

  const VoicePause({
    required this.start,
    required this.duration,
  });

  @override
  String toString() => 'VoicePause(start: $start, duration: $duration)';
}

/// 情緒分析結果
///
/// 包含偵測到的情緒、語速、停頓位置列表、以及音量特徵。
class EmotionResult {
  /// 偵測到的情緒
  final VoiceEmotion emotion;

  /// 語速（字/秒）
  final double speechRate;

  /// 偵測到的停頓列表
  final List<VoicePause> pauses;

  /// 平均音量（0.0 ~ 1.0）
  final double averageVolume;

  /// 音量變化幅度（標準差）
  final double volumeVariation;

  /// 分析信心分數（0.0 ~ 1.0）
  final double confidence;

  const EmotionResult({
    required this.emotion,
    required this.speechRate,
    required this.pauses,
    required this.averageVolume,
    required this.volumeVariation,
    required this.confidence,
  });

  @override
  String toString() =>
      'EmotionResult(emotion: $emotion, speechRate: ${speechRate.toStringAsFixed(1)}, '
      'pauses: ${pauses.length}, avgVol: ${averageVolume.toStringAsFixed(2)}, '
      'confidence: ${confidence.toStringAsFixed(2)})';
}

/// 語氣/情緒分析器
///
/// 接收音訊樣本與辨識文字，分析語速、停頓、音量特徵，
/// 推斷使用者情緒狀態。
///
/// 分析流程：
/// 1. 從音訊樣本計算音量曲線
/// 2. 偵測停頓（音量低於閾值的連續段）
/// 3. 計算語速（文字字數 / 有效發聲時間）
/// 4. 綜合語速、停頓、音量特徵推斷情緒
class VoiceEmotionAnalyzer {
  /// 停頓偵測的音量閾值（低於此值視為沉默）
  static const double _silenceThreshold = 0.05;

  /// 最小停頓長度（短於此不視為停頓）
  static const Duration _minPauseDuration = Duration(milliseconds: 500);

  /// 正常語速基準（中文字/秒）
  static const double _normalSpeechRate = 3.5;

  /// 分析語音特徵並推斷情緒
  ///
  /// [audioSamples] — 音訊振幅樣本（0.0 ~ 1.0），取樣頻率建議 100Hz
  /// [duration] — 總錄音時長
  /// [text] — 辨識出的文字（用於計算語速）
  Future<EmotionResult> analyze({
    required List<double> audioSamples,
    required Duration duration,
    String? text,
  }) async {
    if (audioSamples.isEmpty || duration.inMilliseconds == 0) {
      return EmotionResult(
        emotion: VoiceEmotion.calm,
        speechRate: 0,
        pauses: const [],
        averageVolume: 0,
        volumeVariation: 0,
        confidence: 0,
      );
    }

    // 計算音量統計
    final volumeStats = _computeVolumeStats(audioSamples);

    // 偵測停頓
    final pauses = _detectPauses(audioSamples, duration);

    // 計算語速
    final speechRate = _computeSpeechRate(
      text: text,
      duration: duration,
      pauses: pauses,
    );

    // 推斷情緒
    final emotion = _inferEmotion(
      speechRate: speechRate,
      pauses: pauses,
      volumeStats: volumeStats,
    );

    // 計算信心分數
    final confidence = _computeConfidence(
      audioSamples: audioSamples,
      duration: duration,
      text: text,
    );

    return EmotionResult(
      emotion: emotion,
      speechRate: speechRate,
      pauses: pauses,
      averageVolume: volumeStats.average,
      volumeVariation: volumeStats.standardDeviation,
      confidence: confidence,
    );
  }

  /// 計算音量統計（平均值 + 標準差）
  _VolumeStats _computeVolumeStats(List<double> samples) {
    if (samples.isEmpty) {
      return _VolumeStats(average: 0, standardDeviation: 0);
    }

    final sum = samples.reduce((a, b) => a + b);
    final avg = sum / samples.length;

    final variance = samples.map((s) => (s - avg) * (s - avg)).reduce((a, b) => a + b) / samples.length;
    final std = math.sqrt(variance);

    return _VolumeStats(average: avg, standardDeviation: std);
  }

  /// 偵測停頓（音量低於閾值的連續段）
  List<VoicePause> _detectPauses(
    List<double> samples,
    Duration totalDuration,
  ) {
    final pauses = <VoicePause>[];
    final sampleDuration = totalDuration.inMicroseconds / samples.length;

    int? silenceStartIndex;

    for (var i = 0; i < samples.length; i++) {
      final isSilent = samples[i] < _silenceThreshold;

      if (isSilent) {
        silenceStartIndex ??= i;
      } else {
        if (silenceStartIndex != null) {
          final pauseDuration = Duration(
            microseconds: ((i - silenceStartIndex) * sampleDuration).round(),
          );
          if (pauseDuration >= _minPauseDuration) {
            pauses.add(VoicePause(
              start: Duration(
                microseconds: (silenceStartIndex * sampleDuration).round(),
              ),
              duration: pauseDuration,
            ));
          }
          silenceStartIndex = null;
        }
      }
    }

    // 處理結尾的沉默
    if (silenceStartIndex != null) {
      final pauseDuration = Duration(
        microseconds: ((samples.length - silenceStartIndex) * sampleDuration).round(),
      );
      if (pauseDuration >= _minPauseDuration) {
        pauses.add(VoicePause(
          start: Duration(
            microseconds: (silenceStartIndex * sampleDuration).round(),
          ),
          duration: pauseDuration,
        ));
      }
    }

    return pauses;
  }

  /// 計算語速（字/秒）
  ///
  /// 使用有效發聲時間（扣除停頓時間）來計算語速更準確。
  double _computeSpeechRate({
    String? text,
    required Duration duration,
    required List<VoicePause> pauses,
  }) {
    if (text == null || text.isEmpty) return 0;

    // 中文字數 = 字串長度（去除空格和標點）
    final charCount = text.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '').length;
    if (charCount == 0) return 0;

    // 有效發聲時間 = 總時間 - 停頓時間
    final totalPauseMs = pauses.fold<int>(
      0,
      (sum, p) => sum + p.duration.inMilliseconds,
    );
    final effectiveMs = duration.inMilliseconds - totalPauseMs;
    if (effectiveMs <= 0) return 0;

    return charCount / (effectiveMs / 1000.0);
  }

  /// 綜合特徵推斷情緒
  ///
  /// 推斷規則（依優先級）：
  /// 1. 語速很快 + 音量大 → urgent
  /// 2. 語速慢 + 多停頓 → confused
  /// 3. 音量大 + 音量變化大 → angry
  /// 4. 語速偏快 + 音量適中 → happy
  /// 5. 其他 → calm
  VoiceEmotion _inferEmotion({
    required double speechRate,
    required List<VoicePause> pauses,
    required _VolumeStats volumeStats,
  }) {
    final isFast = speechRate > _normalSpeechRate * 1.4;
    final isSlow = speechRate < _normalSpeechRate * 0.6 && speechRate > 0;
    final isLoud = volumeStats.average > 0.3;
    final hasHighVariation = volumeStats.standardDeviation > 0.15;
    final hasManyPauses = pauses.length >= 3;

    // 急迫：語速快 + 音量大
    if (isFast && isLoud) {
      return VoiceEmotion.urgent;
    }

    // 困惑：語速慢 + 多停頓
    if (isSlow && hasManyPauses) {
      return VoiceEmotion.confused;
    }

    // 憤怒：音量大 + 變化劇烈
    if (isLoud && hasHighVariation) {
      return VoiceEmotion.angry;
    }

    // 開心：語速偏快 + 音量適中
    if (isFast && !isLoud) {
      return VoiceEmotion.happy;
    }

    // 困惑：多停頓但語速不慢
    if (hasManyPauses) {
      return VoiceEmotion.confused;
    }

    // 預設：平靜
    return VoiceEmotion.calm;
  }

  /// 計算分析信心分數
  ///
  /// 樣本越多、時長越長、有文字 → 信心越高
  double _computeConfidence({
    required List<double> audioSamples,
    required Duration duration,
    String? text,
  }) {
    var confidence = 0.0;

    // 樣本數貢獻（500+ 樣本 = 滿分）
    confidence += (audioSamples.length / 500).clamp(0.0, 0.3);

    // 時長貢獻（3秒+ = 滿分）
    confidence += (duration.inSeconds / 3).clamp(0.0, 0.3);

    // 文字貢獻（有文字 = +0.4）
    if (text != null && text.isNotEmpty) {
      confidence += 0.4;
    }

    return confidence.clamp(0.0, 1.0);
  }
}

/// 音量統計結果（內部使用）
class _VolumeStats {
  final double average;
  final double standardDeviation;

  const _VolumeStats({
    required this.average,
    required this.standardDeviation,
  });
}
