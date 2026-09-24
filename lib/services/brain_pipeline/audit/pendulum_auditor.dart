// pendulum_auditor.dart
// Sprint 8 — 每輪分析後記錄擺錘計數到 AuditStore
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 接線點：TransurfingPipeline.analyzeAsync() 完成後呼叫。
// 純函式式的記錄器——拿 reflection，提取 pendulumSignals，寫進 store。

import '../../../models/transurfing_brain.dart';
import 'audit_store.dart';

/// 每輪分析後記錄擺錘計數。
///
/// Pipeline 在 analyzeAsync() 結尾呼叫 [record]，
/// 把當輪偵測到的 PendulumSignal 寫進 AuditStore。
class PendulumAuditor {
  final AuditStore _store;

  PendulumAuditor(this._store);

  /// 記錄一輪分析的擺錘結果。
  void record(BrainReflection reflection) {
    if (reflection.pendulumSignals.isEmpty) return;
    _store.recordPendulums(reflection.pendulumSignals);
  }
}
