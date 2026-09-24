// subworkflow_adapter_test.dart
// SemiCanvas subWorkflow adapter 測試

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';
import 'package:bridge_app/services/semicanvas/workflow_node_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock SubWorkflowRunner — 記錄呼叫參數，回傳固定結果
class _MockSubWorkflowRunner implements SubWorkflowRunner {
  final String _result;
  String? capturedWorkflowRef;
  UpstreamData? capturedUpstreamData;

  _MockSubWorkflowRunner(this._result);

  @override
  Future<String> run({
    required String workflowRef,
    required UpstreamData upstreamData,
  }) async {
    capturedWorkflowRef = workflowRef;
    capturedUpstreamData = upstreamData;
    return _result;
  }
}

/// Mock SubWorkflowRunner — 模擬執行時拋出例外
class _ThrowingSubWorkflowRunner implements SubWorkflowRunner {
  final Object error;

  _ThrowingSubWorkflowRunner(this.error);

  @override
  Future<String> run({
    required String workflowRef,
    required UpstreamData upstreamData,
  }) async {
    throw error;
  }
}

void main() {
  /// 取得 NodeExecutor 的輔助函數
  NodeExecutor buildExecutor(SubWorkflowRunner? runner) {
    final adapters = WorkflowNodeAdapters(subWorkflowRunner: runner);
    return adapters.createNodeExecutor();
  }

  group('SubWorkflow adapter', () {
    test('subWorkflowRunner 未注入時回報錯誤', () async {
      final executor = buildExecutor(null);

      final result = await executor(
        'node-1',
        WorkflowNodeType.subWorkflow,
        {'workflowRef': 'my-workflow'},
        const UpstreamData(),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, '子工作流執行器未注入');
      expect(result.output, isNull);
    });

    test('workflowRef 為空時回報錯誤', () async {
      final runner = _MockSubWorkflowRunner('should-not-be-called');
      final executor = buildExecutor(runner);

      final result = await executor(
        'node-2',
        WorkflowNodeType.subWorkflow,
        {'workflowRef': ''},
        const UpstreamData(),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, '未指定子工作流');
      expect(result.output, isNull);
      // runner 不應被呼叫
      expect(runner.capturedWorkflowRef, isNull);
    });

    test('workflowRef 缺少時也回報錯誤', () async {
      final runner = _MockSubWorkflowRunner('should-not-be-called');
      final executor = buildExecutor(runner);

      final result = await executor(
        'node-3',
        WorkflowNodeType.subWorkflow,
        {},
        const UpstreamData(),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, '未指定子工作流');
      expect(runner.capturedWorkflowRef, isNull);
    });

    test('正常執行 — mock 回傳結果', () async {
      final runner = _MockSubWorkflowRunner('子工作流完成結果');
      final executor = buildExecutor(runner);

      final result = await executor(
        'node-4',
        WorkflowNodeType.subWorkflow,
        {'workflowRef': 'summary-workflow.bridge-workflow'},
        const UpstreamData(),
      );

      expect(result.success, isTrue);
      expect(result.output, '子工作流完成結果');
      expect(result.errorMessage, isNull);
      expect(
        runner.capturedWorkflowRef,
        'summary-workflow.bridge-workflow',
      );
    });

    test('上游輸出正確傳遞給 SubWorkflowRunner', () async {
      final runner = _MockSubWorkflowRunner('output-from-sub');
      final executor = buildExecutor(runner);

      final upstream = UpstreamData(
        texts: {'node-a': 'Hello', 'node-b': 'World'},
      );

      final result = await executor(
        'node-5',
        WorkflowNodeType.subWorkflow,
        {'workflowRef': 'child-workflow'},
        upstream,
      );

      expect(result.success, isTrue);
      expect(result.output, 'output-from-sub');
      // 驗證上游輸出被正確傳遞
      expect(runner.capturedUpstreamData, isNotNull);
      expect(runner.capturedUpstreamData!.texts['node-a'], 'Hello');
      expect(runner.capturedUpstreamData!.texts['node-b'], 'World');
      expect(runner.capturedWorkflowRef, 'child-workflow');
    });

    test('runner 拋出例外時回報錯誤', () async {
      final runner = _ThrowingSubWorkflowRunner('載入失敗');
      final executor = buildExecutor(runner);

      final result = await executor(
        'node-6',
        WorkflowNodeType.subWorkflow,
        {'workflowRef': 'broken-workflow'},
        const UpstreamData(),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('子工作流執行失敗'));
      expect(result.errorMessage, contains('載入失敗'));
    });
  });
}
