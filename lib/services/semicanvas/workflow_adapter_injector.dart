// workflow_adapter_injector.dart
// SemiCanvas Phase 2c+: 具體 Adapter 實作 — 將 app 服務注入 WorkflowNodeAdapters
//
// 7 個抽象介面的具體實作：
// - WorkflowLLMClient          → ApiService.complete()
// - WorkflowToolRunner         → AgentToolRegistry.get(name).execute(args)
// - WorkflowImageGenerator     → BridgeActionExecutor.execute(generateImage)
// - WorkflowVideoGenerator     → BridgeActionExecutor.execute(generateVideo)
// - WorkflowMusicGenerator     → BridgeActionExecutor.execute(generateMusic)
// - WorkflowTtsClient          → BridgeActionExecutor.execute(generateMusic, provider=minimax-tts)
// - WorkflowConditionEvaluator → 內建簡易評估（字串包含）
//
// 使用方式：
//   final adapters = WorkflowAdapterInjector.create(
//     bridgeActionExecutor: executor,
//     agentToolRegistry: registry,
//   );
//   final nodeExecutor = adapters.createNodeExecutor();
//   final wfExecutor = WorkflowExecutor(
//     entityGraph: eg,
//     dagEngine: dag,
//     nodeExecutor: nodeExecutor,
//   );

import 'package:bridge_app/services/api_service.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';
import 'package:bridge_app/services/semicanvas/workflow_node_adapters.dart';

/// ApiService.complete() 包裝成 WorkflowLLMClient
class _ApiServiceLLMClient implements WorkflowLLMClient {
  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    // ApiService.complete 不支援 temperature/maxTokens 參數，
    // 但內部固定 temperature=0.3，足夠工作流使用。
    // 如需自訂 model，透過 model 參數傳入。
    return ApiService.complete(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      model: model,
    );
  }
}

/// AgentToolRegistry 包裝成 WorkflowToolRunner
class _AgentToolRunner implements WorkflowToolRunner {
  final AgentToolRegistry _registry;

  _AgentToolRunner(this._registry);

  @override
  Future<String> runTool({
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final tool = _registry.get(toolName);
    if (tool == null) {
      throw Exception('工具「$toolName」未註冊');
    }
    final result = await tool.execute(args);
    if (!result.success) {
      throw Exception(result.content);
    }
    return result.content;
  }
}

/// BridgeActionExecutor 包裝成 WorkflowImageGenerator
class _BridgeActionImageGenerator implements WorkflowImageGenerator {
  final BridgeActionExecutor _executor;

  _BridgeActionImageGenerator(this._executor);

  @override
  Future<String> generateImage({
    required String prompt,
    String? model,
    String? size,
    String? style,
  }) async {
    final action = BridgeAction(
      type: BridgeActionType.generateImage,
      prompt: prompt,
      provider: model,
    );
    final result = await _executor.execute(action, confirmed: true);
    if (result.status == BridgeActionStatus.completed) {
      return result.mediaUrl ?? result.message;
    }
    throw Exception(result.message);
  }
}

/// BridgeActionExecutor 包裝成 WorkflowVideoGenerator
class _BridgeActionVideoGenerator implements WorkflowVideoGenerator {
  final BridgeActionExecutor _executor;

  _BridgeActionVideoGenerator(this._executor);

  @override
  Future<String> generateVideo({
    required String prompt,
    String? model,
    int? duration,
  }) async {
    final action = BridgeAction(
      type: BridgeActionType.generateVideo,
      prompt: prompt,
      provider: model,
    );
    final result = await _executor.execute(action, confirmed: true);
    if (result.status == BridgeActionStatus.completed) {
      return result.mediaUrl ?? result.message;
    }
    throw Exception(result.message);
  }
}

/// BridgeActionExecutor 包裝成 WorkflowMusicGenerator
class _BridgeActionMusicGenerator implements WorkflowMusicGenerator {
  final BridgeActionExecutor _executor;

  _BridgeActionMusicGenerator(this._executor);

  @override
  Future<String> generateMusic({
    required String prompt,
    String? model,
    int? duration,
    String? genre,
  }) async {
    final action = BridgeAction(
      type: BridgeActionType.generateMusic,
      prompt: prompt,
      provider: model,
    );
    final result = await _executor.execute(action, confirmed: true);
    if (result.status == BridgeActionStatus.completed) {
      return result.mediaUrl ?? result.message;
    }
    throw Exception(result.message);
  }
}

/// BridgeActionExecutor 包裝成 WorkflowTtsClient
/// TTS 複用 generateMusic type，但指定 provider=minimax-tts
class _BridgeActionTtsClient implements WorkflowTtsClient {
  final BridgeActionExecutor _executor;

  _BridgeActionTtsClient(this._executor);

  @override
  Future<String> synthesize({
    required String text,
    String? voice,
    double? speed,
  }) async {
    final action = BridgeAction(
      type: BridgeActionType.generateMusic,
      prompt: text,
      provider: 'minimax-tts',
    );
    final result = await _executor.execute(action, confirmed: true);
    if (result.status == BridgeActionStatus.completed) {
      return result.mediaUrl ?? result.message;
    }
    throw Exception(result.message);
  }
}

/// 內建簡易條件評估器 — 字串包含 + 基本比較
class _SimpleConditionEvaluator implements WorkflowConditionEvaluator {
  @override
  Future<bool> evaluate({
    required String expression,
    required Map<String, String> inputs,
  }) async {
    final inputText = inputs.values.join('\n').toLowerCase();

    // 支援 "contains:xxx" 語法
    if (expression.startsWith('contains:')) {
      final term = expression.substring(9).toLowerCase();
      return inputText.contains(term);
    }

    // 支援 "not_contains:xxx" 語法
    if (expression.startsWith('not_contains:')) {
      final term = expression.substring(13).toLowerCase();
      return !inputText.contains(term);
    }

    // 支援 "equals:xxx" 語法
    if (expression.startsWith('equals:')) {
      final term = expression.substring(7).toLowerCase().trim();
      return inputText.trim() == term;
    }

    // 支援 "not_empty" 語法
    if (expression == 'not_empty') {
      return inputText.trim().isNotEmpty;
    }

    // 支援 "is_empty" 語法
    if (expression == 'is_empty') {
      return inputText.trim().isEmpty;
    }

    // 預設：簡單字串包含
    return inputText.contains(expression.toLowerCase());
  }
}

/// Adapter 注入工廠
class WorkflowAdapterInjector {
  /// 建立已注入 app 服務的 WorkflowNodeAdapters
  ///
  /// [bridgeActionExecutor] — 用於圖片生成（可為 null，圖片節點將回報未注入）
  /// [agentToolRegistry] — 用於工具呼叫（可為 null，工具節點將回報未注入）
  /// [llmClient] — 可覆蓋 LLM client（預設用 ApiService）
  /// [conditionEvaluator] — 可覆蓋條件評估器（預設用內建簡易版）
  static WorkflowNodeAdapters create({
    BridgeActionExecutor? bridgeActionExecutor,
    AgentToolRegistry? agentToolRegistry,
    WorkflowLLMClient? llmClient,
    WorkflowVideoGenerator? videoGenerator,
    WorkflowMusicGenerator? musicGenerator,
    WorkflowTtsClient? ttsClient,
    WorkflowConditionEvaluator? conditionEvaluator,
    SubWorkflowRunner? subWorkflowRunner,
  }) {
    return WorkflowNodeAdapters(
      llmClient: llmClient ?? _ApiServiceLLMClient(),
      toolRunner:
          agentToolRegistry != null ? _AgentToolRunner(agentToolRegistry) : null,
      imageGenerator: bridgeActionExecutor != null
          ? _BridgeActionImageGenerator(bridgeActionExecutor)
          : null,
      videoGenerator: videoGenerator ??
          (bridgeActionExecutor != null
              ? _BridgeActionVideoGenerator(bridgeActionExecutor)
              : null),
      musicGenerator: musicGenerator ??
          (bridgeActionExecutor != null
              ? _BridgeActionMusicGenerator(bridgeActionExecutor)
              : null),
      ttsClient: ttsClient ??
          (bridgeActionExecutor != null
              ? _BridgeActionTtsClient(bridgeActionExecutor)
              : null),
      conditionEvaluator: conditionEvaluator ?? _SimpleConditionEvaluator(),
      subWorkflowRunner: subWorkflowRunner,
    );
  }
}
