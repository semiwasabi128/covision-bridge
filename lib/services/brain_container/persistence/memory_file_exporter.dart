// memory_file_exporter.dart
// [教練 Agent 2026-08-21] 記憶落檔——「檔案系統是唯一真相」兌現。
//
// memories 過去只活 SQLite：DB 損毀＝記憶蒸發，使用者無法用 Finder
// 「看見」自己的記憶、無法備份、無法版本控管。此 exporter 把每筆
// 記憶同步落成 markdown 檔（人類可讀、frontmatter 帶 metadata），
// DB 續任快取索引（向量檢索/圖譜/rooms 統計用）。
//
// 落點：~/Documents/bridge_media/memories/<room>/<memoryId>.md
// （與媒體庫同根——autoIngest 的 watch 已覆蓋該目錄樹，落檔記憶
// 自動進 asset_index，等於順手打通「記憶 → 資產檢索」迴路。）
//
// 設計原則（同 MediaIngestHook）：
// - fire-and-forget：絕不阻塞記憶寫入主流程
// - 失敗只 debugPrint：寫檔失敗不影響 DB 事實
// - 冪等：檔名 = memoryId.md，重寫 = 更新（記憶不可變，實務上同 ID
//   不會重寫，但 UPDATE 路徑若出現也安全覆蓋）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/brain_container/memory.dart';

class MemoryFileExporter {
  MemoryFileExporter._();

  static bool _busy = false;

  /// 寫入路徑（公開給回填服務用）：<Documents>/bridge_media/memories/
  static Future<Directory> memoriesRootForCheck() => _memoriesRoot();

  static Future<Directory> _memoriesRoot() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/bridge_media/memories');
  }

  /// fire-and-forget 入口——writeMany COMMIT 後呼叫。
  /// 同步 await 版（回填服務分批用）
  static Future<void> exportNow(List<Memory> memories) async {
    final root = await _memoriesRoot();
    var written = 0;
    for (final m in memories) {
      try {
        final roomDir = Directory('${root.path}/${_safe(m.room.name)}');
        await roomDir.create(recursive: true);
        await File('${roomDir.path}/${m.id}.md')
            .writeAsString(_render(m), flush: true);
        written++;
      } catch (e) {
        debugPrint('[MemoryFileExporter] 單筆失敗 (${m.id}): $e');
      }
    }
    if (written > 0) {
      debugPrint('[MemoryFileExporter] 落檔 $written 筆 → ${root.path}');
    }
  }

  static void exportFireAndForget(List<Memory> memories) {
    if (memories.isEmpty) return;
    // 同步閉包不可 await（呼叫端是事務後半段）——microtask 排隊
    Future(() => _exportAll(memories)).catchError((e) {
      debugPrint('[MemoryFileExporter] 落檔失敗（不影響 DB）: $e');
    });
  }

  static Future<void> _exportAll(List<Memory> memories) async {
    if (_busy) {
      // 上一批還在寫——重排而非丟失（記憶不可漏）
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _exportAll(memories);
    }
    _busy = true;
    try {
      final root = await _memoriesRoot();
      var written = 0;
      for (final m in memories) {
        try {
          final roomDir = Directory('${root.path}/${_safe(m.room.name)}');
          await roomDir.create(recursive: true);
          final file = File('${roomDir.path}/${m.id}.md');
          await file.writeAsString(_render(m), flush: true);
          written++;
        } catch (e) {
          debugPrint('[MemoryFileExporter] 單筆失敗 (${m.id}): $e');
        }
      }
      if (written > 0) {
        debugPrint('[MemoryFileExporter] 落檔 $written 筆 → ${root.path}');
      }
    } finally {
      _busy = false;
    }
  }

  /// markdown 渲染：frontmatter（機器可讀）＋正文（人類可讀）
  static String _render(Memory m) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('id: ${m.id}');
    buf.writeln('room: ${m.room.name}');
    if (m.subCategory.isNotEmpty) {
      buf.writeln('sub_category: ${m.subCategory}');
    }
    buf.writeln('agent: ${m.agent}');
    if (m.companionId.isNotEmpty) {
      buf.writeln('companion_id: ${m.companionId}');
    }
    buf.writeln('source: ${m.source.dbValue}');
    if (m.sourceId != null && m.sourceId!.isNotEmpty) {
      buf.writeln('source_id: ${m.sourceId}');
    }
    if (m.project.isNotEmpty) {
      buf.writeln('project: ${m.project}');
    }
    if (m.tags.isNotEmpty) {
      buf.writeln('tags: [${m.tags.join(', ')}]');
    }
    buf.writeln('importance: ${m.importance}');
    buf.writeln('created_at: ${m.createdAt.toIso8601String()}');
    if (m.totalChunks > 1) {
      buf.writeln('chunk: ${m.chunkIndex + 1}/${m.totalChunks}');
      if (m.parentMemoryId != null) {
        buf.writeln('parent_memory_id: ${m.parentMemoryId}');
      }
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln(m.content);
    return buf.toString();
  }

  /// 目錄名 sanitize——room 名是 enum，防禦性處理
  static String _safe(String name) {
    return name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
  }
}
