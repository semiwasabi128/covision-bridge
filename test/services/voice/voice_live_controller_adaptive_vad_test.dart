// voice_live_controller_adaptive_vad_test.dart
//
// [小葵 2026-08-31] 語意自適應 VAD 單測——Blue 的 300-800ms 問題：
// 答案不是固定值，是按句尾完整度動態選。純函式直接測。

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/voice/voice_live_controller.dart';

void main() {
  group('adaptiveSilenceFor — 語意自適應沉默時長', () {
    test('問句尾（嗎/呢/？）→ 300ms 快切', () {
      expect(
        VoiceLiveController.adaptiveSilenceFor('你今天過得好嗎'),
        const Duration(milliseconds: 300),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor('那我們要怎麼辦呢'),
        const Duration(milliseconds: 300),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor('你覺得呢？'),
        const Duration(milliseconds: 300),
      );
    });

    test('語氣詞尾（吧/啦/喔/哦/嘛/呀）→ 300ms', () {
      expect(
        VoiceLiveController.adaptiveSilenceFor('就這樣吧'),
        const Duration(milliseconds: 300),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor('好啦我知道了啦'),
        const Duration(milliseconds: 300),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor('原來是這樣喔'),
        const Duration(milliseconds: 300),
      );
    });

    test('句號/驚嘆號尾 → 300ms', () {
      expect(
        VoiceLiveController.adaptiveSilenceFor('我覺得可以。'),
        const Duration(milliseconds: 300),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor('太棒了！'),
        const Duration(milliseconds: 300),
      );
    });

    test('子句中（無句尾訊號）→ 800ms 保護', () {
      expect(
        VoiceLiveController.adaptiveSilenceFor('我覺得這件事情應該要從'),
        const Duration(milliseconds: 800),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor('然後我就想說如果按照那個方法'),
        const Duration(milliseconds: 800),
      );
    });

    test('太短（<2字）→ 800ms（可能只是感嘆或雜音）', () {
      expect(
        VoiceLiveController.adaptiveSilenceFor('嗯'),
        const Duration(milliseconds: 800),
      );
      expect(
        VoiceLiveController.adaptiveSilenceFor(''),
        const Duration(milliseconds: 800),
      );
    });
  });
}
