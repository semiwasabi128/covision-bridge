// memory_recall_service_test.dart
// [小葵 2026-07-25] 記憶回溯機制測試
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/memory_recall_service.dart';
import 'package:bridge_app/models/conversation.dart';

void main() {
  // 建造假對話歷史（超過 12 則以觸發回溯）
  List<Message> buildMockHistory() {
    final messages = <Message>[];
    final base = DateTime(2026, 7, 20, 10, 0);

    // 15 則舊訊息（會被壓縮）
    messages.add(Message(id: '1', role: 'user', content: '我要用 MiniMax 不要 OpenAI', timestamp: base));
    messages.add(Message(id: '2', role: 'assistant', content: '好的，已切換到 MiniMax，API key 已設定完成', timestamp: base.add(const Duration(minutes: 1))));
    messages.add(Message(id: '3', role: 'user', content: '幫我設定 GraphRAG 的向量資料庫', timestamp: base.add(const Duration(minutes: 5))));
    messages.add(Message(id: '4', role: 'assistant', content: 'GraphRAG 向量資料庫設定中，需要 embedding model', timestamp: base.add(const Duration(minutes: 6))));
    messages.add(Message(id: '5', role: 'user', content: '鹿角蕨的圖片生成好了嗎', timestamp: base.add(const Duration(minutes: 10))));
    messages.add(Message(id: '6', role: 'assistant', content: '鹿角蕨圖片已用 gpt-image-1.5 生成完畢', timestamp: base.add(const Duration(minutes: 11))));
    messages.add(Message(id: '7', role: 'user', content: '紙上交易的策略要調整', timestamp: base.add(const Duration(minutes: 15))));
    messages.add(Message(id: '8', role: 'assistant', content: '紙上交易策略已更新為三軌制', timestamp: base.add(const Duration(minutes: 16))));
    messages.add(Message(id: '9', role: 'user', content: '橋樑計畫的畫布做得怎樣了', timestamp: base.add(const Duration(minutes: 20))));
    messages.add(Message(id: '10', role: 'assistant', content: '畫布已完成 v2 遷移，支援拖曳和連線', timestamp: base.add(const Duration(minutes: 21))));
    messages.add(Message(id: '11', role: 'user', content: 'MiniMax 的 key 快過期了', timestamp: base.add(const Duration(minutes: 25))));
    messages.add(Message(id: '12', role: 'assistant', content: '提醒你更新 MiniMax API key', timestamp: base.add(const Duration(minutes: 26))));
    messages.add(Message(id: '13', role: 'user', content: '好的謝謝', timestamp: base.add(const Duration(minutes: 27))));

    // 最近 12 則（LLM 已經看得到，不會被搜尋）
    for (int i = 0; i < 12; i++) {
      messages.add(Message(
        id: 'recent_$i',
        role: i % 2 == 0 ? 'user' : 'assistant',
        content: '最近訊息 $i',
        timestamp: base.add(Duration(hours: i + 1)),
      ));
    }

    return messages;
  }

  group('isMemoryComplaint', () {
    test('直接抱怨型被偵測', () {
      expect(MemoryRecallService.isMemoryComplaint('你忘記了我要用 MiniMax'), isTrue);
      expect(MemoryRecallService.isMemoryComplaint('我之前講過要用 GraphRAG'), isTrue);
      expect(MemoryRecallService.isMemoryComplaint('不是跟你說過了嗎'), isTrue);
      expect(MemoryRecallService.isMemoryComplaint('你怎麼失憶了'), isTrue);
    });

    test('非抱怨不被偵測', () {
      expect(MemoryRecallService.isMemoryComplaint('你好嗎'), isFalse);
      expect(MemoryRecallService.isMemoryComplaint('幫我寫一段程式碼'), isFalse);
      expect(MemoryRecallService.isMemoryComplaint('今天天氣不錯'), isFalse);
    });

    test('句型匹配', () {
      expect(MemoryRecallService.isMemoryComplaint('你之前不是說要用 MiniMax 嗎'), isTrue);
      expect(MemoryRecallService.isMemoryComplaint('我們不是討論過這個了'), isTrue);
    });
  });

  group('extractKeywords', () {
    test('萃取英文專有名詞', () {
      final kws = MemoryRecallService.extractKeywords('你忘記了 MiniMax 的設定');
      final words = kws.map((k) => k.word).toList();
      expect(words, contains('MiniMax'));
    });

    test('萃取中文名詞片語', () {
      final kws = MemoryRecallService.extractKeywords('你忘記了鹿角蕨的圖片');
      final words = kws.map((k) => k.word).toList();
      expect(words, contains('鹿角蕨'));
    });

    test('萃取數字', () {
      final kws = MemoryRecallService.extractKeywords('你忘記了 7/23 討論的事');
      final words = kws.map((k) => k.word).toList();
      expect(words.any((w) => w.contains('7') && w.contains('23')), isTrue);
    });

    test('迭代時保留舊關鍵字', () {
      final kws = MemoryRecallService.extractKeywords(
        '不是這個，是 OpenAI 的',
        previousKeywords: ['MiniMax'],
      );
      final words = kws.map((k) => k.word).toList();
      expect(words, contains('MiniMax'));
      expect(words, contains('OpenAI'));
    });

    test('停用詞被過濾', () {
      final kws = MemoryRecallService.extractKeywords('你忘記了嗎');
      final words = kws.map((k) => k.word).toList();
      expect(words, isNot(contains('你')));
      expect(words, isNot(contains('忘記')));
      expect(words, isNot(contains('嗎')));
    });
  });

  group('search', () {
    test('關鍵字命中正確訊息', () {
      final messages = buildMockHistory();
      final kws = MemoryRecallService.extractKeywords('你忘記了 MiniMax 的設定');
      final fragments = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws,
      );

      expect(fragments, isNotEmpty);
      // MiniMax 相關訊息應該排前面
      expect(fragments.first.hitKeywords, contains('MiniMax'));
    });

    test('不搜尋最近 12 則', () {
      final messages = buildMockHistory();
      final kws = MemoryRecallService.extractKeywords('你忘記了最近訊息');
      final fragments = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws,
      );

      // 最近訊息不應該被搜到
      for (final f in fragments) {
        expect(f.messageId, isNot(contains('recent_')));
      }
    });

    test('排除已回覆的訊息', () {
      final messages = buildMockHistory();
      final kws = MemoryRecallService.extractKeywords('你忘記了 MiniMax');
      final fragments1 = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws,
      );

      // 第一輪找到的訊息 ID
      final excludedIds = fragments1.map((f) => f.messageId).toSet();

      // 第二輪排除第一輪的結果
      final fragments2 = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws,
        excludedMessageIds: excludedIds,
      );

      // 第二輪不應該有第一輪的訊息
      for (final f in fragments2) {
        expect(excludedIds.contains(f.messageId), isFalse);
      }
    });

    test('多關鍵字命中分數較高', () {
      final messages = buildMockHistory();
      final kws = MemoryRecallService.extractKeywords('你忘記了 MiniMax 設定');

      final fragments = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws,
      );

      // 命中多個關鍵字的訊息分數應該比較高
      if (fragments.length >= 2) {
        expect(fragments.first.score, greaterThanOrEqualTo(fragments.last.score));
      }
    });

    test('空關鍵字回傳空', () {
      final messages = buildMockHistory();
      final fragments = MemoryRecallService.search(
        allMessages: messages,
        keywords: [],
      );
      expect(fragments, isEmpty);
    });
  });

  group('buildRecallNote', () {
    test('有結果時格式化正確', () {
      final fragments = [
        RecallFragment(
          messageId: '1',
          timestamp: DateTime(2026, 7, 20, 10, 0),
          role: 'user',
          content: '我要用 MiniMax 不要 OpenAI',
          hitKeywords: ['MiniMax', 'OpenAI'],
          score: 5.0,
        ),
      ];

      final note = MemoryRecallService.buildRecallNote(fragments);
      expect(note, isNotNull);
      expect(note!, contains('記憶回溯'));
      expect(note, contains('MiniMax'));
      expect(note, contains('回覆指引'));
    });

    test('無結果時回傳安心訊息', () {
      final note = MemoryRecallService.buildRecallNote([]);
      expect(note, isNotNull);
      expect(note!, contains('資料一定還在'));
      expect(note, contains('更多線索'));
    });
  });

  group('迭代精進', () {
    test('第二輪搜尋用更多關鍵字更精準', () {
      final messages = buildMockHistory();

      // 第一輪：只搜 MiniMax
      final kws1 = MemoryRecallService.extractKeywords('你忘記了 MiniMax');
      final fragments1 = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws1,
      );
      expect(fragments1, isNotEmpty);

      // 第二輪：加入 OpenAI
      final kws2 = MemoryRecallService.extractKeywords(
        '不是這個，是 OpenAI 的',
        previousKeywords: kws1.map((k) => k.word).toList(),
      );
      final excludedIds = fragments1.map((f) => f.messageId).toSet();
      final fragments2 = MemoryRecallService.search(
        allMessages: messages,
        keywords: kws2,
        excludedMessageIds: excludedIds,
      );

      // 第二輪找到的應該包含 OpenAI 相關
      if (fragments2.isNotEmpty) {
        final hasOpenAI = fragments2.any(
          (f) => f.content.contains('OpenAI') || f.hitKeywords.contains('OpenAI'),
        );
        expect(hasOpenAI, isTrue);
      }
    });
  });
}
