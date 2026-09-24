// memory_asset_link_backfill_service.dart
// [教練 Agent 2026-08-20] 鐵三角 #6——memory_asset_links 回填
//
// 死因鏈：asset_index 從未被 vector_init（#3 已修）→ autoLinkByVector 的
// vector_full_scan 每次炸掉被 catch 靜默吞 → 219 條記憶 × 0 條連結 →
// 資產地圖（跨島橋）沒有半條邊。
//
// 本服務：對「沒有任何 link 的記憶」重跑 autoLinkByVector 邏輯。
// - 完全複用 memories 既有 embedding（不重燒——向量已在庫）
// - 冪等：有 link 的記憶跳過（UNIQUE 約束雙保險）
// - 節流：每批 20 筆、批間 500ms——vector_full_scan 是全掃（26022 筆
//   線性掃描），不與前景搶資源
// - 只在建置連結：不刪不改任何既有 link（附加式，向後相容）

import 'package:flutter/foundation.dart';

import 'brain_database.dart';
import 'cross_link_backfill_worker.dart';

class MemoryAssetLinkBackfillService {
  MemoryAssetLinkBackfillService._();
  static final MemoryAssetLinkBackfillService instance =
      MemoryAssetLinkBackfillService._();

  bool _running = false;
  int _linked = 0;
  int _memoriesProcessed = 0;

  bool get isRunning => _running;
  int get linkedCount => _linked;
  int get memoriesProcessed => _memoriesProcessed;

  /// 啟動背景回填（冪等：無待辦即靜默返回）
  Future<void> start() async {
    if (_running) return;
    final db = BrainDatabase.instance.db;

    final pending = db.select('''
      SELECT COUNT(*) AS n FROM memories m
      WHERE m.embedding IS NOT NULL AND length(m.embedding) > 0
        AND NOT EXISTS (
          SELECT 1 FROM memory_asset_links l WHERE l.memory_id = m.id
        )
    ''');
    final total = pending.first['n'] as int;
    if (total == 0) {
      debugPrint('[LinkBackfill] 無待回填');
      return;
    }
    _running = true;
    debugPrint('[LinkBackfill] 開始：$total 條記憶待建連結');

    var done = 0;
    var created = 0;
    // [教練 Agent 2026-08-20] 修無限迴圈：掃過但建不出 link 的記憶會永遠留在
    // pending（NOT EXISTS 條件永真）→ LIMIT 20 每輪撈同一批永轉。
    // 解法：本輪已嘗試過的記憶 id 記在 Set，Dart 端過濾跳過。
    final attempted = <String>{};
    while (true) {
      final rows = db.select('''
        SELECT m.id, m.embedding AS emb FROM memories m
        WHERE m.embedding IS NOT NULL AND length(m.embedding) > 0
          AND NOT EXISTS (
            SELECT 1 FROM memory_asset_links l WHERE l.memory_id = m.id
          )
        ORDER BY m.created_at ASC
        LIMIT 200
      ''').where((r) => !attempted.contains(r['id'] as String)).take(20).toList();
      if (rows.isEmpty) break;

      for (final row in rows) {
        // 用既有記憶向量 BLOB 直接 full_scan（不重燒 embedding）
        final emb = row['emb'];
        if (emb is! List<int>) continue; // BLOB 才處理（保護型別）
        attempted.add(row['id'] as String);
        final n = CrossLinkBackfillWorker.autoLinkWithExistingVector(
          memoryId: row['id'] as String,
          embeddingBlob: emb,
        );
        created += n;
        done++;
      }
      _linked = created;
      _memoriesProcessed = done;
      // vector_full_scan 是線性全掃——讓出主執行緒
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _running = false;
    debugPrint('[LinkBackfill] 完成：$done 條記憶 → $created 條連結');
  }
}
