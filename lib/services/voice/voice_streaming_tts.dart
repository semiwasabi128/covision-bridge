// voice_streaming_tts.dart — 串流 TTS
//
// Phase 2: Inner Monologue 技術 — Agent 文字邊生成邊念
//
// 不等整段文字完成才開始 TTS — 第一句話生成就開始念。
// 文字分段送 TTS，每段 2-3 句，自然銜接。
//
// 對齊 Moshi Inner Monologue：
//   文字思考 → 文字 token → 語音 token → 語音輸出
//   AgentLoop streaming 輸出 → 分段 → 串流 TTS

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 串流 TTS 引擎
///
/// 接收文字串流（AgentLoop 的 streaming 輸出），
/// 分段送 TTS 朗讀，邊生成邊播放。
///
/// 使用方式：
///   final streamingTts = VoiceStreamingTts(
///     onSpeak: ttsHandler.speak,
///     onStop: ttsHandler.stop,
///   );
///   // AgentLoop 串流輸出時：
///   streamingTts.feed('我先看看這個檔案...');  // 立即開始念
///   streamingTts.feed('好，我找到了問題。');
///   streamingTts.flush();  // 確保最後一段也念完
class VoiceStreamingTts {
  VoiceStreamingTts({
    required this.onSpeak,
    required this.onStop,
    this.sentenceDelimiter = '。！？.!?\n',
    this.minChunkLength = 8,
    this.maxChunkLength = 50,
  });

  /// TTS 朗讀回調
  final void Function(String text) onSpeak;

  /// 停止 TTS 回調
  final Future<void> Function() onStop;

  /// 句子分隔符
  final String sentenceDelimiter;

  /// 最小分段長度（太短不分段，累積到 minChunkLength 才念）
  final int minChunkLength;

  /// 最大分段長度（超過就強制念，不等句號）
  final int maxChunkLength;

  /// 累積的文字 buffer
  final StringBuffer _buffer = StringBuffer();

  /// 是否正在播放
  bool _isSpeaking = false;

  /// 等待播放的佇列
  final List<String> _queue = [];

  /// 是否已停止
  bool _stopped = false;

  /// 餵入文字片段（AgentLoop streaming 輸出）
  ///
  /// 每收到一段文字就檢查是否構成一個可念的片段：
  /// - 遇到句號且長度 >= minChunkLength → 念
  /// - 長度 >= maxChunkLength → 念（不等句號）
  /// - 否則繼續累積
  void feed(String chunk) {
    if (_stopped) return;

    _buffer.write(chunk);
    final text = _buffer.toString();

    // 檢查是否有完整句子可以念
    int lastDelimiter = -1;
    for (int i = text.length - 1; i >= 0; i--) {
      if (sentenceDelimiter.contains(text[i])) {
        lastDelimiter = i;
        break;
      }
    }

    if (lastDelimiter >= 0 && lastDelimiter + 1 >= minChunkLength) {
      // 有完整句子，且夠長 — 念出來
      final toSpeak = text.substring(0, lastDelimiter + 1);
      _buffer.clear();
      _buffer.write(text.substring(lastDelimiter + 1));
      _speakChunk(toSpeak);
    } else if (text.length >= maxChunkLength) {
      // 太長了，強制念
      _buffer.clear();
      _speakChunk(text);
    }
    // 否則繼續累積
  }

  /// 確保 buffer 中剩餘的文字也被念出來
  void flush() {
    if (_stopped) return;

    final remaining = _buffer.toString().trim();
    if (remaining.isNotEmpty) {
      _buffer.clear();
      _speakChunk(remaining);
    }
  }

  /// 念一個片段
  void _speakChunk(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    debugPrint('[StreamingTts] 念: $trimmed');
    _queue.add(trimmed);

    if (!_isSpeaking) {
      _processQueue();
    }
  }

  /// 處理播放佇列
  void _processQueue() {
    if (_queue.isEmpty || _stopped) {
      _isSpeaking = false;
      return;
    }

    _isSpeaking = true;
    final next = _queue.removeAt(0);
    onSpeak(next);

    // flutter_tts 的 speak 是非同步的，這裡不等它完成
    // 實際整合時可以用 TTS 的 completion handler 來驅動下一個
    // 現在先用延遲模擬
    Future.delayed(Duration(milliseconds: _estimateSpeechDuration(next)), () {
      if (!_stopped) {
        _processQueue();
      }
    });
  }

  /// 估算語音播放時間（毫秒）
  ///
  /// 中文大約每字 200ms，英文每字 150ms
  int _estimateSpeechDuration(String text) {
    int chineseCount = 0;
    int otherCount = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF) {
        chineseCount++;
      } else {
        otherCount++;
      }
    }
    return chineseCount * 200 + otherCount * 80 + 200; // 加 200ms 緩衝
  }

  /// 停止播放並清空佇列
  Future<void> stop() async {
    _stopped = true;
    _queue.clear();
    _buffer.clear();
    _isSpeaking = false;
    await onStop();
  }

  /// 重置（用於下一次對話）
  void reset() {
    _stopped = false;
    _queue.clear();
    _buffer.clear();
    _isSpeaking = false;
  }

  /// 是否還有文字在佇列中
  bool get hasPending => _queue.isNotEmpty || _buffer.isNotEmpty;
}
