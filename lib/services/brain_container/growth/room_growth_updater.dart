// room_growth_updater.dart
// 房間生長更新：memory_count 累加 + 分化條件檢查
// 建立日期: 2026-07-02
//
// P1-3 by CEO（教練 Agent）。
// 注意：rooms 表沒有 activity_score 欄位（以利沙在審查修復時簡化了 schema），
// 改用 memory_count 當活躍度指標。分化門檻 = memory_count > 20。

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';

/// 房間生長更新器。
///
/// 在每次記憶寫入後呼叫 [onMemoryAdded]，更新房間的 memory_count
/// 並檢查是否觸發分化條件。
///
/// 注意：P0 的 [MemoryWriter] 已經在 transaction 中更新了 memory_count，
/// 這裡只負責檢查分化條件與記錄分化事件。
class RoomGrowthUpdater {
  final BrainDatabase database;
  RoomGrowthUpdater({required this.database});

  /// 分化門檻：房間記憶數超過此值時觸發分化檢查
  static const int subdivisionThreshold = 20;

  /// 記憶寫入後更新房間生長狀態。
  ///
  /// 回傳更新結果，包含是否觸發分化。
  Future<RoomGrowthUpdateResult> onMemoryAdded(BrainRoom room) async {
    final db = database.db;
    final roomName = room.name;

    // 讀取當前房間狀態
    final rows = db.select(
      'SELECT memory_count, subdivision_count FROM rooms WHERE room = ?',
      [roomName],
    );

    if (rows.isEmpty) {
      // rooms 表沒有這個房間的記錄（理論上 seed data 應該有）
      return RoomGrowthUpdateResult(
        room: room,
        memoryCount: 0,
        subdivisionCount: 0,
        subdivisionTriggered: false,
      );
    }

    final memoryCount = rows.first['memory_count'] as int? ?? 0;
    final subdivisionCount = rows.first['subdivision_count'] as int? ?? 0;

    // 檢查分化條件
    final shouldSubdivide = memoryCount >= subdivisionThreshold &&
        (memoryCount - subdivisionThreshold) % subdivisionThreshold == 0;

    if (shouldSubdivide) {
      // 記錄分化事件
      final now = DateTime.now().millisecondsSinceEpoch;
      final eventId = '${now}_subdiv_$roomName';

      db.execute(
        'INSERT INTO subdivision_events '
        '(id, room, reason, memories_before, memories_after, new_sub_categories, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          eventId,
          roomName,
          'auto_threshold',
          memoryCount - 1,
          memoryCount,
          null, // new_sub_categories 未定，未來由 LLM 生成
          now,
        ],
      );

      // 更新 rooms 表的 subdivision_count
      db.execute(
        'UPDATE rooms SET subdivision_count = subdivision_count + 1, '
        'last_subdivision_at = ?, updated_at = ? '
        'WHERE room = ?',
        [now, now, roomName],
      );

      return RoomGrowthUpdateResult(
        room: room,
        memoryCount: memoryCount,
        subdivisionCount: subdivisionCount + 1,
        subdivisionTriggered: true,
        subdivisionEventId: eventId,
      );
    }

    return RoomGrowthUpdateResult(
      room: room,
      memoryCount: memoryCount,
      subdivisionCount: subdivisionCount,
      subdivisionTriggered: false,
    );
  }

  /// 取得所有房間的生長狀態
  Future<List<RoomState>> getAllRoomStates() async {
    final db = database.db;
    final rows = db.select(
      'SELECT room, memory_count, subdivision_count, last_subdivision_at, updated_at '
      'FROM rooms ORDER BY memory_count DESC',
    );

    return rows.map((row) {
      return RoomState(
        room: BrainRoom.fromStringOrDefault(row['room'] as String?),
        memoryCount: row['memory_count'] as int? ?? 0,
        subdivisionCount: row['subdivision_count'] as int? ?? 0,
        lastSubdivisionAt: row['last_subdivision_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );
    }).toList();
  }

  /// 取得需要分化的房間（memory_count >= threshold）
  Future<List<RoomState>> getRoomsNeedingSubdivision() async {
    final all = await getAllRoomStates();
    return all.where((r) => r.memoryCount >= subdivisionThreshold).toList();
  }
}

/// 房間生長更新結果
class RoomGrowthUpdateResult {
  final BrainRoom room;
  final int memoryCount;
  final int subdivisionCount;
  final bool subdivisionTriggered;
  final String? subdivisionEventId;

  const RoomGrowthUpdateResult({
    required this.room,
    required this.memoryCount,
    required this.subdivisionCount,
    required this.subdivisionTriggered,
    this.subdivisionEventId,
  });

  @override
  String toString() =>
      'RoomGrowthUpdateResult($room, count=$memoryCount, subdiv=$subdivisionCount, '
      'triggered=$subdivisionTriggered)';
}

/// 房間狀態快照
class RoomState {
  final BrainRoom room;
  final int memoryCount;
  final int subdivisionCount;
  final int? lastSubdivisionAt;
  final int? updatedAt;

  const RoomState({
    required this.room,
    required this.memoryCount,
    required this.subdivisionCount,
    this.lastSubdivisionAt,
    this.updatedAt,
  });

  @override
  String toString() =>
      'RoomState($room, count=$memoryCount, subdiv=$subdivisionCount)';
}
