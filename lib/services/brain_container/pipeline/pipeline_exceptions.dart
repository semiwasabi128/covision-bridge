// pipeline_exceptions.dart
// 管線例外定義
// 建立日期: 2026-07-02

/// 管線基礎例外。
class PipelineException implements Exception {
  final String message;
  final String stage;

  PipelineException(this.message, this.stage);

  @override
  String toString() => 'PipelineException($stage): $message';
}

/// 嵌入失敗例外。
class EmbeddingFailedException extends PipelineException {
  EmbeddingFailedException(String message) : super(message, 'embedding');
}

/// 寫入交易失敗例外。
class WriteTransactionFailedException extends PipelineException {
  WriteTransactionFailedException(String message) : super(message, 'write');
}
