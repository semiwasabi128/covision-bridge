/// 第一層虛字答腔引擎
library;

/// 使用者說話時，定時隨機發出虛字答腔（「嗯」「對」「是喔」）。
/// 不經過 LLM，只靠 PersonaVoiceResponses.backchannels 固定池。
///
/// 效果：讓使用者感覺「有人在聽」。
///
/// 時序：使用者說話中 → 每 2-4 秒隨機發一個虛字答腔 → 使用者停止時停止。
///
/// 使用方式：
///   final engine = VoiceBackchannelEngine(
///     persona: personaResponses,
///     onBackchannel: (text) => ttsHandler.speak(text),
///   );
///   engine.start(); // 使用者開始說話
///   engine.stop();  // 使用者停止說話

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'voice_persona_responses.dart';

/// 虛字答腔引擎
///
/// 使用者說話時定時發出虛字答腔。
/// 可被 start() / stop() 控制。
class VoiceBackchannelEngine {
  /// 人格回應池（取 backchannels 用）
  final PersonaVoiceResponses persona;

  /// 答腔回調 — 每次發出虛字答腔時呼叫
  ///
  /// 通常接 TTS 播放。
  final void Function(String backchannel) onBackchannel;

  /// 答腔間隔範圍（秒）
  ///
  /// 每次 random 產生 [minInterval, maxInterval] 之間的間隔。
  final double minIntervalSeconds;
  final double maxIntervalSeconds;

  /// 是否正在運行
  bool _running = false;

  /// 定時器
  Timer? _timer;

  /// 隨機數產生器
  final Random _random = Random();

  /// 建立虛字答腔引擎
  ///
  /// [persona] — 人格回應池
  /// [onBackchannel] — 答腔回調（通常接 TTS）
  /// [minIntervalSeconds] — 最小答腔間隔（預設 2.0 秒）
  /// [maxIntervalSeconds] — 最大答腔間隔（預設 4.0 秒）
  VoiceBackchannelEngine({
    required this.persona,
    required this.onBackchannel,
    this.minIntervalSeconds = 2.0,
    this.maxIntervalSeconds = 4.0,
  });

  /// 是否正在運行
  bool get isRunning => _running;

  /// 開始答腔
  ///
  /// 使用者開始說話時呼叫。
  /// 啟動後每 [minInterval, maxInterval] 秒隨機發出一個虛字答腔。
  void start() {
    if (_running) return;
    _running = true;
    _scheduleNext();
    debugPrint('[VoiceBackchannelEngine] 答腔已啟動');
  }

  /// 停止答腔
  ///
  /// 使用者停止說話時呼叫。
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    debugPrint('[VoiceBackchannelEngine] 答腔已停止');
  }

  /// 排程下一次答腔
  void _scheduleNext() {
    if (!_running) return;

    // 隨機間隔
    final interval = minIntervalSeconds +
        _random.nextDouble() * (maxIntervalSeconds - minIntervalSeconds);

    _timer = Timer(Duration(milliseconds: (interval * 1000).round()), () {
      if (!_running) return;

      // 發出虛字答腔
      final backchannel = persona.randomBackchannel();
      debugPrint('[VoiceBackchannelEngine] 發出答腔: $backchannel');
      onBackchannel(backchannel);

      // 排程下一次
      _scheduleNext();
    });
  }

  /// 釋放資源
  void dispose() {
    stop();
  }
}
