// [教練 Agent 2026-06-28] 改寫：走 app 自己的 gateway URL + token
// 失敗時回傳明確原因，讓使用者知道缺什麼
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/companion.dart';
import 'sovereignty/data_path_gate.dart';
import 'sovereignty/data_path_interceptor.dart';
import 'storage_service.dart';

/// 審查結果的狀態
enum VisionReviewStatus {
  success,           // API 審查成功
  noToken,           // 沒設 API token
  noGateway,         // 沒設 gateway URL
  noImages,          // 角色沒有圖片可審查
  apiError,          // API 呼叫失敗（可能不支援 vision）
  parseError,        // API 回應了但解析失敗
}

/// 審查結果包裝：包含狀態 + 實際結果（如果成功）
class VisionReviewOutcome {
  final VisionReviewStatus status;
  final OpenAiVisualReviewResult? result;
  final String? errorMessage;     // API 回傳的錯誤訊息
  final String? providerUsed;     // 使用的 provider 名稱
  final String? modelUsed;        // 嘗試的模型名稱

  const VisionReviewOutcome({
    required this.status,
    this.result,
    this.errorMessage,
    this.providerUsed,
    this.modelUsed,
  });

  bool get isSuccess => status == VisionReviewStatus.success && result != null;
}

class OpenAiVisualReviewAdapter {
  OpenAiVisualReviewAdapter({Dio? dio})
      : _dio = dio ?? _createDefaultDio();

  static Dio _createDefaultDio() {
    final dio = Dio();
    // [資料主權 P0-b 2026-09-14] 視覺審查流量過 DataPathGate（text/review）
    dio.interceptors.add(SovereigntyInterceptor(
      dataClass: DataPathClass.text,
      purpose: DataPathPurpose.review,
    ));
    return dio;
  }

  final Dio _dio;

  /// 用 app 的 gateway 審查角色造型圖
  /// [教練 Agent 2026-06-28] 支援 A 生成 B 審查：優先讀審查專用設定，fallback 到主腦
  /// 回傳明確的失敗原因，不靜默吞錯
  Future<VisionReviewOutcome> reviewCompanion(Companion companion) async {
    // 1. 取 token：先試審查專用 → fallback 到主腦
    var token = await StorageService.getReviewToken();
    token ??= await StorageService.getToken();
    if (token == null || token.trim().isEmpty) {
      return const VisionReviewOutcome(status: VisionReviewStatus.noToken);
    }

    // 2. 取 gateway URL：先試審查專用 → fallback 到主腦
    var gatewayUrl = await StorageService.getReviewGatewayUrl();
    gatewayUrl ??= await StorageService.getGatewayUrl();
    if (gatewayUrl == null || gatewayUrl.trim().isEmpty) {
      return const VisionReviewOutcome(status: VisionReviewStatus.noGateway);
    }

    // 3. 決定 endpoint + model
    final provider = await StorageService.getReviewProvider() ??
        await StorageService.getProvider() ??
        'default';
    final baseUrl = _resolveBaseUrl(gatewayUrl);
    final endpoint = '$baseUrl/chat/completions';
    // 先試使用者自訂的審查模型 → 否則根據 provider 自動選
    final model = await StorageService.getReviewModel() ??
        _pickVisionModel(provider);

    // 4. 收集圖片
    final images = await _buildImageInputs(companion);
    if (images.isEmpty) {
      return const VisionReviewOutcome(status: VisionReviewStatus.noImages);
    }

    // 5. 呼叫 API
    try {
      final response = await _dio.post(
        endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': _systemPrompt(),
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': _userPrompt(companion, images.length),
                },
                ...images,
              ],
            },
          ],
          // [教練 Agent 2026-07-30] reasoning model 不支援自訂 temperature
          if (!model.toLowerCase().startsWith('kimi-k3') &&
              !model.toLowerCase().startsWith('gpt-5'))
            'temperature': 0.1,
          'max_tokens': 800,
        },
      );

      final content = _extractContent(response.data);
      if (content == null || content.trim().isEmpty) {
        return VisionReviewOutcome(
          status: VisionReviewStatus.parseError,
          providerUsed: provider,
          modelUsed: model,
          errorMessage: 'API 回應中找不到內容',
        );
      }

      final json = _extractJson(content);
      if (json == null) {
        return VisionReviewOutcome(
          status: VisionReviewStatus.parseError,
          providerUsed: provider,
          modelUsed: model,
          errorMessage: '無法從回應中解析 JSON：${content.substring(0, content.length > 200 ? 200 : content.length)}',
        );
      }

      return VisionReviewOutcome(
        status: VisionReviewStatus.success,
        result: OpenAiVisualReviewResult.fromJson(json),
        providerUsed: provider,
        modelUsed: model,
      );
    } on DioException catch (e) {
      // API 呼叫失敗——可能是模型不支援 vision、endpoint 錯誤、token 無效等
      final apiMessage = _extractApiError(e);
      return VisionReviewOutcome(
        status: VisionReviewStatus.apiError,
        providerUsed: provider,
        modelUsed: model,
        errorMessage: apiMessage,
      );
    } catch (e) {
      return VisionReviewOutcome(
        status: VisionReviewStatus.apiError,
        providerUsed: provider,
        modelUsed: model,
        errorMessage: '$e',
      );
    }
  }

  /// 從 DioException 中提取 API 回傳的錯誤訊息
  String _extractApiError(DioException e) {
    if (e.response?.data is Map) {
      final error = e.response?.data['error'];
      if (error is Map) {
        final msg = error['message']?.toString();
        if (msg != null && msg.isNotEmpty) return msg;
      }
      if (error is String) return error;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'API 連線逾時（可能是模型不支援圖片輸入，或伺服器忙碌）';
    }
    if (e.type == DioExceptionType.badResponse) {
      return 'HTTP ${e.response?.statusCode}: ${e.response?.statusMessage ?? '未知錯誤'}';
    }
    return e.message ?? '未知網路錯誤';
  }

  /// 根據 provider 選擇支援 vision 的模型
  String _pickVisionModel(String provider) {
    switch (provider) {
      case 'openai':
        return 'gpt-4o-mini';
      case 'glm':
        return 'glm-4v-flash';
      case 'gemini':
        return 'gemini-3.5-flash';
      case 'claude':
        return 'claude-haiku-4-5';
      case 'kimi':
      case 'default':
      default:
        return 'gpt-4o-mini';
    }
  }

  String _resolveBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/v1')) return u;
    return '$u/v1';
  }

  String _systemPrompt() {
    return [
      '你是 SemiDAO 角色資產分享前的圖片安全與品質預審員。',
      '你會收到一個角色的造型圖片（主形象圖和可能的狀態圖）。',
      '請只根據圖片可見內容判斷，不要推測不存在的內容。',
      '',
      '檢查項目：',
      '1. 成人/裸露/性暗示內容',
      '2. 暴力、仇恨或危險符號',
      '3. Logo、商標或官方混淆風險',
      '4. 明顯可識別的既有 IP 或知名角色',
      '5. 嚴重破圖或無法辨識',
      '',
      '重要判定標準（嚴格遵守）：',
      '- adultContent 只在「明確裸露、性器官可見、性行為姿勢、純色情內容」時為 true。',
      '- 動漫/遊戲風格的角色穿著日常服裝（短褲、背心、緊身衣、泳裝風格但非裸露）不算 adultContent。',
      '- 角色露出手臂、腿部、腹部等非性器官部位不算 adultContent。',
      '- 只有裸露第二性徵或模擬性行為才算 true。',
      '- 若不確定，傾向判 false（讓使用者自選是否分享）。',
      '- 若只是一般風格相似但沒有可識別角色或 Logo，不要判為 identifiableIpRisk。',
      '- qualityScore 只代表能否正常辨識：5=清楚可展示，3=有小瑕疵，1=嚴重破圖。',
      '- 不要用主觀審美扣分；這些圖片可能是使用者剛用 API 生成的正式角色素材。',
      '',
      '請以 JSON 格式回覆，包含以下欄位：',
      '{"adultContent": bool, "violenceOrHate": bool, "logoOrTrademark": bool, "officialConfusion": bool, "identifiableIpRisk": bool, "qualityScore": int(1-5), "qualityIssues": [string], "safeForCommunityPreview": bool, "notes": string}',
    ].join('\n');
  }

  String _userPrompt(Companion companion, int imageCount) {
    return [
      '請檢查以下 $imageCount 張圖片。第一張是主形象圖，其餘可能是狀態圖。',
      '角色名稱：${companion.name}',
      '角色描述：${companion.appearanceDescription}',
      '',
      '請以 JSON 格式回覆審查結果。',
    ].join('\n');
  }

  String? _extractContent(Object? data) {
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    return message['content']?.toString();
  }

  /// 從回應文字中提取 JSON（模型可能包在 markdown code block 裡）
  Map<String, dynamic>? _extractJson(String text) {
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {}

    final jsonBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (jsonBlock != null) {
      try {
        return jsonDecode(jsonBlock.group(1)!.trim()) as Map<String, dynamic>;
      } catch (_) {}
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return jsonDecode(text.substring(start, end + 1))
            as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _buildImageInputs(
    Companion companion,
  ) async {
    final refs = <String>[
      if ((companion.avatarImagePath ?? '').trim().isNotEmpty)
        companion.avatarImagePath!.trim(),
      ...companion.stateImagePaths.values
          .where((value) => value.trim().isNotEmpty)
          .take(6),
    ];
    final images = <Map<String, dynamic>>[];
    for (final ref in refs) {
      final dataUrl = await _asDataUrl(ref);
      if (dataUrl == null) continue;
      images.add({
        'type': 'image_url',
        'image_url': {'url': dataUrl},
      });
    }
    return images;
  }

  Future<String?> _asDataUrl(String value) async {
    if (value.startsWith('data:image/')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (kIsWeb) return null;
    final file = File(value);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final mime = _mimeFromPath(value);
    return 'data:$mime;base64,${base64Encode(Uint8List.fromList(bytes))}';
  }

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }
}

class OpenAiVisualReviewResult {
  final bool adultContent;
  final bool violenceOrHate;
  final bool logoOrTrademark;
  final bool officialConfusion;
  final bool identifiableIpRisk;
  final int qualityScore;
  final List<String> qualityIssues;
  final bool safeForCommunityPreview;
  final String notes;

  const OpenAiVisualReviewResult({
    required this.adultContent,
    required this.violenceOrHate,
    required this.logoOrTrademark,
    required this.officialConfusion,
    required this.identifiableIpRisk,
    required this.qualityScore,
    required this.qualityIssues,
    required this.safeForCommunityPreview,
    required this.notes,
  });

  factory OpenAiVisualReviewResult.fromJson(Map<String, dynamic> json) {
    return OpenAiVisualReviewResult(
      adultContent: json['adultContent'] == true,
      violenceOrHate: json['violenceOrHate'] == true,
      logoOrTrademark: json['logoOrTrademark'] == true,
      officialConfusion: json['officialConfusion'] == true,
      identifiableIpRisk: json['identifiableIpRisk'] == true,
      qualityScore: (json['qualityScore'] as num?)?.round().clamp(1, 5) ?? 3,
      qualityIssues: [
        if (json['qualityIssues'] is List)
          for (final issue in json['qualityIssues'] as List) '$issue',
      ],
      safeForCommunityPreview: json['safeForCommunityPreview'] == true,
      notes: '${json['notes'] ?? ''}',
    );
  }
}
