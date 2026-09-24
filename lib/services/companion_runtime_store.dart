import 'package:flutter/foundation.dart';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import '../models/companion_runtime.dart';

class CompanionRuntimeStore {
  CompanionRuntimeStore._();

  static final CompanionRuntimeStore instance = CompanionRuntimeStore._();

  final ValueNotifier<CompanionRuntimeState> state = ValueNotifier(
    CompanionRuntimeState.initial(),
  );

  CompanionRuntimeState get current => state.value;

  void setActiveCompanion(Companion? companion) {
    if (companion == null) {
      state.value = current.copyWith(
        clearActiveCompanion: true,
        activeCompanionName: '你的 Agent',
        activeCompanionRole: '橋樑代理人',
      );
      return;
    }

    state.value = current.copyWith(
      activeCompanionId: companion.id,
      activeCompanionName: companion.name,
      activeCompanionRole: companion.roleName,
    );
  }

  void updateActivity(AgentActivitySnapshot activity) {
    state.value = current.copyWith(
      activity: activity,
      statusText: activity.active ? activity.stage.label : '自由待機',
    );
  }

  void setStatusText(String statusText) {
    state.value = current.copyWith(statusText: statusText);
  }

  void setFirstAction(CompanionFirstAction action) {
    state.value = current.copyWith(firstAction: action);
  }

  void clearFirstAction() {
    state.value = current.copyWith(clearFirstAction: true);
  }

  void reportBridgeEvidence({
    required String summary,
    required bool completed,
  }) {
    final reply = completed ? '我剛剛替你完成了一次橋樑任務。' : '我剛剛替你檢查了一條橋樑路線，需要你補一把鑰匙。';
    state.value = current.copyWith(
      statusText: reply,
      latestBridgeEvidence: CompanionBridgeEvidence(
        summary: summary,
        status: completed ? 'completed' : 'attention',
        reply: reply,
        occurredAt: DateTime.now(),
      ),
      activity: current.activity.copyWith(
        active: false,
        pulse: false,
        mood: completed ? AgentCompanionMood.proud : AgentCompanionMood.routing,
        action: completed
            ? AgentCompanionAction.bouncing
            : AgentCompanionAction.pointing,
        tick: current.activity.tick + 1,
      ),
    );
  }

  void reportLocalRuntimeSignal({
    required String phase,
    required String title,
    required String detail,
    required String label,
    double? progress,
  }) {
    final isWorking = phase == 'downloading' || phase == 'starting';
    final isReady = phase == 'installed' || phase == 'running';
    final isFailed = phase == 'failed';
    final progressLabel = progress == null
        ? ''
        : ' ${(progress.clamp(0, 1) * 100).round()}%';
    final reply = switch (phase) {
      'downloading' => '我正在替你準備本地主腦$progressLabel。',
      'starting' => '我正在啟動本地主腦。',
      'installed' => '本地主腦已經準備好，可以啟動了。',
      'running' => '本地主腦已經接上，我可以用本地模型替你工作。',
      'failed' => '本地主腦準備時遇到阻礙，需要檢查。',
      _ => detail,
    };
    state.value = current.copyWith(
      statusText: reply,
      latestLocalRuntimeSignal: CompanionLocalRuntimeSignal(
        phase: phase,
        title: title,
        detail: detail,
        label: label,
        progress: progress,
        occurredAt: DateTime.now(),
      ),
      activity: current.activity.copyWith(
        active: isWorking,
        pulse: isWorking || isReady || isFailed,
        mood: isFailed
            ? AgentCompanionMood.routing
            : isReady
            ? AgentCompanionMood.proud
            : AgentCompanionMood.bridging,
        action: isFailed
            ? AgentCompanionAction.pointing
            : isReady
            ? AgentCompanionAction.bouncing
            : AgentCompanionAction.spinning,
        stage: AgentActivityStage.bridge,
        tick: current.activity.tick + 1,
      ),
    );
  }

  void idle() {
    updateActivity(
      current.activity.copyWith(
        active: false,
        pulse: false,
        mood: AgentCompanionMood.idle,
        action: AgentCompanionAction.wandering,
        tick: current.activity.tick + 1,
      ),
    );
  }

  Map<String, dynamic> exportRuntimeJson() => current.toJson();

  @visibleForTesting
  void resetForTest() {
    state.value = CompanionRuntimeState.initial();
  }
}
