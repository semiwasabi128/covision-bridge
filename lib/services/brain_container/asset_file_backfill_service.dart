// asset_file_backfill_service.dart
// [小葵 2026-08-28] Blue「不擠牙膏」二期——落網文字檔內容補嵌
//
// 發現：embed_source='metadata' 的 2,103 筆中，約 1,000+ 筆是
// 真文字檔（.sol/.js/.json/.dart/.yml/.sh/.conf/.spec/.adoc/.rtf），
// 檔案在磁碟上、可讀，但 content_text 空——當初嵌入時被跳過。
// 這些是「擠牙膏」的漏網，本服務把內容讀進來補嵌。
//
// - 冪等：embed_source != 'content' 才處理
// - 誠實：讀不到/損壞 → 標 'unreadable'，維持 metadata 嵌入（不硬嵌）
// - 斷點續跑：批 20 commit + 讓出 isolate（檔案 IO 比 embed 慢）
// - 模型 fallback 停損
// - 進度寫 brain_meta（file_backfill_progress）

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'brain_database.dart';
import 'embedding/embedding_service.dart';

class AssetFileBackfillService {
  AssetFileBackfillService._();
  static final AssetFileBackfillService instance =
      AssetFileBackfillService._();

  /// 可救的文字副檔名（embed 時讀得到內容的）
  static const _textExts = [
    '.sol', '.js', '.json', '.dart', '.yml', '.yaml', '.sh', '.conf',
    '.spec', '.adoc', '.rtf', '.txt', '.md', '.csv', '.html', '.css',
    '.py', '.ts', '.swift', '.go', '.rs', '.toml', '.xml',
  ];

  bool _running = false;
  int _backfilled = 0;

  bool get isRunning => _running;
  int get backfilledCount => _backfilled;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run(BrainDatabase.instance.db);
    } catch (e, st) {
      debugPrint('[FileBackfill] ❌ $e\n$st');
      _mark('error:$e');
    } finally {
      _running = false;
    }
  }

  Future<void> _run(Database db) async {
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      _mark('model_unavailable');
      return;
    }

    final extList = _textExts.map((e) => "'$e'").join(',');
    final total = db.select('''
      SELECT COUNT(*) AS n FROM asset_index
      WHERE COALESCE(embed_source,'') != 'content'
        AND LOWER(COALESCE(file_ext,'')) IN ($extList)
    ''').first['n'] as int;

    if (total == 0) {
      debugPrint('[FileBackfill] ✅ 無待補（冪等跳過）');
      _mark('idle');
      return;
    }
    debugPrint('[FileBackfill] 開始：$total 筆文字檔待補內容');

    final sw = Stopwatch()..start();
    var done = 0;
    const batchSize = 20;

    while (true) {
      final rows = db.select('''
        SELECT id, file_path, folder_root, file_name, display_title
        FROM asset_index
        WHERE COALESCE(embed_source,'') != 'content'
          AND LOWER(COALESCE(file_ext,'')) IN ($extList)
        LIMIT ?
      ''', [batchSize]);
      if (rows.isEmpty) break;

      if (done == 40) {
        final rate = done / sw.elapsedMilliseconds * 1000;
        debugPrint('[FileBackfill] 📊 ${rate.toStringAsFixed(1)} 筆/秒，'
            '剩 ${total - done}');
      }

      // 逐檔讀取（IO），湊一批文字
      final batch = <Map<String, dynamic>>[];
      for (final r in rows) {
        final fullPath = '${r['folder_root']}/${r['file_path']}';
        final f = File(fullPath);
        if (!f.existsSync()) {
          _markUnreadable(db, r['id'] as String);
          continue;
        }
        try {
          var text = await f.readAsString();
          // 二進位污染防護：控制字元太多 = 不是文字
          final controls =
              text.codeUnits.where((c) => c < 9 || (c > 13 && c < 32)).length;
          if (text.isEmpty || controls > text.length * 0.05) {
            _markUnreadable(db, r['id'] as String);
            continue;
          }
          if (text.length > 2000) text = text.substring(0, 2000);
          batch.add({'id': r['id'], 'text': text});
        } catch (_) {
          _markUnreadable(db, r['id'] as String);
        }
      }

      if (batch.isNotEmpty) {
        final results =
            await embedder.embedBatch(batch.map((b) => b['text'] as String).toList());
        if (results.any((r) => r.modelVersion == 'mock-fallback')) {
          debugPrint('[FileBackfill] ⛔ fallback 停損');
          _mark('fallback_stop');
          return;
        }
        db.execute('BEGIN');
        try {
          for (var i = 0; i < batch.length; i++) {
            db.execute(
              "UPDATE asset_index SET embedding = ?, content_text = ?, "
              "embed_source = 'content' WHERE id = ?",
              [
                _vecToBlob(results[i].vector),
                batch[i]['text'],
                batch[i]['id'],
              ],
            );
          }
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
        _backfilled += batch.length;
      }

      done += rows.length;
      _markProgress(done, total);
      if (done % 200 == 0) {
        debugPrint('[FileBackfill] 進度 $done/$total');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    sw.stop();
    _mark('done');
    debugPrint('[FileBackfill] ✅ 完成：補 $_backfilled 筆，'
        '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒');
  }

  void _markUnreadable(Database db, String id) {
    // 標記內容不可讀——維持 metadata 嵌入（有標題/路徑語意），不硬嵌
    db.execute(
      "UPDATE asset_index SET embed_source = 'unreadable' WHERE id = ? AND COALESCE(embed_source,'') NOT IN ('content', 'identity')",
      [id],
    );
  }

  void _mark(String status) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) "
        "VALUES ('file_backfill_status', ?)",
        [status],
      );
    } catch (_) {}
  }

  void _markProgress(int done, int total) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) "
        "VALUES ('file_backfill_progress', '$done/$total')",
      );
    } catch (_) {}
  }

  static Uint8List _vecToBlob(List<double> vec) {
    final bytes = ByteData(vec.length * 4);
    for (var i = 0; i < vec.length; i++) {
      bytes.setFloat32(i * 4, vec[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
