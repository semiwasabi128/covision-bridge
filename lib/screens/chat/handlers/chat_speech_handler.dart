// [教練 Agent Sprint 17 Step 1 2026-07-07]
// ChatSpeechHandler — 語音輸入邏輯，從 chat_screen.dart _ChatScreenState 拆出。
// 持有 SpeechToText + 輸入框 TextEditingController，管理語音聽寫的文字插入。
//
// 設計：
// - listening / initializing 透過 ValueNotifier 暴露，UI 訂閱即可
// - 文字插入邏輯（游標位置、續接前綴、重複偵測）全在 handler 裡
// - 錯誤提示透過 onError 回調讓 Screen 決定怎麼顯示

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ChatSpeechHandler {
  ChatSpeechHandler({
    required this.messageController,
    required this.onError,
    required this.onStateChanged,
  });

  final TextEditingController messageController;
  final void Function(String message) onError;
  final VoidCallback onStateChanged;

  final stt.SpeechToText _speechToText = stt.SpeechToText();

  final ValueNotifier<bool> listening = ValueNotifier<bool>(false);
  final ValueNotifier<bool> initializing = ValueNotifier<bool>(false);

  bool _available = false;

  // --- insertion state ---
  int? _replaceStart;
  int? _replaceEnd;
  String? _continuationPrefix;
  String _lastRecognizedWords = '';
  bool _applyingResult = false;

  // ─── Public API ───

  Future<void> toggle() async {
    if (listening.value) {
      await stop();
      return;
    }
    await start();
  }

  Future<void> start() async {
    if (initializing.value) return;
    initializing.value = true;
    onStateChanged();

    try {
      if (!_available) {
        _available = await _speechToText.initialize(
          debugLogging: kDebugMode,
          onError: _handleError,
          onStatus: _handleStatus,
        );
      }

      if (!_available) {
        onError('無法啟用語音輸入，請確認麥克風與語音辨識權限。');
        return;
      }

      _resetInsertionToCurrentSelection();
      _continuationPrefix = null;
      _lastRecognizedWords = '';
      listening.value = true;
      onStateChanged();

      await _speechToText.listen(
        onResult: _handleResult,
        listenOptions: stt.SpeechListenOptions(
          localeId: 'zh_TW',
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (error) {
      onError('語音輸入啟動失敗：$error');
    } finally {
      initializing.value = false;
      onStateChanged();
    }
  }

  Future<void> stop() async {
    await _speechToText.stop();
    listening.value = false;
    _clearInsertionState();
    onStateChanged();
  }

  /// 使用者手動編輯輸入框時呼叫
  void handleFieldChanged() {
    if (listening.value && !_applyingResult) {
      _markContinuationAfterManualEdit();
      _resetInsertionToCurrentSelection();
    }
  }

  /// 使用者點擊輸入框時呼叫
  void handleFieldTapped() {
    if (!listening.value) return;
    _markContinuationAfterManualEdit();
    _resetInsertionToCurrentSelection();
  }

  /// 清除草稿（含取消語音）
  Future<void> clearDraft() async {
    if (listening.value) {
      await _speechToText.cancel();
    }
    listening.value = false;
    _clearInsertionState();
    messageController.clear();
  }

  void dispose() {
    listening.dispose();
    initializing.dispose();
  }

  // ─── Internal ───

  void _handleResult(SpeechRecognitionResult result) {
    final recognizedWords = result.recognizedWords.trim();
    final words = _freshWords(recognizedWords);
    _lastRecognizedWords = recognizedWords;
    if (words.isEmpty) return;

    final currentText = messageController.text;
    final textLength = currentText.length;
    final range = _replacementRange(textLength);
    final nextText = currentText.replaceRange(range.start, range.end, words);
    final nextOffset = range.start + words.length;
    _replaceStart = range.start;
    _replaceEnd = nextOffset;
    _applyingResult = true;
    messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _applyingResult = false;
    onStateChanged();
  }

  void _handleStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      listening.value = false;
      _clearInsertionState();
      onStateChanged();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    listening.value = false;
    _clearInsertionState();
    onStateChanged();
    onError('語音輸入中斷：${error.errorMsg}');
  }

  // ─── Insertion helpers ───

  ({int start, int end}) _replacementRange(int textLength) {
    final start = _replaceStart;
    final end = _replaceEnd;
    if (start != null && end != null) {
      final normalizedStart = _clamp(start, textLength);
      final normalizedEnd = _clamp(end, textLength);
      return (
        start: math.min(normalizedStart, normalizedEnd),
        end: math.max(normalizedStart, normalizedEnd),
      );
    }

    final selection = messageController.selection;
    if (!selection.isValid) {
      return (start: textLength, end: textLength);
    }
    final normalizedStart = _clamp(selection.start, textLength);
    final normalizedEnd = _clamp(selection.end, textLength);
    return (
      start: math.min(normalizedStart, normalizedEnd),
      end: math.max(normalizedStart, normalizedEnd),
    );
  }

  int _clamp(int index, int textLength) {
    return index.clamp(0, textLength).toInt();
  }

  void _resetInsertionToCurrentSelection() {
    final textLength = messageController.text.length;
    final range = _selectionRange(textLength);
    _replaceStart = range.start;
    _replaceEnd = range.end;
  }

  ({int start, int end}) _selectionRange(int textLength) {
    final selection = messageController.selection;
    if (!selection.isValid) {
      return (start: textLength, end: textLength);
    }
    final normalizedStart = _clamp(selection.start, textLength);
    final normalizedEnd = _clamp(selection.end, textLength);
    return (
      start: math.min(normalizedStart, normalizedEnd),
      end: math.max(normalizedStart, normalizedEnd),
    );
  }

  void _clearInsertionState() {
    _replaceStart = null;
    _replaceEnd = null;
    _continuationPrefix = null;
    _lastRecognizedWords = '';
    _applyingResult = false;
  }

  String _freshWords(String recognizedWords) {
    final words = recognizedWords.trim();
    if (words.isEmpty) return '';
    final prefix = _continuationPrefix?.trim();
    if (prefix == null || prefix.isEmpty) return words;
    if (words == prefix || prefix.startsWith(words)) return '';
    if (words.startsWith(prefix)) {
      return words.substring(prefix.length).trimLeft();
    }
    final overlap = _commonPrefixLength(words, prefix);
    if (overlap >= math.min(words.length, prefix.length) * 0.82) {
      return words.substring(overlap).trimLeft();
    }
    return words;
  }

  int _commonPrefixLength(String value, String prefix) {
    final maxLength = math.min(value.length, prefix.length);
    var index = 0;
    while (index < maxLength &&
        value.codeUnitAt(index) == prefix.codeUnitAt(index)) {
      index += 1;
    }
    return index;
  }

  void _markContinuationAfterManualEdit() {
    final lastWords = _lastRecognizedWords.trim();
    if (lastWords.isEmpty) return;
    _continuationPrefix = lastWords;
  }
}
