// canvas_sub_workflow_runner.dart
// 畫布子工作流執行器 — 載入範本並執行，回傳最終輸出
// [教練 Agent 2026-07-22] Phase G — SubWorkflow 節點實作
//
// 設計：
// - workflowRef 可以是範本 ID（如 'ig_post'）或範本名稱
// - 從 VaultTemplateService 載入範本定義
// - 按範本的 connections 建立簡單 DAG，逐層執行
// - 上游輸出注入 input 節點的 content
// - 回傳 output 節點的結果
// - 不更新畫布視覺狀態（子工作流是背景執行）

import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:bridge_app/services/vault/vault_templates.dart';
import 'package:bridge_app/services/api_service.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/semicanvas/canvas_tts_service.dart';

/// 子工作流執行結果
class _SubWorkflowNodeResult {
  final int nodeIndex;
  final bool success;
  final String output;
  final String? errorMessage;

  const _SubWorkflowNodeResult({
    required this.nodeIndex,
    required this.success,
    this.output = '',
    this.errorMessage,
  });
}

/// 畫布子工作流執行器
class CanvasSubWorkflowRunner {
  CanvasSubWorkflowRunner._();
  static final CanvasSubWorkflowRunner instance = CanvasSubWorkflowRunner._();

  /// 執行子工作流
  ///
  /// [workflowRef] — 範本 ID（如 'ig_post', 'knowledge_digest'）
  /// [upstreamOutputs] — 上游節點的輸出，注入到 input 節點
  Future<String> run({
    required String workflowRef,
    required Map<String, String> upstreamOutputs,
  }) async {
    // 1. 查找範本
    // [教練 Agent 2026-08-15 使用者 提案] workflowRef 支援三種：
    //   a. 檔案路徑（/.../*.bridge-workflow 或 .json）→ 讀檔解析
    //   b. 內建範本 ID（ig_post 等）
    //   c. 範本名稱（模糊 fallback）
    WorkflowTemplate? template;
    if (workflowRef.contains('/') && workflowRef.contains('.')) {
      final file = File(workflowRef);
      if (await file.exists()) {
        final json = await file.readAsString();
        template = VaultTemplateService.instance.fromJson(json);
        if (template == null) {
          throw Exception('工作流檔案格式錯誤: $workflowRef');
        }
      }
    }
    template ??= VaultTemplateService.instance.getBuiltinTemplates()
        .where((t) => t.id == workflowRef || t.name == workflowRef)
        .firstOrNull;

    if (template == null) {
      throw Exception('找不到工作流: $workflowRef');
    }

    debugPrint('[CanvasSubWorkflowRunner] 載入範本: ${template.name} '
        '(${template.nodes.length} 節點)');

    // 2. 準備上游文字
    final upstreamText = upstreamOutputs.values.join('\n');

    // 3. 建立節點索引映射
    final nodeCount = template.nodes.length;
    final outputs = <int, String>{};

    // 4. 建立 DAG 執行順序（簡單拓撲排序）
    final executionOrder = _topologicalSort(template);

    // 5. 逐節點執行
    for (final nodeIndex in executionOrder) {
      final node = template.nodes[nodeIndex];
      final nodeType = node['type']?.toString() ?? 'input';
      final params = (node['params'] as Map<String, dynamic>?) ?? {};

      // 收集上游輸出
      final nodeUpstream = <String, String>{};
      for (final conn in template.connections) {
        final toIndex = conn['to'] as int?;
        if (toIndex == nodeIndex) {
          final fromIndex = conn['from'] as int?;
          if (fromIndex != null && outputs.containsKey(fromIndex)) {
            nodeUpstream['$fromIndex'] = outputs[fromIndex]!;
          }
        }
      }

      final result = await _executeNode(
        nodeIndex: nodeIndex,
        nodeType: nodeType,
        params: params,
        upstreamOutputs: nodeUpstream,
        injectedInput: upstreamText,
      );

      if (result.success) {
        outputs[nodeIndex] = result.output;
      } else {
        debugPrint('[CanvasSubWorkflowRunner] 節點 $nodeIndex ($nodeType) '
            '執行失敗: ${result.errorMessage}');
        // 繼續執行其他節點，不中斷
      }
    }

    // 6. 找 output 節點，回傳其結果
    for (var i = template.nodes.length - 1; i >= 0; i--) {
      final node = template.nodes[i];
      if (node['type'] == 'output' && outputs.containsKey(i)) {
        return outputs[i]!;
      }
    }

    // 如果沒有 output 節點，回傳最後一個成功節點的結果
    if (outputs.isNotEmpty) {
      return outputs.values.last;
    }

    return '（子工作流無輸出）';
  }

  /// 簡單拓撲排序 — 根據 connections 決定執行順序
  List<int> _topologicalSort(WorkflowTemplate template) {
    final nodeCount = template.nodes.length;
    final inDegree = List<int>.filled(nodeCount, 0);
    final adj = <int, List<int>>{};

    for (var i = 0; i < nodeCount; i++) {
      adj[i] = [];
    }

    for (final conn in template.connections) {
      final from = conn['from'] as int?;
      final to = conn['to'] as int?;
      if (from != null && to != null && from < nodeCount && to < nodeCount) {
        adj[from]!.add(to);
        inDegree[to]++;
      }
    }

    // BFS 拓撲排序
    final queue = <int>[];
    for (var i = 0; i < nodeCount; i++) {
      if (inDegree[i] == 0) queue.add(i);
    }

    final result = <int>[];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      result.add(node);
      for (final neighbor in adj[node]!) {
        inDegree[neighbor]--;
        if (inDegree[neighbor] == 0) queue.add(neighbor);
      }
    }

    // 如果有循環， fallback 到順序執行
    if (result.length != nodeCount) {
      return List.generate(nodeCount, (i) => i);
    }

    return result;
  }

  /// 執行單一節點 — 與 V2 workspace 的 _executeNode 邏輯對齊
  Future<_SubWorkflowNodeResult> _executeNode({
    required int nodeIndex,
    required String nodeType,
    required Map<String, dynamic> params,
    required Map<String, String> upstreamOutputs,
    String? injectedInput,
  }) async {
    final upstreamText = upstreamOutputs.values.join('\n');

    try {
      switch (nodeType) {
        case 'input':
          // 如果有注入的上游輸入，用它；否則用 params 的 content
          final content = injectedInput?.isNotEmpty == true
              ? injectedInput!
              : params['content']?.toString() ??
                  params['defaultValue']?.toString() ??
                  '';
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex, success: true, output: content);

        case 'output':
          final combined = upstreamOutputs.values.join('\n');
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex, success: true, output: combined);

        case 'merge':
          final mode = params['mode']?.toString() ?? 'concat';
          String merged;
          switch (mode) {
            case 'first':
              merged = upstreamOutputs.values.firstOrNull ?? '';
            case 'last':
              merged = upstreamOutputs.values.lastOrNull ?? '';
            default:
              merged = upstreamOutputs.values.join('\n');
          }
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex, success: true, output: merged);

        case 'llm':
          final model = params['model']?.toString() ?? 'glm-4.7'; // [教練 Agent 2026-08-01] 更新預設 model
          final promptTemplate = params['prompt']?.toString() ?? '';

          // [教練 Agent 2026-08-01] 變數替換支援
          final String userPrompt;
          if (promptTemplate.contains('{input}') || promptTemplate.contains('{upstream}')) {
            userPrompt = promptTemplate
                .replaceAll('{input}', upstreamText)
                .replaceAll('{upstream}', upstreamText);
          } else if (promptTemplate.isEmpty) {
            userPrompt = upstreamText;
          } else {
            userPrompt = '$promptTemplate\n\nContext:\n$upstreamText';
          }

          final result = await ApiService.complete(
            systemPrompt: 'You are a helpful AI assistant.',
            userPrompt: userPrompt,
            model: model,
          );

          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex, success: true, output: result);

        case 'tool':
          final toolName = params['toolName']?.toString() ??
              params['tool']?.toString() ?? '';
          final args = params['args']?.toString() ?? '';

          BridgeActionType? actionType;
          switch (toolName.toLowerCase()) {
            case 'browse':
            case 'web_search':
              actionType = BridgeActionType.browse;
            case 'desktop_files':
              actionType = BridgeActionType.desktopFiles;
            default:
              return _SubWorkflowNodeResult(
                nodeIndex: nodeIndex,
                success: false,
                errorMessage: '子工作流不支援工具: $toolName',
              );
          }

          final action = BridgeAction(
            type: actionType,
            prompt: args.isNotEmpty ? args : upstreamText,
          );
          final executor = BridgeActionExecutor();
          final result = await executor.execute(action);

          if (result.status == BridgeActionStatus.completed) {
            final output = result.mediaUrl != null
                ? '${result.message}\n媒體: ${result.mediaUrl}'
                : result.message;
            return _SubWorkflowNodeResult(
              nodeIndex: nodeIndex, success: true, output: output);
          }
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: false,
            errorMessage: result.message);

        case 'imageGen':
          final promptText = params['prompt']?.toString() ?? upstreamText;
          final action = BridgeAction(
            type: BridgeActionType.generateImage,
            prompt: promptText,
          );
          final executor = BridgeActionExecutor();
          final result = await executor.execute(action);

          if (result.status == BridgeActionStatus.completed) {
            final output = result.mediaUrl != null
                ? '${result.message}\n媒體: ${result.mediaUrl}'
                : result.message;
            return _SubWorkflowNodeResult(
              nodeIndex: nodeIndex, success: true, output: output);
          }
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: false,
            errorMessage: result.message);

        case 'videoGen':
          final promptText = params['prompt']?.toString() ?? upstreamText;
          final action = BridgeAction(
            type: BridgeActionType.generateVideo,
            prompt: promptText,
          );
          final executor = BridgeActionExecutor();
          final result = await executor.execute(action);

          if (result.status == BridgeActionStatus.completed) {
            final output = result.mediaUrl != null
                ? '${result.message}\n媒體: ${result.mediaUrl}'
                : result.message;
            return _SubWorkflowNodeResult(
              nodeIndex: nodeIndex, success: true, output: output);
          }
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: false,
            errorMessage: result.message);

        case 'musicGen':
          final promptText = params['prompt']?.toString() ?? upstreamText;
          final action = BridgeAction(
            type: BridgeActionType.generateMusic,
            prompt: promptText,
          );
          final executor = BridgeActionExecutor();
          final result = await executor.execute(action);

          if (result.status == BridgeActionStatus.completed) {
            final output = result.mediaUrl != null
                ? '${result.message}\n媒體: ${result.mediaUrl}'
                : result.message;
            return _SubWorkflowNodeResult(
              nodeIndex: nodeIndex, success: true, output: output);
          }
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: false,
            errorMessage: result.message);

        case 'tts':
          final textToSpeak = params['text']?.toString() ?? upstreamText;
          final audioPath = await CanvasTtsService.instance.synthesizeToFile(
            text: textToSpeak,
          );
          if (audioPath != null) {
            return _SubWorkflowNodeResult(
              nodeIndex: nodeIndex,
              success: true,
              output: '語音合成完成\n音檔: $audioPath\n原始文字: $textToSpeak');
          }
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: false,
            errorMessage: '語音合成失敗');

        case 'condition':
          final condition = params['condition']?.toString() ??
              params['expression']?.toString() ?? '';
          final conditionMet = upstreamText.contains(condition);
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: true,
            output: '$upstreamText\n條件 "$condition": ${conditionMet ? 'true' : 'false'}');

        case 'vision':
        case 'characterLock':
          // [教練 Agent 2026-08-01] SubWorkflow 不支援圖片節點（沒有 image binary 傳遞）
          // 回傳 prompt 作為文字結果，讓下游文字鏈繼續
          final promptText = params['prompt']?.toString() ?? upstreamText;
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: true,
            output: '[SubWorkflow 跳過 $nodeType — 需在主畫布執行]\n$promptText',
          );

        default:
          return _SubWorkflowNodeResult(
            nodeIndex: nodeIndex,
            success: false,
            errorMessage: '子工作流不支援節點類型: $nodeType',
          );
      }
    } catch (e) {
      return _SubWorkflowNodeResult(
        nodeIndex: nodeIndex,
        success: false,
        errorMessage: '執行失敗: $e',
      );
    }
  }
}
