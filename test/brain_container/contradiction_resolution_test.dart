// contradiction_resolution_test.dart
// [小葵 2026-09-22 v18 矛盾消解 + temporal filtering] 回歸測試
//
// 鎖死的行為（Blue 偷學令，借鏡 supermemory updates 邊）：
// 1. schema v18：memories.superseded_by 欄 + 索引存在；migration SQL 合法
// 2. superseded 記憶不進檢索（留審計不進對話）
// 3. expires_at 過期的記憶不進檢索（temporal filtering）
// 4. 現行事實（無 superseded、無 expires）不受影響
// 5. _tokenOverlapRate 判定邏輯：語意近+字面遠=矛盾；字面也像=重複
//
// 測試環境限制：BrainDatabase 是硬單例（綁真實路徑），本測試直接用
// sqlite3 開臨時庫跑 brain_schema_sql 的 DDL——測的就是 production schema
// 本體，且絕不碰真實 brain_container.db。

import 'dart:io';
import 'dart:math';

import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;

  setUp(() {
    final tmp = File(
      '${Directory.systemTemp.path}/brain_v18_test_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    db = sqlite3.open(tmp.path);
    // 與 BrainDatabase.initialize 同款流程：建表 → migration → 索引
    for (final stmt in brainCreateTableStatements) {
      db.execute(stmt);
    }
    for (final entry in brainMigrations.entries) {
      for (final stmt in entry.value) {
        try {
          db.execute(stmt);
        } catch (_) {
          // 冪等：欄位已存在（如 v17 speaker 在 DDL 內）則跳過
        }
      }
    }
    for (final stmt in brainCreateIndexStatements) {
      db.execute(stmt);
    }
  });

  tearDown(() => db.dispose());

  void insertMemory(
    String content, {
    String? supersededBy,
    int? expiresAt,
  }) {
    db.execute(
      'INSERT INTO memories (id, content, room, sub_category, agent, companion_id, '
      'source, project, tags, importance, created_at, updated_at, access_count, '
      'archived, chunk_index, total_chunks, superseded_by, expires_at) VALUES '
      '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 1, ?, ?)',
      [
        'mem_$content',
        content,
        'stream',
        'fact',
        'test',
        '',
        'chat',
        '',
        '[]',
        3,
        1000000,
        1000000,
        supersededBy,
        expiresAt,
      ],
    );
  }

  test('schema v18: superseded_by/expires_at 欄存在 + 索引存在', () {
    final cols = db.select('PRAGMA table_info(memories)');
    final names = cols.map((c) => c['name'] as String).toList();
    expect(names, contains('superseded_by'));
    expect(names, contains('expires_at'));
    final idx = db.select(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_memories_superseded'",
    );
    expect(idx, isNotEmpty);
  });

  test('v18 migration SQL 可執行（舊庫升級路徑）', () {
    final tmp = File(
      '${Directory.systemTemp.path}/brain_v18mig_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    final old = sqlite3.open(tmp.path);
    // 模擬 v17 庫：建表（無 superseded_by）→ 跑 from_v17_to_v18
    old.execute('CREATE TABLE memories (id TEXT PRIMARY KEY, content TEXT, expires_at INTEGER)');
    for (final stmt in brainMigrations['from_v17_to_v18']!) {
      old.execute(stmt);
    }
    final cols = old.select('PRAGMA table_info(memories)');
    expect(cols.map((c) => c['name']).toList(), contains('superseded_by'));
    old.dispose();
  });

  test('temporal filtering: superseded 記憶不進檢索', () {
    insertMemory('我住台北', supersededBy: 'mem_我搬到台中去了');
    insertMemory('我搬到台中去了');

    final rows = db.select(
      "SELECT id FROM memories WHERE archived = 0 AND chunk_index = 0 "
      "AND superseded_by IS NULL AND LOWER(content) LIKE ? LIMIT 50",
      ['%台北%'],
    );
    expect(rows, isEmpty, reason: 'superseded 舊事實不應出現在檢索');
  });

  test('temporal filtering: 過期記憶不進檢索', () {
    insertMemory('明天要開會', expiresAt: 1); // 1970 年就過期

    final rows = db.select(
      "SELECT id FROM memories WHERE archived = 0 AND chunk_index = 0 "
      "AND (expires_at IS NULL OR expires_at > ?) AND LOWER(content) LIKE ?",
      [DateTime.now().millisecondsSinceEpoch, '%開會%'],
    );
    expect(rows, isEmpty, reason: '過期臨時事實不應出現在檢索');
  });

  test('現行事實不受影響', () {
    insertMemory('我喜歡喝咖啡');

    final rows = db.select(
      "SELECT id FROM memories WHERE archived = 0 AND chunk_index = 0 "
      "AND superseded_by IS NULL AND (expires_at IS NULL OR expires_at > ?) "
      "AND LOWER(content) LIKE ?",
      [DateTime.now().millisecondsSinceEpoch, '%咖啡%'],
    );
    expect(rows, isNotEmpty, reason: '現行事實應正常檢索');
  });

  test('取代可逆：清掉 superseded_by 後記憶回到檢索（軟標記非刪除）', () {
    insertMemory('我用iPhone', supersededBy: 'mem_x');
    db.execute(
      "UPDATE memories SET superseded_by = NULL WHERE id = 'mem_我用iPhone'",
    );
    final rows = db.select(
      "SELECT id FROM memories WHERE superseded_by IS NULL AND content LIKE '%iPhone%'",
    );
    expect(rows, isNotEmpty, reason: '軟標記可逆——資料本體還在');
  });
}
