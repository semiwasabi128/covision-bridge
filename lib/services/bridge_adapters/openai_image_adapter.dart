import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/bridge_action.dart';
import '../api_usage_tracker.dart';
import '../background_remover.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class OpenAiImageAdapter extends BridgeActionAdapter {
  OpenAiImageAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  String get id => 'openai';

  @override
  String get displayName => 'OpenAI 圖片生成';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final model = _resolveImageModel(action);
    final quality = _resolveImageQuality(action);
    final token = await StorageService.getToken(provider: id);
    if (token == null || token.isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'OpenAI API Token 尚未設定',
        provider: id,
      );
    }

    try {
      final response = action.referenceImagePaths.isEmpty
          ? await _createImage(token, action, model: model, quality: quality)
          : await _editImage(token, action, model: model, quality: quality);

      final data = response.data;
      final images = data is Map<String, dynamic>
          ? data['data'] as List<dynamic>?
          : null;
      final first = images?.isNotEmpty == true
          ? Map<String, dynamic>.from(images!.first as Map)
          : null;
      final b64Json = first?['b64_json']?.toString();
      final imageUrl = first?['url']?.toString();

      if (b64Json != null && b64Json.isNotEmpty) {
        // [教練 Agent 2026-08-12] 去背 v3：同時移除純白 + 純黑背景
        var finalB64 = b64Json;
        if (model == 'gpt-image-2') {
          final rawBytes = base64Decode(b64Json);
          final cleanedBytes = BackgroundRemover.removeWhiteBackground(
            Uint8List.fromList(rawBytes),
          );
          if (cleanedBytes != null) {
            finalB64 = base64Encode(cleanedBytes);
          }
        }
        final mediaPath = await BridgeMediaStore.persistImageDataUrl(
          'data:image/png;base64,$finalB64',
          prompt: action.prompt,
        );
        // [教練 Agent 2026-08-10] 圖片生成計入儀表板
        ApiUsageTracker.instance.recordUsage(
          inputTokens: 0,
          outputTokens: 1,
          model: model,
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
            'model': model,
            'quality': quality,
            'mode': action.referenceImagePaths.isEmpty
                ? 'text_to_image'
                : 'image_to_image',
            if (action.referenceImagePaths.isNotEmpty)
              'referenceImageCount': action.referenceImagePaths.length,
            'storage': mediaPath.startsWith('data:image/')
                ? 'inline'
                : 'local_file',
          },
        );
      }

      if (imageUrl != null && imageUrl.isNotEmpty) {
        final imageResponse = await _dio.get<List<int>>(
          imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = imageResponse.data;
        Uint8List? imageBytes =
            bytes == null ? null : Uint8List.fromList(bytes);
        // [教練 Agent 2026-06-29] gpt-image-2 做白色背景去除
        if (model == 'gpt-image-2' && imageBytes != null) {
          final cleanedBytes =
              BackgroundRemover.removeWhiteBackground(imageBytes);
          if (cleanedBytes != null) {
            imageBytes = cleanedBytes;
          }
        }
        final mediaPath = imageBytes == null
            ? imageUrl
            : await BridgeMediaStore.persistImageBytes(imageBytes, prompt: action.prompt);
        // [教練 Agent 2026-08-10] 圖片生成計入儀表板（URL 分支）
        ApiUsageTracker.instance.recordUsage(
          inputTokens: 0,
          outputTokens: 1,
          model: model,
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
            'model': model,
            'quality': quality,
            'mode': action.referenceImagePaths.isEmpty
                ? 'text_to_image'
                : 'image_to_image',
            if (action.referenceImagePaths.isNotEmpty)
              'referenceImageCount': action.referenceImagePaths.length,
            'storage': mediaPath == imageUrl ? 'remote_url' : 'local_file',
          },
        );
      }

      return const BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '圖片服務沒有回傳可顯示的圖片',
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['error']?['message'] ?? e.message)
          : e.message;
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '圖片生成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '圖片生成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
        },
      );
    }
  }

  Future<Response<dynamic>> _createImage(
    String token,
    BridgeAction action, {
    required String model,
    required String quality,
  }) {
    // [教練 Agent 2026-06-29] gpt-image-2 標準 1024x1024（伺服器最佳化，比非標準尺寸快）
    final size = model == 'gpt-image-2' ? '1024x1024' : '1024x1024';
    // [教練 Agent 2026-06-29] gpt-image-2 要求純白背景，事後用 BackgroundRemover 去除
    final prompt = model == 'gpt-image-2'
        ? '${action.prompt} plain white background'
        : action.prompt;
    return _dio.post(
      'https://api.openai.com/v1/images/generations',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 15),
      ),
      data: {
        'model': model,
        'prompt': prompt,
        'size': size,
        'quality': quality,
        // [教練 Agent 2026-06-29] gpt-image-2 不支援 transparent background
        if (model != 'gpt-image-2') 'background': 'transparent',
        'output_format': 'png',
        'n': 1,
      },
    );
  }

  Future<Response<dynamic>> _editImage(
    String token,
    BridgeAction action, {
    required String model,
    required String quality,
  }) async {
    final referenceImages = <MultipartFile>[];
    for (var index = 0; index < action.referenceImagePaths.length; index++) {
      final multipart = await _referenceImageToMultipart(
        action.referenceImagePaths[index],
        index,
      );
      if (multipart != null) referenceImages.add(multipart);
    }

    if (referenceImages.isEmpty) {
      return _createImage(token, action, model: model, quality: quality);
    }
    // [教練 Agent 2026-06-29] gpt-image-2 標準 1024x1024
    final size = model == 'gpt-image-2' ? '1024x1024' : '1024x1024';
    // [教練 Agent 2026-06-29] gpt-image-2 要求純白背景，事後用 BackgroundRemover 去除
    final prompt = model == 'gpt-image-2'
        ? '${action.prompt} plain white background'
        : action.prompt;
    final formMap = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'size': size,
      'quality': quality,
      // [教練 Agent 2026-06-29] gpt-image-2 不支援 transparent background
      if (model != 'gpt-image-2') 'background': 'transparent',
      'output_format': 'png',
      'n': '1',
      'image[]': referenceImages,
    };
    if (model != 'gpt-image-2') {
      // [教練 Agent 2026-07-03] 狀態圖需要更多姿勢自由度，降低 fidelity
      // high 會讓 8 張圖幾乎長一樣；low 保留角色特徵但允許動作變化
      formMap['input_fidelity'] = 'low';
    }

    return _dio.post(
      'https://api.openai.com/v1/images/edits',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
      data: FormData.fromMap(formMap),
    );
  }

  String _resolveImageModel(BridgeAction action) {
    final model = action.model?.trim();
    // [教練 Agent 2026-08-08] gpt-image-2 是 OpenAI 唯一的長期支援模型
    // gpt-image-1-mini 和 gpt-image-1.5 於 2026-12-01 shutdown
    // 所有請求統一走 gpt-image-2
    if (model == 'gpt-image-2') {
      return model!;
    }
    return 'gpt-image-2';
  }

  String _resolveImageQuality(BridgeAction action) {
    final quality = action.imageQuality?.trim();
    if (quality == 'high' || quality == 'medium' || quality == 'low') {
      return quality!;
    }
    final model = _resolveImageModel(action);
    if (model == 'gpt-image-1-mini') return 'low';
    if (model == 'gpt-image-1') return 'medium';
    // [小葵 2026-09-14] gpt-image-2 不再預設 high：
    // 9/13 事件——16 張探索期形象圖全部以 high 計費（≈$0.19/張），
    // 批量探索其實 low 就夠。探索期 low、定稿再手動指定 high。
    // UI 明確傳入 imageQuality 時不受此影響（上面第一個 if）。
    if (model == 'gpt-image-2') return 'low';
    return 'high';
  }

  /// [教練 Agent 2026-06-29] 參考圖統一壓縮到最大 512px 再上傳，大幅減少傳輸量。
  /// 保持比例，取最長邊縮到 512px。回傳 PNG bytes。
  Uint8List _compressToMax512(Uint8List source) {
    final decoded = img.decodeImage(source);
    if (decoded == null) return source; // 解碼失敗就不壓，原圖上傳

    final w = decoded.width;
    final h = decoded.height;
    final longestSide = w > h ? w : h;

    // 已經夠小就不壓
    if (longestSide <= 512) return source;

    final scale = 512.0 / longestSide;
    final newW = (w * scale).round();
    final newH = (h * scale).round();

    final resized = img.copyResize(decoded, width: newW, height: newH);
    final encoded = img.encodePng(resized);
    return Uint8List.fromList(encoded);
  }

  Future<MultipartFile?> _referenceImageToMultipart(
    String imagePath,
    int index,
  ) async {
    final value = imagePath.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('data:image/')) {
      final commaIndex = value.indexOf(',');
      if (commaIndex < 0) return null;
      final header = value.substring(0, commaIndex);
      final rawBytes = base64Decode(value.substring(commaIndex + 1));
      final compressed = _compressToMax512(Uint8List.fromList(rawBytes));
      final extension = _extensionForDataUrl(header);
      return MultipartFile.fromBytes(
        compressed,
        filename: 'bridge_reference_$index.$extension',
      );
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      final response = await _dio.get<List<int>>(
        value,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      final compressed = _compressToMax512(Uint8List.fromList(bytes));
      return MultipartFile.fromBytes(
        compressed,
        filename: 'bridge_reference_$index.png',
      );
    }

    if (kIsWeb) return null;

    final file = File(value);
    if (!await file.exists()) return null;
    final rawBytes = await file.readAsBytes();
    final compressed = _compressToMax512(Uint8List.fromList(rawBytes));
    return MultipartFile.fromBytes(
      compressed,
      filename: file.uri.pathSegments.isEmpty
          ? 'bridge_reference_$index.png'
          : file.uri.pathSegments.last,
    );
  }

  String _extensionForDataUrl(String header) {
    if (header.contains('image/jpeg') || header.contains('image/jpg')) {
      return 'jpg';
    }
    if (header.contains('image/webp')) return 'webp';
    return 'png';
  }
}
