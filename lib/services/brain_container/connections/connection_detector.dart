// connection_detector.dart
// 連結偵測編排 — strongTie + weakTie
// 建立日期: 2026-07-03

import 'dart:convert';

import 'package:bridge_app/models/brain_container/connection.dart';
import 'package:bridge_app/models/brain_container/connection_type.dart';
import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/connections/connection_repository.dart';

/// 連結偵測器。
///
/// 編排兩種連結偵測（P1 只做 strongTie + weakTie）：
/// - strongTie：向量相似度 > 0.7
/// - weakTie：同房間 + tags 重疊 ≥ 2
class ConnectionDetector {
  final ConnectionRepository repo;
  final BrainDatabase database;

  ConnectionDetector({required this.repo, required this.database});

  /// 對新寫入的記憶偵測連結。
  ///
  /// 回傳新建的連結列表（已強化的不包含在內）。
  Future<List<Connection>> detectForMemory(
    Memory newMemory,
    List<double> vector,
  ) async {
    final strongTies = await _detectStrongTies(newMemory, vector);
    final weakTies = await _detectWeakTies(newMemory);
    final transurfingTies = await _detectTransurfingTies(newMemory);
    return [...strongTies, ...weakTies, ...transurfingTies];
  }

  /// StrongTie：向量相似度 > 0.7。
  ///
  /// 1. 呼叫 [ConnectionRepository.findSimilarMemories]
  /// 2. 對每個結果檢查是否已有連結
  /// 3. 已有 → reinforce；沒有 → insert 新的 Connection
  Future<List<Connection>> _detectStrongTies(
    Memory newMemory,
    List<double> vector,
  ) async {
    final results = <Connection>[];

    final similar = await repo.findSimilarMemories(
      vector,
      threshold: 0.7,
      limit: 10,
      excludeMemoryId: newMemory.id,
    );

    for (final mem in similar) {
      final similarity = 1.0 - mem.distance;
      final existing = await repo.findExisting(newMemory.id, mem.memoryId);
      final existingStrongTie = existing
          .where((c) => c.type == ConnectionType.strongTie)
          .toList();

      if (existingStrongTie.isNotEmpty) {
        await repo.reinforce(existingStrongTie.first.id);
      } else {
        final now = DateTime.now();
        final connection = Connection(
          id: repo.generateUuid(),
          fromMemoryId: newMemory.id,
          toMemoryId: mem.memoryId,
          type: ConnectionType.strongTie,
          similarity: similarity.clamp(0.0, 1.0),
          strength: 0.5,
          reinforcementCount: 0,
          createdAt: now,
          lastReinforcedAt: now,
          dormant: false,
          rationale: 'vector similarity: ${similarity.toStringAsFixed(3)}',
          userMarked: false,
        );
        await repo.insert(connection);
        results.add(connection);
      }
    }

    return results;
  }

  /// WeakTie：同房間 + tags 重疊 ≥ 2。
  ///
  /// 1. SQL 查同房間、非封存的記憶，排除自己
  /// 2. 比較 tags 重疊數 ≥ 2
  /// 3. 已有連結 → reinforce；沒有 → insert 新的 Connection
  Future<List<Connection>> _detectWeakTies(Memory newMemory) async {
    if (newMemory.tags.length < 2) return [];

    final results = <Connection>[];
    final db = database.db;

    final rows = db.select(
      'SELECT id, tags FROM memories '
      'WHERE room = ? AND archived = 0 AND id != ?',
      [newMemory.room.name, newMemory.id],
    );

    final newTags = newMemory.tags.toSet();

    for (final row in rows) {
      final otherId = row['id'] as String? ?? '';
      if (otherId.isEmpty) continue;

      List<String> otherTags;
      try {
        otherTags =
            (jsonDecode(row['tags'] as String? ?? '[]') as List).cast<String>();
      } catch (_) {
        continue;
      }

      final otherTagSet = otherTags.toSet();
      final overlap = newTags.intersection(otherTagSet);

      if (overlap.length < 2) continue;

      final union = newTags.union(otherTagSet);
      final similarity =
          union.isEmpty ? 0.0 : overlap.length / union.length;

      final existing = await repo.findExisting(newMemory.id, otherId);
      final existingWeakTie = existing
          .where((c) => c.type == ConnectionType.weakTie)
          .toList();

      if (existingWeakTie.isNotEmpty) {
        await repo.reinforce(existingWeakTie.first.id);
      } else {
        final now = DateTime.now();
        final connection = Connection(
          id: repo.generateUuid(),
          fromMemoryId: newMemory.id,
          toMemoryId: otherId,
          type: ConnectionType.weakTie,
          similarity: similarity.clamp(0.0, 1.0),
          strength: 0.5,
          reinforcementCount: 0,
          createdAt: now,
          lastReinforcedAt: now,
          dormant: false,
          rationale: 'tag overlap: ${overlap.length} (${overlap.join(', ')})',
          userMarked: false,
        );
        await repo.insert(connection);
        results.add(connection);
      }
    }

    return results;
  }

  /// [教練 Agent 2026-08-08] Transurfing 連結偵測
  ///
  /// doorTie：新記憶在 doors 房間 → 找最近的 stream 記憶建立門連結
  /// bridgeTie：新記憶在 bridges 房間 → 找語意最相關的記憶建立橋連結
  Future<List<Connection>> _detectTransurfingTies(Memory newMemory) async {
    final results = <Connection>[];

    if (newMemory.room == BrainRoom.doors) {
      // 找最近的 stream 記憶——這扇門是從那條水流分出來的
      final db = database.db;
      final rows = db.select(
        "SELECT id FROM memories "
        "WHERE room = 'stream' AND archived = 0 AND id != ? "
        "ORDER BY created_at DESC LIMIT 1",
        [newMemory.id],
      );
      if (rows.isNotEmpty) {
        final parentStreamId = rows.first['id'] as String?;
        if (parentStreamId != null && parentStreamId.isNotEmpty) {
          final existing = await repo.findExisting(newMemory.id, parentStreamId);
          final hasDoorTie = existing
              .where((c) => c.type == ConnectionType.doorTie)
              .toList();
          if (hasDoorTie.isEmpty) {
            final now = DateTime.now();
            final connection = Connection(
              id: repo.generateUuid(),
              fromMemoryId: newMemory.id,
              toMemoryId: parentStreamId,
              type: ConnectionType.doorTie,
              similarity: 0.8,
              strength: 0.7,
              reinforcementCount: 0,
              createdAt: now,
              lastReinforcedAt: now,
              dormant: false,
              rationale: 'transurfing: door opened from stream',
              userMarked: false,
            );
            await repo.insert(connection);
            results.add(connection);
          }
        }
      }
    }

    if (newMemory.room == BrainRoom.bridges) {
      // 橋連結：找 tags 最重疊的非封存記憶
      if (newMemory.tags.length >= 1) {
        final db = database.db;
        final rows = db.select(
          'SELECT id, tags FROM memories '
          "WHERE archived = 0 AND id != ? AND room != 'bridges' "
          'ORDER BY created_at DESC LIMIT 20',
          [newMemory.id],
        );
        final newTags = newMemory.tags.toSet();
        String? bestMatch;
        int bestOverlap = 0;
        for (final row in rows) {
          final otherId = row['id'] as String? ?? '';
          if (otherId.isEmpty) continue;
          List<String> otherTags;
          try {
            otherTags =
                (jsonDecode(row['tags'] as String? ?? '[]') as List).cast<String>();
          } catch (_) {
            continue;
          }
          final overlap = newTags.intersection(otherTags.toSet());
          if (overlap.length > bestOverlap) {
            bestOverlap = overlap.length;
            bestMatch = otherId;
          }
        }
        if (bestMatch != null && bestOverlap > 0) {
          final existing = await repo.findExisting(newMemory.id, bestMatch);
          final hasBridgeTie = existing
              .where((c) => c.type == ConnectionType.bridgeTie)
              .toList();
          if (hasBridgeTie.isEmpty) {
            final now = DateTime.now();
            final connection = Connection(
              id: repo.generateUuid(),
              fromMemoryId: newMemory.id,
              toMemoryId: bestMatch,
              type: ConnectionType.bridgeTie,
              similarity: 0.6,
              strength: 0.5,
              reinforcementCount: 0,
              createdAt: now,
              lastReinforcedAt: now,
              dormant: false,
              rationale: 'transurfing: bridge link ($bestOverlap tag overlap)',
              userMarked: false,
            );
            await repo.insert(connection);
            results.add(connection);
          }
        }
      }
    }

    return results;
  }
}
