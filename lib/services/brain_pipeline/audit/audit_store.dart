// audit_store.dart
// Sprint 8 — 跨對話擺錘審計 + clip 消費計數器（in-memory，可注入 Clock）
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 設計原則：
// - 獨立於 BrainContainer 介面（CEO 修正：不擴充既有 adapter）
// - 可注入 Clock（DateTime Function()），測試可 mock 日期
// - 純 in-memory，重啟歸零；未來 1A 落地可換 SQLite 實作
//
// 混合策略的「兩種來源各自計數」：
// - ruleMatch 和 aiInferred 分開記，不合併
// - Panel 可選擇顯示總計或按來源分開

import '../../../models/transurfing_brain.dart';

/// 一天的擺錘審計紀錄。
class DailyPendulumAudit {
  /// dateKey = 'yyyy-MM-dd'
  final String dateKey;

  /// 每種擺錘類型的計數，key = PendulumSignalType.name
  final Map<String, int> ruleCounts;

  /// AI 版偵測的計數（與 ruleCounts 分開）
  final Map<String, int> aiCounts;

  /// 每種類型的 evidence quotes（前 5 條）
  final Map<String, List<String>> evidenceQuotes;

  const DailyPendulumAudit({
    required this.dateKey,
    this.ruleCounts = const {},
    this.aiCounts = const {},
    this.evidenceQuotes = const {},
  });

  /// 取得某類型的總計數（rule + ai）
  int totalCount(PendulumSignalType type) {
    return (ruleCounts[type.name] ?? 0) + (aiCounts[type.name] ?? 0);
  }

  /// 當天所有擺錘總次數
  int get grandTotal {
    int total = 0;
    for (final type in PendulumSignalType.values) {
      total += totalCount(type);
    }
    return total;
  }

  DailyPendulumAudit copyWith({
    Map<String, int>? ruleCounts,
    Map<String, int>? aiCounts,
    Map<String, List<String>>? evidenceQuotes,
  }) {
    return DailyPendulumAudit(
      dateKey: dateKey,
      ruleCounts: ruleCounts ?? this.ruleCounts,
      aiCounts: aiCounts ?? this.aiCounts,
      evidenceQuotes: evidenceQuotes ?? this.evidenceQuotes,
    );
  }
}

/// 過去 7 天的擺錘審計摘要。
class PendulumAuditSummary {
  /// 7 天的每日審計，index 0 = 最舊，index 6 = 今天
  final List<DailyPendulumAudit> days;

  /// 今天累計的 clip 消費秒數
  final int clipConsumptionSecondsToday;

  /// 是否超過 60 分鐘警示
  bool get clipOverLimit => clipConsumptionSecondsToday >= 3600;

  const PendulumAuditSummary({
    required this.days,
    this.clipConsumptionSecondsToday = 0,
  });

  /// 7 天內某類型的總計數
  int totalForType(PendulumSignalType type) {
    return days.fold(0, (sum, d) => sum + d.totalCount(type));
  }

  /// 7 天內所有擺錘總計
  int get grandTotal {
    return days.fold(0, (sum, d) => sum + d.grandTotal);
  }
}

/// Sprint 8：跨對話擺錘審計 + clip 消費的 in-memory store。
///
/// 使用方式：
/// ```dart
/// final store = AuditStore();
/// pipeline = TransurfingPipeline(auditStore: store);
/// // 每輪分析後 pipeline 自動呼叫 store.recordPendulums(...)
/// final summary = store.getAuditLast7Days();
/// ```
class AuditStore {
  /// 擺錘每日審計：dateKey → DailyPendulumAudit
  final Map<String, DailyPendulumAudit> _pendulumAudit = {};

  /// clip 消費秒數：dateKey → seconds
  final Map<String, int> _clipConsumption = {};

  /// 可注入的時鐘（測試用 mock DateTime）
  final DateTime Function() _clock;

  /// 最大 evidence quotes 保存數
  static const int _maxEvidencePerType = 5;

  AuditStore({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// 今天的 dateKey
  String get _todayKey => _formatDateKey(_clock());

  /// 格式化日期 key
  static String _formatDateKey(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)}';
  }

  // === Pendulum Audit ===

  /// 記錄一輪分析後的擺錘信號。
  void recordPendulums(List<PendulumSignal> signals) {
    final dateKey = _todayKey;
    final existing = _pendulumAudit[dateKey] ??
        DailyPendulumAudit(dateKey: dateKey);

    final newRuleCounts = Map<String, int>.from(existing.ruleCounts);
    final newAiCounts = Map<String, int>.from(existing.aiCounts);
    final newEvidence = Map<String, List<String>>.from(existing.evidenceQuotes);

    for (final signal in signals) {
      final typeName = signal.type.name;
      if (signal.source == PendulumSignalSource.aiInferred) {
        newAiCounts[typeName] = (newAiCounts[typeName] ?? 0) + 1;
      } else {
        newRuleCounts[typeName] = (newRuleCounts[typeName] ?? 0) + 1;
      }

      // 保存 evidence quote（最多 _maxEvidencePerType 條）
      final quotes = newEvidence[typeName] ?? [];
      if (quotes.length < _maxEvidencePerType && signal.evidence.isNotEmpty) {
        quotes.add(signal.evidence);
        newEvidence[typeName] = quotes;
      }
    }

    _pendulumAudit[dateKey] = existing.copyWith(
      ruleCounts: newRuleCounts,
      aiCounts: newAiCounts,
      evidenceQuotes: newEvidence,
    );
  }

  /// 取得過去 7 天的擺錘審計摘要。
  PendulumAuditSummary getAuditLast7Days() {
    final today = _clock();
    final days = <DailyPendulumAudit>[];

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final key = _formatDateKey(date);
      days.add(_pendulumAudit[key] ??
          DailyPendulumAudit(dateKey: key));
    }

    return PendulumAuditSummary(
      days: days,
      clipConsumptionSecondsToday: clipConsumptionSecondsToday,
    );
  }

  // === Clip Consumption ===

  /// 累加 clip 消費秒數
  void addClipConsumptionSeconds(int seconds) {
    if (seconds <= 0) return;
    final key = _todayKey;
    _clipConsumption[key] = (_clipConsumption[key] ?? 0) + seconds;
  }

  /// 今天的 clip 消費秒數
  int get clipConsumptionSecondsToday {
    return _clipConsumption[_todayKey] ?? 0;
  }

  /// 清除所有審計資料（測試 / reset 用）
  void clear() {
    _pendulumAudit.clear();
    _clipConsumption.clear();
  }
}
