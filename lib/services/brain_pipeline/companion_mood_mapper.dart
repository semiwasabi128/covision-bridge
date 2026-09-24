// companion_mood_mapper.dart
// Sprint 7 — 七層結果 → 夥伴 mood / gait / voiceTone 映射
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 把管線七層的判斷結果映射成桌面夥伴的狀態：
// - mood: 注意力 / 擺錘 / 重要性 / 水流 → 夥伴情緒
// - gait: 注意力 / 水流 → 移動方式
// - voiceTone: 心腦對齊 / 重要性 / 行動 → 語氣
//
// 原始 _expressionFor 的純規則邏輯保留在 ActionRouterRule，
// 這裡額外計算 gait / voiceTone 並產出觸發原因說明。

import '../../models/agent_activity.dart';
import '../../models/transurfing_brain.dart';

/// 夥伴狀態映射結果。
class CompanionMoodMapping {
  /// 夥伴情緒（沿用 AgentCompanionMood）。
  final AgentCompanionMood mood;

  /// 夥伴步態。
  final CompanionGait gait;

  /// 夥伴語氣。
  final CompanionVoiceTone voiceTone;

  /// 為什麼選這個狀態（一句話，供 panel 顯示）。
  final String reason;

  const CompanionMoodMapping({
    required this.mood,
    required this.gait,
    required this.voiceTone,
    required this.reason,
  });
}

/// 把七層結果映射成夥伴的 mood / gait / voiceTone。
///
/// 映射規則（按優先序）：
/// 1. 注意力被捕獲 → mood=alert(focused), gait=still, voiceTone=measured
/// 2. 擺錘過多 → mood=grounding(focused), gait=still, voiceTone=measured
/// 3. 過度重要 → mood=calming(focused), gait=stepping, voiceTone=soft
/// 4. 水流順暢 → mood=encouraging(proud), gait=running, voiceTone=brisk
/// 5. 水流停滯 → mood=waiting, gait=paused, voiceTone=measured
/// 6. 預設 → mood=curious, gait=stepping, voiceTone=warm
class CompanionMoodMapper {
  const CompanionMoodMapper();

  /// 從 BrainReflection 計算夥伴狀態映射。
  CompanionMoodMapping mapFromReflection(BrainReflection reflection) {
    final attention = reflection.attentionState;
    final pendulums = reflection.pendulumSignals;
    final importance = reflection.importanceLevel;
    final alignment = reflection.heartMindAlignment;
    final flow = reflection.flowState;
    final move = reflection.recommendedMove;

    // 1. 注意力被捕獲或分散 → 夥伴停下來、沉穩量測
    if (attention == AttentionState.captured ||
        attention == AttentionState.scattered) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.focused,
        gait: CompanionGait.still,
        voiceTone: CompanionVoiceTone.measured,
        reason: '注意力被拉走了，夥伴先停下來穩住',
      );
    }

    // 2. 擺錘過多（>=3 個）→ 夥伴停下來接地
    if (pendulums.length >= 3) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.focused,
        gait: CompanionGait.still,
        voiceTone: CompanionVoiceTone.measured,
        reason: '擺錘太多，夥伴先接地再說',
      );
    }

    // 3. 過度重要 → 夥伴柔和地降重要性
    if (importance == ImportanceLevel.excessive) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.focused,
        gait: CompanionGait.stepping,
        voiceTone: CompanionVoiceTone.soft,
        reason: '事情太重了，夥伴用柔和的語氣陪你放下',
      );
    }

    // 4. 心腦衝突 → 夥伴沉穩量測
    if (alignment == HeartMindAlignment.conflicted ||
        alignment == HeartMindAlignment.mixed) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.focused,
        gait: CompanionGait.stepping,
        voiceTone: CompanionVoiceTone.measured,
        reason: '心與腦在拉扯，夥伴用沉穩的語氣陪你理清',
      );
    }

    // 5. 水流順暢 → 夥伴快步走、輕快
    if (flow == FlowState.withFlow) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.proud,
        gait: CompanionGait.running,
        voiceTone: CompanionVoiceTone.brisk,
        reason: '水流順暢，夥伴輕快地推進',
      );
    }

    // 6. 水流停滯 → 夥伴暫停
    if (flow == FlowState.stalled || flow == FlowState.againstFlow) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.waiting,
        gait: CompanionGait.paused,
        voiceTone: CompanionVoiceTone.measured,
        reason: '水流不順，夥伴先暫停看看',
      );
    }

    // 7. 心腦對齊 → 夥伴溫暖
    if (alignment == HeartMindAlignment.aligned) {
      return CompanionMoodMapping(
        mood: AgentCompanionMood.curious,
        gait: CompanionGait.stepping,
        voiceTone: CompanionVoiceTone.warm,
        reason: '心腦對齊，夥伴溫暖地回應',
      );
    }

    // 8. 預設 → 好奇緩步
    return CompanionMoodMapping(
      mood: AgentCompanionMood.curious,
      gait: CompanionGait.stepping,
      voiceTone: CompanionVoiceTone.warm,
      reason: '夥伴正在觀察',
    );
  }

  /// 把映射結果合進 CompanionExpression（保留原本 mood/action/statusText，補上 gait/voiceTone）。
  CompanionExpression enrichExpression(
    BrainReflection reflection,
  ) {
    final mapping = mapFromReflection(reflection);
    return reflection.companionExpression.withCompanionFields(
      gait: mapping.gait,
      voiceTone: mapping.voiceTone,
    );
  }
}
