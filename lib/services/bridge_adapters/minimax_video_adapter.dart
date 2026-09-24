// minimax_video_adapter.dart
// MiniMax 影片生成 Adapter — Hailuo text-to-video
//
// API: POST https://api.minimax.io/v1/video_generation
// 非同步：建立任務 → 取得 task_id → 輪詢狀態 → 下載檔案
//
// 模型: MiniMax-Hailuo-2.3 (預設), MiniMax-Hailuo-02, T2V-01-Director, T2V-01

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class MinimaxVideoAdapter extends BridgeActionAdapter {
  MinimaxVideoAdapter({Dio? dio})
      : _dio = dio ?? Dio(),
        _pollDio = dio ?? Dio();

  final Dio _dio;
  final Dio _pollDio;

  static const _baseUrl = 'https://api.minimax.io';
  static const _defaultModel = 'MiniMax-Hailuo-2.3';
  static const _defaultDuration = 6;
  static const _defaultResolution = '768P';
  static const _pollInterval = Duration(seconds: 5);
  static const _maxPollAttempts = 120; // 10 分鐘上限

  @override
  String get id => 'minimax-video';

  @override
  String get displayName => 'MiniMax Hailuo 影片生成';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateVideo};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final token = await StorageService.getToken(provider: 'minimax');
    if (token == null || token.isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'MiniMax API Token 尚未設定（需 MiniMax 帳號的 API Key）',
        provider: id,
      );
    }

    final model = action.model?.trim().isNotEmpty == true
        ? action.model!.trim()
        : _defaultModel;

    try {
      // 1. 建立影片生成任務
      final createResp = await _dio.post(
        '$_baseUrl/v1/video_generation',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'prompt': action.prompt,
          'duration': _defaultDuration,
          'resolution': _defaultResolution,
          'prompt_optimizer': true,
        },
      );

      final createData = createResp.data is Map
          ? Map<String, dynamic>.from(createResp.data as Map)
          : <String, dynamic>{};

      final baseResp = createData['base_resp'] as Map<String, dynamic>?;
      final statusCode = baseResp?['status_code'];
      if (statusCode != null && statusCode != 0) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 影片生成失敗：${baseResp?['status_msg']}',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'model': model,
            'statusCode': statusCode,
          },
        );
      }

      final taskId = createData['task_id']?.toString();
      if (taskId == null || taskId.isEmpty) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 未回傳 task_id',
          metadata: {'provider': id, 'model': model},
        );
      }

      // 2. 輪詢任務狀態
      String? fileId;
      String? videoUrl;
      String? failureReason;

      for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
        await Future.delayed(_pollInterval);

        final pollResp = await _pollDio.get(
          '$_baseUrl/v1/query/video_generation?task_id=$taskId',
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          ),
        );

        final pollData = pollResp.data is Map
            ? Map<String, dynamic>.from(pollResp.data as Map)
            : <String, dynamic>{};

        final status = pollData['status']?.toString();
        fileId = pollData['file_id']?.toString();
        videoUrl = pollData['video_url']?.toString();

        if (status == 'success') break;
        if (status == 'failed') {
          failureReason = pollData['base_resp']?['status_msg']?.toString() ??
              '未知錯誤';
          break;
        }
      }

      if (failureReason != null) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 影片生成失敗：$failureReason',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'model': model,
            'taskId': taskId,
          },
        );
      }

      // 3. 取得影片 URL — video_url 或透過 file_id 下載
      String? finalVideoUrl = videoUrl;
      if (finalVideoUrl == null || finalVideoUrl.isEmpty) {
        if (fileId != null && fileId.isNotEmpty) {
          // 透過 file retrieve API 取得下載 URL
          final fileResp = await _dio.get(
            '$_baseUrl/v1/files/retrieve?file_id=$fileId',
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
            ),
          );
          final fileData = fileResp.data is Map
              ? Map<String, dynamic>.from(fileResp.data as Map)
              : <String, dynamic>{};
          finalVideoUrl = fileData['file']?['download_url']?.toString();
        }
      }

      if (finalVideoUrl == null || finalVideoUrl.isEmpty) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 影片生成完成但無法取得下載 URL（taskId=$taskId）',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'model': model,
            'taskId': taskId,
            'fileId': ?fileId,
          },
        );
      }

      // 4. 下載影片到本地
      final videoResponse = await _dio.get<List<int>>(
        finalVideoUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = videoResponse.data;
      final mediaPath = bytes == null
          ? finalVideoUrl
          : await BridgeMediaStore.persistVideoBytes(
              Uint8List.fromList(bytes),
              prompt: action.prompt,
            );

      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: 'MiniMax 影片已生成完成',
        mediaUrl: mediaPath,
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'kind': 'video',
          'model': model,
          'taskId': taskId,
          'fileId': ?fileId,
          'storage': mediaPath == finalVideoUrl ? 'remote_url' : 'local_file',
        },
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['base_resp']?['status_msg'] ??
              e.response?.data['error'] ??
              e.message)
          : e.message;
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'MiniMax 影片生成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'model': _defaultModel,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'MiniMax 影片生成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
        },
      );
    }
  }
}
