/// local_code_generate 工具——呼叫本地模型生成程式碼
///
/// 向量工作流程式碼維度的核心：原生 Agent（主大腦）寫指令，
/// 本地模型（執行者）寫程式碼，原生 Agent校對修正。
///
/// 技術迴路：
/// 1. 原生 Agent組 prompt + context → 送給本地模型
/// 2. 本地模型生成程式碼 → 回傳
/// 3. 原生 Agent校對、修正、整合
///
/// 錯誤處理：
/// - 本地 server 未啟動 → 提示使用者啟動
/// - 120 秒 timeout
/// - 回傳空內容 → 報錯

import 'dart:convert';

import 'package:dio/dio.dart';

import '../agent_tool.dart';

/// 本地程式碼生成 server 的預設端點
const String _kLocalCodeGenBaseUrl = 'http://127.0.0.1:18789';

/// 程式碼生成器的 system prompt
const String _kCodeGenSystemPrompt =
    '你是一個程式碼生成器。根據指令寫出完整、可執行的程式碼。只輸出程式碼，用 ```code 包裹。不要解釋。';

/// local_code_generate AgentTool
///
/// 讓原生 Agent能指揮本地模型寫程式碼。
/// 這是向量工作流程式碼維度的核心——原生 Agent寫指令，本地模型寫程式碼，原生 Agent校對修正。
class LocalCodeGenerateTool extends AgentTool {
  final Dio _dio;

  /// [baseUrl] — 本地 llama-server 的 base URL（預設 http://127.0.0.1:18789）
  /// [dio] — 可注入 Dio 實例（測試用）
  LocalCodeGenerateTool({
    String baseUrl = _kLocalCodeGenBaseUrl,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 30),
              headers: {'Content-Type': 'application/json'},
            ));

  @override
  String get name => 'local_code_generate';

  @override
  String get description =>
      '呼叫本地模型生成程式碼。用於向量工作流程式碼維度——你寫指令，'
      '本地模型寫程式碼，你再校對修正。指令要清楚具體，包含語言、需求、規格。'
      '可附上相關程式碼片段讓本地模型有上下文。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'prompt',
          description: '程式碼生成指令，要清楚具體，包含語言、需求、規格',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'context',
          description: '相關程式碼片段或檔案內容，讓本地模型有上下文',
        ),
        AgentToolParamSpec(
          name: 'language',
          description: '程式語言',
          defaultValue: 'dart',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final prompt = args['prompt']?.toString();
    if (prompt == null || prompt.isEmpty) {
      return AgentToolResult.failure('prompt 為必填參數');
    }

    final context = args['context']?.toString();
    final hasContext = context != null && context.isNotEmpty;

    final language = (args['language']?.toString().isNotEmpty == true)
        ? args['language'].toString()
        : 'dart';

    try {
      // 查詢本地 server 可用模型
      final model = await _resolveModelName();

      // 組 user message——有 context 和沒 context 用不同模板
      final userContent = hasContext
          ? '參考以下上下文：\n$context\n\n根據以下指令寫程式碼：\n$prompt'
          : '根據以下指令寫 $language 程式碼：\n$prompt';

      // 組 OpenAI chat completions request body
      final requestBody = {
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': _kCodeGenSystemPrompt,
          },
          {
            'role': 'user',
            'content': userContent,
          },
        ],
        'max_tokens': 4000,
        'temperature': 0.3,
      };

      // POST 到本地 llama-server
      final response = await _dio.post(
        '/v1/chat/completions',
        data: jsonEncode(requestBody),
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        return AgentToolResult.failure('本地模型回應格式異常：choices 為空');
      }

      final message =
          (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final content = message?['content']?.toString();

      if (content == null || content.isEmpty) {
        return AgentToolResult.failure('本地模型回應內容為空');
      }

      return AgentToolResult.success(
        content,
        metadata: {
          'model': model,
          'prompt': prompt,
          'language': language,
        },
      );
    } on DioException catch (e) {
      // 連線被拒 = server 沒在跑
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return AgentToolResult.failure(
          '無法連接到本地程式碼生成 server（http://127.0.0.1:18789）。'
          '請確認本地 llama-server 已啟動。\n'
          '啟動方式：在 Bridge App 的「本地模型」卡片中啟動 server，'
          '或手動執行 llama-server --port 18789 --model <模型路徑>。\n'
          '詳細錯誤：${e.message}',
        );
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return AgentToolResult.failure(
          '本地程式碼生成逾時（120 秒）。模型可能正在載入或推理中，請稍後再試。',
        );
      }
      // HTTP 錯誤（4xx/5xx）
      final statusCode = e.response?.statusCode;
      final respBody = e.response?.data?.toString() ?? '';
      return AgentToolResult.failure(
        '本地程式碼生成 server 回傳錯誤（HTTP $statusCode）：$respBody',
      );
    } catch (e) {
      return AgentToolResult.failure('本地程式碼生成失敗：$e');
    }
  }

  /// 查詢本地 server 取得可用模型名稱
  ///
  /// 呼叫 /v1/models，取第一個模型。
  /// 失敗時使用預設名稱 "gemma-4-e4b"（llama-server 通常接受任意 model 名稱）。
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
    return 'gemma-4-e4b';
  }
}
