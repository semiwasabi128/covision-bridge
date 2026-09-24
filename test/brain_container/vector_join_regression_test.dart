// vector_join_regression_test.dart
// [小葵 2026-09-23] memories 向量檢索 JOIN 錯欄位回歸測試
//
// 病例（2026-09-23 vector benchmark 抓包）：memories 表的向量檢索 SQL
// 寫 `ON m.id = v.rowid`——memories.id 是 TEXT（如 '1785225948457645_1'），
// vector_full_scan 回的 rowid 是 INTEGER，永遠 JOIN 不上 → 向量檢索
// 靜默回空集合（不報錯！）。四處同款：hybrid_search×2 /
// connection_repository / vault_service。
//
// 歷史：agent_memories 曾犯同款（agent_memory_vector_reachability_test
// 鎖死那邊），memories 漏網。本測試鎖死 memories 側。
//
// 不依賴 TFLite 模型：嵌入用確定性假向量（同一文本→同一向量），
// 重點測「JOIN 後拿得到資料」，不測語意品質（那由
// vector_benchmark_test 用真模型測）。

import 'dart:io';
import 'dart:math';

import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_vector/sqlite_vector.dart';

void main() {
  late sqlite3.Database db;

  setUpAll(() {
    final tmp = File(
      '${Directory.systemTemp.path}/brain_vecjoin_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    sqlite3.sqlite3.loadSqliteVectorExtension();
    db = sqlite3.sqlite3.open(tmp.path);
    for (final sql in brainCreateTableStatements) {
      db.execute(sql);
    }
    for (final sql in brainCreateIndexStatements) {
      db.execute(sql);
    }
    for (final sql in brainSeedStatements) {
      db.execute(sql);
    }
    db.execute(kVectorInitSql);
  });

  tearDownAll(() => db.dispose());

  /// 確定性假向量：字元 code unit → 768 維（同文本同向量，相近文本
  /// 前幾維相近——足夠讓「相似文本」的 cosine 距離小於「無關文本」）。
  List<double> fakeEmbed(String text) {
    final v = List<double>.filled(768, 0.0);
    for (var i = 0; i < text.length && i < 64; i++) {
      v[i] = (text.codeUnitAt(i) % 97) / 97.0;
    }
    return v;
  }

  String jsonVec(List<double> v) => '[${v.map((e) => e.toString()).join(',')}]';

  String insertMemory(String id, String content, List<double> vec) {
    db.execute(
      'INSERT INTO memories (id, content, room, sub_category, agent, companion_id, '
      'source, project, tags, importance, created_at, updated_at, access_count, '
      'archived, chunk_index, total_chunks, embedding, vector_model_version) VALUES '
      "(?, ?, 'stream', 'fact', 'test', '', 'chat', '', '[]', 3, 1000, 1000, 0, 0, 0, 1, "
      'vector_as_f32(?), ?)',
      [id, content, jsonVec(vec), 'test-fake'],
    );
    return id;
  }

  test('核心回歸：TEXT id 的 memories 向量檢索 JOIN 後必須拿得到資料', () {
    // id 刻意用 production 同款格式（timestamp_counter——TEXT）
    insertMemory('1785225948457645_1', '咖啡拿鐵測試', fakeEmbed('咖啡拿鐵測試'));
    insertMemory('1785225948457646_2', '程式碼除錯測試', fakeEmbed('程式碼除錯測試'));

    // production findSimilarMemories 同款 JOIN 形狀（m.rowid = v.rowid）
    final rows = db.select(
      "SELECT m.id, m.content FROM memories m "
      "JOIN vector_full_scan('memories', 'embedding', vector_as_f32(?), 2) AS v "
      "  ON m.rowid = v.rowid "
      "WHERE m.archived = 0 AND m.superseded_by IS NULL",
      [jsonVec(fakeEmbed('咖啡拿鐵測試'))],
    );

    // 修前病況：JOIN 永遠空（TEXT id ≠ INT rowid）——安靜失敗
    expect(rows, isNotEmpty,
        reason: '向量檢索 JOIN 後空集合 = m.id(TEXT)=v.rowid(INT) 炸彈復發');
    expect(rows.first['content'], contains('咖啡'),
        reason: '查「咖啡」必須先召回咖啡記憶（fake embedding 下同文本距離最小）');
  });

  test('四處 production SQL 都用 rowid JOIN——靜態掃描防復發', () {
    // 病理：任何 vector_full_scan 對 memories 的 JOIN 若寫 m.id = v.rowid
    // 就是復發。掃 lib/ 下所有 dart 原始碼，這個 pattern 必須絕跡。
    final libDir = Directory('${Directory.current.path}/lib');
    final offenders = <String>[];
    for (final f in libDir.listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('ON m.id = v.rowid')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: '這些檔案又寫了 m.id = v.rowid（TEXT≠INT 永遠 JOIN 不上）：'
            '${offenders.join(', ')}');
  });
}
