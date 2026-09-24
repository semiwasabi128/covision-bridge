import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';

void main() {
  test('kAgentVectorInitSql 存在且指向 agent_memories', () {
    expect(kAgentVectorInitSql, contains('vector_init'));
    expect(kAgentVectorInitSql, contains("'agent_memories'"));
    expect(kAgentVectorInitSql, contains('dimension=768'));
  });

  test('agent 語意搜尋 SQL 用 rowid join（TEXT id 不能直 join rowid）', () {
    // 從原始碼抓字串驗證形狀——防止未來改動把 agent 查詢的 m.rowid 改回 m.id。
    // 注意：memories 表 id 是 INTEGER PRIMARY KEY，ON m.id = v.rowid 在那裡合法，
    // 所以斷言必須限定在 agent_memories 查詢區塊內。
    final src = File('lib/services/vector_db/hybrid_search_service.dart')
        .readAsStringSync();
    final i = src.indexOf("vector_full_scan('agent_memories'");
    expect(i, greaterThan(0), reason: 'agent_memories 語意搜尋必須存在');
    // agent 查詢區塊往後 500 字內必須是 rowid join
    final block = src.substring(i, i + 500);
    expect(block, contains('ON m.rowid = v.rowid'));
    expect(block.contains('ON m.id = v.rowid'), isFalse);
  });
}
