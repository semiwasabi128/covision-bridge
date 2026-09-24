// memory.dart
// 大腦容器記憶核心 model
// 建立日期: 2026-07-02

import 'dart:convert';
import 'dart:typed_data';

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/room_categories.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';

/// 單一記憶單元。
///
/// 不包含 strength / reinforcementCount — 那些屬於 [Connection]。
/// 向量（embedding）以 BLOB 形式儲存於 SQLite，序列化/反序列化
/// 由 [vectorToJson] / [parseVectorFromBlob] 處理。
class Memory {
  final String id;
  final String content;

  final BrainRoom room;
  final String subCategory;

  final String agent;
  final String companionId; // 來源夥伴 ID（跨 Agent 共享大腦 provenance）
  final MemorySource source;
  final String? sourceId;
  final MemorySpeaker speaker; // [出處戳 2026-09-15] 誰說的（user/agent/external/unknown）

  final String project;
  final List<String> tags;

  final int importance; // 1-5

  /// [教練 Agent 2026-08-19] sub_category → 中文短標籤（圖譜節點第一層文字）
  String get subCategoryLabel {
    // 全域對照：room + sub_category → displayName
    switch (room.name) {
      case 'stream':
        return StreamRoomCategory.tryFromDb(subCategory)?.displayName ?? subCategory;
      case 'doors':
        return DoorsRoomCategory.tryFromDb(subCategory)?.displayName ?? subCategory;
      case 'pendulums':
        return PendulumsRoomCategory.tryFromDb(subCategory)?.displayName ?? subCategory;
      case 'heartMind':
        return HeartMindRoomCategory.tryFromDb(subCategory)?.displayName ?? subCategory;
      case 'fraile':
        return FraileRoomCategory.tryFromDb(subCategory)?.displayName ?? subCategory;
      case 'bridges':
        return BridgesRoomCategory.tryFromDb(subCategory)?.displayName ?? subCategory;
    }
    return subCategory;
  }
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  final int accessCount;
  final bool archived;

  final int chunkIndex;
  final int totalChunks;
  final String? parentMemoryId;

  final String? integrationResult;
  final String? vectorModelVersion;

  const Memory({
    required this.id,
    required this.content,
    required this.room,
    required this.subCategory,
    required this.agent,
    required this.companionId,
    required this.source,
    this.sourceId,
    this.speaker = MemorySpeaker.unknown, // [出處戳] 舊呼叫點零改動（預設 unknown 誠實不猜）
    required this.project,
    required this.tags,
    required this.importance,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    required this.accessCount,
    required this.archived,
    required this.chunkIndex,
    required this.totalChunks,
    this.parentMemoryId,
    this.integrationResult,
    this.vectorModelVersion,
  });

  /// 從 SQLite row（Map）解析。
  ///
  /// 預期欄位名稱與 [toMap] 輸出一致。
  /// tags 以 JSON 字串形式儲存。
  factory Memory.fromMap(Map<String, dynamic> map) {
    // tags JSON 反序列化防護（改善 6）
    List<String> tags;
    try {
      tags = (jsonDecode(map['tags'] as String? ?? '[]') as List)
          .cast<String>();
    } catch (_) {
      tags = [];
    }

    return Memory(
      id: map['id'] as String? ?? '',
      content: map['content'] as String? ?? '',
      room: BrainRoom.fromStringOrDefault(map['room'] as String?),
      subCategory: map['sub_category'] as String? ?? '',
      agent: map['agent'] as String? ?? '',
      companionId: map['companion_id'] as String? ?? '',
      source: MemorySource.fromDbOrDefault(map['source'] as String?),
      sourceId: map['source_id'] as String?,
      speaker: MemorySpeaker.fromDbOrDefault(map['speaker'] as String?), // [出處戳]
      project: map['project'] as String? ?? '',
      tags: tags,
      importance: (map['importance'] as int?) ?? 3,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as int?) ?? 0),
      expiresAt: (map['expires_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['expires_at'] as int?)!)
          : null,
      accessCount: (map['access_count'] as int?) ?? 0,
      archived: (map['archived'] as int?) == 1,
      chunkIndex: (map['chunk_index'] as int?) ?? 0,
      totalChunks: (map['total_chunks'] as int?) ?? 1,
      parentMemoryId: map['parent_memory_id'] as String?,
      integrationResult: map['integration_result'] as String?,
      vectorModelVersion: map['vector_model_version'] as String?,
    );
  }

  /// 序列化為 SQLite row（不含向量欄位）。
  ///
  /// 向量需另外以 [vectorToJson] 轉換後，搭配 vector_as_f32(?) 寫入。
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'room': room.name,
      'sub_category': subCategory,
      'agent': agent,
      'companion_id': companionId,
      'source': source.dbValue,
      'source_id': sourceId,
      'speaker': speaker.dbValue, // [出處戳]
      'project': project,
      'tags': jsonEncode(tags),
      'importance': importance,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'access_count': accessCount,
      'archived': archived ? 1 : 0,
      'chunk_index': chunkIndex,
      'total_chunks': totalChunks,
      'parent_memory_id': parentMemoryId,
      'integration_result': integrationResult,
      'vector_model_version': vectorModelVersion,
    };
  }

  /// 將向量轉為 JSON 字串 '[1.0, 2.0, ...]'。
  ///
  /// 用於 SQLite vector_as_f32(?) 寫入：
  /// ```dart
  /// db.execute(
  ///   'INSERT INTO memories (...) VALUES (..., vector_as_f32(?))',
  ///   [Memory.vectorToJson(vector)],
  /// );
  /// ```
  static String vectorToJson(List<double> vector) {
    return jsonEncode(vector);
  }

  /// 從 BLOB 解析回向量（FLOAT32 little-endian）。
  ///
  /// sqlite_vector 的 embedding 欄位以 f32 BLOB 儲存，
  /// 讀回時可直接用此方法還原為 `[double]`。
  static List<double> parseVectorFromBlob(Uint8List blob) {
    final floatList = blob.buffer.asFloat32List(
      blob.offsetInBytes,
      blob.lengthInBytes ~/ 4,
    );
    return floatList.toList();
  }

  /// 複製並修改部分欄位。
  Memory copyWith({
    String? id,
    String? content,
    BrainRoom? room,
    String? subCategory,
    String? agent,
    String? companionId,
    MemorySource? source,
    MemorySpeaker? speaker, // [出處戳]
    Object? sourceId = _sentinel,
    String? project,
    List<String>? tags,
    int? importance,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? expiresAt = _sentinel,
    int? accessCount,
    bool? archived,
    int? chunkIndex,
    int? totalChunks,
    Object? parentMemoryId = _sentinel,
    Object? integrationResult = _sentinel,
    Object? vectorModelVersion = _sentinel,
  }) {
    return Memory(
      id: id ?? this.id,
      content: content ?? this.content,
      room: room ?? this.room,
      subCategory: subCategory ?? this.subCategory,
      agent: agent ?? this.agent,
      companionId: companionId ?? this.companionId,
      source: source ?? this.source,
      speaker: speaker ?? this.speaker, // [出處戳]
      sourceId: sourceId == _sentinel
          ? this.sourceId
          : sourceId as String?,
      project: project ?? this.project,
      tags: tags ?? List<String>.from(this.tags),
      importance: importance ?? this.importance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt == _sentinel
          ? this.expiresAt
          : expiresAt as DateTime?,
      accessCount: accessCount ?? this.accessCount,
      archived: archived ?? this.archived,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      totalChunks: totalChunks ?? this.totalChunks,
      parentMemoryId: parentMemoryId == _sentinel
          ? this.parentMemoryId
          : parentMemoryId as String?,
      integrationResult: integrationResult == _sentinel
          ? this.integrationResult
          : integrationResult as String?,
      vectorModelVersion: vectorModelVersion == _sentinel
          ? this.vectorModelVersion
          : vectorModelVersion as String?,
    );
  }

  @override
  String toString() =>
      'Memory(id: $id, room: $room, sub: $subCategory, importance: $importance)';
}

const _sentinel = Object();
