// chat_tts_handler_test.dart
// 測試 ChatTtsHandler 的狀態管理邏輯（不測試實際 TTS 引擎）。
//
// FlutterTts 建構時會建立 platform channel，需要 TestWidgetsFlutterBinding
// 才能在測試環境中建立。我們驗證 handler 的初始狀態、ValueNotifier 行為、
// 以及 dispose 後正常結束。

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/screens/chat/handlers/chat_tts_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatTtsHandler — 狀態管理', () {
    test('speaking 初始為 false', () {
      final handler = ChatTtsHandler(onError: (_) {});
      expect(handler.speaking.value, isFalse);
      handler.speaking.dispose();
    });

    test('handler 可建立', () {
      final handler = ChatTtsHandler(onError: (_) {});
      expect(handler, isNotNull);
      handler.speaking.dispose();
    });

    test('speaking 是 ValueNotifier<bool>', () {
      final handler = ChatTtsHandler(onError: (_) {});
      expect(handler.speaking, isA<ValueNotifier<bool>>());
      handler.speaking.dispose();
    });

    test('stop 會將 speaking 設為 false', () async {
      final handler = ChatTtsHandler(onError: (_) {});
      // 即使沒有 init，stop 應該安全地將 speaking 設為 false
      await handler.stop();
      expect(handler.speaking.value, isFalse);
      handler.speaking.dispose();
    });

    test('dispose 可正常呼叫', () async {
      final handler = ChatTtsHandler(onError: (_) {});
      await handler.dispose();
      // dispose 後 speaking notifier 已被 dispose，不會拋出
      expect(true, isTrue); // 到這裡代表 dispose 成功
    });
  });
}
