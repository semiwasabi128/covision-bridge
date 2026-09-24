// memory_write_pipeline.dart
// 記憶寫入管線 — 編排預處理 → 嵌入 → 分類 → 寫入 → 連結偵測
// 建立日期: 2026-07-02
// 修改日期: 2026-07-03 — P1: 接入 RoomClassifier + ConnectionDetector

import 'package:bridge_app/models/brain_container/connection.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/services/brain_container/classification/room_classifier.dart';
import 'package:bridge_app/services/brain_container/connections/connection_detector.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
import 'package:bridge_app/services/brain_container/persistence/memory_draft.dart';
import 'package:bridge_app/services/brain_container/persistence/memory_writer.dart';
import 'package:bridge_app/services/brain_container/preprocessing/content_preprocessor.dart';

/// 記憶寫入管線。
///
/// 編排流程：
/// 1. 預處理（正規化 + 分片）— Step A
/// 2. 嵌入（向量計算）— Step B
/// 3. 房間分類（RoomClassifier）— Step C
/// 4. 組裝 drafts + 寫入 DB — Step D
/// 5. 連結偵測（ConnectionDetector）— Step E
class MemoryWritePipeline {
  final ContentPreprocessor preprocessor;
  final EmbeddingService embedder;
  final MemoryWriter writer;
  final RoomClassifier classifier;
  final ConnectionDetector? connectionDetector;

  MemoryWritePipeline({
    required this.preprocessor,
    required this.embedder,
    required this.writer,
    this.classifier = const RoomClassifier(),
    this.connectionDetector,
  });

  /// 執行記憶寫入管線。
  Future<WritePipelineResult> write({
    required String content,
    required String agent,
    String companionId = '',
    required MemorySource source,
    MemorySpeaker speaker = MemorySpeaker.unknown, // [出處戳] 架構層填
    String project = '',
    List<String> tags = const [],
    int importance = 3,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Step A: 預處理
      final preprocessed = await preprocessor.process(content);

      // Step B: 嵌入
      final embeddings = await embedder.embedBatch(
        preprocessed.chunks.map((c) => c.text).toList(),
      );

      // Step C: 房間分類（用原始內容分類，所有 chunk 共用同一分類）
      final classification = classifier.classify(
        content: content,
        tags: tags,
      );
      final room = classification.room;
      final subCategory = classification.subCategory;

      // Step D: 組裝 drafts + 寫入 DB
      final drafts = <MemoryDraft>[];
      for (var i = 0; i < preprocessed.chunks.length; i++) {
        final chunk = preprocessed.chunks[i];
        final embedding = embeddings[i];
        drafts.add(MemoryDraft(
          content: chunk.text,
          room: room,
          subCategory: subCategory,
          agent: agent,
          companionId: companionId,
          source: source,
          speaker: speaker, // [出處戳]
          project: project,
          tags: tags,
          importance: importance,
          vector: embedding.vector,
          vectorModelVersion: embedding.modelVersion,
          chunkIndex: chunk.chunkIndex,
          totalChunks: chunk.totalChunks,
        ));
      }

      final memories = await writer.writeMany(drafts);

      // Step E: 連結偵測（對 parent memory 偵測）
      var newConnections = <Connection>[];
      if (connectionDetector != null && memories.isNotEmpty) {
        final parent = memories.first;
        final parentVector = drafts.first.vector;
        newConnections = await connectionDetector!.detectForMemory(
          parent,
          parentVector,
        );
      }

      stopwatch.stop();
      return WritePipelineResult(
        memories: memories,
        newConnections: newConnections,
        totalDuration: stopwatch.elapsed,
        partialSuccess: false,
      );
    } catch (e) {
      stopwatch.stop();
      return WritePipelineResult(
        memories: [],
        newConnections: [],
        totalDuration: stopwatch.elapsed,
        partialSuccess: true,
      );
    }
  }
}

/// 管線寫入結果。
class WritePipelineResult {
  final List<Memory> memories;
  final List<Connection> newConnections;
  final Duration totalDuration;
  final bool partialSuccess;

  const WritePipelineResult({
    required this.memories,
    required this.newConnections,
    required this.totalDuration,
    required this.partialSuccess,
  });
}
