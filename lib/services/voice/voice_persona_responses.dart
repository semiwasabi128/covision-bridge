/// 人格回應池 + 生成邏輯
library;

/// 每個夥伴人格有兩層短回應機制：
/// 1. 固定回應池（種子）— 虛字答腔 + 情緒短回應種子
/// 2. 生成邏輯 — 呼叫本地 Gemma 生成不重複的短回應
///
/// 防重複機制：維護最近 10 個回應，生成時在 prompt 中排除已用回應。
///
/// 本地模型 API 呼叫方式參考 local_code_generate_tool.dart：
/// - Dio POST 到 http://127.0.0.1:18789/v1/chat/completions
/// - OpenAI chat completions 格式
/// - 連線失敗時 fallback 到固定池

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'voice_emotion_analyzer.dart';

/// 本地模型 server 的預設端點
const String _kLocalModelBaseUrl = 'http://127.0.0.1:18789';

/// 人格語音回應池
///
/// 管理：
/// - backchannels: 虛字答腔固定池（使用者在說話時隨機插入）
/// - emotionResponseSeeds: 情緒短回應種子（使用者說完一句先回應情緒）
/// - generateShortResponse(): 呼叫本地 Gemma 生成不重複短回應
/// - 防重複機制：最近 _maxRecentResponses 個回應
class PersonaVoiceResponses {
  /// 本地模型 Dio 實例
  final Dio _dio;

  /// 預設模型名稱（查詢 /v1/models 失敗時使用）
  static const String _defaultModelName = 'gemma-4-e4b';

  /// 防重複列表大小
  static const int _maxRecentResponses = 10;

  /// 虛字答腔固定池（使用者在說話時，隨機插入）
  ///
  /// 這些變化度低，固定池就夠。不經過 LLM。
  final List<String> backchannels;

  /// 情緒短回應種子（使用者說完一句，先回應情緒）
  ///
  /// 種子只是起點，真正的短回應由 generateShortResponse() 即時生成。
  final Map<VoiceEmotion, List<String>> emotionResponseSeeds;

  /// 語速（影響 TTS 播放速度）
  /// 1.0 = 正常，1.2 = 活潑，0.9 = 沉穩
  final double speechRate;

  /// 人格名稱（生成 prompt 用）
  final String personaName;

  /// 人格特質描述（生成 prompt 用）
  final String personaTraits;

  /// 最近用過的回應（防重複）
  final List<String> _recentResponses = [];

  /// 建立預設人格回應池
  ///
  /// [personaName] — 人格名稱
  /// [personaTraits] — 人格特質描述
  /// [speechRate] — TTS 語速倍率
  /// [baseUrl] — 本地模型 server URL
  /// [dio] — 可注入 Dio（測試用）
  PersonaVoiceResponses({
    this.personaName = '', // [2026-08-26] 名字主權歸使用者——由呼叫端注入夥伴名
    this.personaTraits = '溫暖、務實、有條理',
    this.speechRate = 1.0,
    String baseUrl = _kLocalModelBaseUrl,
    Dio? dio,
  })  : backchannels = const [
          '嗯',
          '對',
          '是喔',
          '嗯嗯',
          '了解',
          '好',
          '原來如此',
          '我懂',
        ],
        emotionResponseSeeds = const {
          VoiceEmotion.urgent: [
            '哇，那聽起來很急',
            '我馬上來處理',
            '好，我現在就看',
          ],
          VoiceEmotion.confused: [
            '你是不是卡住了？',
            '讓我幫你看看',
            '嗯，我再確認一下',
          ],
          VoiceEmotion.happy: [
            '太好了！',
            '不錯嘛！',
            '哇，恭喜！',
          ],
          VoiceEmotion.angry: [
            '抱歉讓你困擾了',
            '我馬上改',
            '不好意思，我來處理',
          ],
          VoiceEmotion.calm: [
            '嗯，說說看',
            '我在聽',
            '好，繼續',
          ],
        },
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
              headers: {'Content-Type': 'application/json'},
            ));

  /// 從虛字答腔池隨機取一個
  String randomBackchannel() {
    final random = Random();
    return backchannels[random.nextInt(backchannels.length)];
  }

  /// 從情緒種子池隨機取一個
  ///
  /// 種子池是 fallback，優先使用 generateShortResponse() 生成獨特回應。
  String randomEmotionSeed(VoiceEmotion emotion) {
    final seeds = emotionResponseSeeds[emotion];
    if (seeds == null || seeds.isEmpty) return '嗯';
    final random = Random();
    return seeds[random.nextInt(seeds.length)];
  }

  /// 生成不重複的短回應
  ///
  /// 呼叫本地 Gemma 根據人格 + 情緒 + 使用者剛說的話生成獨特短回應。
  /// 失敗時 fallback 到情緒種子池。
  ///
  /// [emotion] — 偵測到的情緒
  /// [userContext] — 使用者剛說的話的摘要
  Future<String> generateShortResponse({
    required VoiceEmotion emotion,
    required String userContext,
  }) async {
    try {
      final model = await _resolveModelName();

      // 組 prompt — 包含人格、情緒、使用者上下文、排除已用回應
      final excludeList = _recentResponses.isEmpty
          ? '（無）'
          : _recentResponses.join('、');

      final systemPrompt = '你是人格「$personaName」，性格：$personaTraits。'
          '根據使用者的情緒和剛說的話，生成一句自然的短回應。'
          '回應要在10字以內，符合你的人格語氣。'
          '只輸出回應本身，不要解釋，不要加引號。';

      final userPrompt = '使用者情緒：${emotion.label}\n'
          '使用者剛說了：$userContext\n\n'
          '請生成一句短回應（10字以內）。\n'
          '不要用以下已用過的回應：$excludeList\n'
          '每次用不同的措辭，像真人一樣不重複。';

      final requestBody = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'max_tokens': 50,
        // [教練 Agent 2026-07-30] reasoning model 不支援自訂 temperature
        if (!model.toLowerCase().startsWith('kimi-k3') &&
            !model.toLowerCase().startsWith('gpt-5'))
          'temperature': 0.8,
      };

      final response = await _dio.post(
        '/v1/chat/completions',
        data: jsonEncode(requestBody),
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        return _fallbackResponse(emotion);
      }

      final message = (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final content = message?['content']?.toString().trim();

      if (content == null || content.isEmpty) {
        return _fallbackResponse(emotion);
      }

      // 清理回應（去除引號、換行）
      final cleaned = content
          .replaceAll(RegExp('["\'\u300c\u300d\u300e\u300f]'), '')
          .replaceAll(RegExp(r'\n+'), ' ')
          .trim();

      if (cleaned.isEmpty) {
        return _fallbackResponse(emotion);
      }

      // 記錄到防重複列表
      _addToRecent(cleaned);

      return cleaned;
    } on DioException catch (e) {
      debugPrint('[PersonaVoiceResponses] 本地模型連線失敗: ${e.type}');
      return _fallbackResponse(emotion);
    } catch (e) {
      debugPrint('[PersonaVoiceResponses] 生成短回應失敗: $e');
      return _fallbackResponse(emotion);
    }
  }

  /// Fallback — 從情緒種子池隨機取（避開最近用過的）
  String _fallbackResponse(VoiceEmotion emotion) {
    final seeds = emotionResponseSeeds[emotion] ?? ['嗯'];

    // 過濾掉最近用過的
    final available = seeds.where((s) => !_recentResponses.contains(s)).toList();
    final pool = available.isEmpty ? seeds : available;

    final random = Random();
    final picked = pool[random.nextInt(pool.length)];
    _addToRecent(picked);
    return picked;
  }

  /// 加入防重複列表（保持最近 _maxRecentResponses 個）
  void _addToRecent(String response) {
    _recentResponses.add(response);
    if (_recentResponses.length > _maxRecentResponses) {
      _recentResponses.removeAt(0);
    }
  }

  /// 取得最近用過的回應列表（唯讀）
  List<String> get recentResponses => List.unmodifiable(_recentResponses);

  /// 清除防重複列表
  void clearRecentResponses() {
    _recentResponses.clear();
  }

  /// 查詢本地 server 取得可用模型名稱
  ///
  /// 呼叫 /v1/models，取第一個模型。
  /// 失敗時使用預設名稱。
  Future<String> _resolveModelName() async {
    try {
      final response = await _dio.get('/v1/models');
      final data = response.data as Map<String, dynamic>;
      final models = data['data'] as List?;
      if (models != null && models.isNotEmpty) {
        final firstModel = models[0] as Map<String, dynamic>;
        final id = firstModel['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (_) {
      // 查詢失敗不阻斷——用預設值繼續
    }
    return _defaultModelName;
  }

  /// 釋放資源
  void dispose() {
    _dio.close();
  }
}
