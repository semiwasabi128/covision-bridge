// asset_reembed_service.dart
// [教練 Agent 2026-08-20] 鐵三角 #2+#4——22484 假向量全量重嵌入服務
//
// 根因（08-19 驗屍）：86% 資產只嵌了檔名字串（IMG_2384.jpg），
// 語義檢索永遠 miss。本服務把這些「假向量」用中繼文字
// （display_title＋系列＋路徑＋檔名＋日期，純規則零 GPU）
// 重嵌，並將 embed_source 標記為 'metadata'（冪等守門）。
//
// 設計（複用 P1-4 SOP）：
// - 冪等：embed_source IS NULL 才處理（舊資料）或 'filename' 標記
// - 斷點續跑：每批 50 筆 commit＋300ms 讓出主 isolate，重啟續跑
// - benchmark 內建（#4）：首批 100 筆量測速率並 debugPrint 外推
//   全程耗時——先知情再跑，不盲跑
// - 讓出 UI：小批次 + delay，不搶前景
// - 誠實：模型 fallback（零向量）時立即停止，不寫垃圾向量

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'asset_metadata_text_builder.dart';
import 'brain_database.dart';
import 'embedding/embedding_service.dart';

class AssetReembedService {
  AssetReembedService._();
  static final AssetReembedService instance = AssetReembedService._();

  bool _running = false;
  int _reembedded = 0;

  bool get isRunning => _running;
  int get reembeddedCount => _reembedded;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run(BrainDatabase.instance.db);
    } catch (e, st) {
      debugPrint('[AssetReembed] ❌ 重嵌失敗: $e\n$st');
    } finally {
      _running = false;
    }
  }

  Future<void> _run(Database db) async {
    final embedder = EmbeddingService.instance;
    // 前置：嵌入模型必須已初始化且可用（fallback 會寫零向量＝垃圾）
    if (!embedder.isModelAvailable) {
      debugPrint('[AssetReembed] ⏸ 嵌入模型未就緒，跳過（不寫零向量）');
      _mark(db, 'model_unavailable');
      return;
    }

    // 待辦：embed_source 尚未標記的（舊假向量沒有標記）
    final total = db.select(
      "SELECT COUNT(*) AS n FROM asset_index "
      "WHERE embedding IS NOT NULL AND (embed_source IS NULL OR embed_source = 'filename')",
    ).first['n'] as int;

    if (total == 0) {
      debugPrint('[AssetReembed] ✅ 無待重嵌資產（冪等跳過）');
      _mark(db, 'idle');
      return;
    }
    debugPrint('[AssetReembed] 開始重嵌：$total 筆待處理');

    final sw = Stopwatch()..start();
    var done = 0;
    const batchSize = 50;

    while (true) {
      final rows = db.select(
        "SELECT id, display_title, topic_cluster, file_path, folder_root, "
        "       file_name, file_modified, content_text, asset_kind "
        "FROM asset_index "
        "WHERE embedding IS NOT NULL AND (embed_source IS NULL OR embed_source = 'filename') "
        "LIMIT ?",
        [batchSize],
      );
      if (rows.isEmpty) break;

      // ── #4 benchmark：首批 100 筆後外推（只印一次）──
      if (done == 100) {
        final rate = done / sw.elapsedMilliseconds * 1000; // 筆/秒
        final etaMin = (total - done) / rate / 60;
        debugPrint(
          '[AssetReembed] 📊 benchmark：${rate.toStringAsFixed(1)} 筆/秒，'
          '剩餘 ${total - done} 筆，預估還要 ${etaMin.toStringAsFixed(1)} 分鐘',
        );
      }

      final texts = rows
          .map((r) => buildMetadataEmbedText({
                'display_title': r['display_title'],
                'topic_cluster': r['topic_cluster'],
                'file_path': r['file_path'],
                'folder_root': r['folder_root'],
                'file_name': r['file_name'],
                'file_modified': r['file_modified'],
              }))
          .toList();

      // 批次嵌入（document 前綴）
      final results = await embedder.embedBatch(texts);
      if (results.any((r) => r.modelVersion == 'mock-fallback')) {
        debugPrint('[AssetReembed] ⛔ 模型 fallback，停止重嵌（不寫零向量）');
        _mark(db, 'fallback_stop');
        return;
      }

      // 寫回：向量 + embed_source 標記
      final txn = 'BEGIN';
      db.execute(txn);
      try {
        for (var i = 0; i < rows.length; i++) {
          final id = rows[i]['id'] as String;
          final vec = results[i].vector;
          final blob = _vecToBlob(vec);
          db.execute(
            "UPDATE asset_index SET embedding = ?, embed_source = 'metadata' WHERE id = ?",
            [blob, id],
          );
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }

      done += rows.length;
      _reembedded = done;
      if (done % 500 == 0) {
        debugPrint('[AssetReembed] 進度 $done/$total');
      }
      // 讓出主 isolate（UI 不卡）
      await Future.delayed(const Duration(milliseconds: 300));
    }

    sw.stop();
    _mark(db, 'done');
    final rate = done / sw.elapsedMilliseconds * 1000;
    debugPrint(
      '[AssetReembed] ✅ 完成：$done 筆，'
      '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒'
      '（${rate.toStringAsFixed(1)} 筆/秒）',
    );
  }

  /// 診斷標記：profile build 看不到 debugPrint，用 DB 說話。
  void _mark(Database db, String status) {
    try {
      db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('reembed_status', ?)",
        [status],
      );
    } catch (_) {}
  }

  /// 768 維 f32 little-endian BLOB（與 vector_as_f32 相容格式）。
  static Uint8List _vecToBlob(List<double> vec) {
    final bytes = ByteData(vec.length * 4);
    for (var i = 0; i < vec.length; i++) {
      bytes.setFloat32(i * 4, vec[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
