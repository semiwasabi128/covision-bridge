// ChatTtsHandler — 語音輸出邏輯，對稱於 ChatSpeechHandler 的語音輸入。
// 持有 FlutterTts，管理 AI 回覆的朗讀。
//
// 設計：
// - speaking 透過 ValueNotifier 暴露，UI 訂閱即可
// - 朗讀前自動去除 markdown 語法，避免朗讀出 **、#、` 等符號
// - 錯誤提示透過 onError 回調讓 Screen 決定怎麼顯示

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ChatTtsHandler {
  ChatTtsHandler({
    required this.onError,
  });

  final void Function(String message) onError;

  final FlutterTts _tts = FlutterTts();

  /// 是否正在朗讀，UI 訂閱即可。
  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  bool _initialized = false;

  // ─── Public API ───

  /// 初始化 TTS 引擎（設定語言為 zh-TW）。
  /// 只會執行一次；重複呼叫安全。
  Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('zh-TW');
      await _tts.setSpeechRate(0.5);
      _tts.setCompletionHandler(() {
        speaking.value = false;
      });
      _tts.setErrorHandler((error) {
        speaking.value = false;
        onError('語音朗讀失敗：$error');
      });
      _initialized = true;
    } catch (error) {
      onError('語音朗讀初始化失敗：$error');
    }
  }

  /// 朗讀文字。如果正在朗讀則先停止再開始。
  Future<void> speak(String text) async {
    if (!_initialized) {
      await init();
    }
    if (speaking.value) {
      await stop();
    }
    final cleanText = _stripMarkdown(text);
    if (cleanText.trim().isEmpty) return;
    speaking.value = true;
    try {
      await _tts.speak(cleanText);
    } catch (error) {
      speaking.value = false;
      onError('語音朗讀失敗：$error');
    }
  }

  /// 停止朗讀。
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // 忽略停止時的錯誤
    }
    speaking.value = false;
  }

  /// 清理資源。
  Future<void> dispose() async {
    await stop();
    speaking.dispose();
  }

  // ─── Internal ───

  /// 去除 markdown 語法，讓朗讀更自然。
  /// 處理 **粗體**、# 標題、`行內程式碼`、```程式碼區塊```、[連結文字](url)、
  /// ![圖片](url)、> 引用、- 列表、* 列表、1. 有序列表 等。
  String _stripMarkdown(String text) {
    var result = text;

    // 程式碼區塊 ```...```
    result = result.replaceAll(RegExp(r'```[\s\S]*?```'), '程式碼');

    // 行內程式碼 `...`
    result = result.replaceAll(RegExp(r'`([^`]*)`'), r'$1');

    // 圖片 ![alt](url)
    result = result.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');

    // 連結 [text](url)
    result = result.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');

    // 粗體+斜體 ***...***
    result = result.replaceAll(RegExp(r'\*\*\*([^*]*)\*\*\*'), r'$1');

    // 粗體 **...**
    result = result.replaceAll(RegExp(r'\*\*([^*]*)\*\*'), r'$1');

    // 粗體 __...__
    result = result.replaceAll(RegExp(r'__([^_]*)__'), r'$1');

    // 斜體 *...*
    result = result.replaceAll(RegExp(r'(?<!\*)\*(?!\*)([^*]*)\*(?!\*)'), r'$1');

    // 斜體 _..._
    result = result.replaceAll(RegExp(r'(?<!_)_(?!_)([^_]*)_(?!_)'), r'$1');

    // 刪除線 ~~...~~
    result = result.replaceAll(RegExp(r'~~([^~]*)~~'), r'$1');

    // 標題 # ## ###
    result = result.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');

    // 引用 >
    result = result.replaceAll(RegExp(r'^>\s*', multiLine: true), '');

    // 無序列表 - * +
    result = result.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');

    // 有序列表 1. 2.
    result = result.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // 水平分割線 --- ***
    result = result.replaceAll(RegExp(r'^[\s]*([-*]){3,}[\s]*$', multiLine: true), '');

    return result.trim();
  }
}
