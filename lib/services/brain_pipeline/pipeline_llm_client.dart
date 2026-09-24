// pipeline_llm_client.dart
// Sprint 3 — 管線專用 LLM Client 介面
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 為什麼不直接用 ApiService？
// ApiService.sendMessage() 是為聊天設計的——它帶 persona、memory、bridge action，
// 太重了。管線的 LLM 呼叫只需要「給 prompt → 拿純文字回來」。
// 這個介面讓 analyzer 可以 mock，不需要真的連 LLM 就能跑測試。

import 'dart:convert';

/// 管線 LLM 呼叫的結果。
class PipelineLLMResponse {
  final String content;
  final int latencyMs;
  final bool succeeded;

  const PipelineLLMResponse({
    required this.content,
    this.latencyMs = 0,
    this.succeeded = true,
  });

  static const PipelineLLMResponse failed = PipelineLLMResponse(
    content: '',
    succeeded: false,
  );
}

/// 管線專用 LLM Client 介面。
/// analyzer 只依賴這個介面，不直接碰 ApiService 或 Dio。
abstract class PipelineLLMClient {
  /// 送 system + user prompt，拿純文字回來。
  /// 失敗時回傳 PipelineLLMResponse.failed，不 throw。
  Future<PipelineLLMResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
  });

  /// 是否可用（測試時可設 false 模擬 LLM 離線）。
  bool get isAvailable;
}

/// 不做任何事的 noop client — LLM 不可用時的預設。
class NoopPipelineLLMClient implements PipelineLLMClient {
  const NoopPipelineLLMClient();

  @override
  Future<PipelineLLMResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
  }) async {
    return PipelineLLMResponse.failed;
  }

  @override
  bool get isAvailable => false;
}

/// 測試用 mock client — 預設回應可自訂，或用 handler 函數動態決定。
class MockPipelineLLMClient implements PipelineLLMClient {
  final Future<PipelineLLMResponse> Function(String systemPrompt, String userPrompt)? handler;
  PipelineLLMResponse _defaultResponse;
  final bool _isAvailable;

  MockPipelineLLMClient({
    this.handler,
    PipelineLLMResponse? defaultResponse,
    bool isAvailable = true,
  })  : _defaultResponse = defaultResponse ??
            const PipelineLLMResponse(content: '{}'),
        _isAvailable = isAvailable;

  @override
  bool get isAvailable => _isAvailable;

  @override
  Future<PipelineLLMResponse> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
  }) async {
    if (handler != null) return handler!(systemPrompt, userPrompt);
    return _defaultResponse;
  }
}

/// 安全解析 LLM 回傳的 JSON。
/// LLM 常會在 JSON 前後加 markdown code block 或多餘文字，
/// 這裡嘗試提取第一個合法 JSON 物件或陣列。
dynamic safeJsonParse(String raw) {
  if (raw.isEmpty) return null;

  // 直接試
  try {
    return jsonDecode(raw);
  } catch (_) {}

  // 去掉 markdown code block
  final codeBlockMatch = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(raw);
  if (codeBlockMatch != null) {
    try {
      return jsonDecode(codeBlockMatch.group(1)!);
    } catch (_) {}
  }

  // 找第一個 { 或 [ 到最後一個 } 或 ]
  final objStart = raw.indexOf('{');
  final arrStart = raw.indexOf('[');
  final start = objStart >= 0 && (arrStart < 0 || objStart < arrStart)
      ? objStart
      : arrStart;
  if (start < 0) return null;

  final endChar = raw[start] == '{' ? '}' : ']';
  final end = raw.lastIndexOf(endChar);
  if (end <= start) return null;

  try {
    return jsonDecode(raw.substring(start, end + 1));
  } catch (_) {
    return null;
  }
}
