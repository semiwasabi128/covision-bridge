// check_capability_status_tool.dart
// P0b: Agent 工具 — 查詢目前系統能力設定狀態
//
// 讓 Agent 能自主檢查：
// - 哪些 LLM provider 已設定 token
// - 圖片生成能力是否就緒
// - Gateway URL 是否設定
// - 目前選定的 provider
//
// 用於 onboarding 引導場景：Agent 先查狀態，再決定引導下一步。

import '../agent_tool.dart';
import '../../storage_service.dart';

class CheckCapabilityStatusTool extends AgentTool {
  @override
  String get name => 'check_capability_status';

  @override
  String get description =>
      '查詢目前系統的 AI 服務設定狀態。回傳哪些 provider 已設定 token、'
      '目前選定的 provider、Gateway URL 是否設定。'
      '用於判斷使用者是否需要引導設定。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final provider = await StorageService.getProvider();
      final gatewayUrl = await StorageService.getGatewayUrl();

      // 掃描所有 provider 的 token 設定狀態
      const providers = ['openai', 'glm', 'kimi', 'minimax', 'gemini', 'claude'];
      final configuredProviders = <String>[];
      for (final p in providers) {
        final token = await StorageService.getToken(provider: p);
        if (token != null && token.trim().isNotEmpty) {
          configuredProviders.add(p);
        }
      }

      // 也檢查預設 token（未指定 provider 的）
      final defaultToken = await StorageService.getToken();
      final hasDefaultToken = defaultToken != null && defaultToken.trim().isNotEmpty;

      final hasGateway = gatewayUrl != null && gatewayUrl.isNotEmpty;
      final hasAnyToken = configuredProviders.isNotEmpty || hasDefaultToken;

      // 組裝狀態報告
      final lines = <String>[];
      lines.add('=== 系統能力設定狀態 ===');
      lines.add('');
      lines.add('目前選定 Provider: ${provider ?? "未設定"}');
      lines.add('Gateway URL: ${hasGateway ? "已設定" : "未設定"}');
      lines.add('已設定 Token 的 Provider: ${configuredProviders.isEmpty ? "無" : configuredProviders.join(", ")}');
      lines.add('預設 Token: ${hasDefaultToken ? "已設定" : "未設定"}');
      lines.add('');

      if (!hasAnyToken) {
        lines.add('⚠️ 狀態：空白狀態 — 尚未設定任何 AI 服務金鑰。');
        lines.add('建議：引導使用者到「系統 → 設定」設定 MiniMax（推薦）或其他 provider。');
        lines.add('MiniMax 註冊網址: https://platform.minimaxi.com/');
      } else if (!hasGateway) {
        lines.add('⚠️ 狀態：已設定 token 但 Gateway URL 未設定。');
        lines.add('建議：引導使用者到「系統 → 設定」設定 Gateway URL。');
      } else {
        lines.add('✅ 狀態：AI 服務已就緒，可以正常對話。');
      }

      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      return AgentToolResult.failure('查詢設定狀態失敗：$e');
    }
  }
}
