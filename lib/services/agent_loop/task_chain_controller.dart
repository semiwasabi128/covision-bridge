// task_chain_controller.dart
// 多步任務鏈控制器 — 依序執行多個 prompt，每步完成後轉譯成自然語言貼給使用者
//
// 使用者 2026-07-18 拍板：
// 「拆成五輪，但 prompt 一次就寫五份，App 內建依序傳遞多個 prompt 的自動機制，
//  傳遞下個 prompt 時就自動把原生 Agent每輪回報內容轉譯成自然語言貼給使用者，
//  這樣使用者的體驗既沒有任務的斷續感也沒有長時間不知道 Agent 做什麼的困擾」
//
// 設計：
// - 外部寫入一個 chain JSON 到 pending/（跟單一任務同一目錄）
// - AgentTaskInbox 掃描到 chain → 通知 NativeAgentLoop
// - NativeAgentLoop 逐一步執行，每步完成後：
//   1. 用 LLM 把 raw result 轉成自然語言摘要
//   2. 推到聊天 UI（讓使用者看到進度）
//   3. 自動注入下一步 prompt
// - 全部完成後寫入 done/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'agent_event_bus.dart';

/// 單一任務鏈步驟
class ChainStep {
  final String id;
  final String title;       // 給使用者看的標題（「改善1：佈局與空間」）
  final String prompt;      // 給原生 Agent的精準 prompt

  ChainStep({required this.id, required this.title, required this.prompt});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'prompt': prompt};
  factory ChainStep.fromJson(Map<String, dynamic> j) => ChainStep(
    id: j['id'] as String, title: j['title'] as String, prompt: j['prompt'] as String,
  );
}

/// 任務鏈
class TaskChain {
  final String chainId;
  final String title;       // 鏈的整體標題（「首頁五大改善」）
  final List<ChainStep> steps;
  final DateTime createdAt;
  int currentStepIndex;

  // [2026-07-18] 鏈完成後自動重啟驗證
  // 不依賴 LLM 自己決定要不要重啟——機械式執行
  final bool requiresRestart;
  final String? restartReason;
  final String? expectedEffect;

  TaskChain({
    required this.chainId,
    required this.title,
    required this.steps,
    required this.createdAt,
    this.currentStepIndex = 0,
    this.requiresRestart = false,
    this.restartReason,
    this.expectedEffect,
  });

  bool get isComplete => currentStepIndex >= steps.length;
  ChainStep? get currentStep => isComplete ? null : steps[currentStepIndex];

  Map<String, dynamic> toJson() => {
    'chain_id': chainId, 'title': title,
    'steps': steps.map((s) => s.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    'current_step': currentStepIndex,
    if (requiresRestart) 'requires_restart': true,
    if (restartReason != null) 'restart_reason': restartReason,
    if (expectedEffect != null) 'expected_effect': expectedEffect,
  };

  factory TaskChain.fromJson(Map<String, dynamic> j) => TaskChain(
    chainId: j['chain_id'] as String,
    title: j['title'] as String,
    steps: (j['steps'] as List).map((s) => ChainStep.fromJson(s as Map<String, dynamic>)).toList(),
    createdAt: DateTime.parse(j['created_at'] as String),
    currentStepIndex: j['current_step'] as int? ?? 0,
    requiresRestart: j['requires_restart'] as bool? ?? false,
    restartReason: j['restart_reason'] as String?,
    expectedEffect: j['expected_effect'] as String?,
  );
}

/// 單步結果
class ChainStepResult {
  final String stepId;
  final String title;
  final String rawResult;     // 原生 Agent的原始回報
  final String? userMessage;  // 轉譯後的自然語言（給使用者看的）
  final bool success;

  ChainStepResult({
    required this.stepId, required this.title,
    required this.rawResult, this.userMessage, required this.success,
  });

  Map<String, dynamic> toJson() => {
    'step_id': stepId, 'title': title,
    'raw_result': rawResult, 'user_message': userMessage,
    'success': success,
  };
}

/// 任務鏈控制器
///
/// 由 NativeAgentLoop 持有。收到 chain 事件後逐一步執行。
/// 每步完成後：
/// 1. 呼叫 onStepComplete callback（讓上層轉譯+推 UI）
/// 2. 自動等待 2 秒（讓使用者讀完訊息）
/// 3. 注入下一步 prompt
class TaskChainController {
  TaskChain? _activeChain;
  final List<ChainStepResult> _results = [];
  final String _chainDirPath;

  /// callback：每步完成後呼叫，回傳轉譯後的自然語言
  /// 上層（NativeAgentLoop）實作：用 LLM 轉譯 → 推聊天 UI
  final Future<String?> Function(String rawResult, String stepTitle)? onTranslateResult;

  /// callback：推訊息到聊天 UI
  final void Function(String message, {String? speakerId, bool isProgress})? onPushToChat;

  /// callback：執行單一步驟的 prompt（呼叫 AgentLoop.run）
  /// 回傳 AgentLoop 的 reply
  final Future<String> Function(String prompt, int maxTurns, bool forceToolUse)? onExecuteStep;

  /// [2026-07-18] callback：chain 完成後需要重啟驗證
  /// 由 NativeAgentLoop 實作：寫 checkpoint → build → restart_app
  /// 機械式執行，不依賴 LLM 判斷
  final Future<void> Function(TaskChain chain)? onChainRequiresRestart;

  TaskChainController({
    this.onTranslateResult,
    this.onPushToChat,
    this.onExecuteStep,
    this.onChainRequiresRestart,
  }) : _chainDirPath = ''; // 動態取得

  static Future<String> getChainDirPath() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/agent_tasks/chains');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  bool get isActive => _activeChain != null && !_activeChain!.isComplete;

  /// 從 JSON 檔案載入任務鏈
  static Future<TaskChain?> loadChain(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return TaskChain.fromJson(json);
    } catch (e) {
      debugPrint('[TaskChain] 載入失敗: $e');
      return null;
    }
  }

  /// 執行整個任務鏈
  Future<void> execute(TaskChain chain) async {
    _activeChain = chain;
    _results.clear();

    // 推鏈開始訊息到 UI
    onPushToChat?.call(
      '🎯 開始執行：${chain.title}\n共 ${chain.steps.length} 個步驟，我會逐步回報進度。',
      isProgress: true,
    );

    while (!chain.isComplete) {
      final step = chain.currentStep!;
      debugPrint('[TaskChain] 執行步驟 ${chain.currentStepIndex + 1}/${chain.steps.length}: ${step.title}');

      // 推步驟開始訊息
      onPushToChat?.call(
        '📍 步驟 ${chain.currentStepIndex + 1}/${chain.steps.length}：${step.title}',
        isProgress: true,
      );

      // 執行步驟
      String rawResult = '';
      bool success = true;
      try {
        rawResult = await onExecuteStep?.call(step.prompt, 25, true) ?? '（無結果）';
      } catch (e) {
        rawResult = '執行失敗：$e';
        success = false;
      }

      // 轉譯成自然語言
      String? userMessage;
      try {
        userMessage = await onTranslateResult?.call(rawResult, step.title);
      } catch (e) {
        debugPrint('[TaskChain] 轉譯失敗: $e');
        userMessage = null;
      }

      // 推步驟結果到 UI
      final displayMsg = userMessage ?? rawResult;
      onPushToChat?.call(displayMsg, isProgress: false);

      _results.add(ChainStepResult(
        stepId: step.id,
        title: step.title,
        rawResult: rawResult,
        userMessage: userMessage,
        success: success,
      ));

      chain.currentStepIndex++;

      // 步驟間等待 2 秒（讓使用者讀完）
      if (!chain.isComplete) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // 推鏈完成訊息
    final successCount = _results.where((r) => r.success).length;
    onPushToChat?.call(
      '✅ ${chain.title} 完成！\n成功 $successCount/${chain.steps.length} 步。',
      isProgress: true,
    );

    // 寫入結果檔案
    await _writeChainResult(chain);

    _activeChain = null;

    // [2026-07-18] 鏈完成後自動重啟驗證（機械式，不靠 LLM）
    if (chain.requiresRestart && onChainRequiresRestart != null) {
      debugPrint('[TaskChain] 鏈完成且 requiresRestart=true，觸發自動重啟驗證');
      onPushToChat?.call(
        '🔄 所有步驟完成，正在 build + 重啟以驗證效果…',
        isProgress: true,
      );
      try {
        await onChainRequiresRestart!.call(chain);
      } catch (e) {
        debugPrint('[TaskChain] 自動重啟失敗: $e');
        onPushToChat?.call('❌ 自動重啟失敗：$e', isProgress: true);
      }
    }
  }

  /// 寫入鏈結果到 chains/done/
  Future<void> _writeChainResult(TaskChain chain) async {
    try {
      final dir = await getChainDirPath();
      final doneDir = Directory('$dir/done');
      if (!doneDir.existsSync()) doneDir.createSync(recursive: true);
      final file = File('${doneDir.path}/${chain.chainId}.json');
      final data = {
        'chain_id': chain.chainId,
        'title': chain.title,
        'completed_at': DateTime.now().toIso8601String(),
        'results': _results.map((r) => r.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data));
      debugPrint('[TaskChain] 結果已寫入: ${file.path}');
    } catch (e) {
      debugPrint('[TaskChain] 寫入結果失敗: $e');
    }
  }
}
