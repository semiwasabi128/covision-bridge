// [教練 Agent P1-1 2026-08-07] MiniMax 圖片生成 Adapter
//
// MiniMax Image API:
//   POST https://api.minimax.io/v1/image_generation
//   Model: image-01
//   Response: data.image_base64 (base64 字串陣列)
//   Auth: Bearer {api_key}
//   支援 text-to-image 和 image-to-image (subject_reference)
//   支援 aspect_ratio

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class MinimaxImageAdapter extends BridgeActionAdapter {
  MinimaxImageAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _endpoint = 'https://api.minimax.io/v1/image_generation';

  @override
  String get id => 'minimax';

  @override
  String get displayName => 'MiniMax 圖片生成';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final token = await StorageService.getToken(provider: id);
    if (token == null || token.isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'MiniMax API Token 尚未設定',
        provider: id,
      );
    }

    final model = 'image-01';
    final aspectRatio = _resolveAspectRatio(action);

    // [小葵 2026-09-22] MiniMax image-01 prompt 上限 1500 字元——超長 prompt
    // 會被 API 直接拒絕（2013 invalid params），症狀=「一秒完成、沒有圖」
    // 假成功。智能截斷：優先保留開頭核心指令，尾部風格細節可犧牲。
    final rawPrompt = action.prompt;
    String prompt;
    String? truncatedNote;
    if (rawPrompt.length > 1450) {
      prompt = rawPrompt.substring(0, 1450);
      // 截到最後一個完整句邊界，避免切在單字中間
      final lastStop = prompt.lastIndexOf('. ') > prompt.lastIndexOf('。')
          ? prompt.lastIndexOf('. ')
          : prompt.lastIndexOf('。');
      if (lastStop > 800) prompt = prompt.substring(0, lastStop + 1);
      truncatedNote = '（提示詞超過 MiniMax 1500 字上限，已智能截斷至 ${prompt.length} 字元）';
    } else {
      prompt = rawPrompt;
    }

    try {
      final response = await _dio.post<dynamic>(
        _endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'prompt': prompt,
          'aspect_ratio': aspectRatio,
          'response_format': 'base64',
          // subject_reference (image-to-image) 如果有參考圖
          if (action.referenceImagePaths.isNotEmpty)
            'subject_reference': await _buildSubjectReference(action),
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 回應格式異常',
        );
      }

      final base64Key = data['data'] is Map
          ? (data['data'] as Map)['image_base64']
          : data['data']?['image_base64'];
      final images = base64Key is List ? base64Key : null;
      final firstB64 = images?.isNotEmpty == true
          ? images!.first.toString()
          : null;

      if (firstB64 == null || firstB64.isEmpty) {
        // 嘗試 URL 格式（某些 response 可能回 URL）
        final urlKey = data['data'] is Map
            ? (data['data'] as Map)['image_urls']
            : null;
        final urls = urlKey is List ? urlKey : null;
        final firstUrl = urls?.isNotEmpty == true ? urls!.first.toString() : null;

        if (firstUrl != null && firstUrl.isNotEmpty) {
          // 下載 URL 圖片
          final imageResponse = await _dio.get<List<int>>(
            firstUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          final bytes = imageResponse.data;
          if (bytes == null) {
            return BridgeActionResult(
              status: BridgeActionStatus.completed,
              message: '圖片已生成完成' + (truncatedNote ?? ''),
              mediaUrl: firstUrl,
              metadata: _buildMetadata(action, model, aspectRatio, 'remote_url'),
            );
          }
          final mediaPath = await BridgeMediaStore.persistImageBytes(
            Uint8List.fromList(bytes),
            prompt: action.prompt,
          );
          return BridgeActionResult(
            status: BridgeActionStatus.completed,
            message: '圖片已生成完成' + (truncatedNote ?? ''),
            mediaUrl: mediaPath,
            metadata: _buildMetadata(action, model, aspectRatio, 'local_file'),
          );
        }

        return const BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 沒有回傳可顯示的圖片',
        );
      }

      // base64 圖片
      final mediaPath = await BridgeMediaStore.persistImageDataUrl(
        'data:image/jpeg;base64,$firstB64',
        prompt: action.prompt,
      );

      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: '圖片已生成完成' + (truncatedNote ?? ''),
        mediaUrl: mediaPath,
        metadata: _buildMetadata(action, model, aspectRatio,
            mediaPath.startsWith('data:') ? 'inline' : 'local_file'),
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['base_resp']?['status_msg'] ??
              e.response?.data['error']?['message'] ??
              e.message)
          : e.message;
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'MiniMax 圖片生成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'MiniMax 圖片生成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
        },
      );
    }
  }

  String _resolveAspectRatio(BridgeAction action) {
    // MiniMax 支援: 1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3
    // BridgeAction 目前沒有 aspect ratio 欄位，預設 1:1
    // 未來可在 action 加 aspectRatio 欄位
    return '1:1';
  }

  Future<List<Map<String, dynamic>>> _buildSubjectReference(
      BridgeAction action) async {
    final refs = <Map<String, dynamic>>[];
    for (final path in action.referenceImagePaths.take(1)) {
      // MiniMax 只支援單張參考圖
      if (path.startsWith('data:image/')) {
        // data URL → 直接用（官方 image_file 支援 data URL）
        refs.add({
          'type': 'character',
          'image_file': path,
        });
      } else if (path.startsWith('http://') || path.startsWith('https://')) {
        refs.add({
          'type': 'character',
          'image_file': path,
        });
      } else {
        // 本機檔案 → 轉 data URL 塞 image_file
        // [小葵 2026-09-14] 修復角色一致性 bug：
        // 舊碼傳 image_base64——官方 schema 沒這欄位，MiniMax 靜默忽略
        // 參考圖、實際跑純文生圖 → 狀態圖角色各長各的。
        // 已 curl 實測：data URL 塞 image_file 才會真正以圖生圖（9/14 對照組驗證）。
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final ext = path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
          refs.add({
            'type': 'character',
            'image_file':
                'data:image/$ext;base64,${base64Encode(bytes)}',
          });
        } else {
          // [小葵 2026-09-14] 安靜失敗病根修復：
          // 檔案讀不到直接拋錯，讓上層誠實回報，不讓 MiniMax 背黑鍋。
          throw Exception('MiniMax 參考圖讀取失敗，檔案不存在：$path');
        }
      }
    }
    return refs;
  }

  Map<String, dynamic> _buildMetadata(
    BridgeAction action,
    String model,
    String aspectRatio,
    String storage,
  ) {
    return {
      'type': action.type.legacyType,
      'provider': id,
      'adapter': displayName,
      'kind': 'image',
      'model': model,
      'aspect_ratio': aspectRatio,
      'mode': action.referenceImagePaths.isEmpty
          ? 'text_to_image'
          : 'image_to_image',
      if (action.referenceImagePaths.isNotEmpty)
        'referenceImageCount': action.referenceImagePaths.length,
      'storage': storage,
    };
  }
}
