// content_preprocessor.dart
// 內容預處理：正規化 + 分片
// 建立日期: 2026-07-02

/// 內容預處理器。
///
/// 負責將原始文字正規化，並在超過閾值時進行滑動視窗分片。
class ContentPreprocessor {
  static const int maxChunkChars = 512;
  static const int overlapChars = 64;
  static const int chunkingThreshold = 800;

  /// 處理原始內容：正規化 + 視需要分片。
  Future<PreprocessedContent> process(String rawContent) async {
    final normalized = _normalize(rawContent);

    if (normalized.length <= chunkingThreshold) {
      return PreprocessedContent(
        normalized: normalized,
        chunks: [TextChunk(text: normalized, chunkIndex: 0, totalChunks: 1)],
        wasChunked: false,
      );
    }

    final chunks = _slidingWindow(normalized);
    return PreprocessedContent(
      normalized: normalized,
      chunks: chunks,
      wasChunked: true,
    );
  }

  /// 正規化文字：trim、統一換行。
  String _normalize(String text) {
    return text.trim().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// 滑動視窗分片：chunk_size=512, overlap=64。
  List<TextChunk> _slidingWindow(String text) {
    final chunks = <TextChunk>[];
    var start = 0;

    while (start < text.length) {
      final end = (start + maxChunkChars).clamp(0, text.length);
      chunks.add(TextChunk(
        text: text.substring(start, end),
        chunkIndex: chunks.length,
        totalChunks: 0,
      ));
      if (end >= text.length) break;
      start = end - overlapChars;
    }

    // 回填 totalChunks
    final total = chunks.length;
    return chunks
        .map((c) => TextChunk(
              text: c.text,
              chunkIndex: c.chunkIndex,
              totalChunks: total,
            ))
        .toList();
  }
}

/// 預處理結果。
class PreprocessedContent {
  final String normalized;
  final List<TextChunk> chunks;
  final bool wasChunked;

  const PreprocessedContent({
    required this.normalized,
    required this.chunks,
    required this.wasChunked,
  });
}

/// 文字分片。
class TextChunk {
  final String text;
  final int chunkIndex;
  final int totalChunks;

  const TextChunk({
    required this.text,
    required this.chunkIndex,
    required this.totalChunks,
  });
}
