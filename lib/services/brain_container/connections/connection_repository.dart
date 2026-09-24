// connection_repository.dart
// 連結 CRUD + 向量相似搜尋
// 建立日期: 2026-07-03

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/connection.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart'; // [出處戳] MemorySpeaker
import 'package:bridge_app/services/brain_container/brain_database.dart';

/// 連結資料庫操作。
///
/// 提供 connections 表的 CRUD 與向量相似搜尋。
class ConnectionRepository {
  final BrainDatabase database;
  int _uuidCounter = 0;

  ConnectionRepository({required this.database});

  /// 新增連結。
  Future<void> insert(Connection connection) async {
    final db = database.db;
    db.execute(
      'INSERT INTO connections (id, from_memory_id, to_memory_id, type, '
      'similarity, strength, reinforcement_count, created_at, '
      'last_reinforced_at, dormant, rationale, user_marked) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        connection.id,
        connection.fromMemoryId,
        connection.toMemoryId,
        connection.type.dbValue,
        connection.similarity,
        connection.strength,
        connection.reinforcementCount,
        connection.createdAt.millisecondsSinceEpoch,
        connection.lastReinforcedAt.millisecondsSinceEpoch,
        connection.dormant ? 1 : 0,
        connection.rationale,
        connection.userMarked ? 1 : 0,
      ],
    );
  }

  /// 強化已存在的連結（reinforcementCount + 1, lastReinforcedAt = now）。
  Future<void> reinforce(String connectionId) async {
    final db = database.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'UPDATE connections SET reinforcement_count = reinforcement_count + 1, '
      'last_reinforced_at = ? WHERE id = ?',
      [now, connectionId],
    );
  }

  /// 查找：from -> ? 的所有連結。
  Future<List<Connection>> findByFrom(String memoryId) async {
    final db = database.db;
    final rows = db.select(
      'SELECT * FROM connections WHERE from_memory_id = ?',
      [memoryId],
    );
    return rows.map(Connection.fromMap).toList();
  }

  /// 查找：兩則記憶之間是否已有連結。
  Future<List<Connection>> findExisting(String fromId, String toId) async {
    final db = database.db;
    final rows = db.select(
      'SELECT * FROM connections WHERE from_memory_id = ? AND to_memory_id = ?',
      [fromId, toId],
    );
    return rows.map(Connection.fromMap).toList();
  }

  /// 向量相似搜尋：用 vector_full_scan 找最相似的記憶。
  ///
  /// [threshold] 是 cosine similarity 閾值（0.0 ~ 1.0）。
  /// vector_full_scan 回傳 distance（0=完全相同, 2=完全相反）。
  /// cosine similarity = 1 - distance，所以 threshold = 0.7 對應 distance < 0.3。
  ///
  /// [excludeMemoryId] 排除自身記憶，避免找到自己。
  Future<List<SimilarMemory>> findSimilarMemories(
    List<double> queryVector, {
    double threshold = 0.7,
    int limit = 10,
    String? excludeMemoryId,
  }) async {
    final db = database.db;
    final maxDistance = 1.0 - threshold;
    // 掃描數量大於最終 limit，預留過濾空間
    final k = (limit * 3).clamp(10, 100);
    final excludeId = excludeMemoryId ?? '';

    final rows = db.select(
    "SELECT m.id, m.content, m.room, m.created_at, m.speaker, v.distance "
    "FROM memories m "
    "JOIN vector_full_scan('memories', 'embedding', vector_as_f32(?), ?) AS v "
    "  ON m.rowid = v.rowid "
    "WHERE m.archived = 0 "
    "  AND m.id != ? "
    // [小葵 2026-09-22 v18 temporal filtering] 三重時效過濾：
    // 1. superseded_by IS NULL——被新事實取代的舊記憶不進檢索（留審計不進對話）
    // 2. expires_at IS NULL OR > now——過期臨時事實（「明天開會」）自然退場
    "  AND m.superseded_by IS NULL "
    "  AND (m.expires_at IS NULL OR m.expires_at > ?) "
    "  AND v.distance <= ? "
    "ORDER BY v.distance ASC "
    "LIMIT ?",
      [
        Memory.vectorToJson(queryVector),
        k,
        excludeId,
        DateTime.now().millisecondsSinceEpoch, // [v18] temporal now
        maxDistance,
        limit,
      ],
    );

    return rows
        .map((row) => SimilarMemory(
              memoryId: row['id'] as String? ?? '',
              distance: (row['distance'] as num?)?.toDouble() ?? 1.0,
              content: row['content'] as String? ?? '',
              room: BrainRoom.fromStringOrDefault(row['room'] as String?),
              // [出處戳 2026-09-15] 攜帶「誰說的」——與時間戳同為第一級事實
              speaker: MemorySpeaker.fromDbOrDefault(row['speaker'] as String?),
              // [時間感 L3 2026-09-12] 攜帶記憶時間戳——記憶的骨架
              createdAt: row['created_at'] is int
                  ? DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int)
                  : DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
            ))
        .toList();
  }

  /// 產生 timestamp-based UUID（與 P0 一致風格）。
  String generateUuid() {
    _uuidCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_uuidCounter';
  }
}

/// 向量相似搜尋結果。
class SimilarMemory {
  /// 相似記憶的 ID
  final String memoryId;

  /// [出處戳 2026-09-15] 誰說的（user/agent/external/unknown）
  final MemorySpeaker speaker;

  /// cosine distance（0=完全相同, 2=完全相反）
  final double distance;

  /// 記憶內容
  final String content;

  /// 所屬房間
  final BrainRoom room;

  /// [時間感 L3 2026-09-12] 記憶建立時間——回顧敘事的骨架
  final DateTime createdAt;

  const SimilarMemory({
    required this.memoryId,
    required this.distance,
    required this.content,
    required this.room,
    this.speaker = MemorySpeaker.unknown, // [出處戳] 預設 unknown（誠實不猜）
    required this.createdAt,
  });
}
