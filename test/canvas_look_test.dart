// canvas_look 場景語言生成測試
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/canvas_look_tool.dart';
import 'package:bridge_app/services/agent_loop/mcp_canvas_tools.dart';

void main() {
  test('場景語言——節點區位/重疊/連線描述', () async {
    final tool = CanvasLookTool(executor: _FakeExec());
    final result = await tool.execute({});
    expect(result.success, isTrue);
    // 場景語言必含：節點數、重疊警示、連線流向
    expect(result.content, contains('2 個節點'));
    expect(result.content, contains('重疊'));
    expect(result.content, contains('「夕陽稻田」→「圖片生成」'));
  });

  test('渲染層視網膜——實測尺寸覆蓋估算值', () async {
    final tool = CanvasLookTool(executor: _FakeExec());
    final result = await tool.execute({});
    // FakeExec 的 renderLayer 給 n1=205x150（≠ state 的 200x146）
    // 場景語言應輸出實測值 205x150（渲染層覆蓋邏輯層）
    expect(result.content, contains('205x150'));
    // 不帶 ≈（實測值不標近似）
    expect(result.content, isNot(contains('205x150≈')));
  });
}

class _FakeExec implements McpCanvasExecutor {
  noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getState) {
      return Future.value({
        'canvasConnected': true,
        'nodes': [
          {
            'id': 'n1', 'title': '夕陽稻田', 'type': 'canvasNode',
            'nodeType': 'input',
            'position': {'x': 100, 'y': 100},
            'size': {'width': 200, 'height': 146},
            'visualState': 'idle',
          },
          {
            'id': 'n2', 'title': '圖片生成', 'type': 'canvasNode',
            'nodeType': 'imageGen',
            'position': {'x': 150, 'y': 150},
            'size': {'width': 322, 'height': 220},
            'visualState': 'done',
          },
        ],
        'connections': [
          {
            'id': 'c1',
            'from': {'nodeId': 'n1', 'port': 'output'},
            'to': {'nodeId': 'n2', 'port': 'prompt'},
          },
        ],
        'viewport': {'offsetX': 0, 'offsetY': 0, 'scale': 0.85},
        'canvasPixelSize': {'width': 1060, 'height': 772},
      });
    }
    if (invocation.memberName == #screenshot) {
      return Future.value('');
    }
    if (invocation.memberName == #getRenderLayerData) {
      return Future<Map<String, dynamic>>.value({
        'n1': {'width': 205.0, 'height': 150.0, 'measured': true},
        'n2': {'width': 330.0, 'height': 224.0, 'measured': true},
      });
    }
    return null;
  }
}
