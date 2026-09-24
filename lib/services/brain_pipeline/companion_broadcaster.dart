// companion_broadcaster.dart
// Sprint 0 — 夥伴狀態廣播介面
// Sprint 7 — 實作 LocalCompanionBroadcaster + BrainReflectionSnapshot
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 管線完成分析後呼叫 [broadcast]，桌面夥伴或其他訂閱者
// 透過 [stream] 接收更新。
//
// Sprint 7 的 LocalCompanionBroadcaster 用 in-process StreamController.broadcast()，
// 讓多個訂閱者同時監聽。熱重載時不會重複訂閱（broadcast stream 可重複 listen）。

import 'dart:async';

import '../../models/transurfing_brain.dart';

/// 夥伴狀態廣播的快照——包含 reflection + 夥伴表情 + 觸發原因。
///
/// 設計原因：廣播時不只要傳 reflection，還要傳夥伴的 mood/gait/voiceTone
/// 和觸發原因，避免訂閱者還要自己計算。
class BrainReflectionSnapshot {
  /// 當輪的 BrainReflection。
  final BrainReflection reflection;

  /// 夥伴表情（含 gait / voiceTone，Sprint 7 由 CompanionMoodMapper 填入）。
  final CompanionExpression companionExpression;

  /// 觸發原因（一句話，說明為什麼夥伴是這個狀態）。
  final String triggerReason;

  /// 廣播時間戳。
  final DateTime timestamp;

  const BrainReflectionSnapshot({
    required this.reflection,
    required this.companionExpression,
    required this.triggerReason,
    required this.timestamp,
  });
}

/// 夥伴狀態廣播介面。
///
/// 管線完成分析後呼叫 [broadcast]，桌面夥伴或其他訂閱者
/// 透過 [stream] 接收更新。
abstract class CompanionBroadcaster {
  /// 廣播一次 BrainReflection 更新。
  void broadcast(BrainReflection reflection);

  /// 訂閱廣播流。Sprint 7 的 LocalCompanionBroadcaster 用 StreamController.broadcast()。
  Stream<BrainReflection> get stream;
}

/// 空實作——Sprint 0~6 使用。
///
/// broadcast 什麼都不做，stream 永遠是空的。
/// Sprint 7 替換為 LocalCompanionBroadcaster 即可。
class NoopCompanionBroadcaster implements CompanionBroadcaster {
  @override
  void broadcast(BrainReflection reflection) {
    // no-op
  }

  @override
  Stream<BrainReflection> get stream => const Stream.empty();
}

/// Sprint 7：in-process 廣播實作。
///
/// 用 [StreamController.broadcast()] 讓多個訂閱者同時監聽。
/// 熱重載不會重複訂閱——broadcast stream 每次 listen 都是獨立的。
///
/// 使用方式：
/// ```dart
/// final broadcaster = LocalCompanionBroadcaster();
/// pipeline = TransurfingPipeline(broadcaster: broadcaster);
/// broadcaster.stream.listen((reflection) { ... });
/// ```
class LocalCompanionBroadcaster implements CompanionBroadcaster {
  final StreamController<BrainReflection> _controller =
      StreamController<BrainReflection>.broadcast();

  @override
  void broadcast(BrainReflection reflection) {
    _controller.add(reflection);
  }

  @override
  Stream<BrainReflection> get stream => _controller.stream;

  /// 關閉 stream（dispose 時呼叫）。
  void dispose() {
    _controller.close();
  }
}
