// [教練 Agent P1-1 2026-08-07] Gemini 圖片生成 Adapter
// [教練 Agent 2026-08-10] 使用 generateContent API（正確 endpoint）
//
// API: POST /v1beta/models/{model}:generateContent
// Body: { contents: [{ parts: [{ text: "prompt" }] }], generationConfig: { responseModalities: ["TEXT","IMAGE"] } }
// Response: candidates[0].content.parts[].inlineData.data (base64)

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/bridge_action.dart';
import '../api_usage_tracker.dart';
import '../bridge_action_executor.dart';
import '../background_remover.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class GeminiImageAdapter extends BridgeActionAdapter {
  GeminiImageAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// [教練 Agent 2026-08-10] 修正 endpoint——generateContent，不是 interactions
  /// generateContent 是 Gemini 圖片生成的正確 API
  /// 參考: https://ai.google.dev/gemini-api/docs/image-generation
  static const _model = 'gemini-3.1-flash-image-preview';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  @override
  String get id => 'gemini';

  @override
  String get displayName => 'Gemini 圖片生成 (Nano Banana 2)';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final token = await StorageService.getToken(provider: id);
    if (token == null || token.isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'Gemini API Key 尚未設定',
        provider: id,
      );
    }

    try {
      // [Blue UX 2026-09-17] 支援圖生圖——狀態圖必須以主形象為母版保持角色
      // 一致性。Gemini generateContent 的多模態輸入格式：參考圖放
      // parts[].inline_data（本地檔案讀成 base64），文字 prompt 在後。
      // 沒帶參考圖時行為不變（純文生圖）。
      final parts = <Map<String, dynamic>>[];
      for (final refPath in action.referenceImagePaths) {
        final cleanPath = refPath.trim();
        if (cleanPath.isEmpty) continue;
        try {
          final bytes = await File(cleanPath).readAsBytes();
          parts.add({
            'inline_data': {
              'mimeType': cleanPath.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg',
              'data': base64Encode(bytes),
            },
          });
        } catch (e) {
          debugPrint('[GeminiImageAdapter] 參考圖讀取失敗 $cleanPath: $e');
        }
      }
      parts.add({'text': action.prompt});

      // [教練 Agent 2026-08-09] 正確的 Gemini generateContent 格式
      // 參考: https://ai.google.dev/gemini-api/docs/image-generation
      final response = await _dio.post<dynamic>(
        '$_endpoint?key=$token',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'contents': [
            {
              'parts': parts,
            },
          ],
          'generationConfig': {
            'responseModalities': ['TEXT', 'IMAGE'],
          },
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'Gemini 回應格式異常',
        );
      }

      // generateContent 回應：candidates[0].content.parts[]
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return const BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'Gemini 沒有回傳候選',
        );
      }
      final contentMap = (candidates[0] as Map<String, dynamic>)['content']
          as Map<String, dynamic>?;
      final partList = contentMap?['parts'] as List<dynamic>?;
      if (partList == null || partList.isEmpty) {
        return const BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'Gemini 沒有回傳圖片',
        );
      }

      // 從 parts 找 inlineData（圖片）
      String? b64;
      for (final part in partList) {
        if (part is Map<String, dynamic>) {
          final inlineData = part['inlineData'];
          if (inlineData is Map<String, dynamic>) {
            b64 = inlineData['data']?.toString();
            if (b64 != null && b64.isNotEmpty) break;
          }
        }
      }

      if (b64 == null || b64.isEmpty) {
        return const BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'Gemini 回應中沒有圖片資料',
        );
      }

      return await _persistAndReturn(action, b64);
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['error']?['message'] ?? e.message)
          : e.message;
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'Gemini 圖片生成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'Gemini 圖片生成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
        },
      );
    }
  }

  /// 共用：base64 → 去背 → 存檔 → BridgeActionResult
  Future<BridgeActionResult> _persistAndReturn(BridgeAction action, String b64) async {
    // [Blue UX 2026-09-17] Gemini 沒有 alpha 通道——prompt 要求 transparent
    // 時它會「畫出」棋盤格假透明（不透明灰白格子）。改請它生純白背景後，
    // 這裡用 BackgroundRemover 做真正去背（與 OpenAI adapter 同款管線：
    // flood-fill → 殘白清除 → 小洞保護 → 揉邊 → 裁切）。
    var finalB64 = b64;
    try {
      final rawBytes = base64Decode(b64);
      final cleanedBytes = BackgroundRemover.removeWhiteBackground(
        Uint8List.fromList(rawBytes),
      );
      if (cleanedBytes != null) {
        finalB64 = base64Encode(cleanedBytes);
      }
    } catch (e) {
      debugPrint('[GeminiImageAdapter] 去背失敗（保留原圖）: $e');
    }
    final mediaPath = await BridgeMediaStore.persistImageDataUrl(
      'data:image/png;base64,$finalB64',
      prompt: action.prompt,
    );
    // [教練 Agent 2026-08-10] 圖片生成也記錄 usage——用 requestCount=1，tokens=0
    // 儀表板需要區分 LLM 呼叫和圖片呼叫，否則圖片完全沒被計入
    ApiUsageTracker.instance.recordUsage(
      inputTokens: 0,
      outputTokens: 1, // 圖片生成 1 次 = 1 單位計數
      model: _model,
      provider: id,
    );
    return BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: '圖片已生成完成',
      mediaUrl: mediaPath,
      metadata: {
        'type': action.type.legacyType,
        'provider': id,
        'adapter': displayName,
        'kind': 'image',
        'model': _model,
        'aspect_ratio': '1:1',
        'mode': 'text_to_image',
        'storage': mediaPath.startsWith('data:') ? 'inline' : 'local_file',
      },
    );
  }
}
