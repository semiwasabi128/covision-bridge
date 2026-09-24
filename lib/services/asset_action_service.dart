// [教練 Agent P0.6a 2026-08-07] Bridge 資產操作服務
//
// 另存、刪除、在 Finder 顯示——統一入口，對話泡泡和未來的 Asset Inspector Window 都呼叫這裡。
// 不擁有資產本身，只對檔案路徑做操作 + 通知呼叫端結果。
//
// 設計原則：
// - 另存 = copy（不動原檔）
// - 刪除 = 刪原檔 + 回報呼叫端讓它更新 conversation/index
// - Finder = macOS open -R

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AssetActionResult {
  final bool success;
  final String message;
  final String? destinationPath;

  const AssetActionResult({
    required this.success,
    required this.message,
    this.destinationPath,
  });
}

class AssetActionService {
  AssetActionService._();
  static final AssetActionService instance = AssetActionService._();

  /// 另存新檔：把 sourcePath 複製到使用者選擇的位置。
  ///
  /// 使用 macOS 原生 save panel（透過 MethodChannel）。
  /// 如果使用者取消，回傳 success=false, message='已取消'。
  Future<AssetActionResult> saveAs(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return const AssetActionResult(
        success: false,
        message: '原始檔案不存在',
      );
    }

    try {
      // 使用 MethodChannel 呼叫 macOS 原生 NSSavePanel
      const platform = MethodChannel('bridge_app/asset_action');
      final result = await platform.invokeMethod<String>('saveAs', {
        'sourcePath': sourcePath,
        'suggestedName': _suggestedName(sourcePath),
      });

      if (result == null) {
        return const AssetActionResult(
          success: false,
          message: '已取消',
        );
      }

      // platform 端已經完成複製，result 是目標路徑
      return AssetActionResult(
        success: true,
        message: '已另存到：$result',
        destinationPath: result,
      );
    } on PlatformException {
      // Fallback：如果 native channel 還沒接，用簡單的 copy 到 Documents
      return _saveAsFallback(sourceFile);
    } on MissingPluginException {
      return _saveAsFallback(sourceFile);
    }
  }

  /// 刪除檔案。
  ///
  /// 只刪檔案本身；conversation metadata 和 vector index 由呼叫端負責更新。
  Future<AssetActionResult> delete(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      return const AssetActionResult(
        success: false,
        message: '檔案不存在（可能已刪除）',
      );
    }

    try {
      await file.delete();
      return AssetActionResult(
        success: true,
        message: '已刪除：${file.uri.pathSegments.last}',
      );
    } catch (e) {
      return AssetActionResult(
        success: false,
        message: '刪除失敗：$e',
      );
    }
  }

  /// 在 macOS Finder 中顯示檔案。
  Future<AssetActionResult> revealInFinder(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      return const AssetActionResult(
        success: false,
        message: '檔案不存在',
      );
    }

    try {
      // macOS: open -R <path> 會在 Finder 中顯示該檔案
      final result = await Process.run('open', ['-R', sourcePath]);
      if (result.exitCode == 0) {
        return const AssetActionResult(
          success: true,
          message: '已在 Finder 中顯示',
        );
      } else {
        return AssetActionResult(
          success: false,
          message: '無法開啟 Finder：${result.stderr}',
        );
      }
    } catch (e) {
      return AssetActionResult(
        success: false,
        message: '開啟 Finder 失敗：$e',
      );
    }
  }

  /// 用 OS 預設應用程式開啟檔案。
  ///
  /// 圖片 → Preview，文件 → Word/Pages，聲音 → Music/QuickTime...
  /// OS 內建預覽本身就有另存、關閉功能，不需要自訂視窗。
  Future<AssetActionResult> openWithDefaultApp(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      return const AssetActionResult(
        success: false,
        message: '檔案不存在',
      );
    }

    try {
      // macOS: open <path> 會用預設應用程式開啟
      final result = await Process.run('open', [sourcePath]);
      if (result.exitCode == 0) {
        return const AssetActionResult(
          success: true,
          message: '已開啟',
        );
      } else {
        return AssetActionResult(
          success: false,
          message: '無法開啟：${result.stderr}',
        );
      }
    } catch (e) {
      return AssetActionResult(
        success: false,
        message: '開啟失敗：$e',
      );
    }
  }

  String _suggestedName(String path) {
    final segments = Uri.file(path).pathSegments;
    return segments.isEmpty ? 'asset' : segments.last;
  }

  /// Fallback：如果 native save panel 還沒接，
  /// 複製到 Documents 目錄下的 bridge_exports/。
  Future<AssetActionResult> _saveAsFallback(File sourceFile) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${docs.path}/bridge_exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final fileName = _suggestedName(sourceFile.path);
      final destPath = '${exportDir.path}/$fileName';
      await sourceFile.copy(destPath);
      return AssetActionResult(
        success: true,
        message: '已另存到：$destPath',
        destinationPath: destPath,
      );
    } catch (e) {
      return AssetActionResult(
        success: false,
        message: '另存失敗：$e',
      );
    }
  }
}
