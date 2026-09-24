import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class ReplicateImageAdapter extends BridgeActionAdapter {
  ReplicateImageAdapter({Dio? dio}) : _dio = dio ?? Dio();

  static const _modelOwner = 'black-forest-labs';
  static const _modelName = 'flux-schnell';
  static const _model = '$_modelOwner/$_modelName';

  final Dio _dio;

  @override
  String get id => 'replicate';

  @override
  String get displayName => 'Replicate FLUX Schnell';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final token = await StorageService.getToken(provider: id);
    if (token == null || token.isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'Replicate API Token 尚未設定',
        provider: id,
      );
    }

    try {
      final response = await _dio.post(
        'https://api.replicate.com/v1/models/$_model/predictions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Prefer': 'wait=60',
            'Cancel-After': '120s',
          },
        ),
        data: {
          'input': {'prompt': action.prompt},
        },
      );

      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final status = data['status']?.toString();
      final error = data['error']?.toString();
      if (error != null && error.isNotEmpty && error != 'null') {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'Replicate 圖片生成失敗：$error',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'adapter': displayName,
            'kind': 'image',
            'model': _model,
          },
        );
      }

      final outputUrl = _extractOutputUrl(data['output']);
      if (outputUrl == null || outputUrl.isEmpty) {
        return BridgeActionResult(
          status: BridgeActionStatus.needsConfirmation,
          message: status == null
              ? 'Replicate 沒有回傳可顯示的圖片'
              : 'Replicate 任務狀態：$status，尚未取得圖片',
          metadata: {
            'provider': id,
            'adapter': displayName,
            'kind': 'image',
            'type': action.type.legacyType,
            'model': _model,
            'predictionId': ?data['id'],
            'status': ?status,
          },
        );
      }

      final imageResponse = await _dio.get<List<int>>(
        outputUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = imageResponse.data;
      final mediaPath = bytes == null
          ? outputUrl
          : await BridgeMediaStore.persistImageBytes(Uint8List.fromList(bytes), prompt: action.prompt);

      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: 'Replicate 圖片已生成完成',
        mediaUrl: mediaPath,
        metadata: {
          'provider': id,
          'adapter': displayName,
          'kind': 'image',
          'type': action.type.legacyType,
          'model': _model,
          'mode': 'text_to_image',
          'storage': mediaPath == outputUrl ? 'remote_url' : 'local_file',
        },
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['detail'] ??
                e.response?.data['error'] ??
                e.message)
          : e.message;
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'Replicate 圖片生成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'kind': 'image',
          'model': _model,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'Replicate 圖片生成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'kind': 'image',
          'model': _model,
        },
      );
    }
  }

  String? _extractOutputUrl(dynamic output) {
    if (output is String) return output;
    if (output is List && output.isNotEmpty) {
      final first = output.first;
      if (first is String) return first;
      if (first is Map && first['url'] != null) return first['url'].toString();
    }
    if (output is Map && output['url'] != null) return output['url'].toString();
    return null;
  }
}
