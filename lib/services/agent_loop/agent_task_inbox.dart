// agent_task_inbox.dart
// 任務注入通道 — 讓外部（開發者/教練 Agent）能派任務給原生 Agent執行
//
// 設計理念（使用者 2026-07-18 拍板）：
// - 使用檔案系統做 IPC（最簡單、跨平台、可審計）
// - 原生 Agent每 10 秒掃描任務目錄
// - 發現新任務 → emit externalTask 事件 → NativeAgentLoop 執行
// - 執行完畢 → 寫結果檔案 → 外部讀取
// - 任務格式：JSON（task_id/prompt/created_at/status/result）
//
// 目錄結構：
//   ~/Library/Containers/farm.semiwasabi.bridgeApp/Data/agent_tasks/
//     ├── pending/      ← 外部寫入，原生 Agent讀取
//     ├── processing/   ← 原生 Agent正在執行
//     └── done/         ← 原生 Agent寫入結果，外部讀取
//
// [Phase 3 2026-07-18]

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'agent_event_bus.dart';

/// 任務狀態
enum TaskStatus {
  pending,
  processing,
  done,
  error,
}

/// 外部任務
class ExternalTask {
  final String taskId;
  final String prompt;
  final DateTime createdAt;
  final TaskStatus status;
  final String? result;
  final String? error;
  final bool forceToolUse; // [教練 Agent 2026-07-18] 任務可要求強制工具使用

  ExternalTask({
    required this.taskId,
    required this.prompt,
    required this.createdAt,
    this.status = TaskStatus.pending,
    this.result,
    this.error,
    this.forceToolUse = false,
  });

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'prompt': prompt,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'result': result,
        'error': error,
        'force_tool_use': forceToolUse,
      };

  factory ExternalTask.fromJson(Map<String, dynamic> json) {
    return ExternalTask(
      taskId: json['task_id'] as String,
      prompt: json['prompt'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: TaskStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TaskStatus.pending,
      ),
      result: json['result'] as String?,
      error: json['error'] as String?,
      forceToolUse: json['force_tool_use'] as bool? ?? false,
    );
  }
}

/// 任務信箱 — 監聽外部任務，執行後寫回結果
///
/// 使用方式：
/// ```dart
/// final inbox = AgentTaskInbox(eventBus: eventBus);
/// inbox.start();  // 啟動監聽
/// // 外部寫入 pending/task.json → inbox 讀取 → emit externalTask
/// ```
class AgentTaskInbox {
  final AgentEventBus _eventBus;
  Timer? _scanTimer;
  bool _isRunning = false;
  final Set<String> _processedTaskIds = {};

  /// 掃描間隔（10 秒）
  static const _scanInterval = Duration(seconds: 10);

  AgentTaskInbox({required AgentEventBus eventBus}) : _eventBus = eventBus;

  /// 取得任務目錄根路徑
  Future<Directory> _getTaskRoot() async {
    final appDir = await getApplicationSupportDirectory();
    final taskRoot = Directory('${appDir.path}/agent_tasks');
    for (final sub in ['pending', 'processing', 'done']) {
      await Directory('${taskRoot.path}/$sub').create(recursive: true);
    }
    return taskRoot;
  }

  /// 取得桌面路徑（用於 debug 存取）
  Future<String> getTaskRootPath() async {
    final root = await _getTaskRoot();
    return root.path;
  }

  /// 啟動任務監聽
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _scanTimer = Timer.periodic(_scanInterval, (_) => _scanPending());
    debugPrint('[任務信箱] 已啟動 — 每 10 秒掃描 pending/');
  }

  /// 停止任務監聽
  void stop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isRunning = false;
    debugPrint('[任務信箱] 已停止');
  }

  /// 掃描 pending 目錄
  Future<void> _scanPending() async {
    try {
      final root = await _getTaskRoot();
      final pendingDir = Directory('${root.path}/pending');
      if (!pendingDir.existsSync()) return;

      final files = pendingDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      for (final file in files) {
        // [2026-07-18] 判斷是任務鏈還是單一任務
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        if (json.containsKey('chain_id')) {
          // 任務鏈 — 通知 NativeAgentLoop 用 TaskChainController 執行
          if (_processedTaskIds.contains(json['chain_id'] as String)) continue;
          _processedTaskIds.add(json['chain_id'] as String);

          final processingFile = File('${root.path}/processing/${file.uri.pathSegments.last}');
          await file.rename(processingFile.path);

          debugPrint('[任務信箱] 收到任務鏈: ${json['chain_id']}');
          _eventBus.emit(
            AgentEventType.externalTask,
            data: {
              'task_id': json['chain_id'] as String,
              'is_chain': true,
              'chain_file': processingFile.path,
              'file_path': processingFile.path,
              'root_path': root.path,
              'prompt': '',  // 鏈的 prompt 在 chain JSON 裡
              'force_tool_use': false,
            },
          );
        } else {
          // 單一任務
          await _processSingleTask(file, root, content, json);
        }
      }
    } catch (e) {
      debugPrint('[任務信箱] 掃描失敗: $e');
    }
  }

  /// 處理單一任務檔案
  Future<void> _processSingleTask(File file, Directory root, String content, Map<String, dynamic> json) async {
    try {
      final task = ExternalTask.fromJson(json);

      // 去重——已處理過的任務不重複執行
      if (_processedTaskIds.contains(task.taskId)) return;
      _processedTaskIds.add(task.taskId);

      // 移動到 processing/
      final processingFile = File('${root.path}/processing/${file.uri.pathSegments.last}');
      await file.rename(processingFile.path);

      debugPrint('[任務信箱] 收到任務: ${task.taskId}');

      // emit 事件讓 NativeAgentLoop 執行
      _eventBus.emit(
        AgentEventType.externalTask,
        data: {
          'task_id': task.taskId,
          'prompt': task.prompt,
          'file_path': processingFile.path,
          'root_path': root.path,
          'force_tool_use': task.forceToolUse,
        },
      );
    } catch (e) {
      debugPrint('[任務信箱] 處理任務失敗: $e');
    }
  }

  /// 寫入任務結果（由 NativeAgentLoop 呼叫）
  Future<void> writeResult({
    required String taskId,
    required String processingFilePath,
    required String rootPath,
    required TaskStatus status,
    String? result,
    String? error,
  }) async {
    final doneFile = File('$rootPath/done/$taskId.json');
    final resultData = {
      'task_id': taskId,
      'status': status.name,
      'result': result,
      'error': error,
      'completed_at': DateTime.now().toIso8601String(),
    };
    await doneFile.writeAsString(jsonEncode(resultData));

    // 清理 processing 檔案
    final processingFile = File(processingFilePath);
    if (processingFile.existsSync()) {
      await processingFile.delete();
    }

    debugPrint('[任務信箱] 任務完成: $taskId → done/');
  }

  /// 釋放資源
  void dispose() {
    stop();
  }
}
