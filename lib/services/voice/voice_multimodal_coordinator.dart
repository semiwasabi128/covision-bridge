// voice_multimodal_coordinator.dart — Phase 3 多模態混合協調器
//
// 統一協調語音對話和多模態操作：
//   3.1 語音 + 螢幕截圖同步 — 使用者說話時自動截圖
//   3.2 語音指導 + 視覺分析 — 截圖 → 視覺分析 → 串流 TTS 念結果
//   3.3 語音 + 程式碼操作同步 — 讀檔 → 生成修復 → 套用 → 驗證
//   3.4 語音 + 畫布操作同步 — 解析意圖 → 放節點 → 連接
//
// 設計要點：
//   - 所有多模態操作都是非同步的，不阻塞語音對話
//   - 操作過程中的中間結果透過 VoiceStreamingTts 念出來
//   - 操作可以被使用者插嘴中斷
//   - 用回調函數和現有工具整合，不直接修改工具程式碼

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_progress_reporter.dart';
import 'voice_streaming_tts.dart';

// ─── 工具回調 typedef ───

/// 螢幕截圖回調 — 回傳截圖檔案路徑，失敗回傳 null
typedef ScreenCaptureCallback = Future<String?> Function();

/// 視覺分析回調 — 接收圖片路徑和查詢文字，回傳分析結果
typedef VisionAnalyzeCallback = Future<String> Function(
  String imagePath,
  String query,
);

/// 程式碼生成回調 — 接收提示詞和上下文，回傳生成的程式碼
typedef CodeGenerateCallback = Future<String> Function(
  String prompt, {
  String? context,
});

/// 讀取檔案回調 — 接收檔案路徑，回傳檔案內容
typedef ReadFileCallback = Future<String> Function(String path);

/// 修補檔案回調 — 接收路徑、舊文字、新文字，回傳是否成功
typedef PatchFileCallback = Future<bool> Function(
  String path,
  String old,
  String new_,
);

/// 執行終端指令回調 — 接收指令，回傳輸出結果
typedef RunTerminalCallback = Future<String> Function(String command);

/// 畫布放置節點回調 — 接收內容和可選父節點 ID
typedef CanvasPlaceCallback = Future<void> Function(
  String content, {
  String? parentId,
});

/// 畫布連接節點回調 — 接收起點和終點節點 ID
typedef CanvasConnectCallback = Future<void> Function(
  String fromId,
  String toId,
);

/// 畫布放置節點回傳結果（含節點 ID，供連接使用）
class CanvasPlaceResult {
  /// 節點 ID
  final String id;

  /// 節點內容
  final String content;

  const CanvasPlaceResult({required this.id, required this.content});
}

/// 帶回傳值的畫布放置回調 — 回傳節點 ID 供後續連接
typedef CanvasPlaceWithIdCallback = Future<CanvasPlaceResult> Function(
  String content, {
  String? parentId,
});

// ─── 多模態任務類型列舉 ───

/// 多模態任務類型
enum MultimodalTaskType {
  /// 螢幕截圖
  screenCapture,

  /// 視覺分析
  visionAnalyze,

  /// 程式碼操作
  codeTask,

  /// 畫布操作
  canvasTask,
}

// ─── VoiceMultimodalCoordinator ───

/// Phase 3 多模態混合協調器
///
/// 協調語音對話和多模態操作，讓 VoiceEngine 在使用者說話時
/// 能同步觸發視覺分析、程式碼操作、畫布操作。
///
/// 使用方式：
///   final coordinator = VoiceMultimodalCoordinator(
///     streamingTts: streamingTts,
///     progressReporter: progressReporter,
///     onScreenCapture: () => agentLoop.executeTool('screen_capture', {}),
///     onVisionAnalyze: (imagePath, query) =>
///         agentLoop.executeTool('local_vision_analyze', {
///           'image_path': imagePath,
///           'query': query,
///         }),
///     // ... 其他回調
///   );
///
///   // 3.1 使用者開始說話時截圖
///   final screenshotPath = await coordinator.captureScreenOnSpeech();
///
///   // 3.2 視覺分析
///   final analysis = await coordinator.analyzeAndSpeak('螢幕上有什麼問題？');
///
///   // 3.3 程式碼修復
///   final result = await coordinator.executeCodeTask(
///     '幫我修這個檔案的型別錯誤',
///     'lib/services/voice/voice_engine.dart',
///   );
///
///   // 3.4 畫布操作
///   await coordinator.executeCanvasTask('幫我建一個語音功能的計畫');
class VoiceMultimodalCoordinator {
  VoiceMultimodalCoordinator({
    this.onScreenCapture,
    this.onVisionAnalyze,
    this.onCodeGenerate,
    this.onReadFile,
    this.onPatchFile,
    this.onRunTerminal,
    this.onCanvasPlace,
    this.onCanvasPlaceWithId,
    this.onCanvasConnect,
    required this.streamingTts,
    required this.progressReporter,
  });

  // ─── 注入的工具回調 ───

  /// 螢幕截圖回調（3.1, 3.2 使用）
  final ScreenCaptureCallback? onScreenCapture;

  /// 視覺分析回調（3.2 使用）
  final VisionAnalyzeCallback? onVisionAnalyze;

  /// 程式碼生成回調（3.3 使用）
  final CodeGenerateCallback? onCodeGenerate;

  /// 讀取檔案回調（3.3 使用）
  final ReadFileCallback? onReadFile;

  /// 修補檔案回調（3.3 使用）
  final PatchFileCallback? onPatchFile;

  /// 執行終端指令回調（3.3 使用）
  final RunTerminalCallback? onRunTerminal;

  /// 畫布放置節點回調 — 簡易版（3.4 使用，不回傳 ID）
  final CanvasPlaceCallback? onCanvasPlace;

  /// 畫布放置節點回調 — 帶 ID 回傳（3.4 使用，供連接）
  final CanvasPlaceWithIdCallback? onCanvasPlaceWithId;

  /// 畫布連接節點回調（3.4 使用）
  final CanvasConnectCallback? onCanvasConnect;

  // ─── 串流 TTS + 進度報告器 ───

  /// 串流 TTS — 念進度用
  final VoiceStreamingTts streamingTts;

  /// 進度報告器 — 第三層現況回報 + 第四層反問
  final VoiceProgressReporter progressReporter;

  // ─── 中斷控制 ───

  /// 是否被中斷（使用者插嘴時設為 true）
  bool _interrupted = false;

  /// 當前正在執行的任務類型（null = 沒有進行中的任務）
  MultimodalTaskType? _currentTask;

  /// 取消 completer — 用於中斷正在等待的 Future
  Completer<void>? _cancelCompleter;

  // ─── 中斷管理 ───

  /// 使用者插嘴中斷
  ///
  /// 停止所有進行中的多模態操作。
  /// 由 VoiceEngine.onUserInterrupt() 呼叫。
  void onUserInterrupt() {
    debugPrint('[MultimodalCoordinator] 使用者插嘴，中斷多模態操作');
    _interrupted = true;
    _cancelCompleter?.complete();
    _cancelCompleter = null;
    streamingTts.stop();
    progressReporter.stop();
  }

  /// 重置中斷狀態（新一輪對話開始時呼叫）
  void reset() {
    _interrupted = false;
    _currentTask = null;
    _cancelCompleter?.complete();
    _cancelCompleter = null;
    streamingTts.reset();
    progressReporter.reset();
  }

  /// 檢查是否已被中斷
  bool get isInterrupted => _interrupted;

  /// 當前是否有進行中的多模態任務
  bool get hasActiveTask => _currentTask != null;

  /// 當前任務類型
  MultimodalTaskType? get currentTask => _currentTask;

  // ─── 內部工具方法 ───

  /// 建立中斷檢查點
  ///
  /// 如果使用者已插嘴，拋出 [_MultimodalInterruptedException]。
  void _checkInterrupted() {
    if (_interrupted) {
      throw _MultimodalInterruptedException();
    }
  }

  /// 念一段文字到串流 TTS
  void _speak(String text) {
    if (_interrupted) return;
    streamingTts.feed(text);
  }

  /// 回報進度（第三層現況回報）
  void _reportProgress(String text) {
    if (_interrupted) return;
    progressReporter.onProgress(text);
  }

  // ─── 3.1 語音 + 螢幕截圖同步 ───

  /// 使用者開始說話時自動截圖
  ///
  /// 在 VoiceEngine.onUserStartedSpeaking() 時呼叫。
  /// 截圖結果可以和語音文字一起送給 AgentLoop，
  /// 讓 Agent 不只聽到使用者說什麼，還看到使用者看什麼。
  ///
  /// 回傳截圖檔案路徑；如果截圖失敗或未設定回調，回傳 null。
  ///
  /// 此方法是非同步的，不會阻塞語音流程 —
  /// 截圖在背景進行，即使截圖還沒完成，語音辨識照樣繼續。
  Future<String?> captureScreenOnSpeech() async {
    if (onScreenCapture == null) {
      debugPrint('[MultimodalCoordinator] 未設定 onScreenCapture，跳過截圖');
      return null;
    }

    _currentTask = MultimodalTaskType.screenCapture;

    try {
      debugPrint('[MultimodalCoordinator] 3.1 使用者說話 → 自動截圖');
      final screenshotPath = await onScreenCapture!();

      if (screenshotPath != null) {
        debugPrint('[MultimodalCoordinator] 截圖完成: $screenshotPath');
      } else {
        debugPrint('[MultimodalCoordinator] 截圖失敗（回傳 null）');
      }

      return screenshotPath;
    } catch (e) {
      debugPrint('[MultimodalCoordinator] 截圖例外: $e');
      return null;
    } finally {
      _currentTask = null;
    }
  }

  // ─── 3.2 語音指導 + 視覺分析 ───

  /// 語音指導 + 視覺分析
  ///
  /// 當使用者問「螢幕上有什麼問題」時：
  ///   1. screen_capture 截圖
  ///   2. local_vision_analyze 分析截圖
  ///   3. 分析結果透過串流 TTS 念出來
  ///
  /// 分析過程的中間結果透過 VoiceProgressReporter 念出來（第三層）。
  ///
  /// [userQuery] — 使用者的問題（例：「螢幕上有什麼問題？」）
  /// 回傳視覺分析的結果文字。
  Future<String> analyzeAndSpeak(String userQuery) async {
    _interrupted = false;
    _currentTask = MultimodalTaskType.visionAnalyze;
    progressReporter.start();

    try {
      // ── 步驟 1：截圖 ──
      _reportProgress('好，我先看看你的螢幕。');
      _checkInterrupted();

      if (onScreenCapture == null) {
        _speak('抱歉，我目前沒有截圖功能。');
        progressReporter.onComplete('截圖功能未設定');
        return '截圖功能未設定';
      }

      final screenshotPath = await onScreenCapture!();
      _checkInterrupted();

      if (screenshotPath == null) {
        _speak('截圖失敗了，你能再說一次嗎？');
        progressReporter.onComplete('截圖失敗');
        return '截圖失敗';
      }

      _reportProgress('截圖好了，我來分析一下。');
      _checkInterrupted();

      // ── 步驟 2：視覺分析 ──
      if (onVisionAnalyze == null) {
        _speak('抱歉，我目前沒有視覺分析功能。');
        progressReporter.onComplete('視覺分析功能未設定');
        return '視覺分析功能未設定';
      }

      final analysisResult = await onVisionAnalyze!(screenshotPath, userQuery);
      _checkInterrupted();

      // ── 步驟 3：串流 TTS 念出分析結果 ──
      _reportProgress('分析完了。');
      _speak(analysisResult);

      progressReporter.onComplete(analysisResult);
      streamingTts.flush();

      debugPrint('[MultimodalCoordinator] 3.2 視覺分析完成: $analysisResult');
      return analysisResult;
    } on _MultimodalInterruptedException {
      debugPrint('[MultimodalCoordinator] 3.2 視覺分析被中斷');
      _speak('好，我先停。');
      return '被使用者中斷';
    } catch (e) {
      debugPrint('[MultimodalCoordinator] 3.2 視覺分析例外: $e');
      _speak('分析時出了點問題：$e');
      progressReporter.onComplete('分析失敗: $e');
      return '分析失敗: $e';
    } finally {
      _currentTask = null;
    }
  }

  // ─── 3.3 語音 + 程式碼操作同步 ───

  /// 語音 + 程式碼操作同步
  ///
  /// 當使用者說「幫我修這個檔案」時：
  ///   1. read_source_file 讀檔
  ///   2. local_code_generate 生成修復程式碼
  ///   3. patch_source_file 套用
  ///   4. run_terminal dart analyze 驗證
  ///   5. 全程透過串流 TTS 報告進度
  ///
  /// [userQuery] — 使用者的修復需求（例：「幫我修這個檔案的型別錯誤」）
  /// [filePath] — 要修復的檔案路徑
  /// 回傳修復結果的摘要文字。
  Future<String> executeCodeTask(
    String userQuery,
    String filePath,
  ) async {
    _interrupted = false;
    _currentTask = MultimodalTaskType.codeTask;
    progressReporter.start();

    try {
      // ── 步驟 1：讀取檔案 ──
      _reportProgress('好，我先讀一下 $filePath。');
      _checkInterrupted();

      if (onReadFile == null) {
        _speak('抱歉，我目前沒有讀檔功能。');
        progressReporter.onComplete('讀檔功能未設定');
        return '讀檔功能未設定';
      }

      final fileContent = await onReadFile!(filePath);
      _checkInterrupted();

      _reportProgress('檔案讀好了，我來想想怎麼修。');
      _checkInterrupted();

      // ── 步驟 2：生成修復程式碼 ──
      if (onCodeGenerate == null) {
        _speak('抱歉，我目前沒有程式碼生成功能。');
        progressReporter.onComplete('程式碼生成功能未設定');
        return '程式碼生成功能未設定';
      }

      final codeGenPrompt = StringBuffer()
        ..writeln('使用者需求：$userQuery')
        ..writeln()
        ..writeln('檔案路徑：$filePath')
        ..writeln()
        ..writeln('目前檔案內容：')
        ..writeln(fileContent)
        ..writeln()
        ..writeln('請生成修復後的完整檔案內容。只輸出程式碼，不要加說明。');

      final generatedCode = await onCodeGenerate!(
        codeGenPrompt.toString(),
        context: fileContent,
      );
      _checkInterrupted();

      _reportProgress('修復程式碼生成好了，我來套用。');
      _checkInterrupted();

      // ── 步驟 3：套用修補 ──
      if (onPatchFile == null) {
        _speak('抱歉，我目前沒有檔案修補功能。');
        progressReporter.onComplete('檔案修補功能未設定');
        return '檔案修補功能未設定';
      }

      // 用整檔替換方式套用：舊內容 → 新內容
      final patchSuccess = await onPatchFile!(
        filePath,
        fileContent,
        generatedCode,
      );
      _checkInterrupted();

      if (!patchSuccess) {
        _speak('套用修補失敗了，檔案內容可能已經變動。');
        progressReporter.onComplete('套用修補失敗');
        return '套用修補失敗';
      }

      _reportProgress('修補套用好了，我來跑 dart analyze 驗證。');
      _checkInterrupted();

      // ── 步驟 4：驗證 ──
      if (onRunTerminal == null) {
        _speak('修補已套用，但我沒有終端功能可以驗證。');
        progressReporter.onComplete('修補已套用（無法驗證）');
        return '修補已套用（無法驗證）';
      }

      final analyzeOutput = await onRunTerminal!('dart analyze $filePath');
      _checkInterrupted();

      // ── 步驟 5：報告結果 ──
      final hasErrors = analyzeOutput.contains('error -');
      final hasWarnings = analyzeOutput.contains('warning -');

      String summary;
      if (!hasErrors && !hasWarnings) {
        summary = '修好了，dart analyze 沒有問題。';
        _speak(summary);
      } else if (!hasErrors) {
        final warningCount =
            'warning -'.allMatches(analyzeOutput).length;
        summary = '修好了，但有 $warningCount 個警告。';
        _speak(summary);
        _speak(analyzeOutput);
      } else {
        final errorCount = 'error -'.allMatches(analyzeOutput).length;
        summary = '修了，但 dart analyze 還有 $errorCount 個錯誤。';
        _speak(summary);
        _speak(analyzeOutput);
      }

      progressReporter.onComplete(summary);
      streamingTts.flush();

      debugPrint('[MultimodalCoordinator] 3.3 程式碼任務完成: $summary');
      return summary;
    } on _MultimodalInterruptedException {
      debugPrint('[MultimodalCoordinator] 3.3 程式碼任務被中斷');
      _speak('好，我先停。');
      return '被使用者中斷';
    } catch (e) {
      debugPrint('[MultimodalCoordinator] 3.3 程式碼任務例外: $e');
      _speak('修檔時出了點問題：$e');
      progressReporter.onComplete('修檔失敗: $e');
      return '修檔失敗: $e';
    } finally {
      _currentTask = null;
    }
  }

  // ─── 3.4 語音 + 畫布操作同步 ───

  /// 語音 + 畫布操作同步
  ///
  /// 當使用者說「幫我建一個計畫」時：
  ///   1. 解析使用者意圖（從自然語言提取計畫結構）
  ///   2. canvas_place 放節點
  ///   3. canvas_connect 連接節點
  ///   4. 全程透過串流 TTS 報告
  ///
  /// [userQuery] — 使用者的畫布需求（例：「幫我建一個語音功能的計畫」）
  Future<void> executeCanvasTask(String userQuery) async {
    _interrupted = false;
    _currentTask = MultimodalTaskType.canvasTask;
    progressReporter.start();

    try {
      // ── 步驟 1：解析使用者意圖 ──
      _reportProgress('好，我來幫你建計畫。');
      _checkInterrupted();

      final planNodes = _parsePlanFromQuery(userQuery);
      _checkInterrupted();

      if (planNodes.isEmpty) {
        _speak('我沒聽清楚要建什麼計畫，你能再說一次嗎？');
        progressReporter.onComplete('無法解析計畫意圖');
        return;
      }

      _reportProgress('我規劃了 ${planNodes.length} 個節點。');
      _checkInterrupted();

      // ── 步驟 2：放置節點 ──
      if (onCanvasPlaceWithId == null && onCanvasPlace == null) {
        _speak('抱歉，我目前沒有畫布功能。');
        progressReporter.onComplete('畫布功能未設定');
        return;
      }

      final placedNodes = <CanvasPlaceResult>[];

      for (var i = 0; i < planNodes.length; i++) {
        _checkInterrupted();

        final nodeContent = planNodes[i];

        if (onCanvasPlaceWithId != null) {
          final result = await onCanvasPlaceWithId!(
            nodeContent,
            parentId: i > 0 ? placedNodes[i - 1].id : null,
          );
          placedNodes.add(result);
        } else if (onCanvasPlace != null) {
          // 簡易版：不回傳 ID，只放置
          await onCanvasPlace!(
            nodeContent,
            parentId: null,
          );
          // 用索引作為假 ID（簡易模式無法精確連接）
          placedNodes.add(CanvasPlaceResult(
            id: 'node_$i',
            content: nodeContent,
          ));
        }

        _reportProgress('放了第 ${i + 1} 個節點：$nodeContent');
      }

      _checkInterrupted();

      // ── 步驟 3：連接節點 ──
      if (onCanvasConnect != null && placedNodes.length > 1) {
        _reportProgress('現在來連接節點。');

        for (var i = 0; i < placedNodes.length - 1; i++) {
          _checkInterrupted();

          await onCanvasConnect!(
            placedNodes[i].id,
            placedNodes[i + 1].id,
          );
        }
      }

      // ── 步驟 4：報告完成 ──
      final summary = '計畫建好了，一共 ${placedNodes.length} 個節點。';
      _speak(summary);

      progressReporter.onComplete(summary);
      streamingTts.flush();

      debugPrint('[MultimodalCoordinator] 3.4 畫布任務完成: $summary');
    } on _MultimodalInterruptedException {
      debugPrint('[MultimodalCoordinator] 3.4 畫布任務被中斷');
      _speak('好，我先停。');
    } catch (e) {
      debugPrint('[MultimodalCoordinator] 3.4 畫布任務例外: $e');
      _speak('建計畫時出了點問題：$e');
      progressReporter.onComplete('畫布任務失敗: $e');
    } finally {
      _currentTask = null;
    }
  }

  /// 從使用者查詢解析計畫節點
  ///
  /// Phase 3 先用簡單的關鍵字解析：
  /// - 如果使用者提到「計畫」「plan」→ 建立標準計畫結構
  /// - 如果使用者提到具體功能名 → 圍繞該功能建節點
  ///
  /// 實際整合時可以用 local_code_generate 或 delegate_subagent 生成更精細的計畫。
  List<String> _parsePlanFromQuery(String query) {
    final nodes = <String>[];

    // 偵測「計畫」「plan」關鍵字
    final isPlanRequest =
        query.contains('計畫') || query.contains('计划') || query.contains('plan');

    if (isPlanRequest) {
      // 嘗試從查詢中提取功能名稱
      final featureName = _extractFeatureName(query);

      if (featureName != null) {
        nodes.addAll([
          '$featureName — 需求分析',
          '$featureName — 架構設計',
          '$featureName — 核心實作',
          '$featureName — 測試驗證',
          '$featureName — 整合上線',
        ]);
      } else {
        // 通用計畫結構
        nodes.addAll([
          '需求分析',
          '架構設計',
          '核心實作',
          '測試驗證',
          '整合上線',
        ]);
      }
    } else {
      // 非計畫類請求 — 嘗試從查詢拆出步驟
      // 用換行或逗號分隔
      final parts = query
          .split(RegExp(r'[\n,，、]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (parts.length > 1) {
        nodes.addAll(parts);
      } else {
        // 只有一句話 — 建一個節點
        nodes.add(query);
      }
    }

    return nodes;
  }

  /// 從查詢中提取功能名稱
  ///
  /// 簡單規則：找「OOO 計畫」「OOO 功能」中的 OOO。
  String? _extractFeatureName(String query) {
    // 嘗試匹配「XXX 計畫」「XXX 功能」「XXX plan」
    final patterns = [
      RegExp(r'(.+?)的?計[畫划]'),
      RegExp(r'(.+?)的?功能'),
      RegExp(r'(.+?)\s*plan'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match != null && match.groupCount >= 1) {
        final name = match.group(1)!.trim();
        // 過濾掉太短或太長的名稱
        if (name.length >= 2 && name.length <= 20) {
          return name;
        }
      }
    }

    return null;
  }

  // ─── 資源管理 ───

  /// 釋放資源
  void dispose() {
    _cancelCompleter?.complete();
    _cancelCompleter = null;
    _currentTask = null;
  }
}

// ─── 內部例外 ───

/// 多模態操作被使用者中斷的例外
///
/// 在操作過程中如果使用者插嘴，會拋出此例外中斷流程。
class _MultimodalInterruptedException implements Exception {
  final String message = '多模態操作被使用者中斷';
}
