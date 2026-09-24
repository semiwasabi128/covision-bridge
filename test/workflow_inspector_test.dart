// workflow_inspector_test.dart
// [小葵 2026-08-21] 自律第三層——工作流體檢實測
// 模擬 $33 事件的爛工作流：空殼生成節點×重複×孤兒 → 必須全部被抓到
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/workflow_inspector.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';

OpenCanvasNode _node(String id, WorkflowNodeType type, Map<String, dynamic> params) {
  return OpenCanvasNode(
    id: id,
    position: const Offset(0, 0),
    entity: Entity(
      id: id,
      type: EntityType.flowstep,
      title: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      source: EntitySource.human,
      tags: const [],
      relations: const [],
      canvasProps: CanvasProps(
        x: 0, y: 0,
        nodeType: type,
        params: params,
        origin: CanvasNodeOrigin.createdOnCanvas,
      ),
      underlying: null,
    ),
  );
}

void main() {
  test('33 美金事件重演：空殼 imageGen ×3 → 未設定警告必抓', () {
    final nodes = {
      'n1': _node('n1', WorkflowNodeType.imageGen, {}),
      'n2': _node('n2', WorkflowNodeType.imageGen, {'prompt': ''}),
      'n3': _node('n3', WorkflowNodeType.imageGen, {'prompt': '要'}),
    };
    final r = WorkflowInspector.inspect(nodes: nodes, edges: ['n1>n9']);
    expect(r.imageNodes, 3);
    expect(r.warnings.any((w) => w.contains('未設定')), isTrue);
    expect(r.hasSevereWarnings, isTrue);
  });

  test('同 prompt ×3 → 重複警告', () {
    final nodes = {
      'n1': _node('n1', WorkflowNodeType.imageGen, {'prompt': '一張漂亮的稻田照片'}),
      'n2': _node('n2', WorkflowNodeType.imageGen, {'prompt': '一張漂亮的稻田照片'}),
      'n3': _node('n3', WorkflowNodeType.imageGen, {'prompt': '一張漂亮的稻田照片'}),
    };
    final r = WorkflowInspector.inspect(nodes: nodes, edges: []);
    expect(r.warnings.any((w) => w.contains('重複')), isTrue);
  });

  test('付費節點沒接下游 → 孤兒警告', () {
    final nodes = {
      'n1': _node('n1', WorkflowNodeType.imageGen, {'prompt': '夕陽下的稻田水彩畫'}),
    };
    final r = WorkflowInspector.inspect(nodes: nodes, edges: []);
    expect(r.warnings.any((w) => w.contains('孤兒')), isTrue);
  });

  test('優質工作流：零警告、預報正確', () {
    final nodes = {
      'in': _node('in', WorkflowNodeType.input, {'content': '主題'}),
      'gen': _node('gen', WorkflowNodeType.imageGen, {'prompt': '夕陽下的稻田水彩畫'}),
      'out': _node('out', WorkflowNodeType.output, {}),
    };
    final r = WorkflowInspector.inspect(
        nodes: nodes, edges: ['in>gen', 'gen>out']);
    expect(r.warnings, isEmpty);
    expect(r.hasSevereWarnings, isFalse);
    expect(r.briefing, contains('圖片 1 張'));
  });

  test('產出預報含品質警告明細', () {
    final nodes = {
      'n1': _node('n1', WorkflowNodeType.videoGen, {}),
    };
    final r = WorkflowInspector.inspect(nodes: nodes, edges: []);
    expect(r.briefing, contains('影片 1 支'));
    expect(r.briefing, contains('品質警告'));
  });
}
