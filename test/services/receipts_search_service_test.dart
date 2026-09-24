// receipts_search_service_test.dart
// [收據搜尋 RC1 2026-09-08] 五域聯合搜尋測試
// 對話域與任務域用 debugSetStorageDirectory mock；
// 大腦域（HybridSearchService）在測試環境無 DB → 驗證 fail-open 空結果不炸。

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/conversation_store.dart';
import 'package:bridge_app/services/tasks/task_session.dart';
import 'package:bridge_app/services/tasks/task_session_store.dart';
import 'package:bridge_app/services/search/receipts_search_service.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ConversationStore._migrateLegacyPrefsIfNeeded 會碰 SharedPreferences
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('receipts_search_test');
    ConversationStore.debugSetStorageDirectory(tmpDir);
    TaskSessionStore.debugSetStorageDirectory(tmpDir);
  });

  tearDown(() async {
    ConversationStore.debugSetStorageDirectory(null);
    TaskSessionStore.debugSetStorageDirectory(null);
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('查「鹿角蕨」——對話域命中（title 與內容雙路徑）', () async {
    // title 命中
    await ConversationStore.save(_conv('c1', '鹿角蕨照顧筆記', ['昨天澆水了']));
    // 內容命中（title 不含關鍵詞）
    await ConversationStore.save(_conv('c2', '日常對話', ['鹿角蕨的新葉展開了耶！']));

    final r = await ReceiptsSearchService.instance.search('鹿角蕨');

    expect(r.conversations.length, 2);
    final ids = r.conversations.map((h) => h.conversationId).toSet();
    expect(ids.contains('c1'), isTrue, reason: 'title 命中');
    expect(ids.contains('c2'), isTrue, reason: '訊息內容命中');
  });

  test('對話命中附 messageId（跳到現場的證據）', () async {
    await ConversationStore.save(
        _conv('c1', '閒聊', ['無關訊息', '今天鹿角蕨長很好']));

    final r = await ReceiptsSearchService.instance.search('鹿角蕨');

    expect(r.conversations.single.messageId, isNotNull,
        reason: '內容命中的 hop 必須帶 messageId 才能跳到那則訊息');
  });

  test('大小寫不敏感', () async {
    await ConversationStore.save(_conv('c1', 'Platycerium notes', []));

    final r = await ReceiptsSearchService.instance.search('platycerium');

    expect(r.conversations.length, 1);
  });

  test('任務域命中（title/instruction/summary）', () async {
    final t1 = TaskSession.create(
      conversationId: 'c', companionId: 'p', workCanvasId: 'w',
      title: '鹿角蕨週報', instruction: '做週報',
    ).transitionTo(TaskStatus.working);
    final t2 = TaskSession.create(
      conversationId: 'c', companionId: 'p', workCanvasId: 'w2',
      title: ' unrelated ', instruction: '整理鹿角蕨照片',
    );
    await TaskSessionStore.save(t1);
    await TaskSessionStore.save(t2);

    final r = await ReceiptsSearchService.instance.search('鹿角蕨');

    expect(r.tasks.length, 2);
    expect(r.tasks.every((h) => h.hop.workCanvasId != null), isTrue,
        reason: '任務 hop 必須帶 workCanvasId 才能跳工作畫布');
  });

  test('大腦域（無 DB 環境）fail-open 空結果不炸', () async {
    final r = await ReceiptsSearchService.instance.search('任何字');
    // 不丟例外、memories/assets 為空（測試環境無 brain DB）
    expect(r.memories, isEmpty);
    expect(r.assets, isEmpty);
  });

  test('空查詢 → 空結果', () async {
    final r = await ReceiptsSearchService.instance.search('   ');
    expect(r.isEmpty, isTrue);
    expect(r.totalHits, 0);
  });
}

/// 測試 helper——建對話（messages 用簡化 ID）
Conversation _conv(String id, String title, List<String> contents) {
  final now = DateTime.now();
  return Conversation(
    id: id,
    title: title,
    createdAt: now,
    updatedAt: now,
    messages: [
      for (var i = 0; i < contents.length; i++)
        Message(
          id: '$id-m$i',
          role: 'user',
          content: contents[i],
          timestamp: now,
        ),
    ],
  );
}
