// embedding_service.dart
// EmbeddingGemma 300M 嵌入服務（P1-4: TFLite via flutter_gemma_embeddings）
// 建立日期: 2026-07-02
// 修改日期: 2026-07-03 — 從 mock 升級為真實 on-device 推論

import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';

/// EmbeddingGemma 300M 嵌入服務。
///
/// 使用 flutter_gemma_embeddings (LiteRT C API + dart:ffi) 在裝置上
/// 跑 EmbeddingGemma 300M 模型，產生 768 維向量。
///
/// - 初始化時檢查模型是否已安裝
/// - 推論後自動 L2 正規化（cosine similarity 友善）
/// - 若模型未安裝，fallback 為零向量（讓管線不中斷）
/// - 模型安裝透過 [EmbeddingModelManager] 處理（下載 + 進度）
class EmbeddingService {
  static final EmbeddingService instance = EmbeddingService._();
  EmbeddingService._();

  static const String currentModelVersion = 'gemma-300m-v1';
  static const int vectorDimension = 768;

  bool _initialized = false;
  EmbeddingModel? _model;

  /// 初始化嵌入服務。
  ///
  /// 檢查 flutter_gemma 是否已有 active embedding model。
  /// 若有，取得 model handle；若無，進入 fallback 模式。
  Future<void> initialize() async {
    if (_initialized) return;
    await _tryGetActiveModel();
    _initialized = true;
  }

  /// 嘗試取得已安裝的 embedding model。
  Future<void> _tryGetActiveModel() async {
    try {
      if (FlutterGemma.hasActiveEmbedder()) {
        _model = await FlutterGemma.getActiveEmbedder();
      }
    } catch (_) {
      _model = null;
    }
  }

  /// 模型安裝完成後呼叫，熱載入 embedding model。
  Future<void> reload() async {
    await _model?.close();
    _model = null;
    await _tryGetActiveModel();
  }

  /// 嵌入單段文字（用於記憶寫入，使用 document 前綴）。
  ///
  /// 回傳 L2 正規化後的 768 維向量。
  /// 若模型不可用，回傳零向量（fallback）。
  Future<EmbeddingResult> embedOne(String text) async {
    if (!_initialized) throw StateError('EmbeddingService 未初始化');

    if (_model != null) {
      try {
        final vector = await _model!.generateEmbedding(
          text,
          taskType: TaskType.retrievalDocument,
        );
        return EmbeddingResult(
          modelVersion: currentModelVersion,
          chunkIndex: 0,
          vector: _l2Normalize(vector),
          computedAt: DateTime.now(),
        );
      } catch (_) {
        // 推論失敗 → fallback
      }
    }

    // Fallback: 零向量
    return EmbeddingResult(
      modelVersion: 'mock-fallback',
      chunkIndex: 0,
      vector: List.filled(vectorDimension, 0.0),
      computedAt: DateTime.now(),
    );
  }

  /// 批次嵌入多段文字（用於記憶寫入，使用 document 前綴）。
  Future<List<EmbeddingResult>> embedBatch(List<String> texts) async {
    if (!_initialized) throw StateError('EmbeddingService 未初始化');

    if (_model != null) {
      try {
        final vectors = await _model!.generateEmbeddings(
          texts,
          taskType: TaskType.retrievalDocument,
        );
        return vectors.asMap().entries.map((e) => EmbeddingResult(
          modelVersion: currentModelVersion,
          chunkIndex: e.key,
          vector: _l2Normalize(e.value),
          computedAt: DateTime.now(),
        )).toList();
      } catch (_) {
        // 推論失敗 → fallback
      }
    }

    // Fallback: 批次零向量
    return texts.asMap().entries.map((e) => EmbeddingResult(
      modelVersion: 'mock-fallback',
      chunkIndex: e.key,
      vector: List.filled(vectorDimension, 0.0),
      computedAt: DateTime.now(),
    )).toList();
  }

  /// 嵌入查詢文字（用於記憶檢索，使用 query 前綴）。
  ///
  /// retrievalQuery 和 retrievalDocument 前綴不同，
  /// 這是 EmbeddingGemma 的設計——查詢和文件用不同前綴提升检索品質。
  Future<List<double>> embedQuery(String query) async {
    if (!_initialized) throw StateError('EmbeddingService 未初始化');

    if (_model != null) {
      try {
        final vector = await _model!.generateEmbedding(
          query,
          taskType: TaskType.retrievalQuery,
        );
        return _l2Normalize(vector);
      } catch (_) {
        // fallback
      }
    }

    return List.filled(vectorDimension, 0.0);
  }

  /// 對向量做 L2 正規化。
  ///
  /// EmbeddingGemma 的原始輸出未正規化。
  /// L2 正規化後 cosine similarity = dot product，
  /// 與 sqlite_vector 的 vector_full_scan distance 計算一致。
  List<double> _l2Normalize(List<double> vector) {
    var sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = sqrt(sumSq);
    if (norm == 0.0) return vector;

    return vector.map((v) => v / norm).toList();
  }

  /// 釋放資源。
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _initialized = false;
  }

  /// 目前是否使用真實模型（非 fallback）。
  bool get isModelAvailable => _model != null;
}

/// 嵌入結果。
class EmbeddingResult {
  final String modelVersion;
  final int chunkIndex;
  final List<double> vector;
  final DateTime computedAt;

  const EmbeddingResult({
    required this.modelVersion,
    required this.chunkIndex,
    required this.vector,
    required this.computedAt,
  });
}
