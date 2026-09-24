// [小葵 2026-08-16 教練模式] canvas_place 工作流節點直通測試
// 繞過 LLM，直接呼叫 executor。
// [2026-09-22 重大演進對齊] executor 已改走「正宮路徑」：
// CanvasMcpRegistry → controller.addWorkflowNode（UI 即時顯示＋canvasId）。
// 沒有前景畫布時會 throw「畫布未就緒」——測試改用 ambient 工作畫布
// （pushAmbientCanvas，即派工任務的 headless 畫布模式）注入 controller。
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/entity_graph_canvas_place_executor.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canvas_place 建工作流節點（正宮路徑＋ambient 工作畫布）', () async {
    // 模擬派工任務的 headless 工作畫布（不污染前景）
    final taskCanvas = CanvasController();
    CanvasMcpRegistry.instance.pushAmbientCanvas(taskCanvas);
    addTearDown(() {
      CanvasMcpRegistry.instance.popAmbientCanvas(taskCanvas);
      taskCanvas.dispose();
    });

    final executor = EntityGraphCanvasPlaceExecutor();

    // 建 input 節點
    final id1 = await executor.place(
      nodeType: 'input',
      content: '主題輸入',
      params: {
        'label': '主題輸入',
        'content': '楠西農場的排水改善',
      },
      x: 300,
      y: 300,
    );
    expect(id1, isNotEmpty, reason: 'input 節點要建得成');
    expect(id1.startsWith('wf-'), isTrue, reason: '正宮路徑的節點 ID 有 wf- 前綴');
    expect(taskCanvas.state.nodes.containsKey(id1), isTrue, reason: '節點要進入畫布 controller state（UI 可見）');

    // 建 knowledge 節點
    final id2 = await executor.place(
      nodeType: 'knowledge',
      content: '知識檢索',
      params: {
        'label': '知識檢索',
        'query': '{input} 楠西農場排水',
        'mode': 'semantic',
        'topK': 5,
      },
      x: 680,
      y: 300,
    );
    expect(id2, isNotEmpty, reason: 'knowledge 節點要建得成');

    // 建 llm 節點
    final id3 = await executor.place(
      nodeType: 'llm',
      content: '重點摘要',
      params: {
        'label': '重點摘要',
        'prompt': '根據知識檢索結果，整理楠西農場排水改善的重點摘要',
        'model': 'glm-5-turbo',
      },
      x: 1060,
      y: 300,
    );
    expect(id3, isNotEmpty, reason: 'llm 節點要建得成');

    // 建 output 節點
    final id4 = await executor.place(
      nodeType: 'output',
      content: '摘要結果',
      params: {'label': '摘要結果'},
      x: 1440,
      y: 300,
    );
    expect(id4, isNotEmpty, reason: 'output 節點要建得成');

    // 四節點全部進入工作畫布 state
    expect(
      taskCanvas.state.nodes.keys,
      containsAll([id1, id2, id3, id4]),
      reason: '四節點都應存在於 ambient 工作畫布',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('沒有畫布時明確報錯（畫布未就緒）', () async {
    // 確保 registry 沒有 controller（前景與 ambient 都清空）
    final registry = CanvasMcpRegistry.instance;
    final savedForeground = registry.foregroundController;
    registry.controller = null;
    addTearDown(() => registry.controller = savedForeground);

    final executor = EntityGraphCanvasPlaceExecutor();
    await expectLater(
      executor.place(nodeType: 'input', content: 'x', x: 0, y: 0),
      throwsStateError,
    );
  });
}
