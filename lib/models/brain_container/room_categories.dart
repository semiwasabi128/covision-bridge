// room_categories.dart
// 大腦容器六大房間的子分類 enum + 工具類
// 建立日期: 2026-07-02

import 'package:bridge_app/models/brain_container/brain_room.dart';

/// 水流軌跡房間子分類
enum StreamRoomCategory {
  smoothFlow,
  repeatedObstacle,
  synchronicity,
  energyFluctuation,

  /// [教練 Agent 2026-08-20] agent 作業快照（「使用者正在…」）——不是心理狀態，
  /// 是觀察日誌。圖譜端降為背景塵埃，不佔記憶節點主舞台。
  observation;

  String get displayName => switch (this) {
        StreamRoomCategory.smoothFlow => '順暢流動',
        StreamRoomCategory.repeatedObstacle => '重複障礙',
        StreamRoomCategory.synchronicity => '同步性事件',
        StreamRoomCategory.energyFluctuation => '能量波動',
        StreamRoomCategory.observation => '觀察日誌',
      };

  /// 嘗試從字串解析，找不到時回傳 null。
  static StreamRoomCategory? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]。
  static StreamRoomCategory fromDbOrDefault(String? v,
      {StreamRoomCategory defaultValue = StreamRoomCategory.smoothFlow}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// 門的紀錄房間子分類
enum DoorsRoomCategory {
  invitationAppeared,
  doorEntered,
  doorMissed,
  doorWaiting;

  String get displayName => switch (this) {
        DoorsRoomCategory.invitationAppeared => '邀請出現',
        DoorsRoomCategory.doorEntered => '門已進入',
        DoorsRoomCategory.doorMissed => '門已錯過',
        DoorsRoomCategory.doorWaiting => '門在等待',
      };

  /// 嘗試從字串解析，找不到時回傳 null。
  static DoorsRoomCategory? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]。
  static DoorsRoomCategory fromDbOrDefault(String? v,
      {DoorsRoomCategory defaultValue = DoorsRoomCategory.invitationAppeared}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// 擺錘警報房間子分類
enum PendulumsRoomCategory {
  mustMoment,
  anxietySource,
  comparisonTarget,
  groupPressure;

  String get displayName => switch (this) {
        PendulumsRoomCategory.mustMoment => '必須時刻',
        PendulumsRoomCategory.anxietySource => '焦慮來源',
        PendulumsRoomCategory.comparisonTarget => '比較目標',
        PendulumsRoomCategory.groupPressure => '群體壓力',
      };

  /// 嘗試從字串解析，找不到時回傳 null。
  static PendulumsRoomCategory? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]。
  static PendulumsRoomCategory fromDbOrDefault(String? v,
      {PendulumsRoomCategory defaultValue = PendulumsRoomCategory.mustMoment}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// 心腦對話房間子分類
enum HeartMindRoomCategory {
  mindSaid,
  heartFelt,
  splitMoment,
  integrationResult;

  String get displayName => switch (this) {
        HeartMindRoomCategory.mindSaid => '腦說',
        HeartMindRoomCategory.heartFelt => '心感',
        HeartMindRoomCategory.splitMoment => '分裂時刻',
        HeartMindRoomCategory.integrationResult => '整合結果',
      };

  /// 嘗試從字串解析，找不到時回傳 null。
  static HeartMindRoomCategory? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]。
  static HeartMindRoomCategory fromDbOrDefault(String? v,
      {HeartMindRoomCategory defaultValue = HeartMindRoomCategory.mindSaid}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// 靈魂頻率房間子分類
enum FraileRoomCategory {
  makesMeGlow,
  judgmentMoment,
  resonance,
  pseudoFraile;

  String get displayName => switch (this) {
        FraileRoomCategory.makesMeGlow => '讓我發光',
        FraileRoomCategory.judgmentMoment => '判斷時刻',
        FraileRoomCategory.resonance => '共振',
        FraileRoomCategory.pseudoFraile => '偽頻率',
      };

  /// 嘗試從字串解析，找不到時回傳 null。
  static FraileRoomCategory? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]。
  static FraileRoomCategory fromDbOrDefault(String? v,
      {FraileRoomCategory defaultValue = FraileRoomCategory.makesMeGlow}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// 跨島連結房間子分類
enum BridgesRoomCategory {
  activeBridging,
  weirdConnection,
  temporalResonance,
  analogicalInsight;

  String get displayName => switch (this) {
        BridgesRoomCategory.activeBridging => '主動連結',
        BridgesRoomCategory.weirdConnection => '奇異連結',
        BridgesRoomCategory.temporalResonance => '時序共振',
        BridgesRoomCategory.analogicalInsight => '類比洞察',
      };

  /// 嘗試從字串解析，找不到時回傳 null。
  static BridgesRoomCategory? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從字串解析，找不到時回傳 [defaultValue]。
  static BridgesRoomCategory fromDbOrDefault(String? v,
      {BridgesRoomCategory defaultValue = BridgesRoomCategory.activeBridging}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// 房間子分類工具類。
///
/// 根據 [BrainRoom] 取得對應子分類 enum 的名稱字串，
/// 用於動態判斷某筆記憶的 subCategory 屬於哪個 enum。
class BrainRoomCategory {
  BrainRoomCategory._();

  /// 回傳指定房間對應的子分類 enum 名稱（Dart enum type name）。
  static String getCategoryName(BrainRoom room) => switch (room) {
        BrainRoom.stream => 'StreamRoomCategory',
        BrainRoom.doors => 'DoorsRoomCategory',
        BrainRoom.pendulums => 'PendulumsRoomCategory',
        BrainRoom.heartMind => 'HeartMindRoomCategory',
        BrainRoom.fraile => 'FraileRoomCategory',
        BrainRoom.bridges => 'BridgesRoomCategory',
      };
}
