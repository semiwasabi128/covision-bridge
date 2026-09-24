/// delegate_batch 工具——批次平行派多個子代理執行任務
///
/// 向量工作流維度 1 的進階：平行多模型協同。
/// App Agent（主大腦）一次派多個子代理，用不同外部 LLM 平行執行任務，
/// 收集所有結果後綜合回覆。類似 Hermes 的平行子代理派發能力。
///
/// 使用情境：
/// - 同時派 3 個子代理分別用 GLM、GPT、Kimi 完成不同子任務
/// - 平行做研究 + 寫作 + 分析
/// - 比較不同模型對同一問題的回答
///
/// 技術迴路：
/// 1. 解析 tasks 陣列（每個 task 有 goal / provider / context）
/// 2. 用 Future.wait 平行派發所有子代理
/// 3. 每個子代理呼叫方式和 delegate_subagent_tool.dart 一樣
/// 4. 收集所有結果，按原始順序回傳
/// 5. 任何一個失敗不影響其他子代理
///
/// 錯誤處理：
/// - 每個子代理獨立 try/catch
/// - 失敗的子代理回傳錯誤訊息，不中斷其他
/// - 全部失敗才回傳整體錯誤
/// - timeout：每個子代理 120 秒，整批 300 秒

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../api_service.dart';
import '../../storage_service.dart';
import '../agent_provider_profile.dart';
import '../agent_profile_store.dart';
import '../agent_tool.dart';
import '../../sovereignty/data_path_gate.dart';
import '../../sovereignty/data_path_interceptor.dart';
import '../../collab/swarm_campaign.dart'; // [TRIO M4] 開戰閘門守衛
import '../../api_usage_tracker.dart'; // [M5b] 時時成本讀數
import 'delegate_subagent_tool.dart' as delegate_subagent_tool;

/// 子代理的 system prompt（與 delegate_subagent_tool 共用）
const String _kBatchSubAgentSystemPrompt =
    '你是一個子代理。專注完成以下任務，不要做其他事。用繁體中文回答。';

/// 支援的 provider 列表（與 delegate_subagent_tool 共用）
const Set<String> _kBatchSupportedProviders = {
  'glm',
  'openai',
  'kimi',
  'claude',
  'gemini',
};

/// delegate_batch AgentTool
///
/// 讓 App Agent 能一次派多個子代理，平行用不同外部 LLM 執行任務。
/// 這是向量工作流維度 1（多模型協同）的批次進階工具。
class DelegateBatchTool extends AgentTool {
  final Dio _dio;

  /// [dio] — 可注入 Dio 實例（測試用）
  DelegateBatchTool({Dio? dio})
      : _dio = dio ?? createSovereigntyDio();


  /// [資料主權 P0-b 2026-09-14] 委派流量過 DataPathGate（text/delegate）——
  /// 靜態工具，兩個 delegate tool 共用。
  static Dio createSovereigntyDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(SovereigntyInterceptor(
      dataClass: DataPathClass.text,
      purpose: DataPathPurpose.delegate,
    ));
    return dio;
  }

  @override
  String get name => 'delegate_batch';

  @override
  String get description =>
      '批次平行派多個子代理執行任務。一次提交多個子代理任務，所有子代理同時執行，'
      '結果平行收集後一次回傳。適合需要同時做多件事的場景（如平行研究 + 寫作 + 分析）。'
      '每個子代理可以指定不同的 provider，利用不同 LLM 的優勢。'
      '任何一個子代理失敗不影響其他子代理。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'tasks',
          description: '子代理任務陣列。每個元素是一個 JSON 物件，包含：\n'
              '- goal（必填）：子代理要完成的任務目標\n'
              '- provider（選填）：用哪個 LLM provider（glm/openai/kimi/claude/gemini）\n'
              '- context（選填）：給子代理的上下文資訊\n'
              '範例：[{"goal":"分析這段程式碼","provider":"glm","context":"..."},{"goal":"寫摘要","provider":"kimi"}]',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    // [TRIO M4 2026-09-22] 開戰閘門守衛——planning 期硬拒絕派兵
    // （Blue 令：六關全過 + 使用者 commit 才開戰，任意開戰都是災難）
    int plannedTroops = 0;
    if (args['tasks'] is List) {
      plannedTroops = (args['tasks'] as List).length;
    } else if (args['tasks'] is String) {
      try {
        final d = jsonDecode(args['tasks'] as String);
        if (d is List) plannedTroops = d.length;
      } catch (_) {}
    }
    final denied = SwarmCommand.instance
        .assertMaySpawn(troopCount: plannedTroops);
    if (denied != null) {
      return AgentToolResult.failure('⛔ 開戰閘門：$denied');
    }

    // [教練 Agent 2026-08-08] Provider 嚴格鎖定——與 delegate_subagent 共用同一把鎖
    // 指定模式下不允許批次派子代理繞過鎖定
    final lockedProvider = delegate_subagent_tool.getSubagentLockedProvider();
    if (lockedProvider != null && lockedProvider.isNotEmpty) {
      return AgentToolResult.failure(
        '使用者已鎖定 $lockedProvider 為指定模型，不允許批次派子代理使用其他 provider。'
        '如需多模型協同，請使用者切換回預設模式。',
      );
    }

    // 解析 tasks 參數——可能是 JSON 字串或已解析的 List
    final tasksArg = args['tasks'];
    if (tasksArg == null) {
      return AgentToolResult.failure('tasks 為必填參數');
    }

    List<dynamic>? taskList;
    if (tasksArg is String) {
      try {
        final decoded = jsonDecode(tasksArg);
        if (decoded is! List) {
          return AgentToolResult.failure('tasks 必須是 JSON 陣列');
        }
        taskList = decoded;
      } catch (e) {
        return AgentToolResult.failure('tasks JSON 解析失敗：$e');
      }
    } else if (tasksArg is List) {
      taskList = tasksArg;
    }
    if (taskList == null) {
      return AgentToolResult.failure(
        'tasks 必須是 JSON 陣列，目前類型：${tasksArg.runtimeType}',
      );
    }

    if (taskList.isEmpty) {
      return AgentToolResult.failure('tasks 陣列不可為空');
    }

    debugPrint('[DelegateBatch] 收到 ${taskList.length} 個子代理任務，開始平行派發');

    // [TRIO M5b 2026-09-23 Blue 令] 時時成本紀錄——作戰成敗數據至關重要：
    // 每兵 spawn 即記、完成即記成敗（帶當下累積 token——cost_tick 原料）
    final campaign = SwarmCommand.instance.active;
    final recorder = campaign != null
        ? SwarmCommand.instance.recorderFor(campaign.id)
        : null;
    if (recorder != null) {
      for (var i = 0; i < taskList.length; i++) {
        final task = taskList[i] as Map<String, dynamic>;
        final goal = (task['goal'] as String?) ?? '任務${i + 1}';
        final provider = (task['provider'] as String?) ?? '?';
        unawaited(recorder.log('spawn',
            agentId: 'troop-$i',
            legion: 'legion-$i',
            data: {'goal': goal, 'provider': provider}));
      }
      unawaited(recorder.log('dispatch', data: {'troops': taskList.length}));
    }

    // 平行派發所有子代理
    final futures = <Future<String>>[];
    for (var i = 0; i < taskList.length; i++) {
      final task = taskList[i];
      futures.add(_executeSingleTask(task, i));
    }

    // 整批 timeout 300 秒
    List<String> results;
    try {
      results = await Future.wait(futures).timeout(
        const Duration(seconds: 300),
      );
    } on TimeoutException {
      // 整批 timeout——但 Future.wait 會丟出，已完成的結果無法取得
      if (recorder != null) {
        unawaited(recorder.log('end',
            data: {'outcome': 'timeout', 'troops': taskList.length}));
      }
      return AgentToolResult.failure(
        '批次執行逾時（300 秒）。部分子代理可能仍在執行中。',
      );
    }

    // [M5b] 成敗紀錄＋時時成本（當下 ApiUsageTracker 讀數）
    if (recorder != null) {
      final spent = ApiUsageTracker.instance.todayTotalTokens;
      for (var i = 0; i < results.length; i++) {
        final failed = results[i].startsWith('[錯誤');
        unawaited(recorder.log(failed ? 'fail' : 'success',
            agentId: 'troop-$i',
            legion: 'legion-$i',
            data: {
              'tokensSoFar': spent,
              'resultHead': results[i].substring(
                  0, results[i].length > 120 ? 120 : results[i].length),
            }));
      }
      unawaited(recorder.log('cost_tick', data: {
        'tokensToday': spent,
        'at': DateTime.now().toIso8601String(),
      }));
    }

    // 檢查是否全部失敗
    final allFailed = results.every((r) => r.startsWith('[錯誤'));
    if (allFailed) {
      return AgentToolResult.failure(
        '所有 ${results.length} 個子代理都失敗了：\n\n${results.join('\n\n---\n\n')}',
      );
    }

    // 按原始順序組裝結果
    final buf = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      if (i > 0) buf.writeln('\n---\n');
      buf.writeln('子代理 ${i + 1} 結果：');
      buf.writeln(results[i]);
    }

    return AgentToolResult.success(
      buf.toString(),
      metadata: {
        'total_tasks': taskList.length,
        'success_count': results.where((r) => !r.startsWith('[錯誤')).length,
        'fail_count': results.where((r) => r.startsWith('[錯誤')).length,
      },
    );
  }

  /// 執行單一子代理任務，回傳結果字串（失敗則回傳 "[錯誤：...]" 格式）
  ///
  /// 獨立 try/catch，確保一個失敗不影響其他。
  Future<String> _executeSingleTask(dynamic task, int index) async {
    try {
      if (task is! Map<String, dynamic>) {
        return '[錯誤：任務 $index 不是有效的 JSON 物件]';
      }

      final goal = task['goal']?.toString();
      if (goal == null || goal.isEmpty) {
        return '[錯誤：任務 $index 缺少必填的 goal 參數]';
      }

      final provider = task['provider']?.toString().trim();
      final context = task['context']?.toString();

      // 判斷要使用哪個 provider
      if (provider == null || provider.isEmpty) {
        // 不指定 → 用當前主大腦的 provider
        final result = await _delegateWithCurrentProvider(
          goal: goal,
          context: context,
        );
        return result.success ? result.content : '[錯誤：${result.content}]';
      }

      // 驗證 provider 是否支援
      if (!_kBatchSupportedProviders.contains(provider)) {
        return '[錯誤：不支援的 provider「$provider」。'
            '支援的 provider：${_kBatchSupportedProviders.join('、')}]';
      }

      final result = await _delegateWithSpecifiedProvider(
        goal: goal,
        context: context,
        provider: provider,
      );
      return result.success ? result.content : '[錯誤：${result.content}]';
    } on TimeoutException {
      return '[錯誤：timeout]';
    } catch (e) {
      return '[錯誤：$e]';
    }
  }

  /// 用當前主大腦的 provider 呼叫子代理
  ///
  /// 走 ApiService.completeWithMessages()，使用全域儲存的 provider/gateway/token。
  Future<AgentToolResult> _delegateWithCurrentProvider({
    required String goal,
    String? context,
  }) async {
    try {
      final provider = await StorageService.getProvider() ?? 'glm';

      final userContent = _buildUserContent(goal: goal, context: context);
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': _kBatchSubAgentSystemPrompt},
        {'role': 'user', 'content': userContent},
      ];

      debugPrint(
        '[DelegateBatch] 子代理用當前 provider=$provider 呼叫',
      );

      final result = await ApiService.completeWithMessages(
        messages: messages,
      ).timeout(const Duration(seconds: 120));

      if (result.trim().isEmpty) {
        return AgentToolResult.failure(
          '子代理（provider=$provider）回傳空內容',
        );
      }

      return AgentToolResult.success(
        result.trim(),
        metadata: {
          'provider': provider,
          'goal': goal,
        },
      );
    } on TimeoutException {
      return AgentToolResult.failure(
        '子代理執行逾時（120 秒）',
      );
    } catch (e) {
      return AgentToolResult.failure('子代理執行失敗：$e');
    }
  }

  /// 用指定的 provider 呼叫子代理
  ///
  /// 直接用該 provider 的雲端 base URL + 對應 token 呼叫 API。
  Future<AgentToolResult> _delegateWithSpecifiedProvider({
    required String goal,
    String? context,
    required String provider,
  }) async {
    try {
      // 取得該 provider 的 token
      final token = await StorageService.getToken(provider: provider);
      if (token == null || token.trim().isEmpty) {
        return AgentToolResult.failure(
          'Provider「$provider」未設定 API Token',
        );
      }

      // 取得 base URL 和預設模型
      final baseUrl = _providerBaseUrlForBatch(provider);
      final resolvedUrl = _resolveBaseUrlForBatch(baseUrl);
      final model = ApiService.defaultModelFor(provider);

      // 取得 ProviderProfile
      final profile = await ProviderProfileStore.instance
          .getProfile(provider, model);

      // 組 messages
      final userContent = _buildUserContent(goal: goal, context: context);
      final apiData = <String, dynamic>{
        'model': model,
        'messages': [
          {'role': 'system', 'content': _kBatchSubAgentSystemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        'stream': true,
      };
      apiData.addAll(profile.apiParams);

      debugPrint(
        '[DelegateBatch] 子代理用指定 provider=$provider, model=$model 呼叫',
      );

      // 呼叫 streaming API
      final result = await _streamChatCompletion(
        resolvedUrl: resolvedUrl,
        token: token,
        apiData: apiData,
        profile: profile,
      ).timeout(const Duration(seconds: 120));

      if (result.trim().isEmpty) {
        return AgentToolResult.failure(
          '子代理（provider=$provider, model=$model）回傳空內容',
        );
      }

      return AgentToolResult.success(
        result.trim(),
        metadata: {
          'provider': provider,
          'model': model,
          'goal': goal,
        },
      );
    } on TimeoutException {
      return AgentToolResult.failure(
        '子代理執行逾時（120 秒）。provider=$provider',
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final respBody = e.response?.data?.toString() ?? '';

      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return AgentToolResult.failure(
          '無法連接到 provider「$provider」的 API server：${e.message}',
        );
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return AgentToolResult.failure(
          '子代理執行逾時（120 秒）。provider=$provider',
        );
      }
      return AgentToolResult.failure(
        'provider「$provider」API 錯誤（HTTP $statusCode）：$respBody',
      );
    } catch (e) {
      return AgentToolResult.failure(
        '子代理執行失敗（provider=$provider）：$e',
      );
    }
  }

  /// 組 user message——有 context 和沒 context 用不同模板
  String _buildUserContent({required String goal, String? context}) {
    final hasContext = context != null && context.isNotEmpty;
    if (hasContext) {
      return '【上下文】\n$context\n\n【任務目標】\n$goal';
    }
    return goal;
  }

  /// 各 provider 的雲端 base URL
  String _providerBaseUrlForBatch(String provider) {
    switch (provider) {
      case 'glm':
        return 'https://open.bigmodel.cn/api/paas/v4';
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'kimi':
        return 'https://api.moonshot.cn/v1';
      case 'claude':
        return 'https://api.anthropic.com/v1';
      case 'gemini':
        return 'https://generativelanguage.googleapis.com/v1beta/openai';
      default:
        return 'https://open.bigmodel.cn/api/paas/v4';
    }
  }

  /// 統一處理 base URL（移除尾部斜線，已有版本路徑則不重複加 /v1）
  String _resolveBaseUrlForBatch(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (RegExp(r'/v\d+$').hasMatch(url)) {
      return url;
    }
    return '$url/v1';
  }

  /// Streaming SSE 請求——與 delegate_subagent_tool 相同邏輯
  ///
  /// 逐 chunk 讀取 SSE stream，組合 content。
  /// 支援 reasoning_content fallback。
  Future<String> _streamChatCompletion({
    required String resolvedUrl,
    required String token,
    required Map<String, dynamic> apiData,
    required ProviderProfile profile,
  }) async {
    final response = await _dio.post(
      '$resolvedUrl/chat/completions',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.stream,
      ),
      data: apiData,
    );

    final stream = response.data.stream as Stream<List<int>>;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final lineBuf = StringBuffer();

    final decodedStream = stream.cast<List<int>>().transform(utf8.decoder);

    await for (final decoded in decodedStream.timeout(
      const Duration(seconds: 90),
    )) {
      lineBuf.write(decoded);

      final raw = lineBuf.toString();
      final events = raw.split('\n\n');
      lineBuf.clear();
      if (!raw.endsWith('\n\n')) {
        lineBuf.write(events.removeLast());
      }

      for (final event in events) {
        for (final line in event.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') continue;
          if (payload.isEmpty) continue;

          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta =
                (choices[0] as Map<String, dynamic>)['delta']
                    as Map<String, dynamic>?;
            if (delta == null) continue;

            final contentDelta = delta['content'] as String?;
            if (contentDelta != null && contentDelta.isNotEmpty) {
              contentBuf.write(contentDelta);
            }

            final reasoningDelta = delta['reasoning_content'] as String?;
            if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
              reasoningBuf.write(reasoningDelta);
            }
          } catch (e) {
            // 單行 parse 失敗不中斷串流
            debugPrint('[DelegateBatch] SSE parse skip: $e');
          }
        }
      }
    }

    final content = contentBuf.toString();
    if (content.isNotEmpty) return content;

    // fallback：如果 content 為空但 reasoning_content 有值
    if (profile.supportsReasoningContent) {
      final reasoning = reasoningBuf.toString();
      if (reasoning.isNotEmpty) return reasoning;
    }

    return '';
  }
}
