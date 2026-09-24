// MCP Canvas Tools — Agent Loop 工具整合
// 把 BridgeMcpServer 的 12 個端點包裝成 AgentTool
// 直接走 callback，不走 HTTP（同進程，零延遲）
// [Phase 0 Track A 2026-07-17]

import 'dart:convert';

import 'agent_tool.dart';
import 'package:bridge_app/services/vault/canvas_snapshot_service.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart' show NodeTypePorts;
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';

/// MCP 畫布工具的執行器介面
///
/// 由 BridgeDesktopScreen 實作，直接呼叫 BridgeMcpServer 的 callback。
/// 不走 HTTP——同進程直接呼叫，零延遲、零序列化開銷。
abstract class McpCanvasExecutor {
  /// 取得畫布狀態
  Future<Map<String, dynamic>> getState();

  /// [教練 Agent 2026-08-21] 自律——工作流體檢（執行前品質檢查）
  Future<Map<String, dynamic>> inspectWorkflow();

  /// [教練 Agent 2026-07-24] 取得 CanvasSnapshot（人機共視核心）
  /// 回傳包含重疊檢測、可見性、viewport 的完整快照
  Future<Map<String, dynamic>> getSnapshot();

  /// [教練 Agent 2026-07-24] 移動節點
  Future<void> moveNode(String nodeId, double x, double y);
  Future<Map<String, dynamic>> autoLayout(); // [教練 Agent 2026-08-26] 一鍵排版

  /// 截取畫布畫面（base64 PNG）
  Future<String> screenshot();

  /// 取得使用者塗鴉標注
  List<Map<String, dynamic>> getAnnotations();

  /// 新增節點
  Future<String> addNode(String type, double x, double y);

  /// 連接節點
  Future<void> connect(
      String fromNodeId, String fromPort, String toNodeId, String toPort);

  /// 移除節點
  Future<void> removeNode(String nodeId);

  /// 執行工作流
  Future<void> execute();

  /// [教練 Agent 2026-08-22 使用者洞察·渲染層視網膜] 渲染層真實測量數據
  /// —ActualSizeCache（NodeWidget 佈局後回測 RenderBox.size）直讀。
  /// 這是「視網膜直接列印」的向量版：真實尺寸取代估算，
  /// 重疊偵測從此不會有 false negative。
  /// 回傳 {'nodeId': {'width': w, 'height': h, 'measured': bool}}
  Future<Map<String, dynamic>> getRenderLayerData();

  /// 切換到畫布 tab
  void navigateToCanvas();

  /// 在對話框發送訊息
  void sendChat(String message, {String? role});

  /// 列出所有畫布
  List<Map<String, dynamic>> listCanvases();

  /// 載入指定畫布
  void loadCanvas(String canvasId);

  /// [教練 Agent 2026-08-16 使用者要求 3] 更新節點參數（merge 模式）
  Future<Map<String, dynamic>> updateNodeParams(
      String nodeId, Map<String, dynamic> params);

  /// [教練 Agent 2026-08-16 使用者要求 3] 取得節點參數
  Future<Map<String, dynamic>> getNodeParams(String nodeId);
}

// ═══════════════════════════════════════════════════
// 工具定義 — 每個 MCP 端點一個 AgentTool
// ═══════════════════════════════════════════════════

/// canvas_get_state — 取得畫布狀態
class CanvasGetStateTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasGetStateTool(this.executor);

  @override
  String get name => 'canvas_get_state';

  @override
  String get description => '取得當前畫布的所有節點、連線、參數狀態。操作畫布前應先呼叫此工具了解現狀。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final state = await executor.getState();
      final nodes = state['nodes'] as List? ?? [];
      final connections = state['connections'] as List? ?? [];
      return AgentToolResult.success(
        '畫布狀態：${nodes.length} 個節點，${connections.length} 條連線。\n'
        '節點列表：\n${_formatNodes(nodes)}\n'
        '連線列表：\n${_formatConnections(connections)}',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }

  String _formatNodes(List nodes) {
    if (nodes.isEmpty) return '（無節點）';
    return nodes.map((n) {
      final m = n as Map<String, dynamic>;
      return '  - ${m['id']}: ${m['type']} @ (${m['x']}, ${m['y']})'
          '${m['title'] != null ? '「${m['title']}」' : ''}';
    }).join('\n');
  }

  String _formatConnections(List conns) {
    if (conns.isEmpty) return '（無連線）';
    return conns.map((c) {
      final m = c as Map<String, dynamic>;
      return '  - ${m['fromNodeId']}:${m['fromPort']} → ${m['toNodeId']}:${m['toPort']}';
    }).join('\n');
  }
}

/// canvas_screenshot — 截取畫布畫面
class CanvasScreenshotTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasScreenshotTool(this.executor);

  @override
  String get name => 'canvas_screenshot';

  @override
  String get description => '截取當前畫布的畫面。用於視覺理解畫布佈局。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final base64Png = await executor.screenshot();
      // [2026-07-20] 防禦空截圖——不在畫布頁面時 screenshot() 回傳空字串
      // 空截圖如果回傳 success，會導致 AgentLoop 嵌入空 image_url →
      // vision API timeout → 無限循環浪費 token
      if (base64Png.isEmpty) {
        return AgentToolResult.failure(
          '畫布截圖為空——可能目前不在畫布頁面，或畫布上沒有內容。',
        );
      }
      return AgentToolResult(
        success: true,
        content: '畫布截圖已擷取（${base64Png.length} chars base64 PNG）。',
        mediaUrl: 'data:image/png;base64,$base64Png',
        metadata: {'imageSize': base64Png.length},
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_get_annotations — 讀取使用者塗鴉標注
class CanvasGetAnnotationsTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasGetAnnotationsTool(this.executor);

  @override
  String get name => 'canvas_get_annotations';

  @override
  String get description => '取得使用者在畫布上的塗鴉標注（座標、bounds、顏色）。使用者畫了東西時呼叫此工具理解意圖。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final annotations = executor.getAnnotations();
      if (annotations.isEmpty) {
        return AgentToolResult.success('目前沒有使用者標注。');
      }
      final formatted = annotations.map((a) {
        return '  - 類型:${a['type'] ?? 'unknown'} '
            '座標:(${a['x'] ?? '?'}, ${a['y'] ?? '?'}) '
            '顏色:${a['color'] ?? '?'} '
            '${a['text'] != null ? '文字:「${a['text']}」' : ''}';
      }).join('\n');
      return AgentToolResult.success(
        '找到 ${annotations.length} 個標注：\n$formatted',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_add_node — 新增工作流節點
class CanvasAddNodeTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasAddNodeTool(this.executor);

  @override
  String get name => 'canvas_add_node';

  @override
  String get description => '在畫布上新增工作流節點。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'type',
      description: '節點類型：input/llm/tool/imageGen/videoGen/musicGen/tts/condition/merge/output/subWorkflow/schedule。'
          '[v213] input 也有 trigger 輸入接頭——排程(schedule)節點的 output 可接在 input 的 trigger 上，'
          '語意=排程到點時觸發 input 匯入。不傳 x/y 會自動排版（不疊節點）。',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'x',
      description: '世界座標 X（預設 300）',
      required: false,
      defaultValue: '300',
    ),
    const AgentToolParamSpec(
      name: 'y',
      description: '世界座標 Y（預設 200）',
      required: false,
      defaultValue: '200',
    ),
    // [教練 Agent 2026-08-21] 自律——生成型節點必帶 prompt（防盲裝）
    const AgentToolParamSpec(
      name: 'prompt',
      description: '生成型節點（imageGen/videoGen/musicGen/llm/tts）必填：'
          '這個節點要生成什麼。蓋節點與設定內容一次完成，不留空殼。',
      required: false,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final type = args['type'] as String? ?? 'input';
      // [v213 Blue 抓包] 沒傳座標時全疊在 (300,200)——節點壓節點、線穿節點。
      // 改：沒傳座標 → 依畫布現有節點數自動排在空位（S 形排版，
      // 每個節點間隔 x+280 / 換行 y+220），Agent 不傳座標也不會疊。
      final state = await executor.getSnapshot();
      final existing = (state['nodes'] as List?)?.length ?? 0;
      final autoX = 200.0 + (existing % 4) * 280;
      final autoY = 150.0 + (existing ~/ 4) * 220;
      final x = (args['x'] as num?)?.toDouble() ?? autoX;
      final y = (args['y'] as num?)?.toDouble() ?? autoY;
      final prompt = args['prompt'] as String?;

      // [教練 Agent 2026-08-21] 自律——防盲裝閘
      // $33 事件的起點：agent 蓋了一堆預設值空殼節點然後執行。
      // 生成型節點沒帶 prompt = 盲裝，直接拒絕。
      const genTypes = ['imageGen', 'videoGen', 'musicGen', 'llm', 'tts'];
      if (genTypes.contains(type) &&
          (prompt == null || prompt.trim().length < 4)) {
        return AgentToolResult.failure(
          '自律規則：新增 $type 節點必須帶 prompt（這個節點要生成什麼）。'
          '不留預設值空殼——空殼工作流執行只會產出無意義內容浪費額度。'
          '請帶上 prompt 參數重試，例如：{"type": "imageGen", "prompt": "夕陽下的稻田水彩畫"}',
        );
      }

      // [教練 Agent 2026-08-21] 防重疊——舊行為：不帶座標全部落在預設 (300,200) 疊成一座山，
      // 而且從不檢查既有節點位置。修：與既有節點太近時自動找空位（網格螺旋展開）。
      var px = x;
      var py = y;
      var overlapFixed = false;
      try {
        final state = await executor.getState();
        final nodes = (state['nodes'] as List? ?? [])
            .map((n) => n as Map<String, dynamic>)
            .toList();
        const minDist = 220.0; // 節點寬約 200，220 = 不重疊的最小間距
        bool tooClose(double cx, double cy) => nodes.any((n) {
              final nx = (n['x'] as num?)?.toDouble() ?? 0;
              final ny = (n['y'] as num?)?.toDouble() ?? 0;
              final dx = nx - cx;
              final dy = ny - cy;
              return dx * dx + dy * dy < minDist * minDist;
            });
        if (tooClose(px, py)) {
          // 螺旋網格找最近空位
          outer:
          for (var ring = 1; ring <= 6; ring++) {
            for (var dx = -ring; dx <= ring; dx++) {
              for (var dy = -ring; dy <= ring; dy++) {
                if (dx.abs() != ring && dy.abs() != ring) continue; // 只走外圈
                final cx = px + dx * 260;
                final cy = py + dy * 260;
                if (!tooClose(cx, cy)) {
                  px = cx;
                  py = cy;
                  overlapFixed = true;
                  break outer;
                }
              }
            }
          }
        }
      } catch (_) {/* 防重疊失敗不擋新增 */}

      final nodeId = await executor.addNode(type, px, py);
      // 帶了 prompt 立即寫入（蓋節點與設定一次完成）
      if (prompt != null && prompt.trim().isNotEmpty) {
        try {
          await executor.updateNodeParams(nodeId, {'prompt': prompt});
        } catch (_) {/* 更新失敗不擋節點，體檢會抓 */}
      }
      return AgentToolResult.success(
        '已新增 $type 節點（ID: $nodeId）於座標 ($px, $py)'
        '${prompt != null ? '，prompt 已設定' : ''}'
        '${overlapFixed ? '（原座標與既有節點重疊，已自動移到空位）' : ''}。',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// McpCanvasConnectTool — 連接兩個節點
class McpCanvasConnectTool extends AgentTool {
  final McpCanvasExecutor executor;
  McpCanvasConnectTool(this.executor);

  @override
  String get name => 'canvas_connect';

  @override
  String get description => '連接兩個節點的 port（output → input）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'fromNodeId', description: '來源節點 ID', required: true),
    const AgentToolParamSpec(name: 'fromPort', description: '來源節點的 output port 名稱', required: true),
    const AgentToolParamSpec(name: 'toNodeId', description: '目標節點 ID', required: true),
    const AgentToolParamSpec(name: 'toPort', description: '目標節點的 input port 名稱', required: true),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final fromNodeId = args['fromNodeId'] as String?;
      final fromPort = args['fromPort'] as String?;
      final toNodeId = args['toNodeId'] as String?;
      final toPort = args['toPort'] as String?;
      if (fromNodeId == null || fromPort == null || toNodeId == null || toPort == null) {
        return AgentToolResult.failure('缺少必要參數：fromNodeId, fromPort, toNodeId, toPort');
      }
      await executor.connect(fromNodeId, fromPort, toNodeId, toPort);
      // [v216 Blue 抓包] 做完必驗證——回讀拓撲確認連線真的存在，
      // 杜絕「說接好了但畫布沒接」的盲宣稱。
      final state = await executor.getState();
      final conns = (state['connections'] as List?) ?? const [];
      final exists = conns.any((c) {
        final m = c as Map;
        final f = m['from'] as Map?;
        final t = m['to'] as Map?;
        return f?['nodeId']?.toString() == fromNodeId &&
            t?['nodeId']?.toString() == toNodeId;
      });
      if (!exists) {
        return AgentToolResult.failure(
          '連線聲稱成功但拓撲驗證失敗：$fromNodeId → $toNodeId 不存在。'
          '可能 port 名不對（input 的觸發接頭叫 trigger）。請用 canvas_get_state 查可用 port。',
        );
      }
      return AgentToolResult.success(
        '已連接並驗證 $fromNodeId:$fromPort → $toNodeId:$toPort ✓',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// McpCanvasRemoveTool — 移除節點
class McpCanvasRemoveTool extends AgentTool {
  final McpCanvasExecutor executor;
  McpCanvasRemoveTool(this.executor);

  @override
  String get name => 'canvas_remove_node';

  @override
  String get description => '移除畫布上的節點。⚠️ 破壞性操作——使用前應先確認。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'nodeId', description: '要移除的節點 ID', required: true),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final nodeId = args['nodeId'] as String?;
      if (nodeId == null) {
        return AgentToolResult.failure('缺少必要參數：nodeId');
      }
      await executor.removeNode(nodeId);
      return AgentToolResult.success('已移除節點 $nodeId。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_execute — 執行工作流
class CanvasExecuteTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasExecuteTool(this.executor);

  @override
  String get name => 'canvas_execute';

  @override
  String get description => '執行畫布上的工作流（DAG 拓撲排序 + 節點執行）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      // [教練 Agent 2026-08-21] 自律——執行前體檢（$33 根治第三層）
      // 爛工作流不該被執行：未設定/重複/孤兒=盲裝鐵證，先修再跑。
      final inspection = await executor.inspectWorkflow();
      if (inspection['hasSevereWarnings'] == true) {
        final warnings = (inspection['warnings'] as List).join('\n• ');
        return AgentToolResult.failure(
          '工作流體檢未通過，已拒絕執行。這是自律規則：盲目裝配的工作流'
          '只會浪費額度產出垃圾。\n品質警告：\n• $warnings\n'
          '請先用 canvas_update_node 補上每個生成節點的 prompt、'
          '把孤兒節點接上消費者、或移除重複節點，然後再執行。',
        );
      }
      await executor.execute();
      return AgentToolResult.success(
        '${inspection['briefing']}\n執行完畢。'.replaceAll('將產出', '已產出'),
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_navigate — 切換到畫布 tab
class CanvasNavigateTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasNavigateTool(this.executor);

  @override
  String get name => 'canvas_navigate';

  @override
  String get description => '切換到畫布 tab，讓使用者看到畫布。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    executor.navigateToCanvas();
    return AgentToolResult.success('已切換到畫布畫面。');
  }
}

/// canvas_send_chat — 在對話框發送訊息
class CanvasSendChatTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasSendChatTool(this.executor);

  @override
  String get name => 'canvas_send_chat';

  @override
  String get description => '在畫布對話框發送訊息給使用者。用於主動報告、解釋操作、提出建議。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'message', description: '訊息內容', required: true),
    const AgentToolParamSpec(
      name: 'role',
      description: '角色：assistant（預設）或 system',
      required: false,
      defaultValue: 'assistant',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final message = args['message'] as String?;
      if (message == null || message.isEmpty) {
        return AgentToolResult.failure('缺少必要參數：message');
      }
      final role = args['role'] as String? ?? 'assistant';
      executor.sendChat(message, role: role);
      return AgentToolResult.success('訊息已發送。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_list — 列出所有畫布
class CanvasListTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasListTool(this.executor);

  @override
  String get name => 'canvas_list';

  @override
  String get description => '列出所有可用畫布。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final canvases = executor.listCanvases();
      if (canvases.isEmpty) {
        return AgentToolResult.success('目前沒有畫布。');
      }
      final formatted = canvases.map((c) {
        return '  - ${c['id']}:「${c['title']}」';
      }).join('\n');
      return AgentToolResult.success('找到 ${canvases.length} 個畫布：\n$formatted');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_load — 載入指定畫布
class CanvasLoadTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasLoadTool(this.executor);

  @override
  String get name => 'canvas_load';

  @override
  String get description => '載入指定畫布。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'canvasId', description: '畫布 ID', required: true),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final canvasId = args['canvasId'] as String?;
      if (canvasId == null) {
        return AgentToolResult.failure('缺少必要參數：canvasId');
      }
      executor.loadCanvas(canvasId);
      return AgentToolResult.success('已載入畫布 $canvasId。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════
// [教練 Agent 2026-07-22] Phase C — Agent 畫布快捷工具
// 讓 Agent 在畫布裡「想做什麼就能做什麼」
// ═══════════════════════════════════════════════════

/// canvas_get_topology — 取得畫布拓撲分析
///
/// Agent 的「結構化視覺」——不用看圖就知道工作流從哪開始、到哪結束、哪裡斷了。
class CanvasGetTopologyTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasGetTopologyTool(this.executor);

  @override
  String get name => 'canvas_get_topology';

  @override
  String get description => '取得畫布的拓撲分析：入口節點、出口節點、工作流鏈、孤立節點、未連接的輸入端口。用於快速判斷畫布結構是否完整。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final snapshot = CanvasSnapshotService.instance.currentSnapshot;
      final topology = snapshot['topology'] as Map<String, dynamic>? ?? {};

      final parts = <String>[];
      final entryPoints = topology['entryPoints'] as List? ?? [];
      final exitPoints = topology['exitPoints'] as List? ?? [];
      final chains = topology['chains'] as List? ?? [];
      final orphans = topology['orphanNodes'] as List? ?? [];
      final disconnected = topology['disconnectedInputs'] as List? ?? [];

      if (entryPoints.isEmpty && exitPoints.isEmpty) {
        return AgentToolResult.success('畫布為空或沒有連線。');
      }

      parts.add('入口節點：${entryPoints.join(", ")}');
      parts.add('出口節點：${exitPoints.join(", ")}');

      if (chains.isNotEmpty) {
        parts.add('\n工作流鏈：');
        for (final c in chains.take(5)) {
          parts.add('  ${(c as List).join(" → ")}');
        }
      }

      if (orphans.isNotEmpty) {
        parts.add('\n⚠️ 孤立節點（未連接）：${orphans.join(", ")}');
      }

      if (disconnected.isNotEmpty) {
        parts.add('\n⚠️ 輸入端口未連接的節點：');
        for (final d in disconnected) {
          final m = d as Map<String, dynamic>;
          parts.add('  - ${m['label']} (${m['nodeId']})');
        }
      }

      if (orphans.isEmpty && disconnected.isEmpty) {
        parts.add('\n✅ 結構完整，無問題。');
      }

      return AgentToolResult.success(parts.join('\n'));
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_batch_connect — 批量建立連線
///
/// Agent 規劃完整工作流時，一次建立多條連線，不用一條條連。
class CanvasBatchConnectTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasBatchConnectTool(this.executor);

  @override
  String get name => 'canvas_batch_connect';

  @override
  String get description => '批量建立多條連線。用於一次連接整個工作流。參數 connections 是 JSON 陣列，每個元素包含 from_node, from_port, to_node, to_port。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'connections',
      description: '連線陣列 JSON，例如：[{"from_node":"wf-001","from_port":"output","to_node":"wf-002","to_port":"input"}]',
      required: true,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final connectionsArg = args['connections'];
      if (connectionsArg == null) {
        return AgentToolResult.failure('缺少必要參數：connections');
      }

      List<dynamic> connections;
      if (connectionsArg is String) {
        connections = jsonDecode(connectionsArg) as List;
      } else if (connectionsArg is List) {
        connections = connectionsArg;
      } else {
        return AgentToolResult.failure('connections 格式錯誤');
      }

      var success = 0;
      var failed = 0;
      for (final c in connections) {
        final m = c as Map<String, dynamic>;
        try {
          await executor.connect(
            m['from_node'] as String,
            m['from_port'] as String? ?? 'output',
            m['to_node'] as String,
            m['to_port'] as String? ?? 'input',
          );
          success++;
        } catch (e) {
          failed++;
        }
      }

      return AgentToolResult.success(
        '批量連線完成：$success 條成功${failed > 0 ? "，$failed 條失敗" : ""}。',
      );
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_load_template — 一鍵載入範本
///
/// Agent 說「載入 IG 範本」→ 系統一次建立完整工作流。
class CanvasLoadTemplateTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasLoadTemplateTool(this.executor);

  @override
  String get name => 'canvas_load_template';

  @override
  String get description => '一鍵載入預設工作流範本。可用範本：ig_post（IG 發文工作流）、knowledge_organize（知識整理）、memory_review（記憶回顧）、multi_model（多模型協作）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'template_name',
      description: '範本名稱：ig_post | knowledge_organize | memory_review | multi_model',
      required: true,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final templateName = args['template_name'] as String?;
      if (templateName == null || templateName.isEmpty) {
        return AgentToolResult.failure('缺少必要參數：template_name');
      }

      // 透過 CanvasMcpRegistry 觸發範本載入
      final reg = CanvasMcpRegistry.instance;
      reg.loadTemplate(templateName);

      return AgentToolResult.success('已觸發載入範本「$templateName」。範本節點正在建立中。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_highlight_node — 高亮指定節點
///
/// Agent 在對話框說「看這個節點」→ 畫布上該節點閃爍。
class CanvasHighlightNodeTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasHighlightNodeTool(this.executor);

  @override
  String get name => 'canvas_highlight_node';

  @override
  String get description => '在畫布上高亮閃爍指定節點，引導使用者注意。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'node_id', description: '要高亮的節點 ID', required: true),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final nodeId = args['node_id'] as String?;
      if (nodeId == null) {
        return AgentToolResult.failure('缺少必要參數：node_id');
      }

      // 透過 CanvasMcpRegistry 觸發高亮
      final reg = CanvasMcpRegistry.instance;
      reg.highlightNode(nodeId);

      return AgentToolResult.success('已高亮節點 $nodeId。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_pan_to_node — 平移畫布到指定節點
///
/// Agent 說「我們來看這個」→ 畫布自動平移到該節點。
class CanvasPanToNodeTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasPanToNodeTool(this.executor);

  @override
  String get name => 'canvas_pan_to_node';

  @override
  String get description => '平移畫布視角到指定節點，讓使用者看到它。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'node_id', description: '要平移到的節點 ID', required: true),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final nodeId = args['node_id'] as String?;
      if (nodeId == null) {
        return AgentToolResult.failure('缺少必要參數：node_id');
      }

      final reg = CanvasMcpRegistry.instance;
      reg.panToNode(nodeId);

      return AgentToolResult.success('已平移到節點 $nodeId。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════
// [教練 Agent 2026-07-24] 人機共視工具 — CanvasSnapshot
// ═══════════════════════════════════════════════════

/// canvas_get_snapshot — 人機共視核心工具
///
/// 原生 Agent呼叫此工具後，會得到完整的畫布狀態報告：
/// - 每個節點的座標、尺寸、是否可見
/// - 哪些節點互相重疊
/// - Viewport 的 scale 和 offset
/// - 診斷結論（良好 / 有重疊 / 有節點在畫面外）
///
/// 這是讓原生 Agent「看到」使用者看到的畫布的唯一方式。
/// 不靠截圖，靠結構化 state。
class CanvasGetSnapshotTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasGetSnapshotTool(this.executor);

  @override
  String get name => 'canvas_get_snapshot';

  @override
  String get description =>
      '取得畫布完整快照（人機共視）。包含節點座標、尺寸、重疊檢測、可見性、viewport 狀態、診斷結論。'
      '當使用者說「節點重疊」「看不到」「位置不對」時，先呼叫此工具了解畫布現狀。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final snapshot = await executor.getSnapshot();
      final report = snapshot['report'] as String? ?? '';
      final overlapCount = snapshot['overlapCount'] ?? 0;
      final hiddenCount = snapshot['hiddenNodes'] ?? 0;
      final totalNodes = snapshot['totalNodes'] ?? 0;

      // 追蹤
      CanvasTrace.log('canvas_get_snapshot',
          '節點=$totalNodes 重疊=$overlapCount 隱藏=$hiddenCount');

      if (overlapCount > 0) {
        return AgentToolResult.success(
          '⚠️ 偵測到 $overlapCount 對節點重疊！\n\n$report',
          metadata: snapshot,
        );
      } else if (hiddenCount > 0) {
        return AgentToolResult.success(
          '⚠️ 有 $hiddenCount 個節點在畫面外！\n\n$report',
          metadata: snapshot,
        );
      } else {
        return AgentToolResult.success(
          '✅ 畫布狀態良好，所有節點可見且無重疊。\n\n$report',
          metadata: snapshot,
        );
      }
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_auto_layout — 一鍵自動排版（[教練 Agent 2026-08-26 使用者 基礎規則]）
///
/// 發現節點重疊/擠在一起時直接呼叫——依連線方向分層排開，
/// 不需要自己算每個節點座標。
class CanvasAutoLayoutTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasAutoLayoutTool(this.executor);

  @override
  String get name => 'canvas_auto_layout';

  @override
  String get description => '一鍵自動排版：依連線拓撲分層排開所有節點，'
      '消除重疊與擠壓。發現節點疊在一起、連線打結、畫面混亂時直接呼叫，'
      '不需要逐節點 canvas_move_node。執行後回報每個節點的新位置。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final result = await executor.autoLayout();
      final moved = result['moved'] as int? ?? 0;
      return AgentToolResult.success(
        '自動排版完成：調整了 $moved 個節點位置。'
        '請用 canvas_get_snapshot 確認效果。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_move_node — 移動節點到新位置
///
/// 原生 Agent偵測到重疊後，可以用此工具修正節點位置。
class CanvasMoveNodeTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasMoveNodeTool(this.executor);

  @override
  String get name => 'canvas_move_node';

  @override
  String get description =>
      '移動節點到新座標。用於修正重疊或調整位置。'
      '座標是世界座標（非螢幕座標）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(name: 'node_id', description: '要移動的節點 ID', required: true),
    const AgentToolParamSpec(name: 'x', description: '新的 x 座標', required: true),
    const AgentToolParamSpec(name: 'y', description: '新的 y 座標', required: true),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final nodeId = args['node_id'] as String?;
      final x = (args['x'] as num?)?.toDouble();
      final y = (args['y'] as num?)?.toDouble();

      if (nodeId == null || x == null || y == null) {
        return AgentToolResult.failure('缺少必要參數：node_id, x, y');
      }

      await executor.moveNode(nodeId, x, y);

      CanvasTrace.log('canvas_move_node',
          '節點 $nodeId → ($x, $y)');

      return AgentToolResult.success('已移動節點 $nodeId 到 ($x, $y)。');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// canvas_detect_crossings — 連線交叉檢測
///
/// 檢查連線是否互相交叉或穿過其他節點。
class CanvasDetectCrossingsTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasDetectCrossingsTool(this.executor);

  @override
  String get name => 'canvas_detect_crossings';

  @override
  String get description =>
      '檢查連線是否互相交叉或穿過其他節點。'
      '連線是工作流的血管——不能交叉（血栓），不能被擋住（堵塞）。'
      '當使用者說「連線不對」「線交錯」時呼叫此工具。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final snapshot = await executor.getSnapshot();
      final nodes = snapshot['nodes'] as List? ?? [];
      final connections = snapshot['connections'] as List? ?? [];

      // 線段相交檢測
      final crossings = <String>[];
      final nodeBlocks = <String>[];

      // 建立節點 Rect
      final nodeRects = <String, Map<String, double>>{};
      for (final n in nodes) {
        final m = n as Map<String, dynamic>;
        final id = m['id'] as String? ?? '';
        final x = (m['x'] as num?)?.toDouble() ?? 0;
        final y = (m['y'] as num?)?.toDouble() ?? 0;
        final w = (m['width'] as num?)?.toDouble() ?? 322;
        final h = (m['height'] as num?)?.toDouble() ?? 200;
        nodeRects[id] = {'l': x, 't': y, 'r': x + w, 'b': y + h};
      }

      // 建立連線端點（從節點中心到節點中心）
      final segments = <Map<String, dynamic>>[];
      for (final c in connections) {
        final m = c as Map<String, dynamic>;
        final fromId = m['fromNodeId'] as String? ?? '';
        final toId = m['toNodeId'] as String? ?? '';
        final fromRect = nodeRects[fromId];
        final toRect = nodeRects[toId];
        if (fromRect != null && toRect != null) {
          segments.add({
            'fromId': fromId,
            'toId': toId,
            'x1': (fromRect['l']! + fromRect['r']!) / 2,
            'y1': (fromRect['t']! + fromRect['b']!) / 2,
            'x2': (toRect['l']! + toRect['r']!) / 2,
            'y2': (toRect['t']! + toRect['b']!) / 2,
          });
        }
      }

      // 檢查線段兩兩相交
      for (var i = 0; i < segments.length; i++) {
        for (var j = i + 1; j < segments.length; j++) {
          final s1 = segments[i];
          final s2 = segments[j];
          if (_segmentsIntersect(
            s1['x1'] as double, s1['y1'] as double,
            s1['x2'] as double, s1['y2'] as double,
            s2['x1'] as double, s2['y1'] as double,
            s2['x2'] as double, s2['y2'] as double,
          )) {
            // 排除共享端點的線段
            final s1Ids = {s1['fromId'], s1['toId']};
            final s2Ids = {s2['fromId'], s2['toId']};
            if (s1Ids.intersection(s2Ids).isEmpty) {
              crossings.add(
                '連線 ${s1['fromId']}→${s1['toId']} 與 ${s2['fromId']}→${s2['toId']} 交叉');
            }
          }
        }
      }

      // 檢查連線是否穿過其他節點
      for (final seg in segments) {
        final fromId = seg['fromId'] as String;
        final toId = seg['toId'] as String;
        for (final entry in nodeRects.entries) {
          final nodeId = entry.key;
          if (nodeId == fromId || nodeId == toId) continue;
          final r = entry.value;
          if (_segmentIntersectsRect(
            seg['x1'] as double, seg['y1'] as double,
            seg['x2'] as double, seg['y2'] as double,
            r['l']!, r['t']!, r['r']!, r['b']!,
          )) {
            nodeBlocks.add('連線 $fromId→$toId 穿過節點 $nodeId');
          }
        }
      }

      CanvasTrace.log('canvas_detect_crossings',
          '交叉=${crossings.length} 被擋=${nodeBlocks.length}');

      final issues = <String>[...crossings, ...nodeBlocks];
      if (issues.isEmpty) {
        return AgentToolResult.success('✅ 連線路徑良好，無交叉、無阻擋。');
      } else {
        return AgentToolResult.success(
          '⚠️ 偵測到 ${issues.length} 個連線問題：\n'
          '${issues.map((s) => '  - $s').join('\n')}');
      }
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }

  /// 線段相交檢測（CCW 判定法）
  static bool _segmentsIntersect(
    double x1, double y1, double x2, double y2,
    double x3, double y3, double x4, double y4,
  ) {
    final d1 = _ccw(x3, y3, x4, y4, x1, y1);
    final d2 = _ccw(x3, y3, x4, y4, x2, y2);
    final d3 = _ccw(x1, y1, x2, y2, x3, y3);
    final d4 = _ccw(x1, y1, x2, y2, x4, y4);
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  static double _ccw(double ax, double ay, double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
  }

  /// 線段是否穿過矩形
  static bool _segmentIntersectsRect(
    double x1, double y1, double x2, double y2,
    double left, double top, double right, double bottom,
  ) {
    // 檢查線段是否與矩形四邊相交
    if (_segmentsIntersect(x1, y1, x2, y2, left, top, right, top)) return true;
    if (_segmentsIntersect(x1, y1, x2, y2, right, top, right, bottom)) return true;
    if (_segmentsIntersect(x1, y1, x2, y2, right, bottom, left, bottom)) return true;
    if (_segmentsIntersect(x1, y1, x2, y2, left, bottom, left, top)) return true;
    // 檢查線段端點是否在矩形內
    if (x1 >= left && x1 <= right && y1 >= top && y1 <= bottom) return true;
    if (x2 >= left && x2 <= right && y2 >= top && y2 <= bottom) return true;
    return false;
  }
}

// ═══════════════════════════════════════════════════
// [教練 Agent 2026-07-24] Tracing — 追蹤每次診斷和操作
// ═══════════════════════════════════════════════════

/// 畫布操作追蹤記錄
class CanvasTrace {
  static final List<Map<String, dynamic>> _logs = [];
  static const int _maxLogs = 100;

  static void log(String action, String detail) {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'detail': detail,
    };
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  static List<Map<String, dynamic>> getLogs() => List.unmodifiable(_logs);

  static String getReport() {
    if (_logs.isEmpty) return '（無追蹤記錄）';
    return _logs.map((e) =>
      '[${e['timestamp']}] ${e['action']}: ${e['detail']}').join('\n');
  }

  static void clear() => _logs.clear();
}

/// [教練 Agent 2026-08-16 使用者要求 3] canvas_update_node — 更新既有節點參數
///
/// 原生 Agent的畫布操盤核心工具之一：改 label/prompt/model/query 等任何參數，
/// merge 模式（只蓋傳入的鍵，其他保留）。白話指令→原生 Agent理解→改卡片內容。
class CanvasUpdateNodeTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasUpdateNodeTool(this.executor);

  @override
  String get name => 'canvas_update_node';

  @override
  String get description =>
      '更新既有節點的參數（merge 模式：只蓋傳入的鍵）。'
      '常用鍵：label（標題）、content/prompt/query（內容）、model、topK 等。'
      '先 canvas_get_node_params 看現值再改，最穩。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        const AgentToolParamSpec(name: 'node_id', description: '目標節點 ID', required: true),
        const AgentToolParamSpec(
            name: 'params',
            description: '要更新的參數（JSON 物件），如 {"label": "判斷風格", "prompt": "分析這張圖"}',
            required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final nodeId = args['node_id'] as String?;
      final params = args['params'];
      if (nodeId == null || params is! Map<String, dynamic>) {
        return AgentToolResult.failure('缺少必要參數：node_id, params（JSON 物件）');
      }
      final merged = await executor.updateNodeParams(nodeId, params);
      CanvasTrace.log('canvas_update_node', '節點 $nodeId ← ${params.keys.join(",")}');
      return AgentToolResult.success('已更新節點 $nodeId，合併後參數：$merged');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}

/// [教練 Agent 2026-08-16 使用者要求 3] canvas_get_node_params — 讀取節點參數
class CanvasGetNodeParamsTool extends AgentTool {
  final McpCanvasExecutor executor;
  CanvasGetNodeParamsTool(this.executor);

  @override
  String get name => 'canvas_get_node_params';

  @override
  String get description =>
      '讀取指定節點的完整參數（label、prompt、model、連線狀態等）。'
      '修改前先讀，確認鍵名與現值。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        const AgentToolParamSpec(name: 'node_id', description: '目標節點 ID', required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final nodeId = args['node_id'] as String?;
      if (nodeId == null) return AgentToolResult.failure('缺少必要參數：node_id');
      final params = await executor.getNodeParams(nodeId);
      CanvasTrace.log('canvas_get_node_params', '節點 $nodeId → ${params.keys.join(",")}');
      return AgentToolResult.success('節點 $nodeId 參數：$params');
    } catch (e) {
      return AgentToolResult.failure(e.toString());
    }
  }
}
