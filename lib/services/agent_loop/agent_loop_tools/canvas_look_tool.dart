/// canvas_look 工具——原生 Agent的「周邊視覺」：直接感知畫布場景
///
/// [教練 Agent 2026-08-22 使用者洞察] 原生 Agent在 App 裡面，他的視覺感受應該比
/// 外部截圖更豐富、更直接——不該「對著自己拍一張照片」繞一圈。
///
/// 三層感官設計：
/// 1. 事件流（CanvasEventBus）＝觸覺——節點在動（已有）
/// 2. canvas_look（本工具）＝周邊視覺——直接讀畫布狀態組成
///    空間場景描述，零截圖、零延遲、信息量比截圖大：
///    精確座標、大小、狀態、遮擋關係、viewport 位置
/// 3. canvas_capture（截圖）＝注視——只在需要看「生成圖內容」
///    （像素級資訊）時用
///
/// 場景語言範例（節錄）：
///   你面前有 6 個節點。viewport 縮放 85%，畫布中心在 (1200, 340)。
///   可見範圍內 6 個節點全在視野：
///   - 「夕陽稻田」(輸入, 320x146) 在左上區 (x=180,y=120)，狀態 idle
///   - 「圖片生成」(322x220) 在中間 (x=620,y=140)，與「女兒的畫」重疊！
///   連線 5 條：「夕陽稻田」→「圖片生成」(prompt)...

import 'dart:math' as math;

import '../agent_tool.dart';
import '../mcp_canvas_tools.dart';

class CanvasLookTool extends AgentTool {
  final McpCanvasExecutor _executor;

  CanvasLookTool({required McpCanvasExecutor executor})
      : _executor = executor;

  @override
  String get name => 'canvas_look';

  @override
  String get description =>
      '直接感知畫布場景（不用截圖）——像張眼環顧四周：哪些節點在哪、'
      '多大、什麼狀態、有無重疊、連線怎麼流、viewport 看到哪個區域。'
      '這是你的周邊視覺，信息量比截圖大且零延遲。'
      '要看生成圖片的「內容」時才用 canvas_capture（注視）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final state = await _executor.getState();
      if (state['canvasConnected'] != true) {
        return AgentToolResult.failure('畫布未連線');
      }
      // [教練 Agent 2026-08-22 渲染層視網膜] 真實尺寸直讀——
      // ActualSizeCache（NodeWidget 佈局後回測）覆蓋邏輯層估算值。
      // 視網膜序列：渲染層測量 > 邏輯層估算，零 false negative。
      try {
        final renderData = await _executor.getRenderLayerData();
        if (renderData.isNotEmpty) {
          state['renderLayer'] = renderData;
          final nodes = (state['nodes'] as List).cast<Map<String, dynamic>>();
          for (final n in nodes) {
            final rd = renderData[n['id']];
            if (rd is Map && rd['measured'] == true) {
              // 新建 map（不原地改寫——原 map 可能是 int 型別的
              // Map<String, int>，塞 double 會 cast 爆）
              n['size'] = {
                'width': rd['width'],
                'height': rd['height'],
              };
              n['renderMeasured'] = true;
            }
          }
        }
      } catch (_) {
        // 渲染層數據不可用時退回邏輯層估算——誠實降級，不擋場景
      }
      final scene = _buildSceneText(state);
      return AgentToolResult.success(scene);
    } catch (e) {
      return AgentToolResult.failure('canvas_look 失敗: $e');
    }
  }

  /// 把結構化 state 組成空間場景語言
  String _buildSceneText(Map<String, dynamic> state) {
    final nodes = (state['nodes'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final connections = (state['connections'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final viewport = (state['viewport'] as Map?)?.cast<String, dynamic>() ?? {};
    final pixelSize = (state['canvasPixelSize'] as Map?)
            ?.cast<String, dynamic>() ??
        {'width': 1060.0, 'height': 772.0};

    final buf = StringBuffer();

    // ── 全景 ──
    buf.writeln('畫布場景：共 ${nodes.length} 個節點、'
        '${connections.length} 條連線。');

    final scale = (viewport['scale'] as num?)?.toDouble() ?? 1.0;
    final offX = (viewport['offsetX'] as num?)?.toDouble() ?? 0.0;
    final offY = (viewport['offsetY'] as num?)?.toDouble() ?? 0.0;
    // viewport 可見的世界座標範圍（offset 是世界中心或原點偏移，
    // 依 canvas_controller 的語意；用畫布中心近似）
    final vw = (pixelSize['width'] as num?)?.toDouble() ?? 1060.0;
    final vh = (pixelSize['height'] as num?)?.toDouble() ?? 772.0;
    buf.writeln('viewport 縮放 ${(scale * 100).round()}%'
        '（可見世界範圍約 ${vw ~/ scale}x${vh ~/ scale} 世界單位）。');

    if (nodes.isEmpty) {
      buf.writeln('畫布是空的。');
      return buf.toString();
    }

    // ── 節點分區描述（相對位置語言）──
    // 找全部節點的包圍盒，把世界分成九宮格語意區
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in nodes) {
      final pos = (n['position'] as Map).cast<String, dynamic>();
      final x = (pos['x'] as num).toDouble();
      final y = (pos['y'] as num).toDouble();
      final size = (n['size'] as Map).cast<String, dynamic>();
      final w = (size['width'] as num?)?.toDouble() ?? 200;
      final h = (size['height'] as num?)?.toDouble() ?? 146;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x + w);
      maxY = math.max(maxY, y + h);
    }
    final boundsW = maxX - minX;
    final boundsH = maxY - minY;

    buf.writeln('節點：');
    for (final n in nodes) {
      final pos = (n['position'] as Map).cast<String, dynamic>();
      final x = (pos['x'] as num).toDouble();
      final y = (pos['y'] as num).toDouble();
      final size = (n['size'] as Map).cast<String, dynamic>();
      final w = (size['width'] as num?)?.toDouble() ?? 200;
      final h = (size['height'] as num?)?.toDouble() ?? 146;
      final title = n['title']?.toString() ?? n['id'].toString();
      final vs = n['visualState']?.toString() ?? 'idle';
      // 渲染層實測 vs 邏輯層估算——標註讓 agent 知道數據精度
      final measured = n['renderMeasured'] == true;

      // 相對區位語言
      final relX = boundsW < 1 ? 0.5 : (x + w / 2 - minX) / boundsW;
      final relY = boundsH < 1 ? 0.5 : (y + h / 2 - minY) / boundsH;
      final zoneX = relX < 0.4 ? '左' : (relX > 0.6 ? '右' : '中');
      final zoneY = relY < 0.4 ? '上' : (relY > 0.6 ? '下' : '中');
      final zone = '$zoneY$zoneX';

      buf.writeln('- 「$title」(${w.round()}x${h.round()}'
          '${measured ? '' : '≈'})'
          ' 在${zone}區 (x=${x.round()},y=${y.round()})，狀態 $vs');
    }

    // ── 重疊檢測（場景語言）──
    final overlaps = <String>[];
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        if (_rectsOverlap(nodes[i], nodes[j])) {
          overlaps.add(
              '「${_titleOf(nodes[i])}」與「${_titleOf(nodes[j])}」重疊！');
        }
      }
    }
    if (overlaps.isNotEmpty) {
      buf.writeln('⚠ 視覺警示：');
      for (final o in overlaps) {
        buf.writeln('- $o');
      }
    }

    // ── 連線流向 ──
    final titleById = <String, String>{};
    for (final n in nodes) {
      titleById[n['id'].toString()] = n['title']?.toString() ?? n['id'].toString();
    }
    if (connections.isNotEmpty) {
      buf.writeln('連線：');
      for (final c in connections) {
        final from = (c['from'] as Map).cast<String, dynamic>();
        final to = (c['to'] as Map).cast<String, dynamic>();
        buf.writeln('- 「${titleById[from['nodeId']] ?? from['nodeId']}」'
            '→「${titleById[to['nodeId']] ?? to['nodeId']}」(${to['port']})');
      }
    }

    return buf.toString();
  }

  bool _rectsOverlap(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ap = (a['position'] as Map).cast<String, dynamic>();
    final bp = (b['position'] as Map).cast<String, dynamic>();
    final as = (a['size'] as Map?)?.cast<String, dynamic>() ?? {};
    final bs = (b['size'] as Map?)?.cast<String, dynamic>() ?? {};
    final ax = (ap['x'] as num).toDouble();
    final ay = (ap['y'] as num).toDouble();
    final aw = (as['width'] as num?)?.toDouble() ?? 200;
    final ah = (as['height'] as num?)?.toDouble() ?? 146;
    final bx = (bp['x'] as num).toDouble();
    final by = (bp['y'] as num).toDouble();
    final bw = (bs['width'] as num?)?.toDouble() ?? 200;
    final bh = (bs['height'] as num?)?.toDouble() ?? 146;
    return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
  }

  String _titleOf(Map<String, dynamic> n) =>
      n['title']?.toString() ?? n['id'].toString();
}
