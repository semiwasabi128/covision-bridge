// heart_mind_store.dart
// Sprint 9 — 心腦整合 statement 的 in-memory 存取
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 獨立於 BrainContainer 介面（與 AuditStore 同策略）
// 未來 1A 落地可換 SQLite 實作
// Idempotent check：同句不重複寫

/// 一筆心腦整合紀錄。
class HeartMindRecord {
  final String statement;
  final String? mindStatement;
  final String? heartStatement;
  final String? userReply;
  final String dateKey;
  final DateTime createdAt;

  const HeartMindRecord({
    required this.statement,
    this.mindStatement,
    this.heartStatement,
    this.userReply,
    required this.dateKey,
    required this.createdAt,
  });
}

/// 心腦整合 statement 的 in-memory store。
///
/// 使用方式：
/// ```dart
/// final store = HeartMindStore();
/// await store.writeStatement(statement: '...', dateKey: '2026-07-04');
/// store.getStatementsForDate('2026-07-04'); // ['...']
/// ```
class HeartMindStore {
  /// dateKey → List<HeartMindRecord>
  final Map<String, List<HeartMindRecord>> _records = {};

  /// 可注入的時鐘
  final DateTime Function() _clock;

  HeartMindStore({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// 寫入一筆整合 statement（含 idempotent check）。
  /// 同一句 statement 同一天不重複寫。
  Future<void> writeStatement({
    required String statement,
    String? mindStatement,
    String? heartStatement,
    String? userReply,
    required String dateKey,
  }) async {
    final existing = _records[dateKey];
    if (existing != null) {
      // Idempotent check
      if (existing.any((r) => r.statement == statement)) {
        return; // 已存在，不重複寫
      }
    }

    _records.putIfAbsent(dateKey, () => []);
    _records[dateKey]!.add(HeartMindRecord(
      statement: statement,
      mindStatement: mindStatement,
      heartStatement: heartStatement,
      userReply: userReply,
      dateKey: dateKey,
      createdAt: _clock(),
    ));
  }

  /// 取得某天的所有整合 statement（按時間順序）。
  List<String> getStatementsForDate(String dateKey) {
    final records = _records[dateKey];
    if (records == null || records.isEmpty) return [];
    return records.map((r) => r.statement).toList();
  }

  /// 取得某天的完整紀錄（含 metadata）。
  List<HeartMindRecord> getRecordsForDate(String dateKey) {
    return _records[dateKey] ?? [];
  }

  /// 取得最近的整合 statement（跨天）。
  /// 回傳最近一天有紀錄的最後一筆。
  String? getLatestStatement() {
    if (_records.isEmpty) return null;
    final sortedKeys = _records.keys.toList()..sort();
    final latestKey = sortedKeys.last;
    final records = _records[latestKey]!;
    if (records.isEmpty) return null;
    return records.last.statement;
  }

  /// 清除所有紀錄（測試 / reset 用）
  void clear() {
    _records.clear();
  }
}
