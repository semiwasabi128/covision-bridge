// lib/services/api_audit_log.dart
//
// [小葵 2026-09-14] API 調用審計日誌——數位主權基礎建設
//
// 緣起：2026-09-13 OpenAI 帳單 $3 事件。Bridge App 直連各 provider，
// 但本地不留任何調用紀錄，稽查只能靠 provider 後台。此服務讓每次
// 對外 API 調用都在本地留下痕跡：
//   - 誰（provider/model）
//   - 什麼時候（timestamp）
//   - 做什麼（action type / query 摘要）
//   - 結果（成功/失敗/原因）
//   - 錢（tokens/費用估算，若 metadata 提供）
//
// 設計原則：
//   1. 絕不影響主流程——audit 寫入失敗靜默吞掉，不能因記帳害死生圖
//   2. JSON Lines 格式（一行一筆），好 grep 好輪替
//   3. 自動輪替：超過 5MB 換新檔，保留 3 份歷史
//   4. 不記 prompt 全文（隱私+體積），只記前 120 字摘要

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ApiAuditLog {
  ApiAuditLog._();

  static File? _logFile;
  static const _maxBytes = 5 * 1024 * 1024; // 5MB
  static const _keepRotated = 3;

  static File _resolveFile() {
    if (_logFile != null) return _logFile!;
    _logFile = File('${_appSupportDir()}/api_audit_log.jsonl');
    return _logFile!;
  }

  static String _appSupportDir() {
    // 與 StorageService golden_keys.json 同層（Application Support/bridge_app）
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/Library/Application Support/bridge_app';
  }

  /// 記錄一次 API 調用。任何失敗都靜默（記帳不能害死主流程）。
  static Future<void> record({
    required String provider,
    required String actionType,
    String? model,
    String? quality,
    String? promptSummary,
    required bool success,
    String? failReason,
    int? durationMs,
    Map<String, dynamic>? usage,
  }) async {
    try {
      final file = _resolveFile();
      await file.parent.create(recursive: true);

      final entry = <String, dynamic>{
        'ts': DateTime.now().toIso8601String(),
        'provider': provider,
        'action': actionType,
        if (model != null) 'model': model,
        if (quality != null) 'quality': quality,
        if (promptSummary != null)
          'prompt':
              promptSummary.length > 120
                  ? '${promptSummary.substring(0, 120)}…'
                  : promptSummary,
        'ok': success,
        if (failReason != null && failReason.isNotEmpty) 'fail': failReason,
        if (durationMs != null) 'ms': durationMs,
        if (usage != null) 'usage': usage,
      };

      await _rotateIfNeeded(file);
      await file.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('[ApiAuditLog] 寫入失敗（靜默）: $e');
    }
  }

  /// 給 executor 用：從 BridgeActionResult 萃取 usage 資訊。
  static Map<String, dynamic>? usageFromMetadata(
    Map<String, dynamic>? metadata,
  ) {
    if (metadata == null) return null;
    final usage = <String, dynamic>{};
    for (final key in [
      'input_tokens',
      'output_tokens',
      'total_tokens',
      'usage',
      'tokens',
    ]) {
      final v = metadata[key];
      if (v != null) usage[key] = v;
    }
    return usage.isEmpty ? null : usage;
  }

  static Future<void> _rotateIfNeeded(File file) async {
    try {
      if (!await file.exists()) return;
      final size = await file.length();
      if (size < _maxBytes) return;
      // api_audit_log.jsonl → api_audit_log.jsonl.1 → .2 → .3（丟掉最舊）
      for (var i = _keepRotated - 1; i >= 1; i--) {
        final from = File('${file.path}.$i');
        if (await from.exists()) {
          await from.rename('${file.path}.${i + 1}');
        }
      }
      await file.rename('${file.path}.1');
    } catch (_) {
      // 輪替失敗就繼續寫原檔，不擋主流程
    }
  }
}
