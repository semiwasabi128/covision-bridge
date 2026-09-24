// canvas_tts_service.dart
// 畫布 TTS 節點執行服務 — 用 FlutterTts 合成語音檔
// [教練 Agent 2026-07-22] Phase G — TTS 節點實作
//
// 設計：
// - 使用 flutter_tts（已是依賴，ChatTtsHandler 示範過用法）
// - macOS 支援 synthesizeToFile，合成到暫存目錄
// - 回傳檔案路徑，供下游節點引用

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class CanvasTtsService {
  CanvasTtsService._();
  static final CanvasTtsService instance = CanvasTtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  /// 初始化 TTS 引擎
  Future<void> _init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('zh-TW');
      await _tts.setSpeechRate(0.5);
      _initialized = true;
    } catch (e) {
      debugPrint('[CanvasTtsService] 初始化失敗: $e');
    }
  }

  /// 將文字合成為語音檔，回傳檔案路徑
  ///
  /// [text] 要朗讀的文字
  /// [voice] 語音（可選，目前未使用）
  /// [speed] 語速 0.0-1.0（可選，預設 0.5）
  Future<String?> synthesizeToFile({
    required String text,
    String? voice,
    double? speed,
  }) async {
    await _init();
    if (text.trim().isEmpty) return null;

    // 設定語速
    if (speed != null) {
      await _tts.setSpeechRate(speed.clamp(0.0, 1.0));
    }

    // 產生暫存檔路徑
    final dir = await getTemporaryDirectory();
    final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.aiff';
    final filePath = '${dir.path}/$fileName';

    // 去除 markdown 語法（複用 ChatTtsHandler 的邏輯）
    final cleanText = _stripMarkdown(text);

    // [小橋 2026-09-18] flutter_tts.synthesizeToFile 在 macOS 靜默失敗（result=1 但檔案不落地）
    // 改用 macOS 原生 say 指令合成 AIFF
    try {
      final rate = (speed ?? 0.5).clamp(0.0, 1.0);
      // say 的 -r 是每分鐘字數；flutter_tts 0.5 ≈ 正常速度 ≈ 180 wpm
      final wpm = (120 + rate * 160).round();
      final voiceArg = (voice == null || voice == 'alloy')
          ? <String>[]
          : <String>['-v', voice];
      final p = await Process.run('say', [
        ...voiceArg,
        '-r', '$wpm',
        '-o', filePath,
        cleanText,
      ]);
      if (p.exitCode == 0 && File(filePath).existsSync()) {
        debugPrint('[CanvasTtsService] 語音合成成功(say): $filePath');
        return filePath;
      }
      debugPrint('[CanvasTtsService] say 合成失敗 exit=${p.exitCode} stderr=${p.stderr}');
      return null;
    } catch (e) {
      debugPrint('[CanvasTtsService] 語音合成例外: $e');
      return null;
    }
  }

  /// 試聽：直接朗讀文字（不產檔案），供設定面板預覽語音
  Future<void> speak({required String text, double? speed}) async {
    await _init();
    if (text.trim().isEmpty) return;
    if (speed != null) {
      await _tts.setSpeechRate(speed.clamp(0.0, 1.0));
    }
    try {
      await _tts.speak(_stripMarkdown(text));
    } catch (e) {
      debugPrint('[CanvasTtsService] 試聽失敗: $e');
    }
  }

  /// 停止試聽
  Future<void> stopSpeak() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// 去除 markdown 語法，讓朗讀更自然
  String _stripMarkdown(String text) {
    var result = text;

    // 程式碼區塊
    result = result.replaceAll(RegExp(r'```[\s\S]*?```'), '程式碼');

    // 行內程式碼
    result = result.replaceAll(RegExp(r'`([^`]*)`'), r'$1');

    // 圖片
    result = result.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');

    // 連結
    result = result.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');

    // 粗體+斜體
    result = result.replaceAll(RegExp(r'\*\*\*([^*]*)\*\*\*'), r'$1');

    // 粗體
    result = result.replaceAll(RegExp(r'\*\*([^*]*)\*\*'), r'$1');
    result = result.replaceAll(RegExp(r'__([^_]*)__'), r'$1');

    // 斜體
    result = result.replaceAll(RegExp(r'(?<!\*)\*(?!\*)([^*]*)\*(?!\*)'), r'$1');
    result = result.replaceAll(RegExp(r'(?<!_)_(?!_)([^_]*)_(?!_)'), r'$1');

    // 標題
    result = result.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');

    // 引用
    result = result.replaceAll(RegExp(r'^>\s*', multiLine: true), '');

    // 列表
    result = result.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // 水平分割線
    result = result.replaceAll(RegExp(r'^[\s]*([-*]){3,}[\s]*$', multiLine: true), '');

    return result.trim();
  }
}
