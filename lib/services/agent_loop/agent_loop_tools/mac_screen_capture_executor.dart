// mac_screen_capture_executor.dart
// B4-2: macOS 原生螢幕截圖 executor — 接 MethodChannel
// Phase 1.5 Open Canvas 螢幕感知
//
// 透過 bridge.screen_capture.macos.v1 MethodChannel 呼叫原生 Swift 層
// 原生層用 CGWindowListCreateImage 截取指定視窗

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'screen_capture_tool.dart';

/// macOS 原生螢幕截圖 executor。
///
/// 透過 MethodChannel 呼叫原生 Swift ScreenCaptureNative。
/// 只在 macOS 上有效；其他平台回傳 UnsupportedError。
class MacScreenCaptureExecutor implements ScreenCaptureExecutor {
  static const _channel = MethodChannel('bridge.screen_capture.macos.v1');

  @override
  Future<ScreenCaptureResult> capture({
    String? windowTitle,
    String? appId,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('screen_capture 只支援 macOS');
    }

    try {
      final result = await _channel.invokeMethod<Map>('captureWindow', {
        if (windowTitle != null && windowTitle.isNotEmpty)
          'windowTitle': windowTitle,
        if (appId != null && appId.isNotEmpty) 'appId': appId,
      });

      if (result == null) {
        throw PlatformException(
          code: 'null_result',
          message: '原生層回傳 null',
        );
      }

      return ScreenCaptureResult(
        screenshotPath: result['screenshotPath'] as String? ?? '',
        windowTitle: result['windowTitle'] as String? ?? '',
        appBundleId: result['appBundleId'] as String? ?? '',
      );
    } on PlatformException catch (e) {
      // 螢幕錄製權限被拒
      if (e.code == 'capture_failed') {
        throw UnsupportedError(
          '螢幕錄製權限未授權。請到「系統設定 → 隱私與安全 → 螢幕錄製」允許 Bridge App。',
        );
      }
      rethrow;
    }
  }

  /// 列出所有可見視窗（供 UI 選擇目標）。
  static Future<List<Map<String, dynamic>>> listWindows() async {
    if (!Platform.isMacOS) return [];

    try {
      final result = await _channel.invokeMethod<List>('listWindows');
      if (result == null) return [];

      return result
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('[MacScreenCaptureExecutor] listWindows 失敗: $e');
      return [];
    }
  }
}
