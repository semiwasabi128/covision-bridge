/// canvas_capture 工具——拍畫布畫面，讓 agent「看見」畫布
///
/// [教練 Agent 2026-08-21] 兩個意識的橋樑——雙向視覺補完。
///
/// 病根：原生 Agent感知畫布只有 canvas_get_state 的 JSON（座標/port/連線）
/// ——他能「知道」，不能「看見」。人類端有無限畫布星空，agent 端
/// 是盲人讀報表。藍圖主張「畫布是兩個意識共同看見的場所」，此工具
/// 兌現它。
///
/// 技術迴路（全部復用既有管線，零新基建）：
/// 1. McpCanvasExecutor.screenshot() → RenderRepaintBoundary → base64 PNG
///    （與 MCP /screenshot 同源——不是另開鏡頭，是共用鏡頭）
/// 2. 本工具存檔到橋樑媒體庫 → 回傳 mediaUrl
/// 3. AgentLoop 既有 multimodal 管線：_isImageMediaUrl → _buildImageContent
///    → image_url content block → vision LLM 看見像素
/// 4. 既有截圖 eviction：LLM 看完自動清掉，回到主力模型推理
///
/// 與 screen_capture（隱私敏感的原生螢幕截圖）不同：本工具只拍
/// 橋樑自己的畫布 widget，不碰使用者的其他視窗，無隱私顧慮，免開關。

import 'dart:convert';
import 'dart:io';

import '../agent_tool.dart';
import 'package:bridge_app/services/agent_loop/mcp_canvas_tools.dart';

/// canvas_capture 的 AgentTool
///
/// 參數 [region] 預留未來擴充（目前拍整個畫布 viewport）。
class CanvasCaptureTool extends AgentTool {
  final McpCanvasExecutor _executor;

  CanvasCaptureTool({required McpCanvasExecutor executor})
      : _executor = executor;

  @override
  String get name => 'canvas_capture';

  @override
  String get description =>
      '拍下畫布目前的畫面並親眼看見它（vision）。'
      '在以下時機使用：放好節點後驗證視覺呈現是否符合預期、'
      '檢查節點是否重疊或連線是否交錯（視覺層，比 snapshot 更直觀）、'
      '使用者說「你看畫面」時、任何需要「看見」而非「知道」的時刻。'
      '回傳截圖檔案路徑，圖片會自動進入你的視覺（multimodal）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final b64 = await _executor.screenshot();
      if (b64.isEmpty) {
        return AgentToolResult.failure('畫布截圖失敗：空內容（畫布可能未渲染）');
      }
      final bytes = base64Decode(b64);

      // 存到橋樑媒體庫（autoIngest watch 範圍外，不污染索引）
      final dir = Directory('/tmp');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/canvas_capture_$ts.png';
      await File(path).writeAsBytes(bytes);

      return AgentToolResult.success(
        '已拍下畫布畫面（${bytes.length} bytes）。請用視覺檢查：'
        '節點有無重疊、連線有無交錯、排版是否符合你想呈現的樣子。',
        mediaUrl: path,
        metadata: {'path': path, 'bytes': bytes.length},
      );
    } catch (e) {
      return AgentToolResult.failure('canvas_capture 失敗: $e');
    }
  }
}
