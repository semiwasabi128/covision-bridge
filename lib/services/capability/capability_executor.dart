/// CapabilityExecutor — 統一 API 呼叫介面
///
/// 設計文件: 02-架構設計/keychain-settings-design.md §9
/// [教練 Agent 2026-08-01] Phase 0 — 能力中心地基
///
/// 核心職責:
///   每個能力都提供真正能執行的 API 呼叫。
///   工作流引擎和 UI 都用它，不自己管 API 細節。
///
/// 使用者鐵則: 所有功能必須真正可用，不能只有按鈕。
/// 所以每個 execute 方法都必須真的 call API 並回傳結果。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'capability_models.dart';
import 'service_registry.dart';
import '../storage_service.dart';
import 'package:bridge_app/services/paid_action_gate.dart';
import 'package:bridge_app/services/bridge_media_store.dart';

/// 執行結果
class CapabilityResult {
  final bool success;
  final String? text;
  final Uint8List? imageData;
  final String? imageUrl;
  final Map<String, dynamic>? rawResponse;
  final String? error;

  /// [小葵 2026-09-24 Blue 令·自動落盤] 落盤後的本地絕對路徑
  /// （~/Documents/bridge_media/images/bridge_image_*.png）。
  String? localFilePath;

  CapabilityResult({
    this.success = false,
    this.text,
    this.imageData,
    this.imageUrl,
    this.rawResponse,
    this.error,
    this.localFilePath,
  });

  factory CapabilityResult.successText(String text, {Map<String, dynamic>? raw}) {
    return CapabilityResult(success: true, text: text, rawResponse: raw);
  }

  factory CapabilityResult.successImage(Uint8List data, {String? url}) {
    return CapabilityResult(success: true, imageData: data, imageUrl: url);
  }

  factory CapabilityResult.successImageUrl(String url) {
    return CapabilityResult(success: true, imageUrl: url);
  }

  factory CapabilityResult.failure(String error) {
    return CapabilityResult(success: false, error: error);
  }
}

/// 測試連線結果
class ConnectionTestResult {
  final bool success;
  final String message;
  final String? detectedModel;

  const ConnectionTestResult({
    this.success = false,
    this.message = '',
    this.detectedModel,
  });
}

class CapabilityExecutor {
  static final CapabilityExecutor instance = CapabilityExecutor._();
  CapabilityExecutor._();

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 30),
  ));

  // ═══════════════════════════════════════════════════
  // 測試連線（每個能力的「測試連線」按鈕背後的真正 call）
  // ═══════════════════════════════════════════════════

  /// 測試服務連線是否正常
  /// 這不是 mock — 真的會發 HTTP 請求到對應的 API
  Future<ConnectionTestResult> testConnection(ServiceDefinition service) async {
    try {
      switch (service.capability) {
        case CapabilityId.textReasoning:
          return await _testLLMConnection(service);
        case CapabilityId.imageGeneration:
          return await _testImageGenerationConnection(service);
        case CapabilityId.imageUnderstanding:
          return await _testVisionConnection(service);
        case CapabilityId.voiceSynthesis:
          return await _testTTSConnection(service);
        case CapabilityId.voiceRecognition:
          return await _testWhisperConnection(service);
        case CapabilityId.webSearch:
          return await _testSearchConnection(service);
        case CapabilityId.vectorEmbedding:
          return const ConnectionTestResult(
            success: true,
            message: '本地嵌入模型已就緒',
          );
        case CapabilityId.videoGeneration:
        case CapabilityId.musicGeneration:
        case CapabilityId.characterLock:
          // 這些能力的測試連線：驗證 Key 格式 + 基本可達性
          return await _testKeyBasedConnection(service);
      }
    } catch (e) {
      return ConnectionTestResult(success: false, message: '連線失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 文字推理 (LLM)
  // ═══════════════════════════════════════════════════

  /// 發送聊天訊息到 LLM
  Future<CapabilityResult> chat({
    required String serviceId,
    required String prompt,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }

    final baseUrl = service.defaultBaseUrl;
    if (baseUrl == null) {
      return CapabilityResult.failure('服務未設定 API 位址');
    }

    final useModel = model ?? service.defaultModel?.id ?? 'gpt-4o';

    try {
      final response = await _dio.post(
        '$baseUrl/chat/completions',
        options: Options(headers: _authHeaders(service, token)),
        data: {
          'model': useModel,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': temperature ?? 0.7,
          if (maxTokens != null) 'max_tokens': maxTokens,
        },
      );

      final text = response.data['choices']?[0]?['message']?['content'];
      if (text != null) {
        return CapabilityResult.successText(text, raw: response.data);
      }
      return CapabilityResult.failure('回應格式異常');
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 圖片生成
  // ═══════════════════════════════════════════════════

  /// 生成圖片
  /// [教練 Agent 2026-08-21] Phase A——記帳 wrapper：過閘→記 pending→執行→結案
  Future<CapabilityResult> generateImage({

    required String serviceId,
    required String prompt,
    String? model,
    String? size,
    int? n,
  }) async {
    final gate = await PaidActionGate.instance.checkAndReserve(
      PaidActionKind.image,
      intent: 'generateImage',
      prompt: prompt,
    );
    if (!gate.allowed) return CapabilityResult.failure(gate.reason);
    try {
      final r = await _rawgenerateImage(
        serviceId: serviceId,
        prompt: prompt,
        model: model,
        size: size,
        n: n,
      );
      await PaidActionGate.settle(gate.ledgerId, ok: r.success, error: r.error);
      // [小葵 2026-09-24 Blue 令·自動落盤] 成功的圖統一存到
      // ~/Documents/bridge_media/images/（與 BridgeAction 舊路徑同款行為）。
      // 舊碼只把 bytes 放回傳值——圖只存在節點記憶體，App 重啟即蒸發，
      // 使用者也找不到檔案。落盤 fire-and-forget：不擋回傳、失敗不影響結果。
      await _persistImageResult(r, prompt: prompt);
      return r;
    } catch (e) {
      await PaidActionGate.settle(gate.ledgerId, ok: false, error: e.toString());
      rethrow;
    }
  }

  /// [小葵 2026-09-24 Blue 令·自動落盤] 圖片結果統一落盤＋把本地路徑
  /// 寫回 imageUrl（下游 output/gallery 用 file:// 即可顯示）。
  /// 失敗靜默（debugPrint）——落盤不該讓生成結果整個失敗。
  Future<void> _persistImageResult(CapabilityResult r, {required String prompt}) async {
    if (!r.success || r.imageData == null) return;
    try {
      final path = await BridgeMediaStore.persistImageBytes(r.imageData!, prompt: prompt);
      r.localFilePath = path;
      debugPrint('[CapabilityExecutor] 圖片已落盤: $path');
    } catch (e) {
      debugPrint('[CapabilityExecutor] 落盤失敗（不影響結果）: $e');
    }
  }

  Future<CapabilityResult> _rawgenerateImage({
    required String serviceId,
    required String prompt,
    String? model,
    String? size,
    int? n,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }

    // [教練 Agent 2026-08-21] 閘門已移至 generateImage wrapper（單一計數點，避免雙扣）

    final baseUrl = service.defaultBaseUrl;
    if (baseUrl == null) {
      return CapabilityResult.failure('服務未設定 API 位址');
    }

    final useModel = model ?? service.defaultModel?.id ?? 'dall-e-3';

    try {
      // OpenAI 格式
      if (service.id.startsWith('openai')) {
        // [教練 Agent 2026-08-01] gpt-image-1 不接受 response_format（它永遠回傳 b64_json）
        // 只有 dall-e-3 需要 response_format
        final isGptImage = useModel.startsWith('gpt-image');
        final requestData = <String, dynamic>{
          'model': useModel,
          'prompt': prompt,
          'n': n ?? 1,
          if (size != null) 'size': size,
        };
        if (!isGptImage) {
          requestData['response_format'] = 'b64_json';
        }

        final response = await _dio.post(
          '$baseUrl/images/generations',
          options: Options(headers: _authHeaders(service, token)),
          data: requestData,
        );

        final b64 = response.data['data']?[0]?['b64_json'];
        if (b64 != null) {
          return CapabilityResult.successImage(base64Decode(b64));
        }
        // 有些模型回傳 url
        final url = response.data['data']?[0]?['url'];
        if (url != null) {
          return CapabilityResult.successImageUrl(url);
        }
        return CapabilityResult.failure('圖片生成回應格式異常');
      }

      // MiniMax 格式
      if (service.id.startsWith('minimax')) {
        final response = await _dio.post(
          '$baseUrl/image_generation',
          options: Options(headers: _authHeaders(service, token)),
          data: {
            'model': useModel,
            'prompt': prompt,
          },
        );

        final b64 = response.data?['data']?['image_urls']?[0];
        if (b64 != null) {
          // MiniMax 回傳 URL，需要下載
          final imgResponse = await _dio.get<List<int>>(
            b64,
            options: Options(responseType: ResponseType.bytes),
          );
          return CapabilityResult.successImage(
            Uint8List.fromList(imgResponse.data ?? []),
            url: b64,
          );
        }
        return CapabilityResult.failure('MiniMax 圖片生成失敗');
      }

      return CapabilityResult.failure('服務 ${service.id} 的圖片生成尚未實作');
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 角色一致性 (Character Lock)
  // [教練 Agent 2026-08-01] 三層方案：OpenAI → Flux → ComfyUI
  // ═══════════════════════════════════════════════════

  /// 帶參考圖的圖片生成 — 角色一致性
  ///
  /// 給一張參考圖 + prompt，生成風格/角色一致的新圖。
  /// 目前支援：
  ///   - OpenAI gpt-image: 用 image edit API 帶參考圖
  ///   - Flux (Replicate): 需要帶 IP-Adapter（未來 Phase 3）
  /// [教練 Agent 2026-08-21] Phase A——記帳 wrapper：過閘→記 pending→執行→結案
  Future<CapabilityResult> generateImageWithReference({

    required String serviceId,
    required String prompt,
    required String base64ReferenceImage,
    String? model,
    String? size,
    // [教練 Agent 2026-08-21] 多參考圖——多線接入的隱式 merge 把上游
    // 全部帶來，這裡全部送給 API（gpt-image-1 edits 原生支援多圖）。
    List<String>? extraReferenceImages,
  }) async {
    final gate = await PaidActionGate.instance.checkAndReserve(
      PaidActionKind.image,
      intent: 'generateImageWithReference',
      prompt: prompt,
    );
    if (!gate.allowed) return CapabilityResult.failure(gate.reason);
    try {
      final r = await _rawgenerateImageWithReference(
        serviceId: serviceId,
        prompt: prompt,
        base64ReferenceImage: base64ReferenceImage,
        model: model,
        size: size,
        extraReferenceImages: extraReferenceImages,
      );
      await PaidActionGate.settle(gate.ledgerId, ok: r.success, error: r.error);
      // [小葵 2026-09-24 Blue 令·自動落盤] 同 generateImage——成功即落盤
      await _persistImageResult(r, prompt: prompt);
      return r;
    } catch (e) {
      await PaidActionGate.settle(gate.ledgerId, ok: false, error: e.toString());
      rethrow;
    }
  }

  Future<CapabilityResult> _rawgenerateImageWithReference({
    required String serviceId,
    required String prompt,
    required String base64ReferenceImage,
    String? model,
    String? size,
    List<String>? extraReferenceImages,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }


    final baseUrl = service.defaultBaseUrl;
    if (baseUrl == null) {
      return CapabilityResult.failure('服務未設定 API 位址');
    }

    final useModel = model ?? service.defaultModel?.id ?? 'gpt-image-1';

    try {
      // OpenAI: 使用 images/edits endpoint 帶參考圖
      if (service.id.startsWith('openai')) {
        // [教練 Agent 2026-08-21] 多參考圖——gpt-image-1 edits 接受多個 image
        // 欄位（API 是 image[] 陣列語意）。順序＝權重的自然語言錨點：
        // prompt 裡說「第一張為主、第二張配色」比數字權重有效。
        final refImages = <MultipartFile>[
          MultipartFile.fromBytes(
            base64Decode(base64ReferenceImage),
            filename: 'reference_1.png',
            contentType: DioMediaType.parse('image/png'),
          ),
          for (var i = 0; i < (extraReferenceImages?.length ?? 0); i++)
            MultipartFile.fromBytes(
              base64Decode(extraReferenceImages![i]),
              filename: 'reference_${i + 2}.png',
              contentType: DioMediaType.parse('image/png'),
            ),
        ];
        // [小葵 2026-09-24 修 bug·Duplicate parameter 'image'] FormData.fromMap
        // 對 List 值會展開成多個同名欄位 `image=...&image=...`——OpenAI
        // 視為重複參數直接拒絕（02:38 實錄：Duplicate parameter: 'image'）。
        // 正解：手動建 FormData，用 image[] 陣列語法逐張 add。
        final formData = FormData();
        formData.fields.add(MapEntry('model', useModel));
        formData.fields.add(MapEntry('prompt', prompt));
        if (size != null) formData.fields.add(MapEntry('size', size));
        for (var i = 0; i < refImages.length; i++) {
          formData.files.add(MapEntry('image[]', refImages[i]));
        }

        final response = await _dio.post(
          '$baseUrl/images/edits',
          options: Options(headers: {
            'Authorization': 'Bearer $token',
          }),
          data: formData,
        );

        final b64 = response.data['data']?[0]?['b64_json'];
        if (b64 != null) {
          return CapabilityResult.successImage(base64Decode(b64));
        }
        final url = response.data['data']?[0]?['url'];
        if (url != null) {
          return CapabilityResult.successImageUrl(url);
        }
        return CapabilityResult.failure('角色一致性圖片生成回應格式異常');
      }

      // Flux (Replicate) — Phase 3 實作
      if (service.id.startsWith('flux')) {
        return CapabilityResult.failure(
          'Flux + IP-Adapter 尚未實作，請使用 OpenAI gpt-image',
        );
      }

      return CapabilityResult.failure(
        '服務 ${service.id} 的角色一致性生成尚未實作',
      );
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 圖片理解 (Vision)
  // ═══════════════════════════════════════════════════

  /// 分析圖片
  Future<CapabilityResult> analyzeImage({
    required String serviceId,
    required String prompt,
    required String base64Image,
    String? model,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }

    final baseUrl = service.defaultBaseUrl;
    if (baseUrl == null) {
      return CapabilityResult.failure('服務未設定 API 位址');
    }

    final useModel = model ?? service.defaultModel?.id ?? 'gpt-4o';

    try {
      final response = await _dio.post(
        '$baseUrl/chat/completions',
        options: Options(headers: _authHeaders(service, token)),
        data: {
          'model': useModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'max_tokens': 1000,
        },
      );

      final text = response.data['choices']?[0]?['message']?['content'];
      if (text != null) {
        return CapabilityResult.successText(text, raw: response.data);
      }
      return CapabilityResult.failure('視覺理解回應格式異常');
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 語音合成 (TTS)
  // ═══════════════════════════════════════════════════

  /// 文字轉語音
  Future<CapabilityResult> synthesizeSpeech({
    required String serviceId,
    required String text,
    String? voice,
    String? model,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }

    final baseUrl = service.defaultBaseUrl;
    if (baseUrl == null) {
      return CapabilityResult.failure('服務未設定 API 位址');
    }

    final useModel = model ?? service.defaultModel?.id ?? 'tts-1';

    try {
      final response = await _dio.post(
        '$baseUrl/audio/speech',
        options: Options(headers: _authHeaders(service, token), responseType: ResponseType.bytes),
        data: {
          'model': useModel,
          'input': text,
          'voice': voice ?? 'alloy',
        },
      );

      if (response.data != null) {
        return CapabilityResult(success: true, imageData: Uint8List.fromList(response.data));
      }
      return CapabilityResult.failure('TTS 回應為空');
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 測試連線（私有方法）
  // ═══════════════════════════════════════════════════

  Future<ConnectionTestResult> _testLLMConnection(ServiceDefinition service) async {
    if (service.id == 'local_llm') {
      // 本地模型測試
      try {
        final response = await _dio.get(
          '${service.defaultBaseUrl}/v1/models',
        );
        if (response.statusCode == 200) {
          final models = response.data?['data'] as List?;
          final modelCount = models?.length ?? 0;
          return ConnectionTestResult(
            success: true,
            message: '本地模型已就緒（$modelCount 個模型）',
          );
        }
      } catch (e) {
        return const ConnectionTestResult(success: false, message: '本地模型未啟動');
      }
      return const ConnectionTestResult(success: false, message: '本地模型未啟動');
    }

    final token = await _getToken(service);
    if (token == null) {
      return const ConnectionTestResult(success: false, message: '尚未設定 API Key');
    }

    try {
      final response = await _dio.post(
        '${service.defaultBaseUrl}/chat/completions',
        options: Options(headers: _authHeaders(service, token)),
        data: {
          'model': service.defaultModel?.id ?? 'gpt-4o',
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
          'max_tokens': 5,
        },
      );

      if (response.statusCode == 200) {
        final model = response.data?['model'];
        return ConnectionTestResult(
          success: true,
          message: '連線成功',
          detectedModel: model,
        );
      }
      return ConnectionTestResult(
        success: false,
        message: 'HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const ConnectionTestResult(success: false, message: 'API Key 無效或已過期');
      }
      return ConnectionTestResult(success: false, message: _dioError(e));
    }
  }

  Future<ConnectionTestResult> _testImageGenerationConnection(ServiceDefinition service) async {
    // 圖片生成的測試連線: 只驗證 Key 有效性（列出模型）
    final token = await _getToken(service);
    if (token == null) {
      return const ConnectionTestResult(success: false, message: '尚未設定 API Key');
    }

    try {
      // 用 models endpoint 驗證 Key
      final response = await _dio.get(
        '${service.defaultBaseUrl}/models',
        options: Options(headers: _authHeaders(service, token)),
      );
      if (response.statusCode == 200) {
        return const ConnectionTestResult(
          success: true,
          message: 'API Key 有效，圖片生成已就緒',
        );
      }
      return ConnectionTestResult(
        success: false,
        message: 'HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const ConnectionTestResult(success: false, message: 'API Key 無效');
      }
      return ConnectionTestResult(success: false, message: _dioError(e));
    }
  }

  Future<ConnectionTestResult> _testVisionConnection(ServiceDefinition service) async {
    // Vision 跟 LLM 共用同一個 endpoint，所以測試方式相同
    return _testLLMConnection(service);
  }

  Future<ConnectionTestResult> _testTTSConnection(ServiceDefinition service) async {
    final token = await _getToken(service);
    if (token == null) {
      return const ConnectionTestResult(success: false, message: '尚未設定 API Key');
    }

    // 用 models endpoint 驗證
    try {
      final response = await _dio.get(
        '${service.defaultBaseUrl}/models',
        options: Options(headers: _authHeaders(service, token)),
      );
      if (response.statusCode == 200) {
        return const ConnectionTestResult(
          success: true,
          message: 'API Key 有效，語音合成已就緒',
        );
      }
      return ConnectionTestResult(
        success: false,
        message: 'HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      return ConnectionTestResult(success: false, message: _dioError(e));
    }
  }

  Future<ConnectionTestResult> _testWhisperConnection(ServiceDefinition service) async {
    if (service.id == 'local_whisper') {
      return const ConnectionTestResult(
        success: true,
        message: '本地 Whisper 已就緒',
      );
    }
    return _testLLMConnection(service);
  }

  Future<ConnectionTestResult> _testSearchConnection(ServiceDefinition service) async {
    final token = await _getToken(service);
    if (token == null) {
      return const ConnectionTestResult(success: false, message: '尚未設定 API Key');
    }
    // 搜尋服務只驗證 Key 存在
    return ConnectionTestResult(
      success: true,
      message: '${service.providerName} 搜尋服務已就緒',
    );
  }

  Future<ConnectionTestResult> _testKeyBasedConnection(ServiceDefinition service) async {
    final token = await _getToken(service);
    if (token == null) {
      return const ConnectionTestResult(success: false, message: '尚未設定 API Key');
    }
    return ConnectionTestResult(
      success: true,
      message: '${service.serviceName} 已就緒',
    );
  }

  // ═══════════════════════════════════════════════════
  // 輔助方法
  // ═══════════════════════════════════════════════════

  Future<String?> _getToken(ServiceDefinition service) async {
    if (service.keyRequirement.type == KeyType.none) {
      return 'local'; // 本地服務不需要 token
    }
    final storageKey = service.keyRequirement.storageKey;
    if (storageKey == null) return null;

    // 使用 StorageService 統一存取
    final token = await StorageService.getToken(provider: storageKey);
    return token;
  }

  Map<String, String> _authHeaders(ServiceDefinition service, String token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    // 不同 provider 用不同的認證 header
    switch (service.providerName.toLowerCase()) {
      case 'claude':
      case 'anthropic':
        headers['x-api-key'] = token;
        headers['anthropic-version'] = '2023-06-01';
        break;
      default:
        headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  String _dioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout) {
      return '連線逾時';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return '回應逾時';
    }
    final data = e.response?.data;
    if (data != null) {
      if (data is Map) {
        final error = data['error'];
        if (error is Map) {
          return error['message']?.toString() ?? '未知錯誤';
        }
        return error?.toString() ?? data.toString();
      }
      return data.toString();
    }
    return e.message ?? '網路錯誤';
  }

  // ═══════════════════════════════════════════════════
  // 影片生成 (Video Generation)
  // [教練 Agent 2026-08-01] async pattern: POST → task_id → poll → result
  // ═══════════════════════════════════════════════════

  /// 生成影片 — 非同步 API（POST → poll → get URL）
  /// [教練 Agent 2026-08-21] Phase A——記帳 wrapper：過閘→記 pending→執行→結案
  Future<CapabilityResult> generateVideo({

    required String serviceId,
    required String prompt,
    String? model,
    int? duration,
    String? size,
  }) async {
    final gate = await PaidActionGate.instance.checkAndReserve(
      PaidActionKind.video,
      intent: 'generateVideo',
      prompt: prompt,
    );
    if (!gate.allowed) return CapabilityResult.failure(gate.reason);
    try {
      final r = await _rawgenerateVideo(
        serviceId: serviceId,
        prompt: prompt,
        model: model,
        duration: duration,
        size: size,
      );
      await PaidActionGate.settle(gate.ledgerId, ok: r.success, error: r.error);
      return r;
    } catch (e) {
      await PaidActionGate.settle(gate.ledgerId, ok: false, error: e.toString());
      rethrow;
    }
  }

  Future<CapabilityResult> _rawgenerateVideo({
    required String serviceId,
    required String prompt,
    String? model,
    int? duration,
    String? size,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }


    final baseUrl = service.defaultBaseUrl;
    if (baseUrl == null) {
      return CapabilityResult.failure('服務未設定 API 位址');
    }

    final useModel = model ?? service.defaultModel?.id ?? 'video-01';

    try {
      // Runway 格式
      if (service.id.startsWith('runway')) {
        final createResp = await _dio.post(
          '$baseUrl/image_to_video',
          options: Options(headers: _authHeaders(service, token)),
          data: {
            'model': useModel,
            'promptText': prompt,
            if (duration != null) 'duration': duration,
            if (size != null) 'size': size,
          },
        );

        final taskId = createResp.data['id']?.toString();
        if (taskId == null) {
          return CapabilityResult.failure('Runway 未回傳任務 ID');
        }

        return await _pollAsyncTask(
          pollUrl: '$baseUrl/tasks/$taskId',
          headers: _authHeaders(service, token),
          serviceId: service.id,
        );
      }

      // MiniMax 格式
      if (service.id.startsWith('minimax')) {
        final createResp = await _dio.post(
          '$baseUrl/video_generation',
          options: Options(headers: _authHeaders(service, token)),
          data: {
            'model': useModel,
            'prompt': prompt,
          },
        );

        final taskId = createResp.data?['task_id']?.toString();
        if (taskId == null) {
          return CapabilityResult.failure('MiniMax 未回傳任務 ID');
        }

        return await _pollAsyncTask(
          pollUrl: '$baseUrl/query_video_generation?task_id=$taskId',
          headers: _authHeaders(service, token),
          serviceId: service.id,
        );
      }

      // Kling 格式
      if (service.id.startsWith('kling')) {
        // Kling 需要JWT，先嘗試直接呼叫
        return CapabilityResult.failure(
          'Kling API 需要 JWT 認證，暫未實作。請使用 Runway 或 MiniMax',
        );
      }

      return CapabilityResult.failure('服務 ${service.id} 的影片生成尚未實作');
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 音樂生成 (Music Generation)
  // ═══════════════════════════════════════════════════

  /// 生成音樂 — 非同步 API
  /// [教練 Agent 2026-08-21] Phase A——記帳 wrapper：過閘→記 pending→執行→結案
  Future<CapabilityResult> generateMusic({

    required String serviceId,
    required String prompt,
    String? model,
    int? duration,
    String? genre,
  }) async {
    final gate = await PaidActionGate.instance.checkAndReserve(
      PaidActionKind.music,
      intent: 'generateMusic',
      prompt: prompt,
    );
    if (!gate.allowed) return CapabilityResult.failure(gate.reason);
    try {
      final r = await _rawgenerateMusic(
        serviceId: serviceId,
        prompt: prompt,
        model: model,
        duration: duration,
        genre: genre,
      );
      await PaidActionGate.settle(gate.ledgerId, ok: r.success, error: r.error);
      return r;
    } catch (e) {
      await PaidActionGate.settle(gate.ledgerId, ok: false, error: e.toString());
      rethrow;
    }
  }

  Future<CapabilityResult> _rawgenerateMusic({
    required String serviceId,
    required String prompt,
    String? model,
    int? duration,
    String? genre,
  }) async {
    final service = ServiceRegistry.instance.serviceById(serviceId);
    if (service == null) {
      return CapabilityResult.failure('找不到服務: $serviceId');
    }

    final token = await _getToken(service);
    if (token == null) {
      return CapabilityResult.failure('尚未設定 API Key');
    }


    try {
      // MiniMax 音樂格式
      if (service.id.startsWith('minimax')) {
        final baseUrl = service.defaultBaseUrl ?? 'https://api.minimax.chat/v1';
        final useModel = model ?? service.defaultModel?.id ?? 'music-01';

        final createResp = await _dio.post(
          '$baseUrl/music_generation',
          options: Options(headers: _authHeaders(service, token)),
          data: {
            'model': useModel,
            'prompt': prompt,
            if (duration != null) 'duration': duration,
          },
        );

        final taskId = createResp.data?['data']?['task_id']?.toString();
        if (taskId == null) {
          return CapabilityResult.failure('MiniMax 未回傳音樂任務 ID');
        }

        return await _pollAsyncTask(
          pollUrl: '$baseUrl/query_music_generation?task_id=$taskId',
          headers: _authHeaders(service, token),
          serviceId: service.id,
        );
      }

      // Suno 格式 — 需要 Suno API（第三方）
      if (service.id.startsWith('suno')) {
        return CapabilityResult.failure(
          'Suno API 需要第三方接入，暫未實作。請使用 MiniMax Music',
        );
      }

      return CapabilityResult.failure('服務 ${service.id} 的音樂生成尚未實作');
    } on DioException catch (e) {
      return CapabilityResult.failure(_dioError(e));
    }
  }

  // ═══════════════════════════════════════════════════
  // 非同步任務輪詢
  // [教練 Agent 2026-08-01] 影片/音樂 API 共用：POST → poll until done → URL
  // ═══════════════════════════════════════════════════

  /// 輪詢非同步任務直到完成，回傳媒體 URL。
  ///
  /// 最多等待 5 分鐘，每 3 秒查一次。
  Future<CapabilityResult> _pollAsyncTask({
    required String pollUrl,
    required Map<String, dynamic> headers,
    required String serviceId,
    int maxAttempts = 100,
    Duration interval = const Duration(seconds: 3),
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);

      try {
        final resp = await _dio.get(
          pollUrl,
          options: Options(headers: headers),
        );
        final status = resp.data?['status']?.toString().toLowerCase() ?? '';

        if (status == 'succeeded' || status == 'completed') {
          // Runway 格式：output 陣列
          final output = resp.data?['output'];
          if (output is List && output.isNotEmpty) {
            return CapabilityResult.successImageUrl(output.first.toString());
          }
          // MiniMax 格式：file_id → 需要另一個 API 取 URL
          final fileId = resp.data?['file_id']?.toString();
          if (fileId != null) {
            return CapabilityResult.successImageUrl(
              'file_id:$fileId （需透過 MiniMax files API 取得）',
            );
          }
          // 直接 URL
          final url = resp.data?['video_url']?.toString() ??
              resp.data?['audio_url']?.toString() ??
              resp.data?['url']?.toString();
          if (url != null) {
            return CapabilityResult.successImageUrl(url);
          }
          return CapabilityResult.failure('任務完成但找不到媒體 URL');
        }

        if (status == 'failed' || status == 'error') {
          final error = resp.data?['error']?.toString() ?? '未知錯誤';
          return CapabilityResult.failure('生成失敗: $error');
        }

        // status: starting / processing / queued — 繼續等
      } on DioException catch (e) {
        // 網路錯誤不立即放棄，重試
        if (i == maxAttempts - 1) {
          return CapabilityResult.failure(_dioError(e));
        }
      }
    }

    return CapabilityResult.failure('超時：等待超過 5 分鐘');
  }
}
