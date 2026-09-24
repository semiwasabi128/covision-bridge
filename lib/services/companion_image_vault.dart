// [Blue 2026-09-17] 夥伴圖像保管庫（Companion Image Vault）
//
// 問題：主形象/狀態圖存在 ~/Documents/bridge_media（使用者可見可刪），
// 使用者誤刪 → App 顯示全部消失。
//
// 方案：存檔（_confirmCandidate）時把圖複製進 App 容器內的保管庫：
//   ~/Library/Containers/farm.semiwasabi.bridgeApp/Data/
//     Library/Application Support/farm.semiwasabi.bridgeApp/
//     companion_vault/<companionId>/avatar.png、state_<id>.png
// 使用者碰不到（macOS Sandbox 容器），不怕誤刪。
//
// 設計原則：
// - 保管庫是「鎖定副本」：bridge_media 原檔仍在（生成管線繼續用它），
//   存檔時複製進 vault 並把 Companion 的路徑指向 vault 副本
// - 冪等：同一張圖重複存檔覆寫同名檔，不會堆積
// - 失敗安全：複製失敗時保留原路徑（退回舊行為），絕不因 vault 失敗
//   讓使用者存不了檔

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CompanionImageVault {
  CompanionImageVault._();

  static const _vaultDirName = 'companion_vault';

  static Directory? _cacheVaultRoot;

  /// 保管庫根目錄（App 容器內，使用者不可見）
  static Future<Directory> _vaultRoot() async {
    if (_cacheVaultRoot != null) return _cacheVaultRoot!;
    final appSupport = await getApplicationSupportDirectory();
    final root = Directory('${appSupport.path}/$_vaultDirName');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _cacheVaultRoot = root;
    return root;
  }

  /// 把一張圖收進保管庫，回傳 vault 內新路徑。
  /// 來源不存在 / 複製失敗 → 回傳 null（呼叫端保留原路徑）。
  static Future<String?> _vaultCopy(
    String companionId,
    String fileName,
    String? sourcePath,
  ) async {
    final src = sourcePath?.trim() ?? '';
    if (src.isEmpty || src.startsWith('data:')) return null;
    final file = File(src);
    if (!await file.exists()) return null;
    try {
      final root = await _vaultRoot();
      final dir = Directory('${root.path}/$companionId');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final dest = File('${dir.path}/$fileName');
      await file.copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint('[CompanionImageVault] 複製失敗 $src: $e');
      return null;
    }
  }

  /// 存檔時呼叫：把 companion 的主形象 + 全部狀態圖收進保管庫。
  /// 回傳（avatarPath, statePaths）——已指向 vault 副本；失敗的項目
  /// 保留原路徑。
  static Future<CompanionVaultResult> lockIn({
    required String companionId,
    required String? avatarImagePath,
    required Map<String, String> stateImagePaths,
  }) async {
    // 主形象
    final newAvatar = await _vaultCopy(
      companionId,
      'avatar.${_extOf(avatarImagePath) ?? 'png'}',
      avatarImagePath,
    );

    // 狀態圖
    final newStates = <String, String>{};
    for (final entry in stateImagePaths.entries) {
      if (entry.value.trim().isEmpty) continue;
      final copied = await _vaultCopy(
        companionId,
        'state_${entry.key}.${_extOf(entry.value) ?? 'png'}',
        entry.value,
      );
      newStates[entry.key] = copied ?? entry.value;
    }

    return CompanionVaultResult(
      avatarImagePath:
          newAvatar ?? (avatarImagePath?.trim().isNotEmpty == true
              ? avatarImagePath
              : null),
      stateImagePaths: newStates,
    );
  }

  static String? _extOf(String? path) {
    final p = path?.trim() ?? '';
    if (!p.contains('.')) return null;
    final ext = p.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
        return ext;
      default:
        return null;
    }
  }
}

class CompanionVaultResult {
  const CompanionVaultResult({
    required this.avatarImagePath,
    required this.stateImagePaths,
  });

  final String? avatarImagePath;
  final Map<String, String> stateImagePaths;
}
