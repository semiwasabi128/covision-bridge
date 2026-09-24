// routine_recorder_test.dart
// [刀 5] 示範錄製器測試——事件過濾與操作故事

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/routines/routine_recorder.dart';
import 'package:bridge_app/services/vault/canvas_event_bus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // broadcast stream 事件非同步送達——emit 後讓 event loop 跑一圈
  Future<void> flushEvents() async {
    await Future<void>.delayed(Duration.zero);
  }

  group('RoutineRecorder', () {
    test('錄製中——誕生事件計數、噪音事件忽略', () async {
      final r = RoutineRecorder.instance;
      r.start('canvas_test');

      // 誕生事件（該錄）
      CanvasEventBus.instance.emit(CanvasEventType.nodeAdded,
          nodeId: 'n1', nodeType: 'llm');
      CanvasEventBus.instance.emit(CanvasEventType.connectionAdded,
          nodeId: 'n1');
      CanvasEventBus.instance.emit(CanvasEventType.nodeParamsChanged,
          nodeId: 'n1', nodeType: 'llm');

      // 噪音事件（不該錄）
      CanvasEventBus.instance.emit(CanvasEventType.toolChanged);
      CanvasEventBus.instance.emit(CanvasEventType.nodeSelected, nodeId: 'n1');
      CanvasEventBus.instance.emit(CanvasEventType.nodeMoved, nodeId: 'n1');

      await flushEvents();
      expect(r.eventCount, 3);
      expect(r.story.length, 3);
      expect(r.story[0], contains('LLM'));
      expect(r.story[1], contains('連線'));
      expect(r.story[2], contains('參數'));

      final rec = r.stop();
      expect(rec, isNotNull);
      expect(rec!.eventCount, 3);
      expect(r.isRecording, isFalse);
    });

    test('停止後——事件流不再累積', () async {
      final r = RoutineRecorder.instance;
      r.start('c');
      CanvasEventBus.instance.emit(CanvasEventType.nodeAdded,
          nodeId: 'n1', nodeType: 'input');
      await flushEvents();
      r.stop();
      final countAfter = r.eventCount;
      CanvasEventBus.instance.emit(CanvasEventType.nodeAdded,
          nodeId: 'n2', nodeType: 'output');
      await flushEvents();
      expect(r.eventCount, countAfter); // 不增
      expect(r.isRecording, isFalse);
    });

    test('放棄——清空不影響後續', () async {
      final r = RoutineRecorder.instance;
      r.start('c');
      CanvasEventBus.instance.emit(CanvasEventType.nodeAdded,
          nodeId: 'n1', nodeType: 'text');
      await flushEvents();
      r.discard();
      expect(r.isRecording, isFalse);
      expect(r.story, isEmpty);
    });

    test('重複 start 冪等——不會雙訂閱', () async {
      final r = RoutineRecorder.instance;
      r.start('c1');
      r.start('c1'); // 第二次 no-op
      CanvasEventBus.instance.emit(CanvasEventType.nodeAdded,
          nodeId: 'n1', nodeType: 'llm');
      await flushEvents();
      expect(r.eventCount, 1); // 只算一次
      r.stop();
    });
  });
}
