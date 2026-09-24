// flutter_self_capture_executor.dart
// App 自拍功能 — 用 Flutter RepaintBoundary 截取 App 自己的畫面
// 不需要系統螢幕錄製權限，不受前景/背景影響
// 截圖存到 ring buffer 目錄，自動清理舊的
//
// 2026-07-18 使用者 提議：App 自己自拍，不靠系統截圖
// 原因：使用者在使用時電腦會做其他事，系統截圖會截到背景 App

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'screen_capture_tool.dart';

/// App 自拍 executor — 用 RepaintBoundary 截取 App 自己的畫面
///
/// 使用方式：
/// 1. 在畫面的最外層用 RepaintBoundary + GlobalKey 包裝
/// 2. 把 GlobalKey 傳給此 executor
/// 3. capture() 時用 boundary.toImage() 截圖 → 存 PNG
class FlutterSelfCaptureExecutor implements ScreenCaptureExecutor {
  final GlobalKey _boundaryKey;
  final int _maxScreenshots;

  /// [_boundaryKey] — 包裹畫面的 RepaintBoundary 的 GlobalKey
  /// [_maxScreenshots] — ring buffer 上限，超過自動刪最舊的（預設 20）
  FlutterSelfCaptureExecutor({
    required GlobalKey boundaryKey,
    int maxScreenshots = 20,
  })  : _boundaryKey = boundaryKey,
        _maxScreenshots = maxScreenshots;

  @override
  Future<ScreenCaptureResult> capture({
    String? windowTitle,
    String? appId,
  }) async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;

    if (boundary == null || !boundary.attached) {
      throw UnsupportedError('截圖失敗：RepaintBoundary 未掛載或找不到');
    }

    // 截圖 — pixelRatio 2.0 兼顧品質與速度
    final image = await boundary.toImage(pixelRatio: 2.0);

    // 轉 PNG bytes
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw UnsupportedError('截圖失敗：PNG 編碼失敗');
    }

    final pngBytes = byteData.buffer.asUint8List();

    // 存檔 — 到 Application Support/Bridge/screenshots/
    final appSupportDir = await getApplicationSupportDirectory();
    final screenshotsDir = Directory('${appSupportDir.path}/Bridge/screenshots');
    if (!screenshotsDir.existsSync()) {
      screenshotsDir.createSync(recursive: true);
    }

    // ring buffer 清理 — 刪除超過上限的舊截圖
    await _cleanupOldScreenshots(screenshotsDir);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${screenshotsDir.path}/screenshot_$timestamp.png';
    final file = File(filePath);
    await file.writeAsBytes(pngBytes);

    debugPrint('[自拍] 截圖完成：$filePath (${pngBytes.length} bytes)');

    return ScreenCaptureResult(
      screenshotPath: filePath,
      windowTitle: 'Bridge Desktop',
      appBundleId: 'farm.semiwasabi.bridgeApp',
    );
  }

  /// ring buffer 清理 — 只保留最近 [_maxScreenshots] 張截圖
  Future<void> _cleanupOldScreenshots(Directory dir) async {
    try {
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();

      if (files.length >= _maxScreenshots) {
        // 按修改時間排序，刪最舊的
        files.sort((a, b) =>
            a.statSync().modified.compareTo(b.statSync().modified));
        final toDelete = files.length - _maxScreenshots + 1;
        for (var i = 0; i < toDelete; i++) {
          await files[i].delete();
          debugPrint('[自拍] 清理舊截圖：${files[i].path}');
        }
      }
    } catch (e) {
      debugPrint('[自拍] 清理舊截圖失敗（不影響截圖）: $e');
    }
  }
}
