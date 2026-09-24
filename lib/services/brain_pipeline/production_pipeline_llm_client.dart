// production_pipeline_llm_client.dart
// [Sprint 11 Part B 以利沙] 生產環境 PipelineLLMClient——用 ApiService 包一層
//
// 不直接碰 Dio，也不重複維護 provider/token/baseUrl 邏輯。
// 只負責：把 PipelineLLMClient 介面橋接到 ApiService.complete()。

import 'pipeline_llm_client.dart';
import '../api_service.dart';
import '../storage_service.dart';

class ProductionPipelineLLMClient implements PipelineLLMClient {
  @override
  bool get isAvailable => _cachedAvailable;

  bool _cachedAvailable = false;

  /// 初始化時呼叫，檢查 token 是否可用。
  /// [CEO 修正] 用 StorageService.hasToken() 而非 ApiService.token（不存在）。
  Future<void> refreshAvailability() async {
    _cachedAvailable = await StorageService.hasToken();
  }

  @override
  Future<PipelineLLMResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final content = await ApiService.complete(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        model: model,
      );
      return PipelineLLMResponse(
        content: content,
        latencyMs: stopwatch.elapsedMilliseconds,
        succeeded: true,
      );
    } catch (e) {
      return PipelineLLMResponse(
        content: '',
        latencyMs: stopwatch.elapsedMilliseconds,
        succeeded: false,
      );
    }
  }
}
