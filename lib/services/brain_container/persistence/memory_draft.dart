// memory_draft.dart
// 記憶草稿 — 管線寫入前的暫存結構
// 建立日期: 2026-07-02

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';

/// 記憶寫入草稿。
///
/// 由管線組裝，包含內容、房間分類、嵌入向量等資訊，
/// 交由 [MemoryWriter] 寫入 DB。
class MemoryDraft {
  final String content;
  final BrainRoom room;
  final String subCategory;
  final String agent;
  final String companionId;
  final MemorySource source;
  final String? sourceId;
  final MemorySpeaker speaker; // [出處戳 2026-09-15] 誰說的——寫入點架構層填
  final String project;
  final List<String> tags;
  final int importance;
  final List<double> vector;
  final String vectorModelVersion;
  final int chunkIndex;
  final int totalChunks;

  const MemoryDraft({
    required this.content,
    required this.room,
    required this.subCategory,
    required this.agent,
    required this.companionId,
    required this.source,
    this.sourceId,
    this.speaker = MemorySpeaker.unknown, // [出處戳] 未標記=unknown（誠實不猜）
    required this.project,
    required this.tags,
    required this.importance,
    required this.vector,
    required this.vectorModelVersion,
    required this.chunkIndex,
    required this.totalChunks,
  });

  /// 轉為 [Memory] 實例（寫入 DB 後用）。
  Memory toMemory(String id, String? parentId) {
    final now = DateTime.now();
    return Memory(
      id: id,
      content: content,
      room: room,
      subCategory: subCategory,
      agent: agent,
      companionId: companionId,
      source: source,
      sourceId: sourceId,
      speaker: speaker, // [出處戳]
      project: project,
      tags: tags,
      importance: importance,
      createdAt: now,
      updatedAt: now,
      accessCount: 0,
      archived: false,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      parentMemoryId: parentId,
      vectorModelVersion: vectorModelVersion,
    );
  }
}
