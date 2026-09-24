// embedding_model_manager.dart
// EmbeddingGemma 模型下載安裝管理器
// 建立日期: 2026-07-03

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:path_provider/path_provider.dart';

import '../../vector_db/embedding_progress_tracker.dart';
import 'embedding_service.dart';

/// EmbeddingGemma 模型管理器。
///
/// 負責：
/// 1. 首次啟動時初始化 flutter_gemma + LiteRT embedding backend
/// 2. 下載安裝 .tflite 模型 + sentencepiece tokenizer
/// 3. 下載進度回報（供 UI 顯示進度條）
/// 4. 安裝完成後通知 EmbeddingService 熱載入
class EmbeddingModelManager {
  static final EmbeddingModelManager instance = EmbeddingModelManager._();
  EmbeddingModelManager._();

  // HuggingFace litert-community/embeddinggemma-300m
  // gated model：需要 HF token 才能下載
  static const String _modelUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/'
      'embeddinggemma-300M_seq512_mixed-precision.tflite';
  static const String _tokenizerUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/'
      'sentencepiece.model';

  bool _flutterGemmaInitialized = false;

  /// 初始化 flutter_gemma 核心 + LiteRT embedding backend。
  ///
  /// 必須在 FlutterGemma.installEmbedder() 之前呼叫。
  /// [huggingFaceToken] 用於下載 gated model（HF 帳號需已接受授權）。
  Future<void> initializeCore({
    String? huggingFaceToken,
  }) async {
    if (_flutterGemmaInitialized) return;

    // [教練 Agent 2026-07-25] 確保 LiteRT companion dylibs 在 app bundle 裡
    // flutter_gemma_embeddings 的 Native Assets hook 在 macOS 跳過 companion dylibs，
    // 導致 LiteRtLm.dylib 的 @rpath 相依性找不到。這裡在 initialize 前自動修復。
    await _ensureCompanionDylibs();

    await FlutterGemma.initialize(
      huggingFaceToken: huggingFaceToken,
      embeddingBackends: [LiteRtEmbeddingBackend()],
    );

    _flutterGemmaInitialized = true;
  }

  /// [教練 Agent 2026-07-25] 確保 LiteRT companion dylibs 在 app bundle 的 Frameworks 目錄
  ///
  /// 問題：flutter_gemma_embeddings 的 build hook 在 macOS 跳過 companion dylibs
  /// （install_name_tool headerpad 問題 #247），LiteRtLm.dylib 相依：
  ///   @rpath/libGemmaModelConstraintProvider.dylib
  ///   @rpath/libLiteRtMetalAccelerator.dylib
  /// 少了這些 dylib → dlopen 失敗 → fallback 零向量模式。
  ///
  /// 解法：從 flutter_gemma 的快取目錄複製到 app bundle Frameworks。
  static const _companionDylibs = [
    'libGemmaModelConstraintProvider.dylib',
    'libLiteRtMetalAccelerator.dylib',
  ];

  Future<void> _ensureCompanionDylibs() async {
    if (!Platform.isMacOS) return;

    try {
      // app bundle 的 Frameworks 目錄
      final exeDir = File(Platform.resolvedExecutable).parent;
      final frameworksDir = Directory('${exeDir.parent.path}/Frameworks');

      // flutter_gemma 快取目錄
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;
      final cacheDir = Directory('$home/Library/Caches/flutter_gemma/native/macos_arm64');

      if (!cacheDir.existsSync() || !frameworksDir.existsSync()) return;

      for (final dylibName in _companionDylibs) {
        final src = File('${cacheDir.path}/$dylibName');
        final dst = File('${frameworksDir.path}/$dylibName');
        if (src.existsSync() && !dst.existsSync()) {
          await src.copy(dst.path);
          debugPrint('[EmbeddingManager] 複製 companion dylib: $dylibName');
        }
      }
    } catch (e) {
      debugPrint('[EmbeddingManager] companion dylib 修復失敗（非致命）: $e');
    }
  }

  /// 檢查模型是否已安裝。
  bool get isModelInstalled => FlutterGemma.hasActiveEmbedder();

  /// 下載安裝 EmbeddingGemma 模型。
  ///
  /// [onModelProgress] / [onTokenizerProgress] 回報下載進度 (0-100)。
  /// 安裝完成後自動設為 active embedding model，
  /// 並通知 EmbeddingService 熱載入。
  ///
  /// [huggingFaceToken] 用於下載 gated model。
  ///
  /// 進度同時透過 [EmbeddingProgressTracker.downloadStream] 廣播，
  /// 因此即使呼叫端的 Widget 被銷毀（使用者切換頁面），
  /// 下載仍在背景繼續，進度可在任意頁面顯示。
  Future<void> installModel({
    String? huggingFaceToken,
    void Function(int progress)? onModelProgress,
    void Function(int progress)? onTokenizerProgress,
  }) async {
    final tracker = EmbeddingProgressTracker.instance;
    tracker.startDownload();

    // 合併回調：同時通知呼叫端 UI + 全域 tracker
    void modelCb(int p) {
      onModelProgress?.call(p);
      tracker.updateModelProgress(p);
    }

    void tokenizerCb(int p) {
      onTokenizerProgress?.call(p);
      tracker.updateTokenizerProgress(p);
    }

    try {
      if (!_flutterGemmaInitialized) {
        await initializeCore(huggingFaceToken: huggingFaceToken);
      }

      await FlutterGemma.installEmbedder()
          .modelFromNetwork(_modelUrl, token: huggingFaceToken)
          .tokenizerFromNetwork(_tokenizerUrl, token: huggingFaceToken)
          .withModelProgress(modelCb)
          .withTokenizerProgress(tokenizerCb)
          .install();

      // 通知 EmbeddingService 熱載入
      await EmbeddingService.instance.reload();

      tracker.completeDownload();
    } catch (e) {
      tracker.failDownload(e.toString());
      rethrow;
    }
  }

  /// 是否有模型下載正在進行（透過全域 tracker 判斷）。
  bool get isDownloading => EmbeddingProgressTracker.instance.isDownloading;

  /// 初始化 EmbeddingService（檢查是否有已安裝的模型）。
  ///
  /// App 啟動時呼叫：
  /// 1. initializeCore() — 註冊 LiteRT backend
  /// 2. 若 hasActiveEmbedder() 為 false 但磁碟上有模型檔案，
  ///    用 installEmbedder().modelFromFile().tokenizerFromFile().install()
  ///    把磁碟上的模型載入成 active embedder（install 是 idempotent，不重下載）
  /// 3. EmbeddingService.instance.initialize() — 取得 model handle
  Future<void> bootstrap({
    String? huggingFaceToken,
  }) async {
    await initializeCore(huggingFaceToken: huggingFaceToken);

    // [教練 Agent 2026-07-19] 修復：App 重啟後 hasActiveEmbedder() 為 false
    // 因為 active spec 是 in-memory，重啟後清空。但磁碟上的模型檔案還在。
    // 用 modelFromFile 從磁碟重新載入成 active，install() 是 idempotent。
    if (!FlutterGemma.hasActiveEmbedder()) {
      await _tryLoadFromDisk();
    }

    await EmbeddingService.instance.initialize();
  }

  /// 嘗試從磁碟載入已安裝的 EmbeddingGemma 模型。
  ///
  /// 模型檔案路徑（macOS App container）：
  ///   {appSupportDir}/flutter_gemma/embeddinggemma-300M_seq512_mixed-precision.tflite
  ///   {appSupportDir}/flutter_gemma/sentencepiece.model
  Future<void> _tryLoadFromDisk() async {
    try {
      final dir = await _getFlutterGemmaDir();
      final modelFile =
          '${dir.path}/embeddinggemma-300M_seq512_mixed-precision.tflite';
      final tokenizerFile = '${dir.path}/sentencepiece.model';

      debugPrint('[EmbeddingModelManager] 尋找模型: $modelFile');

      final modelExists = await File(modelFile).exists();
      final tokenizerExists = await File(tokenizerFile).exists();

      if (modelExists && tokenizerExists) {
        debugPrint(
            '[EmbeddingModelManager] 磁碟上找到模型，重新載入成 active embedder...');
        await FlutterGemma.installEmbedder()
            .modelFromFile(modelFile)
            .tokenizerFromFile(tokenizerFile)
            .install();
        debugPrint('[EmbeddingModelManager] 模型重新載入成功 ✅');
      } else {
        debugPrint(
            '[EmbeddingModelManager] 磁碟上無模型檔案（model=$modelExists, tokenizer=$tokenizerExists），維持 fallback 模式');
      }
    } catch (e) {
      debugPrint('[EmbeddingModelManager] 從磁碟載入模型失敗: $e');
    }
  }

  /// 取得 flutter_gemma 模型目錄。
  ///
  /// macOS App container 路徑：
  ///   ~/Library/Containers/{bundleId}/Data/Library/Application Support/{bundleId}/flutter_gemma/
  Future<Directory> _getFlutterGemmaDir() async {
    final appSupport = await getApplicationSupportDirectory();
    return Directory('${appSupport.path}/flutter_gemma');
  }
}
