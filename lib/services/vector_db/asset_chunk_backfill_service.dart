// asset_chunk_backfill_service.dart
// [教練 Agent 2026-08-21] 鐵三角第二期 #1——asset_chunks 回填 worker
//
// chunk 表（schema v11 DDL 已存在）從未有 writer——本服務補上：
// - 對象：content_text > 600 字的資產（850 文字檔 + 長描述圖檔），
//   短內容單片即可被找到，不值得切片（DB 也省）
// - 切法：512+64 滑窗（content_preprocessor 同配方），
//   但 600-1200 字只出 1-2 片——大多數檔案自然輕量
// - 冪等：chunk_id = {asset_id}_{index}，UNIQUE(asset_id, chunk_index)
//   + INSERT OR IGNORE；已有 chunk 的資產直接跳過
// - 斷點續跑：逐批 commit，任何時刻中斷重跑即續
// - 讓出 UI：批間 await Future.delayed，embedding 走本地 TFLite
//   （EmbeddingGemma-300M，已在EmbeddingService 單例）
// - 進度：brain_meta.asset_chunk_backfill 記錄進度，MCP 可查
//
// 與 26142 全量重嵌（2026-08-20）同一 SOP。

import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';
import '../brain_container/embedding/embedding_service.dart';

class AssetChunkBackfillService {
  AssetChunkBackfillService._();
  static final AssetChunkBackfillService instance = AssetChunkBackfillService._();

  bool _running = false;
  int _chunked = 0;
  int _assetsProcessed = 0;

  /// [教練 Agent 2026-08-21] #10 背景導入進度提示：對 UI 廣播
  /// （done/total；total=0 且 !running = 無事發生）
  final progress = ValueNotifier<String>('');

  bool get isRunning => _running;
  int get chunkCount => _chunked;
  int get assetsProcessed => _assetsProcessed;

  static const _chunkSize = 512;
  static const _chunkOverlap = 64;
  static const _minCharsToChunk = 600;

  /// 啟動背景回填（冪等：無待辦靜默返回）
  Future<void> start() async {
    if (_running) return;
    final db = BrainDatabase.instance.db;

    final pending = db.select('''
      SELECT COUNT(*) AS n FROM asset_index a
      WHERE LENGTH(a.content_text) > $_minCharsToChunk
        AND a.index_status = 'indexed'
        AND NOT EXISTS (
          SELECT 1 FROM asset_chunks c WHERE c.asset_id = a.id
        )
    ''');
    final total = pending.first['n'] as int;
    if (total == 0) {
      debugPrint('[ChunkBackfill] 無待辦');
      return;
    }
    _running = true;
    progress.value = '0/$total';
    debugPrint('[ChunkBackfill] 開始：$total 個長內容資產待切片');

    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      debugPrint('[ChunkBackfill] embedding 模型不可用——中止');
      _running = false;
      return;
    }

    // [教練 Agent 2026-08-21] #11 model_version 守門員：chunk 表內已有其他
    // 版本的向量 → 中止（防新舊混用）。全空或同版本才放行。
    final recorded = db.select(
      "SELECT value FROM brain_meta WHERE key = 'chunk_vector_model'",
    );
    final currentModel = EmbeddingService.currentModelVersion;
    if (recorded.isNotEmpty && (recorded.first['value'] as String) != currentModel) {
      debugPrint(
        '[ChunkBackfill] 版本不符（表內 '
        '${recorded.first['value']} vs 現在 $currentModel）——中止防混用',
      );
      _running = false;
      return;
    }

    var done = 0;
    while (true) {
      final rows = db.select('''
        SELECT a.id, a.content_text FROM asset_index a
        WHERE LENGTH(a.content_text) > $_minCharsToChunk
          AND a.index_status = 'indexed'
          AND NOT EXISTS (
            SELECT 1 FROM asset_chunks c WHERE c.asset_id = a.id
          )
        ORDER BY a.rowid ASC
        LIMIT 8
      ''');
      if (rows.isEmpty) break;

      for (final row in rows) {
        final assetId = row['id'] as String;
        final text = (row['content_text'] as String?) ?? '';
        final chunks = _slidingWindow(text);
        if (chunks.isEmpty) {
          // 標記空 chunk 佔位以免重掃（內容被 trim 成空）
          db.execute(
            'INSERT OR IGNORE INTO asset_chunks '
            '(chunk_id, asset_id, chunk_index, content, char_count, created_at) '
            "VALUES (?, ?, 0, '', 0, ?)",
            ['${assetId}_0', assetId, DateTime.now().millisecondsSinceEpoch],
          );
          continue;
        }
        try {
          final results = await embedder.embedBatch(chunks);
          final now = DateTime.now().millisecondsSinceEpoch;
          for (var i = 0; i < chunks.length; i++) {
            final vec = results[i].vector;
            final blob = _vectorToBlob(vec);
            db.execute(
              'INSERT OR IGNORE INTO asset_chunks '
              '(chunk_id, asset_id, chunk_index, content, char_count, '
              ' embedding, embed_source, model_version, created_at) '
              "VALUES (?, ?, ?, ?, ?, ?, 'text', ?, ?)",
              [
                '${assetId}_$i',
                assetId,
                i,
                chunks[i],
                chunks[i].length,
                blob,
                results[i].modelVersion,
                now,
              ],
            );
          }
          _chunked += chunks.length;
        } catch (e) {
          debugPrint('[ChunkBackfill] asset $assetId 失敗（跳過）: $e');
        }
        _assetsProcessed++;
      }
      done += rows.length;
      progress.value = '$done/$total';

      db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value, updated_at) VALUES "
        "('asset_chunk_backfill', ?, ?)",
        [
          '$done/$total',
          DateTime.now().millisecondsSinceEpoch,
        ],
      );

      // 讓出 UI
      await Future.delayed(const Duration(milliseconds: 300));
    }

    db.execute(
      "INSERT OR REPLACE INTO brain_meta (key, value, updated_at) VALUES "
      "('chunk_vector_model', ?, ?)",
      [currentModel, DateTime.now().millisecondsSinceEpoch],
    );
    _running = false;
    progress.value = ''; // 清空 = 結束
    debugPrint('[ChunkBackfill] 完成：$_assetsProcessed 資產 / $_chunked chunks');
  }

  /// 512+64 滑窗切片（與 content_preprocessor 同配方）
  List<String> _slidingWindow(String text) {
    final clean = text.trim();
    if (clean.length < _minCharsToChunk) return [];
    if (clean.length <= _chunkSize) return [clean];

    final chunks = <String>[];
    var start = 0;
    while (start < clean.length) {
      final end = (start + _chunkSize).clamp(0, clean.length);
      chunks.add(clean.substring(start, end));
      if (end >= clean.length) break;
      start = end - _chunkOverlap;
    }
    // 上限保護：單檔最多 40 片（~2 萬字），超長的截斷（罕見）
    return chunks.take(40).toList();
  }

  /// `List<double>` → f32 little-endian BLOB
  static Uint8List _vectorToBlob(List<double> vec) {
    final bytes = Uint8List(vec.length * 4);
    final bd = ByteData.view(bytes.buffer);
    for (var i = 0; i < vec.length; i++) {
      bd.setFloat32(i * 4, vec[i], Endian.little);
    }
    return bytes;
  }
}
