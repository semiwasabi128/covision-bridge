// connection.dart
// 記憶連結 model
// 建立日期: 2026-07-02

import 'package:bridge_app/models/brain_container/connection_type.dart';

/// 兩則記憶之間的連結關係。
///
/// 與 [Memory] 分離：strength / reinforcementCount 屬於此處，
/// 不屬於 Memory。
class Connection {
  final String id;
  final String fromMemoryId;
  final String toMemoryId;

  final ConnectionType type;

  final double similarity; // 0.0 ~ 1.0
  final double strength; // 0.1 ~ 1.0

  final int reinforcementCount;
  final DateTime createdAt;
  final DateTime lastReinforcedAt;

  final bool dormant;
  final String? rationale;
  final bool userMarked;

  const Connection({
    required this.id,
    required this.fromMemoryId,
    required this.toMemoryId,
    required this.type,
    required this.similarity,
    required this.strength,
    required this.reinforcementCount,
    required this.createdAt,
    required this.lastReinforcedAt,
    required this.dormant,
    this.rationale,
    required this.userMarked,
  });

  factory Connection.fromMap(Map<String, dynamic> map) {
    return Connection(
      id: map['id'] as String? ?? '',
      fromMemoryId: map['from_memory_id'] as String? ?? '',
      toMemoryId: map['to_memory_id'] as String? ?? '',
      type: ConnectionType.fromDbOrDefault(map['type'] as String?),
      similarity:
          ((map['similarity'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      // 改善 4: strength clamp 到 0.1~1.0
      strength:
          ((map['strength'] as num?)?.toDouble() ?? 0.5).clamp(0.1, 1.0),
      reinforcementCount: (map['reinforcement_count'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      lastReinforcedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['last_reinforced_at'] as int?) ?? 0),
      dormant: (map['dormant'] as int?) == 1,
      rationale: map['rationale'] as String?,
      userMarked: (map['user_marked'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'from_memory_id': fromMemoryId,
      'to_memory_id': toMemoryId,
      'type': type.dbValue,
      'similarity': similarity,
      'strength': strength,
      'reinforcement_count': reinforcementCount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_reinforced_at': lastReinforcedAt.millisecondsSinceEpoch,
      'dormant': dormant ? 1 : 0,
      'rationale': rationale,
      'user_marked': userMarked ? 1 : 0,
    };
  }

  Connection copyWith({
    String? id,
    String? fromMemoryId,
    String? toMemoryId,
    ConnectionType? type,
    double? similarity,
    double? strength,
    int? reinforcementCount,
    DateTime? createdAt,
    DateTime? lastReinforcedAt,
    bool? dormant,
    Object? rationale = _sentinel,
    bool? userMarked,
  }) {
    return Connection(
      id: id ?? this.id,
      fromMemoryId: fromMemoryId ?? this.fromMemoryId,
      toMemoryId: toMemoryId ?? this.toMemoryId,
      type: type ?? this.type,
      similarity: similarity ?? this.similarity,
      strength: strength ?? this.strength,
      reinforcementCount: reinforcementCount ?? this.reinforcementCount,
      createdAt: createdAt ?? this.createdAt,
      lastReinforcedAt: lastReinforcedAt ?? this.lastReinforcedAt,
      dormant: dormant ?? this.dormant,
      rationale: rationale == _sentinel
          ? this.rationale
          : rationale as String?,
      userMarked: userMarked ?? this.userMarked,
    );
  }

  @override
  String toString() =>
      'Connection($fromMemoryId → $toMemoryId, type: $type, strength: $strength)';
}

const _sentinel = Object();
