// voice_speech_handler.dart
// [教練 Agent 2026-07-28] Voice AI 專用語音辨識 handler
//
// 只負責把 speech_to_text 的結果餵給 VoiceEngine，
// 不碰任何 TextEditingController（避免 paste bug）。
//
// [教練 Agent 2026-07-28] UX 改善：
// - initialize() 失敗時提供明確的麥克風權限錯誤訊息
// - 區分「權限未開啟」和「初始化失敗」兩種情況

import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../services/voice/voice_engine.dart';

/// Voice AI 專用語音辨識 handler — 只驅動 VoiceEngine，不碰輸入框。
class VoiceSpeechHandler {
  VoiceSpeechHandler({
    required this.voiceEngine,
    this.onError,
  });

  final SpeechToText _speechToText = SpeechToText();
  final VoiceEngine voiceEngine;
  final void Function(String)? onError;

  bool _available = false;
  bool _listening = false;
  bool _initialized = false;

  /// [教練 Agent 2026-08-03] 振幅串流（normalized 0.0~1.0）
  /// 給 UI（麥克風按鈕波形）訂閱真實音量
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// [教練 Agent 2026-08-03] partial 文字串流（STT 即時辨識中文字）
  /// 給 UI 顯示在浮層 overlay
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  Stream<String> get partialTextStream => _partialTextController.stream;
  String _lastPartialText = '';

  /// [小葵 2026-08-30] final result 串流
  /// 注意：partialTextStream 在 final 時推「空字串」（清 overlay 用），
  /// 所以下游要拿最終辨識文字必須訂這個 stream——之前 VoiceLiveController
  /// 訂 partialTextStream 等「非空 final」永遠等不到（根因見該檔註解）。
  final StreamController<String> _finalTextController =
      StreamController<String>.broadcast();
  Stream<String> get finalTextStream => _finalTextController.stream;

  /// [小葵 2026-08-30] 最後 partial 文字（VAD fallback 用——
  /// STT final 遲到時用最後 partial 當最終文字，不丟句）
  String get lastPartialText => _lastPartialText;

  /// [小葵 2026-09-24 Blue 抓包④] 句界重置——dispatch 一句後切斷 STT 累積。
  /// macOS dictation 的 recognizedWords 跨句累積（越滾越長），導致
  /// 下一輪 fallback 把前面所有句子一起送出（log 鐵證：
  /// 「...誒」→「...誒誒記得」→「...誒誒記得對啊所以」）。
  /// 呼叫此方法後，lastPartialText 歸零、之後的 partial 只取
  /// 「已送出長度之後」的新增句。
  void resetSessionBaseline() {
    _lastPartialText = '';
    _cumulativePrefixLen = 0;
  }

  /// [小葵 2026-09-24 Blue 抓包④] dispatch 記帳——VoiceLive 送出一句後，
  /// 把該句（疊加在 STT 累積字串上的長度）記為前綴，之後 partial 只推新增。
  void markDispatched(String dispatchedText) {
    // dispatchedText 是從 lastPartialText 切出來的——疊回累積長度
    final newTotal =
        _cumulativePrefixLen + dispatchedText.trim().length;
    // 只有「確實在累積字串內前進」才更新（防倒退）
    if (newTotal >= _cumulativePrefixLen) {
      _cumulativePrefixLen = newTotal;
    }
    _lastPartialText = '';
  }

  /// [小葵 2026-09-24 Blue 抓包④] 裱除已送出前綴——fallback 拿
  /// lastPartialText（STT 累積全文）時，切掉已送出長度只回新增句。
  String stripDispatchedPrefix(String s) {
    if (_cumulativePrefixLen <= 0) return s;
    if (s.length <= _cumulativePrefixLen) return '';
    return s.substring(_cumulativePrefixLen);
  }

  /// 已送出（切句）的累積長度——partial 進來時裱掉這段前綴
  int _cumulativePrefixLen = 0;

  bool get isListening => _listening;
  bool get isAvailable => _available;

  /// [教練 Agent 2026-08-03] 處理 STT 音量回調
  /// speech_to_text 的 soundLevel 是 dB（負值），正規化到 0.0~1.0
  /// - 一般音量 -30 ~ 0 dB → 0.5 ~ 1.0
  /// - 安靜 -50 ~ -30 dB → 0.0 ~ 0.5
  void _handleSoundLevel(double level) {
    // dB → 線性：-60 dB → 0.0, 0 dB → 1.0
    final normalized = ((level + 60) / 60).clamp(0.0, 1.0);
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(normalized);
    }
  }

  /// 啟動語音監聽
  ///
  /// 如果 initialize() 失敗（通常代表麥克風權限未開啟），
  /// 會透過 onError 回報權限錯誤訊息。
  Future<void> start() async {
    if (_listening) return;

    try {
      // 首次使用需要 initialize
      if (!_initialized) {
        _available = await _speechToText.initialize(
          debugLogging: kDebugMode,
          onError: _handleError,
          onStatus: _handleStatus,
        );
        _initialized = true;
        // [教練 Agent 2026-08-03] initialize 後 wait 200ms 再 listen
        // speech_to_text 在 macOS 首次啟動有時序問題（需要初始化音訊 session）
        // 立即 listen 會失敗（首幀拿不到 mic）→ 200ms 延遲可解
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (!_available) {
        // initialize 回傳 false → 麥克風權限未開啟或語音辨識不可用
        onError?.call('麥克風權限未開啟，請到系統設定 > 隱私與安全 > 麥克風允許橋樑');
        return;
      }

      _listening = true;
      // [教練 Agent 2026-08-03] 拿掉 voiceEngine.onUserStartedSpeaking()
      // voiceEngine 是全雙工對話引擎，會自己觸發送出
      // 改為：partial → controller，語音停止時統一由 _toggleVoiceConversation 送一次
      // 避免雙重送出

      await _speechToText.listen(
        onResult: _handleResult,
        onSoundLevelChange: _handleSoundLevel,  // [教練 Agent 2026-08-03] 訂閱真實音量
        listenOptions: SpeechListenOptions(
          localeId: 'zh_TW',
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );

      // [教練 Agent 2026-08-03] 首次 listen 後等 500ms 檢查
      // speech_to_text 套件首次 listen 經常失敗（音訊 session 還沒準備好）
      // 等 500ms 後若 _listening 已被 _handleStatus 設為 false（status=notListening）→ 重試一次
      await Future.delayed(const Duration(milliseconds: 500));
      if (_listening && !_speechToText.isListening) {
        debugPrint('[VoiceSpeechHandler] 首次 listen 失敗，重試一次');
        _listening = false;
        try {
          await _speechToText.listen(
            onResult: _handleResult,
            onSoundLevelChange: _handleSoundLevel,
            listenOptions: SpeechListenOptions(
              localeId: 'zh_TW',
              listenMode: ListenMode.dictation,
              partialResults: true,
              cancelOnError: false,
            ),
          );
        } catch (e) {
          debugPrint('[VoiceSpeechHandler] 重試也失敗：$e');
        }
      }
    } catch (error) {
      _listening = false;
      final errorMsg = error.toString();

      // 常見權限錯誤模式
      if (errorMsg.contains('permission') ||
          errorMsg.contains('Permission') ||
          errorMsg.contains('denied') ||
          errorMsg.contains('microphone') ||
          errorMsg.contains('Microphone')) {
        onError?.call('麥克風權限未開啟，請到系統設定 > 隱私與安全 > 麥克風允許橋樑');
      } else {
        onError?.call('語音監聽啟動失敗：$error');
      }
    }
  }

  /// 停止語音監聽
  Future<void> stop() async {
    await _speechToText.stop();
    _listening = false;
    // [教練 Agent 2026-08-03] 拿掉 voiceEngine.onUserStoppedSpeaking()（避免雙重送出）
  }

  void dispose() {
    _speechToText.cancel();
    _amplitudeController.close();
    _partialTextController.close();  // [教練 Agent 2026-08-03]
    _finalTextController.close();  // [小葵 2026-08-30]
  }

  // ─── Internal ───

  void _handleResult(SpeechRecognitionResult result) {
    final recognizedWords = result.recognizedWords.trim();

    // [教練 Agent 2026-08-03] 推 partial 文字到 stream（給 UI overlay 顯示）
    if (result.finalResult) {
      // 最終結果 — partial overlay 推空字串清掉
      if (_lastPartialText.isNotEmpty) {
        _lastPartialText = '';
        if (!_partialTextController.isClosed) {
          _partialTextController.add('');
        }
      }
      // [小葵 2026-09-24 Blue 抓包④] final 也是累積的——切掉已送出前綴再推
      if (recognizedWords.isNotEmpty && !_finalTextController.isClosed) {
        _finalTextController.add(stripDispatchedPrefix(recognizedWords));
      }
    } else {
      // partial 結果
      if (recognizedWords != _lastPartialText) {
        // [小葵 2026-09-24 Blue 抓包④] dictation 累積裱除——
        // recognizedWords 含「本 session 已送出的句子」時，只推新增部分。
        String visible = recognizedWords;
        if (_cumulativePrefixLen > 0 &&
            recognizedWords.length >= _cumulativePrefixLen) {
          visible = recognizedWords.substring(_cumulativePrefixLen);
        }
        _lastPartialText = recognizedWords;
        if (visible.trim().isNotEmpty &&
            !_partialTextController.isClosed) {
          _partialTextController.add(visible);
        }
      }
    }

    if (recognizedWords.isEmpty) return;

    // [教練 Agent 2026-08-03] 不呼叫 voiceEngine.onSpeechRecognized
    // 改為：partial 文字已寫入 controller，語音停止時統一由 _toggleVoiceConversation 送一次
    // 舊邏輯會在 final 結果時觸發一次送出 + 語音停止又送一次 → 重複
  }

  void _handleStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _listening = false;
      // [教練 Agent 2026-08-03] 拿掉 voiceEngine.onUserStoppedSpeaking()
      // 改由 _toggleVoiceConversation 統一處理停止
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _listening = false;
    debugPrint('[VoiceSpeechHandler] 語音辨識錯誤：${error.errorMsg}');

    // 常見錯誤類型處理
    final msg = error.errorMsg.toLowerCase();
    if (msg.contains('permission') || msg.contains('denied')) {
      onError?.call('麥克風權限未開啟，請到系統設定 > 隱私與安全 > 麥克風允許橋樑');
    } else if (msg.contains('no_speech') || msg.contains('nospeech')) {
      // 沒有偵測到語音 — 不算錯誤，靜默處理
      debugPrint('[VoiceSpeechHandler] 未偵測到語音輸入');
    } else if (msg.contains('network') || msg.contains('server')) {
      onError?.call('語音辨識服務無法連線，請檢查網路狀態');
    } else {
      onError?.call('語音辨識錯誤：${error.errorMsg}');
    }
  }
}
