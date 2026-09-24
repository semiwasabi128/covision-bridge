// kokoro_tts_service.dart
// Kokoro TTS 服務 — 管理本地 Python Kokoro server 的啟動/停止與 HTTP 通訊
//
// 架構：
//   Flutter App ←→ HTTP → Python kokoro_server.py (FastAPI)
//                              ↓
//                         Kokoro-82M 模型 + misaki[zh] 中文支援
//                              ↓
//                         音檔 bytes (WAV/MP3)
//
// 情緒控制：透過 emotion 參數傳遞（amused/anger/disgust/neutral/sleepiness），
// Python server 端使用 style vector 優化語音表現。
//
// 參考：local_model_runtime_service.dart 的 server 管理模式

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Kokoro TTS server 運行狀態
enum KokoroTtsPhase {
  stopped, // 已停止
  starting, // 啟動中
  running, // 運行中
  failed, // 啟動失敗
}

/// Kokoro TTS 語音合成請求參數
class KokoroTtsRequest {
  final String text; // 要合成的文字
  final String voice; // 聲音名稱（如 'zf_xiaoxiao'）
  final double speed; // 語速 0.5–2.0
  final String? emotion; // 情緒標籤（amused/anger/disgust/neutral/sleepiness）
  final double emotionSensitivity; // 情緒敏感度 0.0–1.0

  // [教練 Agent 2026-08-03] Phase 1 (C3): 混合聲音
  final String? secondaryVoice; // 副聲音（混合用，null=不混合）
  final double voiceBlend; // 主聲音比例 0.0~1.0

  const KokoroTtsRequest({
    required this.text,
    required this.voice,
    this.speed = 1.0,
    this.emotion,
    this.emotionSensitivity = 0.5,
    this.secondaryVoice,
    this.voiceBlend = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'voice': voice,
    'speed': speed,
    if (emotion != null) 'emotion': emotion,
    'emotion_sensitivity': emotionSensitivity,
    if (secondaryVoice != null) 'secondary_voice': secondaryVoice,
    'voice_blend': voiceBlend,
  };
}

/// Kokoro TTS 語音合成結果
class KokoroTtsResult {
  final Uint8List audioBytes; // 音檔二進位資料
  final String format; // 音檔格式（'wav' 或 'mp3'）
  final double? durationSec; // 音檔時長（秒）
  final int sampleRate; // 取樣率

  const KokoroTtsResult({
    required this.audioBytes,
    this.format = 'wav',
    this.durationSec,
    this.sampleRate = 24000,
  });
}

/// 可用的 Kokoro 聲音資訊
class KokoroVoice {
  final String id; // 聲音 ID（如 'zf_xiaoxiao'）
  final String name; // 顯示名稱（如 '小曉'）
  final String gender; // 性別（'female' / 'male'）
  final String language; // 語言（'zh' / 'en' 等）

  const KokoroVoice({
    required this.id,
    required this.name,
    required this.gender,
    required this.language,
  });

  factory KokoroVoice.fromJson(Map<String, dynamic> json) => KokoroVoice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? json['id'] as String? ?? '',
    gender: json['gender'] as String? ?? 'unknown',
    language: json['language'] as String? ?? 'zh',
  );
}

/// Kokoro TTS 服務 — 管理 Python Kokoro server 的生命週期與 API 呼叫
///
/// 使用方式：
/// ```dart
/// final tts = KokoroTtsService();
/// await tts.startServer();
/// final result = await tts.synthesize(KokoroTtsRequest(
///   text: '你好，我是你的夥伴。',
///   voice: 'zf_xiaoxiao',
/// ));
/// // 播放 result.audioBytes
/// await tts.stopServer();
/// ```
class KokoroTtsService {
  /// 預設 server 端口
  static const int defaultPort = 18900;

  /// 預設 Python 腳本路徑（相對於專案根目錄）
  static const String defaultScriptPath = 'python/kokoro_server.py';

  /// 預設 Python 執行檔
  static const String defaultPythonBin = 'python3';

  /// 健康檢查重試次數
  // [小葵 2026-09-06] 冷啟動載入 Kokoro-82M 實測 35~50s，舊值 10×2s=20s 會在
  // 模型載入中判定失敗並殺掉 server → 永遠 fallback 系統 TTS（機械人聲根因）。
  // 新預算 30×3s=90s；launchd 常駐後一般數秒內即就緒。
  static const int _healthRetryCount = 30;

  /// 健康檢查間隔（毫秒）
  static const int _healthRetryIntervalMs = 3000;

  /// 單次 TTS 請求超時（秒）
  static const int _ttsTimeoutSec = 60;

  KokoroTtsService({
    this._port = defaultPort,
    this._scriptPath = defaultScriptPath,
    this._pythonBin = defaultPythonBin,
    Dio? dio,
  }) : _dio = dio ?? Dio();
  final int _port;
  final String _scriptPath;
  final String _pythonBin;
  final Dio _dio;

  Process? _process;
  KokoroTtsPhase _phase = KokoroTtsPhase.stopped;
  String _lastError = '';

  /// 目前運行狀態
  KokoroTtsPhase get phase => _phase;

  /// 是否正在運行
  bool get isRunning => _phase == KokoroTtsPhase.running;

  /// server base URL
  String get baseUrl => 'http://127.0.0.1:$_port';

  /// 最後錯誤訊息
  String get lastError => _lastError;

  // ============================================================
  // Server 生命週期管理
  // ============================================================

  /// 啟動 Python Kokoro server
  ///
  /// [projectRoot] 為專案根目錄路徑，用於定位 python/kokoro_server.py。
  /// 若未提供則嘗試從當前目錄推測。
  ///
  /// [小葵 2026-08-30] 三段式啟動（金鑰匙原則——使用者零設定）：
  /// 1. 先健康檢查：port 18900 已有 server 在跑 → 直接重用（不重複 spawn）
  /// 2. 探測 venv Python：python/.venv/bin/python（kokoro 只裝在 venv，
  ///    系統 python3 是 3.9 沒有依賴，直接啟動必失敗）
  /// 3. 找不到 venv 才退回 defaultPythonBin（開發機外場景）
  Future<bool> startServer({String? projectRoot}) async {
    if (_phase == KokoroTtsPhase.running) {
      debugPrint('[KokoroTts] server 已在運行中');
      return true;
    }
    if (_phase == KokoroTtsPhase.starting) {
      debugPrint('[KokoroTts] server 啟動中，請稍候');
      return false;
    }

    // [小葵 2026-08-30] Step 1：先健康檢查——已有 server 直接重用。
    // 跟 18789 llama-server「port 被佔即重用」同一原則。
    if (await checkHealth()) {
      _phase = KokoroTtsPhase.running;
      debugPrint('[KokoroTts] ✅ 發現既有 server，直接重用：$baseUrl');
      return true;
    }

    _phase = KokoroTtsPhase.starting;
    _lastError = '';

    try {
      final fullPath = _resolveScriptPath(projectRoot);

      // [小葵 2026-08-30] Step 2：探測 venv Python（kokoro 依賴只裝在 venv）
      final resolvedRoot = projectRoot ?? _defaultProjectRoot();
      String pythonBin = _pythonBin;
      final venvPython = '$resolvedRoot/python/.venv/bin/python';
      if (await File(venvPython).exists()) {
        pythonBin = venvPython;
        debugPrint('[KokoroTts] 使用 venv Python：$pythonBin');
      } else {
        debugPrint('[KokoroTts] 未找到 venv（$venvPython），退回 $pythonBin');
      }

      debugPrint('[KokoroTts] 啟動 server：$pythonBin $fullPath --port $_port');

      _process = await Process.start(
        pythonBin,
        [fullPath, '--port', '$_port'],
        environment: {
          'PYTHONUNBUFFERED': '1',
        },
      );

      // 監聽 stdout/stderr 用於除錯
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[KokoroTts] stderr: $data');
        if (data.contains('Error') || data.contains('Traceback')) {
          _lastError = data.trim();
        }
      });

      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[KokoroTts] stdout: $data');
      });

      // 等待 server 就緒（健康檢查重試）
      final healthy = await _waitForHealth();
      if (healthy) {
        _phase = KokoroTtsPhase.running;
        debugPrint('[KokoroTts] ✅ server 已就緒：$baseUrl');
        return true;
      } else {
        _phase = KokoroTtsPhase.failed;
        _lastError = '健康檢查失敗，server 未在預期時間內就緒';
        debugPrint('[KokoroTts] ❌ $_lastError');
        await _killProcess();
        return false;
      }
    } catch (error) {
      _phase = KokoroTtsPhase.failed;
      _lastError = '啟動失敗：$error';
      debugPrint('[KokoroTts] ❌ $_lastError');
      await _killProcess();
      return false;
    }
  }

  /// 停止 Kokoro TTS server
  ///
  /// [小葵 2026-09-06] App 不再殺 Kokoro server——與 18789 llama-server 同原則：
  /// server 是共用資源（launchd 常駐，KeepAlive 顧活）。App 端只斷開追蹤，
  /// 不 termination。殺掉只會讓下一次對談重新冷啟動 35~50s 又失敗 fallback。
  Future<void> stopServer() async {
    debugPrint('[KokoroTts] 停止追蹤 server（不終止進程——launchd 常駐共用）');
    _process = null;
    _phase = KokoroTtsPhase.stopped;
  }

  /// 檢查 server 是否健康
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      return response.statusCode == 200 &&
          response.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // TTS API 呼叫
  // ============================================================

  /// 合成語音（同步模式 — 等待完整音檔後回傳）
  ///
  /// 回傳 [KokoroTtsResult] 包含音檔 bytes，失敗時拋出例外。
  Future<KokoroTtsResult> synthesize(KokoroTtsRequest request) async {
    if (!isRunning) {
      throw StateError('Kokoro TTS server 未運行，請先呼叫 startServer()');
    }

    debugPrint(
      '[KokoroTts] 合成語音：'
      'voice=${request.voice}, '
      'speed=${request.speed}, '
      'emotion=${request.emotion ?? "none"}, '
      'text.length=${request.text.length}',
    );

    final response = await _dio.post<List<int>>(
      '$baseUrl/tts',
      data: request.toJson(),
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: _ttsTimeoutSec),
        sendTimeout: const Duration(seconds: 10),
      ),
    );

    final bytes = Uint8List.fromList(response.data ?? []);
    if (bytes.isEmpty) {
      throw StateError('Kokoro TTS 回傳空音檔');
    }

    // 從 response headers 取得格式資訊
    final contentType = response.headers.value('content-type') ?? '';
    final format = contentType.contains('mp3') ? 'mp3' : 'wav';

    debugPrint(
      '[KokoroTts] ✅ 合成完成：${bytes.length} bytes, format=$format',
    );

    return KokoroTtsResult(
      audioBytes: bytes,
      format: format,
      sampleRate: 24000,
    );
  }

  /// 合成語音（串流模式 — 逐段回傳音檔 chunks）
  ///
  /// [onChunk] 會在每收到一段音檔資料時被呼叫。
  /// 適合即時播放場景，減少首音延遲。
  Future<void> synthesizeStream(
    KokoroTtsRequest request, {
    required void Function(Uint8List chunk) onChunk,
  }) async {
    if (!isRunning) {
      throw StateError('Kokoro TTS server 未運行，請先呼叫 startServer()');
    }

    debugPrint('[KokoroTts] 串流合成：voice=${request.voice}');

    final response = await _dio.post<ResponseBody>(
      '$baseUrl/tts/stream',
      data: request.toJson(),
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(seconds: _ttsTimeoutSec),
        sendTimeout: const Duration(seconds: 10),
      ),
    );

    final stream = response.data?.stream;
    if (stream == null) {
      throw StateError('Kokoro TTS 串流回傳為空');
    }

    await for (final chunk in stream) {
      onChunk(Uint8List.fromList(chunk));
    }

    debugPrint('[KokoroTts] ✅ 串流合成完成');
  }

  /// 取得可用聲音列表
  ///
  /// 回傳 server 支援的所有聲音，包含中文與英文。
  Future<List<KokoroVoice>> listVoices() async {
    if (!isRunning) {
      throw StateError('Kokoro TTS server 未運行，請先呼叫 startServer()');
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/voices',
      options: Options(
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ),
    );

    final voicesList = response.data?['voices'] as List? ?? [];
    return voicesList
        .map((item) =>
            item is Map ? KokoroVoice.fromJson(Map<String, dynamic>.from(item)) : null)
        .whereType<KokoroVoice>()
        .toList();
  }

  // ============================================================
  // 內部方法
  // ============================================================

  /// 解析 Python 腳本完整路徑
  String _resolveScriptPath(String? projectRoot) {
    if (projectRoot != null) {
      return '$projectRoot/$_scriptPath';
    }
    return _scriptPath;
  }

  /// [小葵 2026-08-30] 推測專案根目錄（venv 探測用）
  ///
  /// App 打包後 CWD 不可靠，用幾個候選路徑探測（不含個人路徑——開源紅牌）：
  /// 1. 環境變數 BRIDGE_APP_ROOT（部署機明確指定）
  /// 2. 當前工作目錄（flutter run / 從 repo 啟動時可靠）
  String _defaultProjectRoot() {
    final envRoot = Platform.environment['BRIDGE_APP_ROOT'];
    final candidates = [
      if (envRoot != null && envRoot.isNotEmpty) envRoot,
      Directory.current.path,
    ];
    for (final root in candidates) {
      if (File('$root/$_scriptPath').existsSync()) {
        return root;
      }
    }
    return candidates.isNotEmpty ? candidates.last : Directory.current.path;
  }

  /// 等待 server 健康檢查通過
  Future<bool> _waitForHealth() async {
    for (int attempt = 0; attempt < _healthRetryCount; attempt++) {
      debugPrint(
        '[KokoroTts] 健康檢查 attempt ${attempt + 1}/$_healthRetryCount',
      );
      if (await checkHealth()) {
        return true;
      }
      await Future.delayed(
        const Duration(milliseconds: _healthRetryIntervalMs),
      );
    }
    return false;
  }

  /// 終止 Python 進程
  Future<void> _killProcess() async {
    final process = _process;
    if (process == null) return;
    _process = null;
    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (error) {
      debugPrint('[KokoroTts] 終止進程時發生錯誤：$error');
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // 忽略 — 進程可能已結束
      }
    }
  }

  /// 釋放資源（等同 stopServer）
  Future<void> dispose() async {
    await stopServer();
    _dio.close();
  }
}

/// 中文聲音預設列表（與 Python server 端保持同步）
///
/// 這些是 Kokoro 模型內建的中文字音，可在 server 未啟動時用於 UI 顯示。
const List<KokoroVoice> kokoroChineseVoices = [
  KokoroVoice(id: 'zf_xiaoxiao', name: '小曉', gender: 'female', language: 'zh'),
  KokoroVoice(id: 'zf_xiaobei', name: '小貝', gender: 'female', language: 'zh'),
  KokoroVoice(id: 'zf_xiaoni', name: '小霓', gender: 'female', language: 'zh'),
  KokoroVoice(id: 'zf_xiaoyi', name: '小藝', gender: 'female', language: 'zh'),
  KokoroVoice(id: 'zm_yunjian', name: '雲健', gender: 'male', language: 'zh'),
  KokoroVoice(id: 'zm_yunxi', name: '雲希', gender: 'male', language: 'zh'),
  KokoroVoice(id: 'zm_yunxia', name: '雲夏', gender: 'male', language: 'zh'),
  KokoroVoice(id: 'zm_yunyang', name: '雲揚', gender: 'male', language: 'zh'),
];

/// 支援的情緒標籤
const List<String> kokoroEmotions = [
  'neutral', // 中性
  'amused', // 愉悅
  'anger', // 憤怒
  'disgust', // 厭惡
  'sleepiness', // 困倦
];

/// 將情緒標籤轉為中文顯示名稱
String kokoroEmotionLabel(String emotion) {
  return switch (emotion) {
    'neutral' => '中性',
    'amused' => '愉悅',
    'anger' => '憤怒',
    'disgust' => '厭惡',
    'sleepiness' => '困倦',
    _ => emotion,
  };
}
