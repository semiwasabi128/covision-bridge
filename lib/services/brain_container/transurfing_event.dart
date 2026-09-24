// [教練 Agent 2026-08-08] Transurfing 事件 — Layer C 沉浸層觸發
//
// 當 Transurfing Engine 發生重要事件時（水流匯入、門打開、橋建成），
// 透過此 broadcaster 通知 UI 層顯示沉浸式動畫。
//
// 設計：
// - 使用 ChangeNotifier 模式，UI widget 監聽變化
// - 事件帶時間戳，UI 自動退場
// - GPU 友善：粒子數上限 4096，動畫 ≤ 2.5 秒

import 'package:flutter/foundation.dart';

/// Transurfing 沉浸層事件類型
enum TransurfingEventType {
  /// 水流匯入——一條水流完成，成果落地
  streamConfluence,

  /// 門打開——新的門被創建
  doorOpened,

  /// 橋建成——跨水流連結建立
  bridgeFormed,

  /// 水流恢復——從橋回來接續
  streamResumed,
}

/// 一次 Transurfing 沉浸層事件
class TransurfingEvent {
  final TransurfingEventType type;
  final String title;
  final String? bridgeNote;
  final DateTime timestamp;

  TransurfingEvent({
    required this.type,
    required this.title,
    this.bridgeNote,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 動畫持續時間（毫秒）——不同事件有不同的節奏
  int get durationMs => switch (type) {
        TransurfingEventType.streamConfluence => 2500,
        TransurfingEventType.doorOpened => 1800,
        TransurfingEventType.bridgeFormed => 2200,
        TransurfingEventType.streamResumed => 1500,
      };
}

/// Transurfing 事件廣播器
///
/// TransurfingEngine 在關鍵操作後呼叫 broadcast()，
/// UI 層的沉浸式 overlay 監聽此物件。
class TransurfingEventBroadcaster extends ChangeNotifier {
  TransurfingEventBroadcaster._();
  static final TransurfingEventBroadcaster instance =
      TransurfingEventBroadcaster._();

  TransurfingEvent? _lastEvent;
  TransurfingEvent? get lastEvent => _lastEvent;

  /// 發出一個事件
  void broadcast(TransurfingEvent event) {
    _lastEvent = event;
    debugPrint(
      '[TransurfingEvent] ${event.type.name}: ${event.title}'
      '${event.bridgeNote != null ? ' — ${event.bridgeNote}' : ''}',
    );
    notifyListeners();
  }

  /// 清除事件（動畫結束後呼叫）
  void clear() {
    _lastEvent = null;
    notifyListeners();
  }
}
