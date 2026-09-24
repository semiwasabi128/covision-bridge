// connection_type.dart
// 記憶連結類型 enum
// 建立日期: 2026-07-02

/// 記憶之間的連結類型。
enum ConnectionType {
  /// 向量相似度聚類
  strongTie,

  /// 概念共振
  weakTie,

  /// 時序連結
  temporalTie,

  /// 意圖連結
  intentionTie,

  /// [教練 Agent 2026-08-08] Transurfing：門的連結
  /// from_memory 是一扇門（從 to_memory 這條水流分出來的）
  doorTie,

  /// [教練 Agent 2026-08-08] Transurfing：橋的連結
  /// from_memory 可以從 to_memory 的門回來接續
  bridgeTie;

  /// 存入 SQLite 時使用的值
  String get dbValue => name;

  /// 從 SQLite 讀回時解析（找不到時 throw StateError）。
  static ConnectionType fromDb(String v) =>
      values.firstWhere((e) => e.name == v);

  /// 從 SQLite 讀回時嘗試解析，找不到時回傳 null（不 throw）。
  static ConnectionType? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從 SQLite 讀回時解析，找不到時回傳 [defaultValue]（不 throw）。
  static ConnectionType fromDbOrDefault(String? v,
      {ConnectionType defaultValue = ConnectionType.weakTie}) {
    return tryFromDb(v) ?? defaultValue;
  }
}
