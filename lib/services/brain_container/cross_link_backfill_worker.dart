// cross_link_backfill_worker.dart
// [教練 Agent 2026-08-20] 鐵三角 #6——用既有向量建 link 的同步 worker
//
// 與 CrossReferenceService.autoLinkByVector 同邏輯，但不重燒 embedding——
// 直接吃 memories.embedding 欄位的 BLOB（768 維 f32 little-endian，
// 3072 bytes）做 vector_full_scan。同步方法：由 backfill service 在
// 批次間隔中呼叫，失敗靜默降級（單筆失敗不阻斷整批）。

import 'brain_database.dart';

class CrossLinkBackfillWorker {
  /// 用記憶既有向量掃 asset_index，相似度 > 0.55 建 referenced link。
  /// 回傳：本次新建的 link 數。
  ///
  /// [embeddingBlob] 必須是 BLOB（Uint8List）——vector_full_scan 對
  /// BLOB 直通，不需 vector_as_f32（那是 JSON 字串用的）。
  static int autoLinkWithExistingVector({
    required String memoryId,
    required List<int> embeddingBlob,
  }) {
    final db = BrainDatabase.instance.db;
    try {
      if (embeddingBlob.length != 768 * 4) return 0; // 768 維 f32

      final results = db.select(
        "SELECT a.id, v.distance "
        "FROM asset_index a "
        "JOIN vector_full_scan('asset_index', 'embedding', ?, 20) AS v "
        "  ON a.rowid = v.rowid "
        "WHERE a.index_status = 'indexed' AND a.embedding IS NOT NULL "
        "ORDER BY v.distance ASC "
        "LIMIT 10",
        [embeddingBlob],
      );
      if (results.isEmpty) return 0;

      var count = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in results) {
        final distance = (row['distance'] as num?)?.toDouble() ?? 1.0;
        final similarity = (1.0 - (distance / 2.0)).clamp(0.0, 1.0);
        // [教練 Agent 2026-08-21] 門檻二次校準（重嵌後實測）：26142 筆全量
        // 重嵌完成後量測 230 條記憶 best-match 分佈——真匹配 0.55-0.69
        // （鹿角蕨/農場語義全對），噪音頂 0.35，分離帶極寬。取 0.50：
        // 留語義餘裕、噪音仍全擋。
        if (similarity > 0.50) {
          final assetId = row['id'] as String;
          final linkId = 'bkfill_${memoryId}_${assetId}_referenced';
          db.execute(
            'INSERT OR IGNORE INTO memory_asset_links '
            '(id, memory_id, asset_id, link_type, note, created_at) '
            "VALUES (?, ?, ?, 'referenced', 'backfill 2026-08-20', ?)",
            [linkId, memoryId, assetId, now],
          );
          final changes = db.select('SELECT changes() AS c');
          count += (changes.first['c'] as int?) ?? 0;
        }
      }
      return count;
    } catch (_) {
      // 單筆失敗靜默降級——不阻斷整批
      return 0;
    }
  }
}
