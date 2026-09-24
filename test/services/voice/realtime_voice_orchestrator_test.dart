// realtime_voice_orchestrator_test.dart
//
// 快答慢想雙軌協調器測試——不碰真 LLM/Kokoro/afplay，
// 快軌注入 mock、TTS 用 fake player 觀察行為。
//
// 2026-08-30 小葵

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/tts/kokoro_tts_service.dart';
import 'package:bridge_app/services/voice/native_audio_bytes_player.dart';
import 'package:bridge_app/services/voice/realtime_voice_orchestrator.dart';

/// 假播放器——記錄每次 play，立即完成
class _FakePlayer implements NativeAudioBytesPlayer {
  final List<String> played = [];
  int stopCount = 0;

  @override
  Future<void> play(Uint8List bytes, {String extension = 'wav'}) async {
    // bytes 內容無法直接判讀文字，用 synthesize 攔截側錄
  }

  void recordStop() => stopCount++;

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {}

  @override
  bool get isPlaying => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 假 Kokoro——不啟動真 server，把 synthesize 的文字側錄下來
class _FakeKokoro implements KokoroTtsService {
  final List<String> synthesized = [];
  bool running = true;

  @override
  Future<KokoroTtsResult> synthesize(KokoroTtsRequest request) async {
    synthesized.add(request.text);
    return KokoroTtsResult(audioBytes: Uint8List(0));
  }

  @override
  Future<bool> startServer({String? projectRoot}) async => true;

  @override
  Future<void> stopServer() async {}

  @override
  Future<void> dispose() async {}

  @override
  bool get isRunning => running;

  @override
  String get lastError => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('快軌先行——fastReplyReady 事件先於 fullReplyReady', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    final events = <RealtimeVoiceEventType>[];
    final fastDone = Completer<void>();
    final slowDone = Completer<void>();

    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return '答案是重力。<emotion>amused</emotion>';
      },
    );
    orch.events.listen((e) {
      events.add(e.type);
      if (e.type == RealtimeVoiceEventType.fastReplyReady) fastDone.complete();
      if (e.type == RealtimeVoiceEventType.fullReplyReady) slowDone.complete();
    });
    await orch.start();

    orch.onUserTurnComplete(
      '為什麼蘋果會往下掉？',
      onSlowLane: (t) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return '答案是重力。重力是地球質量造成的吸引力，牛頓因此提出萬有引力定律。';
      },
    );

    await fastDone.future;
    await slowDone.future;
    await Future.delayed(const Duration(milliseconds: 100));

    final fastIdx = events.indexOf(RealtimeVoiceEventType.fastReplyReady);
    final fullIdx = events.indexOf(RealtimeVoiceEventType.fullReplyReady);
    expect(fastIdx, greaterThanOrEqualTo(0));
    expect(fullIdx, greaterThan(fastIdx), reason: '快軌必須先出聲');
    orch.dispose();
  });

  test('慢軌接續朗讀——跳過快軌已念的重點句', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) async => '答案是重力。',
    );
    await orch.start();

    orch.onUserTurnComplete(
      '為什麼蘋果會往下掉？',
      onSlowLane: (t) async =>
          '答案是重力。重力是地球質量造成的吸引力。牛頓因此提出萬有引力定律。',
    );

    // 等雙軌都完成 + TTS 佇列消化
    await Future.delayed(const Duration(milliseconds: 300));

    // 索引 0=填充音「嗯」、1=快軌重點；後續不得再包含「答案是重力」
    expect(kokoro.synthesized[1], contains('答案是重力'));
    final rest = kokoro.synthesized.skip(2).join('|');
    expect(rest, isNot(contains('答案是重力')),
        reason: '慢軌接續時不應重念快軌重點');
    orch.dispose();
  });

  test('插嘴——TTS 佇列 flush、後續慢軌結果作廢', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) async => '先講結論。',
    );
    await orch.start();

    final synthesizedBefore = <String>[];
    orch.onUserTurnComplete(
      '長問題',
      onSlowLane: (t) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return '這是慢軌的完整回答，有很多句。第二句也在這裡。';
      },
    );
    synthesizedBefore.addAll(kokoro.synthesized);

    // 快軌還在念時使用者插嘴
    await Future.delayed(const Duration(milliseconds: 10));
    orch.onBargeIn();

    await Future.delayed(const Duration(milliseconds: 400));
    // 插嘴後不再有新的 synthesize（慢軌結果被世代作廢）
    final synthesizedAfter = kokoro.synthesized.length;
    expect(player.stopCount, greaterThan(0), reason: '插嘴必須停播放');
    await Future.delayed(const Duration(milliseconds: 100));
    expect(kokoro.synthesized.length, synthesizedAfter,
        reason: '插嘴後不得再合成新句');
    orch.dispose();
  });

  test('快軌失敗不影響慢軌——雙軌互為保險', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    final fullReady = Completer<void>();
    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) => throw Exception('快軌掛了'),
    );
    orch.events.listen((e) {
      if (e.type == RealtimeVoiceEventType.fullReplyReady) {
        fullReady.complete();
      }
    });
    await orch.start();

    orch.onUserTurnComplete(
      '問題',
      onSlowLane: (t) async => '慢軌完整回答。',
    );

    await fullReady.future.timeout(const Duration(seconds: 2));
    await Future.delayed(const Duration(milliseconds: 100));
    expect(kokoro.synthesized, isNotEmpty,
        reason: '快軌失敗時慢軌結果仍要念出來');
    orch.dispose();
  });

  test('切句——標點切句、超長強制切', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) async => '無',
    );
    await orch.start();

    final long =
        '這是一個沒有標點的超長句子'.padRight(80, '字') + '。接著第二句。';
    orch.onUserTurnComplete(
      'q',
      onSlowLane: (t) async => long,
    );

    await Future.delayed(const Duration(milliseconds: 900));
    // 至少切成 2 段（60 字強制切 + 剩餘）
    expect(kokoro.synthesized.length, greaterThanOrEqualTo(2));
    orch.dispose();
  });

  test('backchannel——只接話，不派慢軌', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    var slowLaneCalled = false;
    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) async =>
          '<type>backchannel</type><emotion>neutral</emotion>什麼事？',
    );
    await orch.start();

    orch.onUserTurnComplete(
      '你知道嗎？',
      onSlowLane: (t) async {
        slowLaneCalled = true;
        return '不應該被呼叫';
      },
    );

    await Future.delayed(const Duration(milliseconds: 300));
    expect(slowLaneCalled, false, reason: 'backchannel 不派慢軌');
    // [2026-08-31] floor-hold「嗯」先播——快軌接話在其後
    expect(kokoro.synthesized, contains('什麼事？'));
    expect(kokoro.synthesized.first, '嗯');
    orch.dispose();
  });

  test('structure——骨架先出聲，慢軌照發', () async {
    final player = _FakePlayer();
    final kokoro = _FakeKokoro();
    var slowLaneCalled = false;
    final orch = RealtimeVoiceOrchestrator(
      player: player as NativeAudioBytesPlayer,
      kokoro: kokoro as KokoroTtsService,
      fastLaneCall: (t, ctx) async =>
          '<type>structure</type><emotion>amused</emotion>這有三個原因，我一個一個說。',
    );
    await orch.start();

    orch.onUserTurnComplete(
      '為什麼專案會延遲？',
      onSlowLane: (t) async {
        slowLaneCalled = true;
        return '第一個原因是需求變更。第二個原因是人力不足。第三個原因是測試時間被壓縮。';
      },
    );

    await Future.delayed(const Duration(milliseconds: 300));
    expect(slowLaneCalled, true, reason: 'structure 要派慢軌織內容');
    expect(kokoro.synthesized[1], contains('三個原因'));
    orch.dispose();
  });

  test('parseFastLaneReply——無標籤容錯為 direct，速度 1.0', () {
    final r = parseFastLaneReply('直接回答。');
    expect(r.type, FastLaneType.direct);
    expect(r.text, '直接回答。');
    expect(r.speed, 1.0);
  });

  test('parseFastLaneReply——backchannel 帶放慢語速', () {
    final r = parseFastLaneReply(
        '<type>backchannel</type><emotion>neutral</emotion>怎麼了？');
    expect(r.type, FastLaneType.backchannel);
    expect(r.text, '怎麼了？');
    expect(r.emotion, 'neutral');
    expect(r.speed, lessThan(1.0), reason: '接話要放慢');
  });

  group('splitNonverbalTokens — 非語言擬聲拆分 v2', () {
    test('括號框住的笑聲——零歧義切出', () {
      final parts = splitNonverbalTokens('（哈哈）你猜怎麼著');
      expect(parts.first.isNonverbal, true);
      expect(parts.first.text, '哈哈');
      expect(parts.first.weight, 2);
      expect(parts.last.text, '你猜怎麼著');
      expect(parts.last.isNonverbal, false);
    });

    test('長笑聲權重更高——哈～哈哈哈～哈哈', () {
      final parts = splitNonverbalTokens('（哈～哈哈哈～哈哈）真的假的');
      expect(parts.first.isNonverbal, true);
      expect(parts.first.weight, 6, reason: '6 個哈=展開的笑');
      expect(parts.first.text, contains('哈哈哈'));
    });

    test('無括號連續笑聲 run 也切出', () {
      final parts = splitNonverbalTokens('哈哈，你猜怎麼著');
      expect(parts.first.isNonverbal, true);
      expect(parts.first.text, '哈哈');
    });

    test('括號內是普通註記→不當聲音', () {
      final parts = splitNonverbalTokens('這個（技術上來說）不對');
      expect(parts.every((p) => !p.isNonverbal), true);
    });

    test('句中嘆氣也切出', () {
      final parts = splitNonverbalTokens('唉，這就很麻煩了');
      expect(parts.first.isNonverbal, true);
      expect(parts.first.text, '唉');
    });

    test('詞中的字不誤拆（哈士奇）', () {
      final parts = splitNonverbalTokens('我養了一隻哈士奇');
      expect(parts.length, 1);
      expect(parts.first.isNonverbal, false);
    });

    test('無擬聲原樣返回', () {
      final parts = splitNonverbalTokens('直接回答。');
      expect(parts.single.isNonverbal, false);
    });
  });
}
