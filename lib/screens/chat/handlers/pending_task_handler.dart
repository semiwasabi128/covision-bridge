// [教練 Agent Sprint 17 Step 7 2026-07-07]
// Pending task handler — 從 chat_screen.dart 提取。
// 處理 PendingBridgeTask 的載入、恢復、自動恢復、放下。
import 'package:flutter/material.dart';

import '../../../models/agent_activity.dart';
import '../../../models/bridge_action.dart';
import '../../../services/agent_activity_store.dart';
import '../../../services/bridge_action_executor.dart';
import '../../../services/capability_activation_signal.dart';
import '../../../services/pending_bridge_task_store.dart';
import '../widgets/pending_task_banner.dart';

class PendingTaskHandlerConfig {
  final PendingBridgeTaskStore pendingBridgeTaskStore;
  final BridgeActionExecutor bridgeActionExecutor;
  final PendingBridgeTask? Function() getPendingBridgeTask;
  final void Function(PendingBridgeTask?) setPendingBridgeTask;
  final bool Function() getAutoResumingPendingTask;
  final void Function(bool) setAutoResumingPendingTask;
  final bool autoResumePendingTaskOnStartup;
  final bool Function() mounted;
  final void Function(void Function() fn) setState;
  final BuildContext Function() context;
  final Future<void> Function(String) appendLocalSystemMessage;
  final Future<void> Function(BridgeActionResult) appendBridgeResultMessage;
  final Future<void> Function(BridgeAction, BridgeActionResult)
      appendBridgeConfirmationMessage;
  final void Function(String) setMessageInputText;

  const PendingTaskHandlerConfig({
    required this.pendingBridgeTaskStore,
    required this.bridgeActionExecutor,
    required this.getPendingBridgeTask,
    required this.setPendingBridgeTask,
    required this.getAutoResumingPendingTask,
    required this.setAutoResumingPendingTask,
    required this.autoResumePendingTaskOnStartup,
    required this.mounted,
    required this.setState,
    required this.context,
    required this.appendLocalSystemMessage,
    required this.appendBridgeResultMessage,
    required this.appendBridgeConfirmationMessage,
    required this.setMessageInputText,
  });
}

class PendingTaskHandler {
  final PendingTaskHandlerConfig config;

  PendingTaskHandler(this.config);

  /// 載入待恢復任務，如有則顯示 SnackBar 並嘗試自動恢復。
  Future<void> loadPendingBridgeTask() async {
    final task = await config.pendingBridgeTaskStore.loadActive();
    if (!config.mounted()) return;
    config.setState(() => config.setPendingBridgeTask(task));
    if (task != null) {
      _showPendingTaskSnackBar();
    }
    if (task?.bridgeAction != null) {
      if (!config.autoResumePendingTaskOnStartup) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!config.mounted()) return;
        tryAutoResumePendingBridgeTask(task!);
      });
    }
  }

  /// 手動恢復 — 把任務請求放回輸入框，靜默放下任務。
  Future<void> resumePendingBridgeTask(PendingBridgeTask task) async {
    config.setState(() => config.setMessageInputText(task.request));
    await dismissPendingBridgeTask(task.id, silent: true);
  }

  /// 自動恢復 — 直接執行橋樑動作。
  Future<void> tryAutoResumePendingBridgeTask(
    PendingBridgeTask task, {
    CapabilityActivationSignal? signal,
  }) async {
    if (config.getAutoResumingPendingTask() || task.bridgeAction == null) {
      return;
    }
    config.setState(() => config.setAutoResumingPendingTask(true));
    AgentActivityStore.instance.update(
      stage: AgentActivityStage.bridge,
      telemetry: const AgentActivityTelemetry(bridgeActions: 1),
      pulse: true,
    );

    final result = await config.bridgeActionExecutor.execute(task.bridgeAction!);
    if (!config.mounted()) return;

    config.setState(() => config.setAutoResumingPendingTask(false));
    AgentActivityStore.instance.idle();

    switch (result.status) {
      case BridgeActionStatus.completed:
        await config.pendingBridgeTaskStore.clear(taskId: task.id);
        if (config.mounted()) {
          config.setState(() => config.setPendingBridgeTask(null));
        }
        await config.appendLocalSystemMessage(
          signal == null
              ? '能力已開通，我已自動回到原本卡點並接續執行：${task.request}'
              : '${signal.title}，我已自動回到原本卡點並接續執行：${task.request}',
        );
        await config.appendBridgeResultMessage(result);
        break;
      case BridgeActionStatus.needsConfirmation:
        await config.appendBridgeConfirmationMessage(task.bridgeAction!, result);
        break;
      case BridgeActionStatus.needsProvider:
      case BridgeActionStatus.unsupported:
        if (config.mounted()) {
          config.setState(() => config.setPendingBridgeTask(task));
        }
        if (config.mounted()) {
          _showPendingTaskSnackBar();
        }
        break;
    }
  }

  /// 放下待恢復任務。
  Future<void> dismissPendingBridgeTask(
    String taskId, {
    bool silent = false,
  }) async {
    await config.pendingBridgeTaskStore.clear(taskId: taskId);
    if (!config.mounted()) return;
    config.setState(() => config.setPendingBridgeTask(null));
    if (!silent) {
      ScaffoldMessenger.of(config.context()).showSnackBar(
        const SnackBar(
          content: Text('已放下這個待恢復任務。'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showPendingTaskSnackBar() {
    ScaffoldMessenger.of(config.context()).showSnackBar(
      SnackBar(
        content: const Text('有待恢復的橋樑任務'),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            final task = config.getPendingBridgeTask();
            if (task == null) return;
            showModalBottomSheet(
              context: config.context(),
              builder: (context) => Padding(
                padding: const EdgeInsets.all(16),
                child: PendingBridgeTaskBanner(
                  task: task,
                  autoResuming: config.getAutoResumingPendingTask(),
                  onDismiss: () =>
                      dismissPendingBridgeTask(task.id),
                  onResume: () => resumePendingBridgeTask(task),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
