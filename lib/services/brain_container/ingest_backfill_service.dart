// ingest_backfill_service.dart
// [教練 Agent 2026-08-20] P1-4 ingest 治本——背景導入回填服務
//
// 使用者 憲章：「熱/溫/冷分層＋背景導入」——APP 24/7 開機，利用閒置時機
// 慢慢崁入。本服務用「純規則推導」（不燒 LLM/GPU）回填 v10 三欄位：
//   display_title  — 人話標題（剝機器前綴/日期白話化）
//   origin_kind    — 資料來源性質（farm/agent/human/media/code/doc…）
//   topic_cluster  — 主題集群鍵（合集分組依據，圖譜合集直接吃這欄）
//
// 之後 LLM 抽樣標註（熱資料層）可在本服務之上「升級」display_title，
// 規則版永遠是 fallback——向後相容不鎖死。
//
// 節流：每批 500 筆、批間 200ms——不與前景渲染搶資源。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'brain_database.dart';

class IngestBackfillService {
  IngestBackfillService._();
  static final IngestBackfillService instance = IngestBackfillService._();

  bool _running = false;
  int _backfilled = 0;

  bool get isRunning => _running;
  int get backfilledCount => _backfilled;

  /// 啟動背景回填（冪等：跑過或無待辦即靜默返回）
  Future<void> start() async {
    if (_running) return;
    if (!BrainDatabase.instance.isInitialized) return;
    final db = BrainDatabase.instance.db;

    final pending = db.select(
      'SELECT COUNT(*) AS n FROM asset_index WHERE display_title IS NULL',
    );
    final total = pending.first['n'] as int;
    if (total == 0) {
      debugPrint('[IngestBackfill] 無待回填（$_backfilled 筆已處理）');
      return;
    }
    _running = true;
    debugPrint('[IngestBackfill] 開始背景回填：$total 筆待辦');

    var done = 0;
    while (done < total) {
      final rows = db.select(
        'SELECT id, file_name, title, folder_root, source_type, asset_kind '
        'FROM asset_index WHERE display_title IS NULL LIMIT 500',
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        final fileName = (row['file_name'] as String?) ?? '';
        final title = row['title'] as String?;
        final folderRoot = (row['folder_root'] as String?) ?? '';
        final sourceType = (row['source_type'] as String?) ?? 'imported';
        final assetKind = (row['asset_kind'] as String?) ?? '';

        final dt = _deriveDisplayTitle(fileName, title);
        final ok = _deriveOriginKind(folderRoot, sourceType, assetKind);
        final tc = _deriveTopicCluster(fileName);

        db.execute(
          'UPDATE asset_index SET display_title = ?, origin_kind = ?, '
          'topic_cluster = ? WHERE id = ?',
          [dt, ok, tc, row['id']],
        );
      }
      done += rows.length;
      _backfilled = done;
      // 讓出主執行緒——背景導入不與使用者操作搶資源
      await Future.delayed(const Duration(milliseconds: 200));
      if (done % 5000 == 0) {
        debugPrint('[IngestBackfill] 進度 $done/$total');
      }
    }
    _running = false;
    debugPrint('[IngestBackfill] 完成：$done 筆');
  }

  /// display_title 推導（與 CanvasNode.displayTitle 同規則——單一真相在
  /// 檔名規則，Dart 端 fallback 與 DB 端回填永遠一致）
  static String _deriveDisplayTitle(String fileName, String? title) {
    var name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    for (final prefix in [
      'inspection-record-',
      'bridge_image_',
      'canvas-workflow-',
      'pack_',
    ]) {
      if (name.startsWith(prefix)) {
        var rest = name.substring(prefix.length);
        if (rest.length >= 8 && RegExp(r'^\d{8,}').hasMatch(rest)) {
          rest = rest.substring(0, 8);
        }
        final label = prefix == 'inspection-record-'
            ? '巡查紀錄'
            : prefix == 'bridge_image_'
                ? '生成圖像'
                : prefix == 'canvas-workflow-'
                    ? '畫布工作流'
                    : '打包';
        return rest.isEmpty ? label : '$label $rest';
      }
    }
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[_-](.+)$').firstMatch(name);
    if (m != null) {
      return '${m.group(4)} ${m.group(2)}/${m.group(3)}';
    }
    // title 欄有人工/上游標題且夠短 → 用它
    final t = title?.trim();
    if (t != null && t.isNotEmpty && t.length < name.length) return t;
    return name.isEmpty ? '未命名' : name;
  }

  /// origin_kind 推導：folder_root / source_type / asset_kind 三訊號
  static String _deriveOriginKind(
      String folderRoot, String sourceType, String assetKind) {
    final fr = folderRoot.toLowerCase();
    if (fr.contains('farm') || fr.contains('農場')) return 'farm';
    if (sourceType == 'agent' || fr.contains('agent')) return 'agent';
    if (assetKind == 'image' || assetKind == 'photo') return 'media';
    if (assetKind == 'code' || fr.contains('repo') || fr.contains('project')) {
      return 'code';
    }
    if (assetKind == 'document' || assetKind == 'note') return 'doc';
    return 'human';
  }

  /// topic_cluster 推導：系列鍵（與圖譜 _seriesKeyOf 同規則）
  static String _deriveTopicCluster(String fileName) {
    var name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    for (final prefix in [
      'inspection-record-',
      'bridge_image_',
      'canvas-workflow-',
      'pack_',
    ]) {
      if (name.startsWith(prefix)) {
        return switch (prefix) {
          'inspection-record-' => '巡查紀錄',
          'bridge_image_' => '生成圖像',
          'canvas-workflow-' => '畫布工作流',
          _ => '打包',
        };
      }
    }
    final m = RegExp(r'^\d{4}-\d{2}-\d{2}[_-](.+)$').firstMatch(name);
    if (m != null) return m.group(1)!;
    final m2 = RegExp(r'^([\u4e00-\u9fa5]{2,8})[_-]').firstMatch(name);
    if (m2 != null) return m2.group(1)!;
    return 'solo';
  }
}
