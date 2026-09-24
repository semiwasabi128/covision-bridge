// system_routine_recorder_test.dart
// [刀 5 延伸 SR.5] 全電腦示範錄製——Dart 純函式部分測試

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/routines/system_routine_recorder.dart';

void main() {
  group('SystemRoutineEvent.fromMap 正規化', () {
    test('點擊事件——AX 欄位完整帶入', () {
      final e = SystemRoutineEvent.fromMap({
        'action': 'click', 't': 1234.5,
        'x': 100.0, 'y': 200.0,
        'app': 'Safari', 'window': '鹿角蕨照護',
        'role': 'AXButton', 'title': '加入購物車',
      }, 0);
      expect(e.action, 'click');
      expect(e.app, 'Safari');
      expect(e.role, 'AXButton');
      expect(e.story, '在 Safari 點了 「加入購物車」');
    });

    test('密碼框遮罩——雙保險（Swift 已遮，Dart 再驗）', () {
      final e = SystemRoutineEvent.fromMap({
        'action': 'click', 't': 1,
        'app': 'Chrome', 'role': 'AXSecureTextField',
        'title': '密碼', 'value': '****', 'masked': true,
      }, 0);
      expect(e.masked, isTrue);
      expect(e.value, '****'); // 永不洩漏
    });

    test('長值截斷 30 字（隱私鐵則）', () {
      final long = 'a' * 50;
      final e = SystemRoutineEvent.fromMap({
        'action': 'click', 't': 1,
        'app': 'Notes', 'role': 'AXTextArea', 'value': long,
      }, 0);
      expect(e.value!.length, 31); // 30 + …
      expect(e.value!.endsWith('…'), isTrue);
    });

    test('鍵盤事件——修飾鍵與故事', () {
      final e = SystemRoutineEvent.fromMap({
        'action': 'key', 't': 2, 'keyCode': 36, 'mods': ['cmd'],
        'app': 'Finder',
      }, 1);
      expect(e.story, '在 Finder 按了 cmd+Return');
    });

    test('toMap round-trip——平台中立 JSON 可逆', () {
      final m = {
        'action': 'click', 't': 1.5, 'x': 10.0, 'y': 20.0,
        'app': 'Xcode', 'role': 'AXMenuItem', 'title': 'Build',
      };
      final e = SystemRoutineEvent.fromMap(m, 7);
      final out = e.toMap();
      final back = SystemRoutineEvent.fromMap(out, 7);
      expect(back.app, e.app);
      expect(back.title, e.title);
      expect(back.seq, 7);
    });
  });

  group('SystemRoutineRecorder 初始狀態', () {
    test('未錄製——start 前狀態乾淨', () {
      final r = SystemRoutineRecorder.instance;
      expect(r.isRecording, isFalse);
      expect(r.eventCount, 0);
      expect(r.story, isEmpty);
      expect(r.export()['version'], 1);
    });
  });
}
