// room_growth.dart
// 房間生長狀態 model + 細分事件 model
// 建立日期: 2026-07-02

import 'package:bridge_app/models/brain_container/brain_room.dart';

/// 房間生長狀態。
///
/// 記錄每個房間目前的記憶量、細分數量、上次細分時間等，
/// 用於判斷是否需要自動細分（subdivision）。
class RoomGrowth {
  final String id;
  final BrainRoom room;
  final int memoryCount;
  final int subdivisionCount;
  final DateTime lastSubdivisionAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoomGrowth({
    required this.id,
    required this.room,
    required this.memoryCount,
    required this.subdivisionCount,
    required this.lastSubdivisionAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoomGrowth.fromMap(Map<String, dynamic> map) {
    return RoomGrowth(
      id: map['id'] as String? ?? '',
      room: BrainRoom.fromStringOrDefault(map['room'] as String?),
      memoryCount: (map['memory_count'] as int?) ?? 0,
      subdivisionCount: (map['subdivision_count'] as int?) ?? 0,
      lastSubdivisionAt: DateTime.fromMillisecondsSinceEpoch(
          (map['last_subdivision_at'] as int?) ?? 0),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as int?) ?? 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'room': room.name,
      'memory_count': memoryCount,
      'subdivision_count': subdivisionCount,
      'last_subdivision_at': lastSubdivisionAt.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  RoomGrowth copyWith({
    String? id,
    BrainRoom? room,
    int? memoryCount,
    int? subdivisionCount,
    DateTime? lastSubdivisionAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoomGrowth(
      id: id ?? this.id,
      room: room ?? this.room,
      memoryCount: memoryCount ?? this.memoryCount,
      subdivisionCount: subdivisionCount ?? this.subdivisionCount,
      lastSubdivisionAt: lastSubdivisionAt ?? this.lastSubdivisionAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 細分事件紀錄。
///
/// 當一個房間的記憶量超過閾值，系統自動觸發細分，
/// 產生一筆 SubdivisionEvent 記錄細分原因、結果與時間。
class SubdivisionEvent {
  final String id;
  final BrainRoom room;
  final String reason;
  final int memoriesBefore;
  final int memoriesAfter;
  final String? newSubCategories;
  final DateTime createdAt;

  const SubdivisionEvent({
    required this.id,
    required this.room,
    required this.reason,
    required this.memoriesBefore,
    required this.memoriesAfter,
    this.newSubCategories,
    required this.createdAt,
  });

  factory SubdivisionEvent.fromMap(Map<String, dynamic> map) {
    return SubdivisionEvent(
      id: map['id'] as String? ?? '',
      room: BrainRoom.fromStringOrDefault(map['room'] as String?),
      reason: map['reason'] as String? ?? '',
      memoriesBefore: (map['memories_before'] as int?) ?? 0,
      memoriesAfter: (map['memories_after'] as int?) ?? 0,
      newSubCategories: map['new_sub_categories'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'room': room.name,
      'reason': reason,
      'memories_before': memoriesBefore,
      'memories_after': memoriesAfter,
      'new_sub_categories': newSubCategories,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  SubdivisionEvent copyWith({
    String? id,
    BrainRoom? room,
    String? reason,
    int? memoriesBefore,
    int? memoriesAfter,
    Object? newSubCategories = _sentinel,
    DateTime? createdAt,
  }) {
    return SubdivisionEvent(
      id: id ?? this.id,
      room: room ?? this.room,
      reason: reason ?? this.reason,
      memoriesBefore: memoriesBefore ?? this.memoriesBefore,
      memoriesAfter: memoriesAfter ?? this.memoriesAfter,
      newSubCategories: newSubCategories == _sentinel
          ? this.newSubCategories
          : newSubCategories as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

const _sentinel = Object();
