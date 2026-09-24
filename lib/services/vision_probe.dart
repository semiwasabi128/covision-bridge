// [教練 Agent P2 2026-08-08] Vision Probe
//
// P2 合約要求：
// - 啟動前 probe llama-server 是否接受 vision multimodal request
// - 讀取 runtime 實際 model id，不可只看 catalog label
// - timeout 設定與顯示文字使用同一個值
// - 不可因為 image generation 失敗就自動轉 vision
//
// 使用方式：
//   final probe = VisionProbe();
//   final result = await probe.check(serverUrl);
//   if (result.supported) { ... }

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Vision probe 結果
class VisionProbeResult {
  /// 本地模型是否接受 vision multimodal request
  final bool supported;

  /// runtime 實際 model id（不是 catalog label）
  final String? modelId;

  /// probe 用的 server URL
  final String? serverUrl;

  /// 不支援時的原因（給使用者看的中文）
  final String? reason;

  /// probe 花的時間（ms）
  final int elapsedMs;

  const VisionProbeResult({
    required this.supported,
    this.modelId,
    this.serverUrl,
    this.reason,
    required this.elapsedMs,
  });

  @override
  String toString() =>
      'VisionProbeResult(supported=$supported, model=$modelId, '
      'url=$serverUrl, elapsed=${elapsedMs}ms)';
}

/// [教練 Agent P2 2026-08-08] 偵測本地模型是否支援 vision multimodal
///
/// 不是看 model name 猜（名字裡有 "vision" 不代表真的能用），
/// 而是送一個極小的 multimodal request 看它是否正常回應。
///
/// 判斷邏輯：
/// 1. GET /v1/models → 取得實際 model id
/// 2. POST /v1/chat/completions 帶一個 1x1 透明 PNG + 極短 prompt
/// 3. HTTP 200 + 有回應文字 → supported
/// 4. HTTP 4xx 帶 "vision"/"multimodal"/"image" 相關錯誤 → 不支援
/// 5. timeout → 不支援
class VisionProbe {
  final Dio _dio;

  /// [教練 Agent P2] probe 超時 = 8 秒（和 UI 顯示的「正在分析圖片…」 timeout 一致）
  static const probeTimeout = Duration(seconds: 8);

  /// Vision 任務實際超時（和 UI 顯示文字共用這個值）
  static const visionTaskTimeout = Duration(seconds: 30);

  /// 1x1 透明 PNG 的 base64
  static const _tinyPngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

  VisionProbe({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: probeTimeout,
              receiveTimeout: probeTimeout,
            ));

  /// 檢查指定的本地模型伺服器是否支援 vision
  Future<VisionProbeResult> check(String serverUrl) async {
    final sw = Stopwatch()..start();

    // 1. 先取 model id
    final modelId = await _fetchModelId(serverUrl);
    if (modelId == null) {
      sw.stop();
      return VisionProbeResult(
        supported: false,
        serverUrl: serverUrl,
        reason: '無法連接本地模型伺服器',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    // 2. 送一個 tiny multimodal request 測試
    try {
      final response = await _dio.post<dynamic>(
        '$serverUrl/v1/chat/completions',
        data: {
          'model': modelId,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'What color?'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$_tinyPngBase64',
                  },
                },
              ],
            }
          ],
          'max_tokens': 5,
          'temperature': 0.1,
        },
      ).timeout(probeTimeout);

      final data = response.data as Map<String, dynamic>?;
      final choices = data?['choices'] as List<dynamic>?;
      final hasContent = choices != null &&
          choices.isNotEmpty &&
          (choices.first as Map)['message']?['content'] != null;

      sw.stop();
      return VisionProbeResult(
        supported: hasContent,
        modelId: modelId,
        serverUrl: serverUrl,
        reason: hasContent ? null : '模型回應為空，可能不支援圖片輸入',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final detail = e.message ?? e.type.name;
      // 如果錯誤訊息提到 vision/image/multimodal，明確判斷為不支援
      final isVisionUnsupported = detail.toLowerCase().containsAny([
        'vision',
        'multimodal',
        'image',
        'not supported',
        'unsupported',
      ]);
      return VisionProbeResult(
        supported: false,
        modelId: modelId,
        serverUrl: serverUrl,
        reason: isVisionUnsupported
            ? '目前載入的本地模型（$modelId）不支援圖片辨識'
            : '本地模型連線異常：$detail',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return VisionProbeResult(
        supported: false,
        modelId: modelId,
        serverUrl: serverUrl,
        reason: '偵測逾時，本地模型可能不支援圖片辨識',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// GET /v1/models 取得實際載入的 model id
  Future<String?> _fetchModelId(String serverUrl) async {
    try {
      final response = await _dio.get<dynamic>(
        '$serverUrl/v1/models',
      ).timeout(probeTimeout);

      final data = response.data as Map<String, dynamic>?;
      final models = data?['data'] as List<dynamic>?;
      if (models != null && models.isNotEmpty) {
        final firstModel = models.first as Map<String, dynamic>;
        return firstModel['id']?.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VisionProbe] _fetchModelId failed: $e');
      }
    }
    return null;
  }
}

extension _StringContainsAny on String {
  bool containsAny(List<String> patterns) {
    final lower = toLowerCase();
    return patterns.any((p) => lower.contains(p));
  }
}
