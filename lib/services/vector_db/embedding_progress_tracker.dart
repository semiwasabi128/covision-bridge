// embedding_progress_tracker.dart
// [教練 Agent 2026-07-28] 全域背景嵌入進度追蹤 singleton
//
// 設計文件：vector-db-brain-fusion-design.md 決策 3
// - 嵌入任務在背景繼續，切換頁面不中斷
// - 進度條可在任意頁面顯示（header / floating widget）
// - 圖譜用 Stream 監聽嵌入完成事件，新連線漸入動畫
// - 模型下載也是同樣道理
//
// 純 Dart singleton，不依賴 Flutter UI。
// 用 StreamController<EmbeddingProgress> 發送進度事件。

import 'dart:async';

/// 嵌入進度階段
enum EmbeddingStage {
  idle,       // 無任務
  scanning,   // 掃描檔案中
  embedding,  // 生成向量中
  completing, // 收尾（更新 manifest 等）
  done,       // 全部完成
  error,      // 錯誤中止
}

/// 嵌入進度事件
///
/// 每次 embedding 處理一個檔案後發送一個事件。
/// 圖譜頁面可監聽 [EmbeddingProgressTracker.progressStream]，
// 在每個 fileCompleted 事件時觸發連線漸入動畫。
class EmbeddingProgress {
  final int done;
  final int total;
  final String? currentFile;
  final EmbeddingStage stage;
  final String? error;

  /// 0.0 ~ 1.0
  double get fraction => total > 0 ? done / total : 0.0;

  /// 百分比整數 0~100
  int get percent => total > 0 ? (done * 100 ~/ total) : 0;

  /// 是否正在執行
  bool get isActive =>
      stage == EmbeddingStage.scanning ||
      stage == EmbeddingStage.embedding ||
      stage == EmbeddingStage.completing;

  const EmbeddingProgress({
    this.done = 0,
    this.total = 0,
    this.currentFile,
    this.stage = EmbeddingStage.idle,
    this.error,
  });

  static const idle = EmbeddingProgress(stage: EmbeddingStage.idle);

  EmbeddingProgress copyWith({
    int? done,
    int? total,
    String? currentFile,
    EmbeddingStage? stage,
    String? error,
  }) {
    return EmbeddingProgress(
      done: done ?? this.done,
      total: total ?? this.total,
      currentFile: currentFile ?? this.currentFile,
      stage: stage ?? this.stage,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    switch (stage) {
      case EmbeddingStage.idle:
        return 'EmbeddingProgress(idle)';
      case EmbeddingStage.done:
        return 'EmbeddingProgress(done: $done/$total)';
      case EmbeddingStage.error:
        return 'EmbeddingProgress(error: $error)';
      default:
        return 'EmbeddingProgress($stage: $done/$total, '
            'file=$currentFile, $percent%)';
    }
  }
}

/// 模型下載進度事件
class ModelDownloadProgress {
  final int modelProgress;      // 0-100
  final int tokenizerProgress;  // 0-100
  final bool isDownloading;
  final bool isCompleted;
  final String? error;

  const ModelDownloadProgress({
    this.modelProgress = 0,
    this.tokenizerProgress = 0,
    this.isDownloading = false,
    this.isCompleted = false,
    this.error,
  });

  static const idle = ModelDownloadProgress();

  /// 整體進度百分比（模型 ~97% + tokenizer ~3%）
  int get overallPercent {
    return ((modelProgress * 0.97 + tokenizerProgress * 0.03).round())
        .clamp(0, 100);
  }

  ModelDownloadProgress copyWith({
    int? modelProgress,
    int? tokenizerProgress,
    bool? isDownloading,
    bool? isCompleted,
    String? error,
  }) {
    return ModelDownloadProgress(
      modelProgress: modelProgress ?? this.modelProgress,
      tokenizerProgress: tokenizerProgress ?? this.tokenizerProgress,
      isDownloading: isDownloading ?? this.isDownloading,
      isCompleted: isCompleted ?? this.isCompleted,
      error: error ?? this.error,
    );
  }
}

/// 全域背景嵌入進度追蹤 singleton。
///
/// 純 Dart，不依賴 Flutter UI。
/// 任何頁面都可以監聽 [progressStream] 顯示進度條。
///
/// 使用方式：
/// ```dart
/// // 開始嵌入（在 AssetIndexService.generateEmbeddings 內部呼叫）
/// EmbeddingProgressTracker.instance.startEmbedding(total: 100);
/// EmbeddingProgressTracker.instance.updateFile(
///   done: 1, total: 100, currentFile: 'note.md');
///
/// // 任意頁面監聯進度
/// EmbeddingProgressTracker.instance.progressStream.listen((p) {
///   print('${p.percent}% - ${p.currentFile}');
/// });
/// ```
class EmbeddingProgressTracker {
  static final EmbeddingProgressTracker instance =
      EmbeddingProgressTracker._();
  EmbeddingProgressTracker._();

  // ── 嵌入進度 ──────────────────────────────────────────

  final StreamController<EmbeddingProgress> _progressController =
      StreamController<EmbeddingProgress>.broadcast();

  /// 嵌入進度 Stream（broadcast，可多頁面同時監聽）
  Stream<EmbeddingProgress> get progressStream => _progressController.stream;

  /// 目前進度快照
  EmbeddingProgress _currentProgress = EmbeddingProgress.idle;
  EmbeddingProgress get currentProgress => _currentProgress;

  /// 是否有嵌入任務正在執行
  bool get isEmbeddingActive => _currentProgress.isActive;

  /// 開始嵌入任務
  void startEmbedding({required int total, String? rootPath}) {
    _currentProgress = EmbeddingProgress(
      done: 0,
      total: total,
      stage: EmbeddingStage.embedding,
    );
    _emit();
  }

  /// 更新嵌入進度（每處理完一個檔案呼叫）
  void updateFile({
    required int done,
    required int total,
    String? currentFile,
  }) {
    _currentProgress = EmbeddingProgress(
      done: done,
      total: total,
      currentFile: currentFile,
      stage: EmbeddingStage.embedding,
    );
    _emit();
  }

  /// 進入收尾階段
  void setCompleting() {
    _currentProgress = _currentProgress.copyWith(
      stage: EmbeddingStage.completing,
    );
    _emit();
  }

  /// 嵌入完成
  void completeEmbedding() {
    _currentProgress = EmbeddingProgress(
      done: _currentProgress.total,
      total: _currentProgress.total,
      stage: EmbeddingStage.done,
    );
    _emit();
    // 1.5 秒後回到 idle，讓 UI 有時間顯示完成狀態
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_currentProgress.stage == EmbeddingStage.done) {
        _currentProgress = EmbeddingProgress.idle;
        _emit();
      }
    });
  }

  /// 嵌入錯誤
  void failEmbedding(String error) {
    _currentProgress = EmbeddingProgress(
      done: _currentProgress.done,
      total: _currentProgress.total,
      currentFile: _currentProgress.currentFile,
      stage: EmbeddingStage.error,
      error: error,
    );
    _emit();
    // 3 秒後回到 idle
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentProgress.stage == EmbeddingStage.error) {
        _currentProgress = EmbeddingProgress.idle;
        _emit();
      }
    });
  }

  // ── 模型下載進度 ──────────────────────────────────────

  final StreamController<ModelDownloadProgress> _downloadController =
      StreamController<ModelDownloadProgress>.broadcast();

  /// 模型下載進度 Stream
  Stream<ModelDownloadProgress> get downloadStream =>
      _downloadController.stream;

  ModelDownloadProgress _currentDownload = ModelDownloadProgress.idle;
  ModelDownloadProgress get currentDownload => _currentDownload;

  /// 是否有模型下載正在執行
  bool get isDownloading => _currentDownload.isDownloading;

  /// 開始模型下載
  void startDownload() {
    _currentDownload = const ModelDownloadProgress(
      isDownloading: true,
    );
    _emitDownload();
  }

  /// 更新模型檔案下載進度
  void updateModelProgress(int progress) {
    _currentDownload = _currentDownload.copyWith(
      modelProgress: progress,
    );
    _emitDownload();
  }

  /// 更新 tokenizer 下載進度
  void updateTokenizerProgress(int progress) {
    _currentDownload = _currentDownload.copyWith(
      tokenizerProgress: progress,
    );
    _emitDownload();
  }

  /// 模型下載完成
  void completeDownload() {
    _currentDownload = const ModelDownloadProgress(
      modelProgress: 100,
      tokenizerProgress: 100,
      isCompleted: true,
    );
    _emitDownload();
    // 2 秒後回到 idle
    Future.delayed(const Duration(seconds: 2), () {
      if (_currentDownload.isCompleted) {
        _currentDownload = ModelDownloadProgress.idle;
        _emitDownload();
      }
    });
  }

  /// 模型下載失敗
  void failDownload(String error) {
    _currentDownload = _currentDownload.copyWith(
      isDownloading: false,
      error: error,
    );
    _emitDownload();
    // 5 秒後回到 idle
    Future.delayed(const Duration(seconds: 5), () {
      if (_currentDownload.error != null && !_currentDownload.isCompleted) {
        _currentDownload = ModelDownloadProgress.idle;
        _emitDownload();
      }
    });
  }

  // ── 內部 ──────────────────────────────────────────────

  void _emit() {
    if (!_progressController.isClosed) {
      _progressController.add(_currentProgress);
    }
  }

  void _emitDownload() {
    if (!_downloadController.isClosed) {
      _downloadController.add(_currentDownload);
    }
  }

  /// 釋放資源（通常在 app 關閉時呼叫）
  void dispose() {
    _progressController.close();
    _downloadController.close();
  }
}
