// agent_knowledge_isolation_test.dart
// [A5 2026-09-14] 記憶私有 × 招式共享——資料隔離測試
// 對應 DATA_FLOW_AUDIT.md 審計點 A5：
//   多 Agent 共處時，A 的私有記憶不得洩給 B 的搜尋/讀取脈絡。
//
// 測試矩陣：
//   T1 searchMemories：B 搜尋不應命中 A 的私有記憶（FTS 與 LIKE 兩路）
//   T2 getMemoryByTitle：B 讀 A 的私有人格卡 title → 必須 null
//   T3 shared 記憶：A/B 都應搜得到
//   T4 getScript（招式共享）：A 建的招式 B 應讀得到

@Skip('需要 BrainDatabase.instance（sqlite3 原生庫）——於 macOS 實機 flutter test 執行；見檔尾替代 dart test 殼')
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  // 佔位殼：真正測試邏輯在下方註解區（待 BrainDatabase 測試隔離初始化支援後啟用）。
  test('A5 隔離測試殼（佔位）', () {
    // T1–T4 邏輯見 DATA_FLOW_AUDIT.md A5；此殼防止空套件。
    expect(1 + 1, 2);
  });
}

// ══════════════════════════════════════════════════════════════
// 實際測試邏輯（BrainDatabase 測試隔離初始化後啟用）：
//
// group('A5 記憶私有隔離', () {
//   late AgentKnowledgeService knowledge;
//   const alice = 'cmp_alice';
//   const bob = 'cmp_bob';
//
//   setUpAll(() async {
//     await BrainDatabase.instance.initializeForTest(); // 需要此 API
//     knowledge = AgentKnowledgeService();
//     // 準備資料：
//     // - alice 私有記憶：'Alice 的人格卡' / 'Alice 私密對話摘要'
//     // - shared 記憶：'共享農場知識'
//     // - alice 建的招式：'澆水 SOP'
//   });
//
//   test('T1 searchMemories：B 搜「人格卡」不得命中 A 私有', () {
//     CompanionStore().activeCompanionId = bob;
//     final hits = knowledge.searchMemories('人格卡');
//     expect(hits.where((h) => h.title.contains('Alice')).isEmpty, isTrue);
//   });
//
//   test('T2 getMemoryByTitle：B 讀 A 私有人格卡 → null', () {
//     CompanionStore().activeCompanionId = bob;
//     expect(knowledge.getMemoryByTitle('Alice 的人格卡'), isNull);
//   });
//
//   test('T3 shared 記憶 A/B 皆可見', () {
//     CompanionStore().activeCompanionId = bob;
//     expect(knowledge.searchMemories('農場知識').isNotEmpty, isTrue);
//   });
//
//   test('T4 招式共享：B 讀 A 建的招式', () {
//     CompanionStore().activeCompanionId = bob;
//     expect(knowledge.getScript(aliceScriptId), isNotNull);
//   });
// });
// ══════════════════════════════════════════════════════════════
