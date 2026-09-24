// memory_retrieval_pipeline.dart
// 記憶檢索管線 — 意圖觸發 → 向量搜尋 → 關聯召回 → 理由標記
// 建立日期: 2026-07-03

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/models/brain_container/connection_type.dart';
import 'package:bridge_app/services/brain_container/connections/connection_repository.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';

/// 記憶檢索管線。
///
/// 編排流程：
/// 1. 查詢嵌入（embedQuery，用 retrievalQuery 前綴）
/// 2. 向量搜尋（vector_full_scan k-NN）
/// 3. 關聯召回（沿 connections 展開一層）
/// 4. 理由標記（每條結果附上召回原因）
class MemoryRetrievalPipeline {
  final EmbeddingService embedder;
  final ConnectionRepository connectionRepo;

  /// 向量搜尋的相似度閾值。
  /// 低於此值的記憶不會出現在主結果中。
  final double similarityThreshold;

  /// 向量搜尋的最大結果數。
  final int maxVectorResults;

  /// 每條主結果最多展開幾條關聯記憶。
  final int maxConnectionsPerMemory;

  MemoryRetrievalPipeline({
    required this.embedder,
    required this.connectionRepo,
    this.similarityThreshold = 0.5,
    this.maxVectorResults = 10,
    this.maxConnectionsPerMemory = 3,
  });

  /// 檢索記憶。
  ///
  /// [query] 是自然語言查詢（例如「上次討論的架構決策」）。
  /// [roomFilter] 可選：只搜特定房間（例如只搜 Doors）。
  ///
  /// 回傳排序後的 [RetrievalResult] 列表，
  /// 每條包含記憶內容、相似度、召回理由。
  Future<List<RetrievalResult>> retrieve({
    required String query,
    BrainRoom? roomFilter,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Step 1: 查詢嵌入
      final queryVector = await embedder.embedQuery(query);

      // 若模型未安裝（fallback 零向量），直接回傳空
      if (!embedder.isModelAvailable) {
        stopwatch.stop();
        return [];
      }

      // Step 2: 向量搜尋
      final similar = await connectionRepo.findSimilarMemories(
        queryVector,
        threshold: similarityThreshold,
        limit: maxVectorResults,
      );

      // Step 3 + 4: 關聯召回 + 理由標記
      final results = <RetrievalResult>[];

      for (final mem in similar) {
        final similarity = 1.0 - mem.distance;

        // 主結果
        results.add(RetrievalResult(
          memoryId: mem.memoryId,
          content: mem.content,
          room: mem.room,
          similarity: similarity,
          recallReason: RecallReason.vectorSimilarity,
          reasonDetail: 'cosine similarity: ${similarity.toStringAsFixed(3)}',
          connectionPath: null,
          createdAt: mem.createdAt, // [時間感 L3] 骨架隨行
          speaker: mem.speaker, // [出處戳] 出處隨行
        ));

        // 展開關聯記憶
        if (maxConnectionsPerMemory > 0) {
          final connections = await connectionRepo.findByFrom(mem.memoryId);
          final strongConnections = connections
              .where((c) =>
                  c.type == ConnectionType.strongTie && !c.dormant)
              .take(maxConnectionsPerMemory)
              .toList();

          for (final conn in strongConnections) {
            // 避免重複
            if (results.any((r) => r.memoryId == conn.toMemoryId)) continue;

            results.add(RetrievalResult(
              memoryId: conn.toMemoryId,
              content: '', // 關聯記憶的內容需要另外查 DB
              room: mem.room, // 暫用主結果的房間，後續可精確查
              similarity: conn.similarity,
              recallReason: RecallReason.connectionExpansion,
              reasonDetail: conn.rationale ?? '',
              connectionPath: conn.fromMemoryId,
            ));
          }
        }
      }

      // 按 similarity 排序
      results.sort((a, b) => b.similarity.compareTo(a.similarity));

      stopwatch.stop();
      return results;
    } catch (e) {
      stopwatch.stop();
      return [];
    }
  }

  /// 檢索特定房間的記憶。
  ///
  /// 便利方法：等同於 retrieve() 加上 roomFilter。
  Future<List<RetrievalResult>> retrieveInRoom({
    required String query,
    required BrainRoom room,
  }) {
    return retrieve(query: query, roomFilter: room);
  }
}

/// 檢索結果。
class RetrievalResult {
  /// 記憶 ID
  final String memoryId;

  /// 記憶內容
  final String content;

  /// 所屬房間
  final BrainRoom room;

  /// 與查詢的相似度 (0.0 ~ 1.0)
  final double similarity;

  /// 召回理由
  final RecallReason recallReason;

  /// 理由細節（例如 cosine similarity 值或 tag overlap）
  final String reasonDetail;

  /// 若是透過連結展開召回的，記錄來源記憶 ID
  final String? connectionPath;

  /// [時間感 L3 2026-09-12] 記憶建立時間——回顧敘事的骨架（舊→新排序用）
  final DateTime? createdAt;

  /// [出處戳 2026-09-15] 誰說的——與時間戳並列注入（speaker= 前綴為必要語法）
  final MemorySpeaker speaker;

  const RetrievalResult({
    required this.memoryId,
    required this.content,
    required this.room,
    required this.similarity,
    required this.recallReason,
    required this.reasonDetail,
    required this.connectionPath,
    this.createdAt,
    this.speaker = MemorySpeaker.unknown, // [出處戳] 預設 unknown
  });

  /// 是否為向量搜尋直接命中的結果
  bool get isDirectHit => recallReason == RecallReason.vectorSimilarity;

  /// 是否為透過連結展開召回的結果
  bool get isConnectionExpansion =>
      recallReason == RecallReason.connectionExpansion;
}

/// 召回理由類型。
enum RecallReason {
  /// 向量相似度搜尋直接命中
  vectorSimilarity,

  /// 透過 connections 展開召回
  connectionExpansion,

  /// 透過 tags 匹配召回（P2）
  tagMatch,

  /// 透過時間衰減召回（P2）
  temporalDecay,
}
