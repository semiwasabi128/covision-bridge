// minimax_tts_adapter.dart
// MiniMax 語音合成 Adapter — speech-2.8-hd model
//
// API: POST https://api.minimax.io/v1/t2a_v2
// 同步：送出 text → 回傳 hex-encoded audio 或 URL
//
// 模型: speech-2.8-hd (預設), speech-2.8-turbo, speech-2.6-hd, speech-2.6-turbo
//
// 注意: voice_setting 中的 speed/vol/pitch 必須是整數（不能用浮點數）

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class MinimaxTtsAdapter extends BridgeActionAdapter {
  MinimaxTtsAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _baseUrl = 'https://api.minimax.io';
  static const _defaultModel = 'speech-2.8-hd';
  static const _defaultVoiceId = 'English_expressive_narrator';

  @override
  String get id => 'minimax-tts';

  @override
  String get displayName => 'MiniMax Speech 2.8 HD 語音合成';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateMusic};

  @override
  bool canHandle(BridgeAction action, String provider) {
    // TTS 複用 generateMusic type，但 provider 必須是 minimax-tts
    return supportedTypes.contains(action.type) && provider == id;
  }

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

    // [小葵 2026-09-24] 音色偏好：companion.voiceName 存非預設值時覆蓋（例：小葵
    // 的 xiaokui_video_voice＝H3 影片原聲克隆）。prompt 尾端可帶 [voice:xxx] [pitch:n]
    // 指定音色/音高（語音腳本產生器用）；否則讀 StorageService 的 ttsVoicePreference。
    var voiceId = _defaultVoiceId;
    var pitch = 0;
    final voiceTag = RegExp(r'\[voice:([A-Za-z0-9_]+)\]').firstMatch(action.prompt);
    final pitchTag = RegExp(r'\[pitch:(-?\d+)\]').firstMatch(action.prompt);
    if (voiceTag != null) voiceId = voiceTag.group(1)!;
    if (pitchTag != null) pitch = int.parse(pitchTag.group(1)!);
    if (voiceTag == null) {
      final saved = await StorageService.getTtsVoicePreference();
      if (saved != null && saved.isNotEmpty) voiceId = saved;
    }

    try {
      final resp = await _dio.post(
        '$_baseUrl/v1/t2a_v2',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'text': action.prompt,
          'stream': false,
          'language_boost': 'auto',
          'output_format': 'url',
          'voice_setting': {
            'voice_id': voiceId,
            'speed': 1,
            'vol': 1,
            'pitch': pitch,
          },
          'audio_setting': {
            'sample_rate': 32000,
            'bitrate': 128000,
            'format': 'mp3',
            'channel': 1,
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
          message: 'MiniMax 語音合成失敗：${baseResp?['status_msg']}',
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
          message: 'MiniMax 未回傳語音資料',
          metadata: {'provider': id, 'model': model},
        );
      }

      String mediaPath;

      if (audioData.startsWith('http://') || audioData.startsWith('https://')) {
        final audioResp = await _dio.get<List<int>>(
          audioData,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = audioResp.data;
        mediaPath = bytes == null
            ? audioData
            : await BridgeMediaStore.persistAudioBytes(
                Uint8List.fromList(bytes),
              );
      } else {
        // hex 模式
        final audioBytes = _decodeHex(audioData);
        mediaPath = await BridgeMediaStore.persistAudioBytes(
          Uint8List.fromList(audioBytes),
        );
      }

      final extraInfo = data['extra_info'] as Map<String, dynamic>?;

      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: 'MiniMax 語音已合成完成',
        mediaUrl: mediaPath,
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'kind': 'tts',
          'model': model,
          'voiceId': voiceId,
          'audioLength': ?extraInfo?['audio_length'],
          'sampleRate': ?extraInfo?['audio_sample_rate'],
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
        message: 'MiniMax 語音合成失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'model': _defaultModel,
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: 'MiniMax 語音合成失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
        },
      );
    }
  }

  List<int> _decodeHex(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final result = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      result.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
