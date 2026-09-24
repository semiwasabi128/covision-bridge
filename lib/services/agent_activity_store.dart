import 'package:flutter/foundation.dart';

import '../models/agent_activity.dart';
import 'companion_runtime_store.dart';

class AgentActivityStore {
  // [小葵 2026-09-19 過程直播] 最新關鍵近況——懸浮窗/任何 UI 可讀（非工程流水帳）
  final ValueNotifier<String?> latestLoopStatus = ValueNotifier<String?>(null);
  void pushLoopStatus(String status) {
    var t = status.trim();
    if (t.isEmpty) return;
    if (t.length > 60) t = '${t.substring(0, 60)}…';
    latestLoopStatus.value = t;
  }

  void clearLoopStatus() {
    latestLoopStatus.value = null;
  }

  AgentActivityStore._();

  static final AgentActivityStore instance = AgentActivityStore._();

  final ValueNotifier<AgentActivitySnapshot> snapshot = ValueNotifier(
    const AgentActivitySnapshot(),
  );

  AgentActivitySnapshot get current => snapshot.value;

  void update({
    AgentActivityStage? stage,
    AgentActivityTelemetry? telemetry,
    bool? pulse,
    bool? active,
    AgentCompanionMood? mood,
    AgentCompanionAction? action,
  }) {
    final nextStage = stage ?? current.stage;
    final next = current.copyWith(
      stage: nextStage,
      telemetry: telemetry,
      pulse: pulse,
      active: active ?? true,
      mood: mood ?? AgentActivitySnapshot.moodForStage(nextStage),
      action: action ?? AgentActivitySnapshot.actionForStage(nextStage),
      tick: current.tick + 1,
    );
    snapshot.value = next;
    CompanionRuntimeStore.instance.updateActivity(next);
  }

  void idle() {
    final next = current.copyWith(
      pulse: false,
      active: false,
      mood: AgentCompanionMood.idle,
      action: AgentCompanionAction.wandering,
      tick: current.tick + 1,
    );
    snapshot.value = next;
    CompanionRuntimeStore.instance.updateActivity(next);
  }

  void advanceDemo() {
    final currentIndex = agentActivityStages.indexOf(current.stage);
    final nextStage =
        agentActivityStages[(currentIndex + 1) % agentActivityStages.length];
    update(
      stage: nextStage,
      pulse: !current.pulse,
      telemetry: current.telemetry.copyWith(
        messages: current.telemetry.messages + 1,
        chars: current.telemetry.chars + 240,
        memories: (current.telemetry.memories + 1) % 5,
        bridgeActions: nextStage == AgentActivityStage.bridge
            ? current.telemetry.bridgeActions + 1
            : current.telemetry.bridgeActions,
        attachments: nextStage == AgentActivityStage.bridge ? 1 : 0,
        tokens: current.telemetry.tokens + 180,
      ),
    );
  }

  void seedDemo() {
    if (current.active || current.telemetry.messages > 0) return;
    update(
      stage: AgentActivityStage.understanding,
      pulse: true,
      telemetry: const AgentActivityTelemetry(
        messages: 3,
        chars: 860,
        memories: 1,
      ),
    );
  }

  @visibleForTesting
  void resetForTest() {
    snapshot.value = const AgentActivitySnapshot();
    CompanionRuntimeStore.instance.updateActivity(snapshot.value);
  }
}
