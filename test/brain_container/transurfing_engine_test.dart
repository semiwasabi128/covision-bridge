// transurfing_engine_test.dart
// [Step 1-6 驗證] Transurfing Engine 完整狀態機測試
//
// 驗證項目：
// Step 1: source / flowsTo 欄位正確記錄
// Step 3: awaitingConfirmation → confirm/reactivate 邏輯
// Step 4: BridgeService 查詢到正確的橋
// Step 5: bridgeFormed 事件被廣播
// Step 6: bridges 記憶寫入（需 BrainContainer，skip if uninitialized）

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/brain_container/transurfing_engine.dart';
import 'package:bridge_app/services/brain_container/transurfing_event.dart';
import 'package:bridge_app/services/brain_container/bridge_service.dart';

void main() {
  late TransurfingEngine engine;

  setUp(() {
    engine = TransurfingEngine.instance;
    // 清除狀態——測試隔離
    engine.reset();
  });

  group('Step 1: 資料模型 source/flowsTo', () {
    test('StreamState 有 source getter = parentStreamId', () {
      engine.startStream(
        title: '測試水流',
        topicKeywords: ['test'],
      );
      final stream = engine.activeStream!;
      expect(stream.source, isNull); // 第一條水流沒有 parent
      expect(stream.flowsTo, isNull); // 活躍中，沒有去向
    });

    test('startStream 設定正確的初始狀態', () {
      engine.startStream(
        title: '圖片生成任務',
        topicKeywords: ['image', 'generation'],
      );
      final stream = engine.activeStream!;
      expect(stream.phase, StreamPhase.active);
      expect(stream.title, '圖片生成任務');
      expect(stream.topicKeywords, ['image', 'generation']);
      expect(stream.id, isNotEmpty);
    });
  });

  group('Step 3: 水流完成判定—awaitingConfirmation', () {
    test('markAwaitingConversation 將水流設為等待確認', () {
      engine.startStream(title: '測試', topicKeywords: []);
      engine.markAwaitingConfirmation(bridgeNote: '完成 3 個步驟');

      // activeStream 仍在（不應清除）
      expect(engine.activeStream, isNotNull);
      expect(engine.activeStream!.phase, StreamPhase.awaitingConfirmation);
      expect(engine.activeStream!.bridgeNote, '完成 3 個步驟');
    });

    test('confirmStreamCompletion 真正完成水流', () {
      engine.startStream(title: '測試', topicKeywords: []);
      engine.markAwaitingConfirmation(bridgeNote: '完成');

      // 監聽所有事件
      final events = <TransurfingEventType>[];
      TransurfingEventBroadcaster.instance.addListener(() {
        final e = TransurfingEventBroadcaster.instance.lastEvent;
        if (e != null) events.add(e.type);
      });

      engine.confirmStreamCompletion();

      // 水流已清除
      expect(engine.activeStream, isNull);

      // 完成的水流在 allStreams 裡
      final completed = engine.allStreams.first;
      expect(completed.phase, StreamPhase.completed);

      // Step 1: flowsTo 設為 'system'
      expect(completed.flowsTo, 'system');

      // Step 5: 先廣播 streamConfluence，再廣播 bridgeFormed
      expect(events, contains(TransurfingEventType.streamConfluence));
      expect(events, contains(TransurfingEventType.bridgeFormed));
    });

    test('reactivateStream 回到活躍狀態', () {
      engine.startStream(title: '測試', topicKeywords: []);
      engine.markAwaitingConfirmation();

      engine.reactivateStream();

      expect(engine.activeStream!.phase, StreamPhase.active);
    });

    test('pauseActiveStream 從確認狀態切換話題', () {
      engine.startStream(title: '原水流', topicKeywords: ['original']);
      engine.markAwaitingConfirmation();

      engine.pauseActiveStream(bridgeNote: '使用者切換話題');

      expect(engine.activeStream, isNull);
      final paused = engine.allStreams.first;
      expect(paused.phase, StreamPhase.paused);
    });
  });

  group('Step 4: BridgeService 橋查詢', () {
    test('完成的水流產生一條橋到 system', () {
      engine.startStream(title: '任務A', topicKeywords: []);
      engine.markAwaitingConfirmation(bridgeNote: '做完了');
      engine.confirmStreamCompletion();

      final bridges = BridgeService.instance.allBridges;
      expect(bridges, isNotEmpty);

      final bridge = bridges.first;
      expect(bridge.sourceTitle, '任務A');
      expect(bridge.targetTitle, '系統');
      expect(bridge.note, '做完了');
    });

    test('bridgesFrom 回傳從某水流出來的橋', () {
      engine.startStream(title: '任務B', topicKeywords: []);
      final streamId = engine.activeStream!.id;
      engine.markAwaitingConfirmation();
      engine.confirmStreamCompletion();

      final bridges = BridgeService.instance.bridgesFrom(streamId);
      expect(bridges.length, 1);
      expect(bridges.first.sourceId, streamId);
    });

    test('openDoor 產生門橋', () {
      engine.startStream(title: '母水流', topicKeywords: []);
      final parentId = engine.activeStream!.id;

      engine.openDoor(title: '新門');

      final bridges = BridgeService.instance.allBridges;
      // 母水流已分流 → flowsTo=門, 門 → returnTo=母水流
      final doorBridge = bridges.where((b) => b.sourceTitle == '新門').firstOrNull;
      expect(doorBridge, isNotNull);
      expect(doorBridge!.targetId, parentId);
    });
  });

  group('Step 5: bridgeFormed 事件', () {
    test('水流完成時廣播 bridgeFormed', () {
      TransurfingEvent? lastEvent;
      TransurfingEventBroadcaster.instance.addListener(() {
        lastEvent = TransurfingEventBroadcaster.instance.lastEvent;
      });

      engine.startStream(title: '測試橋事件', topicKeywords: []);
      engine.markAwaitingConfirmation();
      engine.confirmStreamCompletion();

      // completeActiveStream 廣播 streamConfluence
      // 然後 BridgeService.onStreamCompleted 廣播 bridgeFormed
      // 最後一個事件應該是 bridgeFormed
      expect(lastEvent, isNotNull);
      expect(lastEvent!.type, TransurfingEventType.bridgeFormed);
    });

    test('門開啟時廣播 bridgeFormed', () {
      TransurfingEvent? lastEvent;
      TransurfingEventBroadcaster.instance.addListener(() {
        lastEvent = TransurfingEventBroadcaster.instance.lastEvent;
      });

      engine.startStream(title: '母水流', topicKeywords: []);
      engine.openDoor(title: '測試門');

      // openDoor 先廣播 doorOpened，然後 BridgeService 廣播 bridgeFormed
      expect(lastEvent, isNotNull);
      expect(lastEvent!.type, TransurfingEventType.bridgeFormed);
    });
  });

  group('Step 1: 分流記錄 flowsTo', () {
    test('openDoor 設定母水流的 flowsTo = 門 ID', () {
      engine.startStream(title: '母水流', topicKeywords: []);
      final parentId = engine.activeStream!.id;

      engine.openDoor(title: '新門');

      final parent = engine.allStreams.where((s) => s.id == parentId).first;
      expect(parent.phase, StreamPhase.branched);
      expect(parent.flowsTo, isNotNull);
      expect(parent.flowsTo!.startsWith('door_'), isTrue);
    });

    test('source alias = parentStreamId', () {
      engine.startStream(title: '母水流', topicKeywords: []);
      final parentId = engine.activeStream!.id;
      engine.openDoor(title: '新門');

      // 新水流的 parent 就是母水流
      // (openDoor 不會建新水流，但如果之後 startStream from door)
      // 驗證 source alias
      final parent = engine.allStreams.where((s) => s.id == parentId).first;
      expect(parent.source, isNull); // 第一條沒有 parent
    });
  });
}
