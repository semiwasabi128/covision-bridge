// routine_recorder.dart
// [刀 5 D5.1 2026-09-08] 示範錄製——「我做一遍，橋樑記住，永遠會跑」
//
// 錄的是結構化操作事件（CanvasEventBus），不是螢幕畫面——
// 重播精確、可編輯、可 diff（報告明言做得比 Grok Bot teach-a-task 好的地方）。
//
// 雙軌設計：
//   ① 操作故事（事件序列→人類可讀一行字）——顯示「你做了什麼」
//   ② 最終快照（stop 時抓畫布完整 nodes+connections）——範本本體。
//     快照法比逐事件重放穩：編輯途中改來改去（加了又刪）不影響範本正確性。
//
// 設計稿：docs/specs/2026-09-08-show-once-routine.md

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/vault/canvas_event_bus.dart';

/// 一次錄製的成果
class RoutineRecording {
  final String canvasId;
  final DateTime startedAt;
  final DateTime stoppedAt;
  final List<String> story; // 人類可讀操作故事（「加了 LLM 節點」…）
  final int eventCount;

  const RoutineRecording({
    required this.canvasId,
    required this.startedAt,
    required this.stoppedAt,
    required this.story,
    required this.eventCount,
  });
}

/// 示範錄製器——單例
class RoutineRecorder {
  RoutineRecorder._();
  static final RoutineRecorder instance = RoutineRecorder._();

  StreamSubscription<CanvasEvent>? _sub;
  bool _recording = false;
  String? _canvasId;
  DateTime? _startedAt;
  final List<String> _story = [];
  int _eventCount = 0;

  bool get isRecording => _recording;
  int get eventCount => _eventCount;
  List<String> get story => List.unmodifiable(_story);

  /// 開始錄製（冪等保護——已在錄就 no-op）
  void start(String canvasId) {
    if (_recording) return;
    _recording = true;
    _canvasId = canvasId;
    _startedAt = DateTime.now();
    _story.clear();
    _eventCount = 0;
    _sub?.cancel();
    _sub = CanvasEventBus.instance.stream.listen(_onEvent);
    debugPrint('[RoutineRecorder] 開始錄製 canvas=$canvasId');
  }

  void _onEvent(CanvasEvent e) {
    if (!_recording) return;
    // 只錄「誕生與改變」事件；載入/清除/工具切換是噪音
    final line = _storyLine(e);
    if (line == null) return;
    _eventCount++;
    _story.add(line);
    debugPrint('[RoutineRecorder] $_eventCount. $line');
  }

  String? _storyLine(CanvasEvent e) {
    switch (e.type) {
      case CanvasEventType.nodeAdded:
        return '加了 ${_nodeLabel(e.nodeType)} 節點';
      case CanvasEventType.connectionAdded:
        return '建立了連線';
      case CanvasEventType.nodeParamsChanged:
      case CanvasEventType.nodeEdited:
        return '調整了 ${_nodeLabel(e.nodeType)} 的參數';
      case CanvasEventType.nodeRemoved:
        return '刪除了 ${_nodeLabel(e.nodeType)} 節點';
      case CanvasEventType.connectionRemoved:
        return '移除了連線';
      case CanvasEventType.batchLoaded:
        return null; // 匯入不錄（那是重播不是示範）
      default:
        return null; // 其餘（doodle/toolChanged/…）對範本無意義
    }
  }

  String _nodeLabel(String? nodeType) {
    switch (nodeType) {
      case 'llm':
        return 'LLM';
      case 'imageGen':
        return '圖像生成';
      case 'input':
        return '輸入';
      case 'output':
        return '輸出';
      case 'text':
        return '文字';
      default:
        return nodeType ?? '?';
    }
  }

  /// 停止錄製——回傳成果（呼叫端接著抓畫布快照存範本）
  RoutineRecording? stop() {
    if (!_recording) return null;
    _sub?.cancel();
    _sub = null;
    _recording = false;
    final rec = RoutineRecording(
      canvasId: _canvasId ?? '',
      startedAt: _startedAt ?? DateTime.now(),
      stoppedAt: DateTime.now(),
      story: List.of(_story),
      eventCount: _eventCount,
    );
    debugPrint('[RoutineRecorder] 停止：${rec.eventCount} 個操作');
    return rec;
  }

  /// 放棄（事件清空，畫布不動）
  void discard() {
    _sub?.cancel();
    _sub = null;
    _recording = false;
    _story.clear();
    _eventCount = 0;
    debugPrint('[RoutineRecorder] 放棄錄製');
  }
}
