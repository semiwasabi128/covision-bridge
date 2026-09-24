// memory_file_backfill_service.dart
// [教練 Agent 2026-08-21] 記憶落檔存量回填——把 DB 既有 memories 一次性
// 落成 md（冪等：檔案已存在即跳過）。新記憶由 MemoryFileExporter
// 即時落檔；這裡只負責歷史存量（或未來任何缺口）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../models/brain_container/memory.dart';
import '../brain_container_service.dart';
import '../brain_database.dart';
import 'memory_file_exporter.dart';

class MemoryFileBackfillService {
  MemoryFileBackfillService._();
  static final MemoryFileBackfillService instance =
      MemoryFileBackfillService._();

  bool _running = false;

  /// 啟動回填（冪等，fire-and-forget）
  void start() {
    if (_running) return;
    _running = true;
    Future(() => _backfill()).catchError((e) {
      debugPrint('[MemoryFileBackfill] 失敗: $e');
    });
  }

  Future<void> _backfill() async {
    try {
      if (!BrainContainerService.instance.isInitialized) return;
      final db = BrainDatabase.instance.db;

      final rows = db.select('SELECT * FROM memories ORDER BY created_at');
      final all = <Memory>[];
      for (final row in rows) {
        try {
          all.add(Memory.fromMap(row));
        } catch (_) {}
      }

      // 檔案存在性批次檢查
      final root = await MemoryFileExporter.memoriesRootForCheck();
      final existing = <String>{};
      if (root.existsSync()) {
        await for (final roomDirEntity in root.list(followLinks: false)) {
          if (roomDirEntity is! Directory) continue;
          final roomDir = roomDirEntity;
          await for (final fEntity in roomDir.list()) {
            if (fEntity is! File) continue;
            final f = fEntity;
            final base = f.path.split('/').last;
            if (base.endsWith('.md')) {
              existing.add(base.substring(0, base.length - 3));
            }
          }
        }
      }
      final missing = all.where((m) => !existing.contains(m.id)).toList();
      if (missing.isEmpty) {
        debugPrint('[MemoryFileBackfill] 無缺口，跳過');
        return;
      }
      debugPrint('[MemoryFileBackfill] 補落檔 ${missing.length} 筆');
      const batch = 50;
      for (var i = 0; i < missing.length; i += batch) {
        final chunk = missing.sublist(
            i, (i + batch > missing.length) ? missing.length : i + batch);
        // 直接同步寫（exportFireAndForget 的 busy 鎖一次只能一批）
        await MemoryFileExporter.exportNow(chunk);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      debugPrint('[MemoryFileBackfill] 存量回填完成');
    } catch (e) {
      debugPrint('[MemoryFileBackfill] 失敗: $e');
    } finally {
      _running = false;
    }
  }
}
