import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp(
      'bridge_conversation_store_test_',
    );
    ConversationStore.debugSetStorageDirectory(tempDir);
  });

  tearDown(() async {
    ConversationStore.debugSetStorageDirectory(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saves conversations to file instead of SharedPreferences', () async {
    final conversation = Conversation.create(title: '桌面整理測試');

    await ConversationStore.save(conversation);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bridge_conversations'), isNull);

    final file = File('${tempDir.path}/conversations.json');
    expect(await file.exists(), isTrue);
    expect(await ConversationStore.getById(conversation.id), isNotNull);
  });

  test(
    'migrates legacy SharedPreferences conversations and removes old key',
    () async {
      final legacyConversation = Conversation.create(title: '舊對話');
      SharedPreferences.setMockInitialValues({
        'bridge_conversations': jsonEncode([legacyConversation.toJson()]),
      });

      final conversations = await ConversationStore.getAll();

      expect(conversations, hasLength(1));
      expect(conversations.first.title, '舊對話');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bridge_conversations'), isNull);

      final file = File('${tempDir.path}/conversations.json');
      expect(await file.exists(), isTrue);
    },
  );
}
