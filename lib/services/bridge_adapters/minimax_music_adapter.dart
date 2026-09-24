// minimax_music_adapter.dart
// MiniMax 音樂生成 Adapter — music-2.6 model
//
// API: POST https://api.minimax.io/v1/music_generation
// 同步：送出 prompt + lyrics → 回傳 hex-encoded audio 或 URL
//
// 模型: music-2.6 (預設), music-2.6-free, music-cover, music-cover-free

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class MinimaxMusicAdapter extends BridgeActionAdapter {
  MinimaxMusicAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _baseUrl = 'https://api.minimax.io';
  static const _defaultModel = 'music-2.6';

  @override
  String get id => 'minimax-music';

  @override
  String get displayName => 'MiniMax Music 2.6 音樂生成';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateMusic};

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
      final resp = await _dio.post(
        '$_baseUrl/v1/music_generation',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'prompt': _extractPrompt(action),
          'lyrics': _extractLyrics(action),
          'is_instrumental': _isInstrumental(action),
          'stream': false,
          'output_format': 'url',
          'audio_setting': {
            'sample_rate': 44100,
            'bitrate': 256000,
            'format': 'mp3',
          },
        },
      );

      final data = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : <String, dynamic>{};

      final baseResp = data['base_resp'] as Map<String, dynamic>?;
      final statusCode = baseResp?['status_code'];
      if (statusCode != null && statusCode != 0) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 音樂生成失敗：${baseResp?['status_msg']}',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'model': model,
            'statusCode': statusCode,
          },
        );
      }

      final audioData = data['data']?['audio']?.toString();
      if (audioData == null || audioData.isEmpty) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: 'MiniMax 未回傳音訊資料',
          metadata: {'provider': id, 'model': model},
        );
      }

      // output_format='url' → audio 是下載 URL
      // output_format='hex' → audio 是 hex-encoded bytes
      String mediaPath;

      if (audioData.startsWith('http://') || audioData.startsWith('https://')) {
        // URL 模式：下載到本地（URL 24 小時過期）
        final audioResp = await _dio.get<List<int>>(
          audioData,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = audioResp.data;
        mediaPath = bytes == null
            ? audioData
            : await BridgeMediaStore.persistAudioBytes(
                Uint8List.fromList(bytes),
                prompt: action.prompt,
              );
      } else {
        // hex 模式：解碼 hex → bytes
        final audioBytes = _decodeHex(audioData);
        mediaPath = await BridgeMediaStore.persistAudioBytes(
          Uint8List.fromList(audioBytes),
          prompt: action.prompt,
        );
      }

      final extraInfo = data['extra_info'] as Map<String, dynamic>?;

      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: 'MiniMax 音樂已生成完成',
        mediaUrl: mediaPath,
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'kind': 'music',
          'model': model,
          'duration': ?extraInfo?['music_duration'],
          'sampleRate': ?extraInfo?['music_sample_rate'],
          'bitrate': ?extraInfo?['bitrate'],
          'storage': mediaPath.startsWith('http') ? 'remote_url' : 'local_file',
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
        message: 'MiniMax 音樂生成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'model': _defaultModel,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'MiniMax 音樂生成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
        },
      );
    }
  }

  /// 從 action prompt 提取音樂描述部分（---lyrics--- 之前）
  String _extractPrompt(BridgeAction action) {
    final parts = action.prompt.split('---lyrics---');
    return parts[0].trim();
  }

  /// 從 action prompt 提取歌詞 — 用 `---lyrics---` 分隔描述與歌詞
  /// 例如: "Pop, melancholic\n---lyrics---\n[verse]\nStreetlights flicker..."
  String? _extractLyrics(BridgeAction action) {
    final parts = action.prompt.split('---lyrics---');
    if (parts.length < 2) return null;
    final lyrics = parts[1].trim();
    return lyrics.isEmpty ? null : lyrics;
  }

  /// 是否為純音樂（無人聲）— prompt 包含 "instrumental" 關鍵字
  bool _isInstrumental(BridgeAction action) {
    return action.prompt.toLowerCase().contains('instrumental');
  }

  /// hex 字串解碼為 bytes
  List<int> _decodeHex(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final result = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      result.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
