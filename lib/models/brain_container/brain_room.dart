// brain_room.dart
// 大腦容器六大房間 enum
// 建立日期: 2026-07-02

/// 大腦容器六大房間。
///
/// 每個房間對應一種記憶的生態位：水流軌跡、門的紀錄、擺錘警報、
/// 心腦對話、靈魂頻率、跨島連結。
enum BrainRoom {
  /// 水流軌跡 — 日常流動與能量變化
  stream,

  /// 門的紀錄 — 機會出現、進入、錯過
  doors,

  /// 擺錘警報 — 內在張力、壓力、比較
  pendulums,

  /// 心腦對話 — 理性與感受的交會
  heartMind,

  /// 靈魂頻率 — 發光、判斷、共振
  fraile,

  /// 跨島連結 — 主動連結、奇異連結、時序共振
  bridges;

  /// 中文顯示名稱
  String get displayName => switch (this) {
        BrainRoom.stream => '水流軌跡',
        BrainRoom.doors => '門的紀錄',
        BrainRoom.pendulums => '擺錘警報',
        BrainRoom.heartMind => '心腦對話',
        BrainRoom.fraile => '靈魂頻率',
        BrainRoom.bridges => '跨島連結',
      };

  /// Emoji 圖示
  String get icon => switch (this) {
        BrainRoom.stream => '🌊',
        BrainRoom.doors => '🚪',
        BrainRoom.pendulums => '🔔',
        BrainRoom.heartMind => '💗',
        BrainRoom.fraile => '✨',
        BrainRoom.bridges => '🌉',
      };

  /// 從字串解析（大小寫敏感，匹配 enum name）。
  /// 找不到時擲 [ArgumentError]。
  static BrainRoom fromString(String value) {
    for (final room in BrainRoom.values) {
      if (room.name == value) return room;
    }
    throw ArgumentError('Unknown BrainRoom: $value');
  }

  /// 從字串嘗試解析，找不到時回傳 null（不 throw）。
  static BrainRoom? tryParse(String? value) {
    if (value == null) return null;
    for (final room in BrainRoom.values) {
      if (room.name == value) return room;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]（不 throw）。
  static BrainRoom fromStringOrDefault(String? value,
      {BrainRoom defaultValue = BrainRoom.stream}) {
    return tryParse(value) ?? defaultValue;
  }
}
