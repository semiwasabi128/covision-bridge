/// BridgeAction 工具——把現有 BridgeActionExecutor 包成 AgentTool
///
/// 7 種 BridgeAction 各自封裝成一個 AgentTool：
/// browse, vision, generate_image, document, desktop_files
/// （generate_music/generate_video 目前 needsProvider，不註冊）

import '../agent_tool.dart';
import '../../bridge_action_executor.dart';
import '../../../models/bridge_action.dart';

/// 共用基底：把 BridgeActionExecutor 包成 AgentTool
class _BridgeActionToolBase extends AgentTool {
  final BridgeActionExecutor _executor;
  final BridgeActionType _actionType;
  final String _toolName;
  final String _description;
  final List<AgentToolParamSpec> _paramSpecs;

  _BridgeActionToolBase({
    required BridgeActionExecutor executor,
    required BridgeActionType actionType,
    required String toolName,
    required String description,
    required List<AgentToolParamSpec> paramSpecs,
  })  : _executor = executor,
        _actionType = actionType,
        _toolName = toolName,
        _description = description,
        _paramSpecs = paramSpecs;

  @override
  String get name => _toolName;

  @override
  String get description => _description;

  @override
  List<AgentToolParamSpec> get paramSpecs => _paramSpecs;

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final prompt = args['prompt']?.toString() ?? '';
    if (prompt.isEmpty) {
      return AgentToolResult.failure('prompt 參數為空');
    }

    // [教練 Agent 2026-08-09] 不讓 LLM 指定 provider——LLM 會偏好自己的 provider
    // （例如 gemini 會指定 gemini），但該 provider 可能沒有圖片生成能力。
    // 讓 CapabilityRouter 自動選最佳 adapter。
    final action = BridgeAction(
      type: _actionType,
      prompt: prompt,
    );

    try {
      final result = await _executor.execute(action);
      if (result.status == BridgeActionStatus.completed) {
        return AgentToolResult.success(
          result.message,
          mediaUrl: result.mediaUrl,
          metadata: result.metadata,
        );
      } else if (result.status == BridgeActionStatus.needsProvider) {
        return AgentToolResult.failure(
          '服務未設定：${result.message}',
        );
      } else if (result.status == BridgeActionStatus.needsConfirmation) {
        return AgentToolResult.failure(
          '需要使用者確認：${result.message}',
        );
      } else {
        return AgentToolResult.failure(result.message);
      }
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// 網頁搜尋
class BrowseTool extends _BridgeActionToolBase {
  BrowseTool(BridgeActionExecutor executor)
      : super(
          executor: executor,
          actionType: BridgeActionType.browse,
          toolName: 'web_search',
          description: '搜尋網路資訊。用於查詢最新消息、事實查證、尋找資料。',
          paramSpecs: [
            AgentToolParamSpec(
              name: 'query',
              description: '搜尋關鍵字',
              required: true,
            ),
          ],
        );

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? args['prompt']?.toString() ?? '';
    return super.execute({'prompt': query, if (args['provider'] != null) 'provider': args['provider']});
  }
}

/// 圖片辨識
class VisionTool extends _BridgeActionToolBase {
  VisionTool(BridgeActionExecutor executor)
      : super(
          executor: executor,
          actionType: BridgeActionType.vision,
          toolName: 'image_recognition',
          description: '辨識圖片內容。用於分析使用者上傳的圖片。',
          paramSpecs: [
            AgentToolParamSpec(
              name: 'prompt',
              description: '要對圖片提出的問題或描述需求',
              required: true,
            ),
          ],
        );
}

/// 圖片生成
class GenerateImageTool extends _BridgeActionToolBase {
  GenerateImageTool(BridgeActionExecutor executor)
      : super(
          executor: executor,
          actionType: BridgeActionType.generateImage,
          toolName: 'generate_image',
          description: '生成圖片。用於畫圖、設計、視覺創作。',
          paramSpecs: [
            AgentToolParamSpec(
              name: 'prompt',
              description: '圖片描述',
              required: true,
            ),
            AgentToolParamSpec(
              name: 'provider',
              description: '圖片生成服務商（如 openai, replicate）',
            ),
          ],
        );
}

/// 文件產出
class DocumentTool extends _BridgeActionToolBase {
  DocumentTool(BridgeActionExecutor executor)
      : super(
          executor: executor,
          actionType: BridgeActionType.document,
          toolName: 'create_document',
          description: '產出文件或報告。用於整理資訊成文件格式。',
          paramSpecs: [
            AgentToolParamSpec(
              name: 'prompt',
              description: '文件內容描述',
              required: true,
            ),
          ],
        );
}

/// 桌面檔案管理
class DesktopFilesTool extends _BridgeActionToolBase {
  DesktopFilesTool(BridgeActionExecutor executor)
      : super(
          executor: executor,
          actionType: BridgeActionType.desktopFiles,
          toolName: 'desktop_files',
          description: '掃描和管理桌面檔案。用於整理本地檔案、查看檔案分類。',
          paramSpecs: [
            AgentToolParamSpec(
              name: 'prompt',
              description: '檔案管理需求描述',
              required: true,
            ),
          ],
        );
}
