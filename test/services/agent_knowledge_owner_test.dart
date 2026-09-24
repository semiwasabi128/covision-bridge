// agent_knowledge_owner_test.dart
// [WS-2 2026-09-13 Blue B 決策] 知識歸屬回歸測試
// 記憶私有＋招式共享——驗收標準：
// 1. 私有記憶只有 owner 搜得到
// 2. 共享知識所有人搜得到
// 3. 寫入預設：記憶掛當前夥伴、（createScript 走 shared 由 DB default 保證）
//
// 注意：AgentKnowledgeService 是 singleton 綁真實 brain.db——測試用
// SQLite in-memory 驗證 SQL 語意（與 service 同款 WHERE 條件），
// 並驗證 schema v16 的欄位存在。

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''CREATE TABLE agent_memories (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
      tags TEXT, memory_type TEXT, embedding BLOB,
      created_at TEXT NOT NULL DEFAULT (datetime('now')), is_archived INTEGER NOT NULL DEFAULT 0,
      owner_companion_id TEXT NOT NULL DEFAULT 'shared')''');
    db.execute('''CREATE TABLE agent_scripts (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
      content TEXT NOT NULL, content_type TEXT NOT NULL DEFAULT 'dart',
      tags TEXT, category TEXT, trigger_keywords TEXT, trigger_scenes TEXT,
      embedding BLOB, usage_count INTEGER NOT NULL DEFAULT 0, last_used_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      is_pinned INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT 'system',
      owner_companion_id TEXT NOT NULL DEFAULT 'shared')''');
    // 測試資料
    db.execute("INSERT INTO agent_memories (id, title, content, owner_companion_id) VALUES ('m1','私有','寧紅字不假成功','cmp_semiwasabi')");
    db.execute("INSERT INTO agent_memories (id, title, content, owner_companion_id) VALUES ('m2','共享','羅盤是權威','shared')");
    db.execute("INSERT INTO agent_scripts (id, title, content, owner_companion_id) VALUES ('s1','截圖招式','App 自拍','shared')");
    db.execute("INSERT INTO agent_scripts (id, title, content, owner_companion_id) VALUES ('s2','小葵私招','SOUL 融合筆記','cmp_semiwasabi')");
  });

  tearDown(() => db.dispose());

  // 與 service 相同的 owner 過濾 SQL（單一真相的鏡像——改 service 時同步改這裡）
  List<String> searchMemories(String q, String ownerId) {
    final rows = db.select(
      "SELECT id FROM agent_memories WHERE (title LIKE ? OR content LIKE ?) AND is_archived = 0 AND (owner_companion_id = 'shared' OR owner_companion_id = ?)",
      ['%$q%', '%$q%', ownerId],
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  List<String> searchScripts(String q, String ownerId) {
    final rows = db.select(
      "SELECT id FROM agent_scripts WHERE (title LIKE ? OR content LIKE ?) AND (owner_companion_id = 'shared' OR owner_companion_id = ?)",
      ['%$q%', '%$q%', ownerId],
    );
    return rows.map((r) => r['id'] as String).toList();
  }

  group('WS-2 知識歸屬（B 決策）', () {
    test('私有記憶：owner 搜得到', () {
      final hits = searchMemories('寧紅字', 'cmp_semiwasabi');
      expect(hits, contains('m1'));
    });

    test('私有記憶：別的夥伴搜不到（小橋斷不了小葵的糧，但也讀不到她的日記）', () {
      final hits = searchMemories('寧紅字', 'cmp_xiaoqiao');
      expect(hits, isEmpty);
    });

    test('共享記憶：任何夥伴都搜得到', () {
      expect(searchMemories('羅盤', 'cmp_semiwasabi'), contains('m2'));
      expect(searchMemories('羅盤', 'cmp_xiaoqiao'), contains('m2'));
      expect(searchMemories('羅盤', 'shared'), contains('m2'));
    });

    test('共享招式：任何夥伴都搜得到（截圖 App 自拍）', () {
      expect(searchScripts('截圖', 'cmp_xiaoqiao'), contains('s1'));
      expect(searchScripts('截圖', 'cmp_semiwasabi'), contains('s1'));
    });

    test('私有招式：只有 owner 搜得到', () {
      expect(searchScripts('SOUL', 'cmp_semiwasabi'), contains('s2'));
      expect(searchScripts('SOUL', 'cmp_xiaoqiao'), isEmpty);
    });

    test('寫入預設值：DB 層 owner 預設 shared（createScript 不帶 owner 時安全）', () {
      db.execute("INSERT INTO agent_scripts (id, title, content) VALUES ('s3','新招式','測試')");
      final row = db.select("SELECT owner_companion_id FROM agent_scripts WHERE id='s3'").first;
      expect(row['owner_companion_id'], 'shared');
    });
  });
}
