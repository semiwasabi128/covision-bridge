// canvas_place_tool_test.dart
// Phase 1.5 A3 (S24d) — canvas_place 工具測試
//
// 測試：
// 1. 工具介面定義正確（name, description, paramSpecs）
// 2. 缺 entityId + content → 失敗
// 3. 用 stub executor → 失敗訊息含未實作
// 4. 用 mock executor → 成功放回畫布
// 5. 座標解析正確（int/double/string）
// 6. asSuggestion 參數解析

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/canvas_place_tool.dart';

/// Mock executor——模擬成功放回畫布
class _MockCanvasPlaceExecutor implements CanvasPlaceExecutor {
  String? lastEntityId;
  String? lastContent;
  String? lastEntityType;
  String? lastNodeType;
  Map<String, dynamic>? lastParams;
  double? lastX;
  double? lastY;
  bool? lastAsSuggestion;

  @override
  Future<String> place({
    String? entityId,
    String? content,
    String? entityType,
    double? x,
    double? y,
    bool asSuggestion = false,
    String? nodeType,
    Map<String, dynamic>? params,
  }) async {
    lastEntityId = entityId;
    lastContent = content;
    lastEntityType = entityType;
    lastNodeType = nodeType;
    lastParams = params;
    lastX = x;
    lastY = y;
    lastAsSuggestion = asSuggestion;
    return 'canvas_node_${DateTime.now().millisecondsSinceEpoch}';
  }
}

void main() {
  group('CanvasPlaceTool — 介面定義', () {
    test('name 是 canvas_place', () {
      final tool = CanvasPlaceTool(StubCanvasPlaceExecutor());
      expect(tool.name, 'canvas_place');
    });

    test('description 非空且包含關鍵詞', () {
      final tool = CanvasPlaceTool(StubCanvasPlaceExecutor());
      expect(tool.description, isNotEmpty);
      expect(tool.description, contains('畫布'));
    });

    test('paramSpecs 包含必要參數', () {
      final tool = CanvasPlaceTool(StubCanvasPlaceExecutor());
      final names = tool.paramSpecs.map((p) => p.name).toList();
      expect(names, contains('entityId'));
      expect(names, contains('content'));
      expect(names, contains('entityType'));
      expect(names, contains('x'));
      expect(names, contains('y'));
      expect(names, contains('asSuggestion'));
    });

    test('entityType 有預設值 annotation', () {
      final tool = CanvasPlaceTool(StubCanvasPlaceExecutor());
      final spec = tool.paramSpecs.firstWhere((p) => p.name == 'entityType');
      expect(spec.defaultValue, 'annotation');
    });

    test('toPromptDescription 產生有效描述', () {
      final tool = CanvasPlaceTool(StubCanvasPlaceExecutor());
      final desc = tool.toPromptDescription();
      expect(desc, contains('canvas_place'));
      expect(desc, contains('entityId'));
      expect(desc, contains('content'));
    });
  });

  group('CanvasPlaceTool — 參數驗證', () {
    test('缺 entityId 和 content → 失敗', () async {
      final tool = CanvasPlaceTool(_MockCanvasPlaceExecutor());
      final result = await tool.execute({});

      expect(result.success, isFalse);
      expect(result.content, contains('entityId'));
      expect(result.content, contains('content'));
    });

    test('entityId 和 content 都空字串 → 失敗', () async {
      final tool = CanvasPlaceTool(_MockCanvasPlaceExecutor());
      final result = await tool.execute({
        'entityId': '',
        'content': '',
      });

      expect(result.success, isFalse);
    });
  });

  group('CanvasPlaceTool — stub executor 行為', () {
    test('stub executor → 失敗訊息含未實作', () async {
      final tool = CanvasPlaceTool(StubCanvasPlaceExecutor());
      final result = await tool.execute({
        'content': '測試內容',
      });

      expect(result.success, isFalse);
      expect(result.content, contains('未實作'));
    });
  });

  group('CanvasPlaceTool — mock executor 行為', () {
    test('用 content 建新節點 → 成功', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      final result = await tool.execute({
        'content': 'Agent 觀察到使用者正在看 Figma 設計稿',
        'entityType': 'annotation',
      });

      expect(result.success, isTrue);
      expect(result.content, contains('放回畫布'));
      expect(result.metadata!['nodeId'], isNotNull);
      expect(mock.lastContent, 'Agent 觀察到使用者正在看 Figma 設計稿');
      expect(mock.lastEntityType, 'annotation');
    });

    test('用 entityId 放已有 Entity → 成功', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      final result = await tool.execute({
        'entityId': 'mem_001',
      });

      expect(result.success, isTrue);
      expect(mock.lastEntityId, 'mem_001');
    });

    test('指定座標 → 傳給 executor', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '測試',
        'x': 100.0,
        'y': 200.0,
      });

      expect(mock.lastX, 100.0);
      expect(mock.lastY, 200.0);
    });

    test('座標用 int → 正確解析為 double', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '測試',
        'x': 50,
        'y': 75,
      });

      expect(mock.lastX, 50.0);
      expect(mock.lastY, 75.0);
    });

    test('座標用字串 → 正確解析', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '測試',
        'x': '120.5',
        'y': '80',
      });

      expect(mock.lastX, 120.5);
      expect(mock.lastY, 80.0);
    });

    test('不傳座標 → executor 收到 null', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '測試',
      });

      expect(mock.lastX, isNull);
      expect(mock.lastY, isNull);
    });

    test('asSuggestion=true → 傳給 executor', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '建議關聯',
        'asSuggestion': 'true',
      });

      expect(mock.lastAsSuggestion, isTrue);
    });

    test('asSuggestion 不傳 → 預設 false', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '一般節點',
      });

      expect(mock.lastAsSuggestion, isFalse);
    });

    test('entityType 不傳 → 預設 annotation', () async {
      final mock = _MockCanvasPlaceExecutor();
      final tool = CanvasPlaceTool(mock);
      await tool.execute({
        'content': '測試',
      });

      expect(mock.lastEntityType, 'annotation');
    });

    test('asSuggestion=true → 結果含「建議節點」', () async {
      final tool = CanvasPlaceTool(_MockCanvasPlaceExecutor());
      final result = await tool.execute({
        'content': '建議',
        'asSuggestion': 'true',
      });

      expect(result.success, isTrue);
      expect(result.content, contains('建議節點'));
    });

    test('asSuggestion=false → 結果含「正式節點」', () async {
      final tool = CanvasPlaceTool(_MockCanvasPlaceExecutor());
      final result = await tool.execute({
        'content': '正式',
        'asSuggestion': 'false',
      });

      expect(result.success, isTrue);
      expect(result.content, contains('正式節點'));
    });
  });

  group('StubCanvasPlaceExecutor', () {
    test('place 擲 UnsupportedError', () async {
      final executor = StubCanvasPlaceExecutor();
      expect(
        () => executor.place(content: 'test'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
