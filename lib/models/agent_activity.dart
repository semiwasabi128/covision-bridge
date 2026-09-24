import 'package:flutter/material.dart';

class AgentActivityStage {
  final String label;
  final String shortLabel;
  final String detail;
  final IconData icon;

  const AgentActivityStage({
    required this.label,
    required this.shortLabel,
    required this.detail,
    required this.icon,
  });

  static const understanding = AgentActivityStage(
    label: '正在理解你的需求',
    shortLabel: '理解',
    detail: '整理訊息、附件與目前對話意圖。',
    icon: Icons.lightbulb_outline,
  );

  static const context = AgentActivityStage(
    label: '正在整理上下文',
    shortLabel: '上下文',
    detail: '帶入長期記憶，必要時壓縮較早對話。',
    icon: Icons.compress_outlined,
  );

  static const routing = AgentActivityStage(
    label: '正在選擇橋樑能力',
    shortLabel: '路由',
    detail: '判斷是否需要文件、圖片或其他能力服務。',
    icon: Icons.hub_outlined,
  );

  static const waiting = AgentActivityStage(
    label: '正在等待 AI 回應',
    shortLabel: '回應',
    detail: '已送出請求，等待目前主腦服務回覆。',
    icon: Icons.auto_awesome,
  );

  static const composing = AgentActivityStage(
    label: '正在整理回覆',
    shortLabel: '整理',
    detail: '解析橋樑動作、token 與回覆內容。',
    icon: Icons.edit_note,
  );

  static const bridge = AgentActivityStage(
    label: '正在執行橋樑能力',
    shortLabel: '橋樑',
    detail: '交給能力路由器，連接合適的服務。',
    icon: Icons.account_tree_outlined,
  );
}

const agentActivityStages = [
  AgentActivityStage.understanding,
  AgentActivityStage.context,
  AgentActivityStage.routing,
  AgentActivityStage.waiting,
  AgentActivityStage.composing,
  AgentActivityStage.bridge,
];

/// [教練 Agent 2026-07-03] 狀態圖多樣性 prompt 擴展
/// 每個狀態有獨特的姿勢、構圖、視角、動態描述，
/// 確保 8 張圖即使遠看也有明顯差異。
/// 角色特徵不變（臉、服裝、配色），但肢體語言和場景大幅變化。
/// 注意：idle（待機）不在這裡 — 主形象圖即為待機圖，不額外生成。
const stateImagePoseGuides = <String, String>{
  'wandering': '動態構圖，角色正在走路，身體微微前傾，一腳抬起，'
      '手臂自然擺動，像是剛發現有趣的東西。視角略低（仰角 15°），'
      '構圖偏右，左側有飄動的光粒子作為環境點綴。',

  'reading': '特寫構圖（膝上），角色坐在地面盤腿，手中捧著發光的光頁，'
      '低頭專注閱讀，另一手托腮。視角俯角 30°，構圖置中，'
      '光頁的藍白光芒照亮角色臉部。',

  'pointing': '戲劇性構圖，角色側身站立，右手伸直指向遠方，'
      '左手插腰，身體微轉 3/4 側面，表情自信。視角仰角 20°，'
      '構圖偏左，指向方向有光束引導線。',

  'bridging': '能量構圖，角色雙手張開向兩側伸展，掌心發光，'
      '身邊環繞數條發光能量線連接畫面邊緣，表情專注。'
      '視角正面微仰，構圖置中，背景有電路紋路光效。',

  'celebrating': '動感構圖，角色雙手高舉跳起，身體在空中，'
      '雙腳離地，周圍散落星星和光芒特效，表情大笑。'
      '視角仰角 25°，構圖置中偏低，上方有煙花光點。',

  'writing': '桌面視角構圖，角色趴在桌面邊緣，一手拿筆在光面上書寫，'
      '身體前傾，表情認真。視角俯角 45°（鳥瞰），構圖偏右上，'
      '左下有文字光跡。',

  'stuck': '情緒構圖，角色蹲坐地面，雙手抱膝，頭上有一個問號或打結符號，'
      '表情苦惱微嘟嘴。視角平視微俯，構圖偏左下，'
      '右上方有漂浮的困惑符號。',

  'idea': '爆發構圖，角色單腳跪地，右手握拳向上揮出，'
      '頭頂有一個大燈泡發光，表情興奮張眼。視角仰角 30°，'
      '構圖偏右，燈泡光芒從左上灑下。',
};

class AgentActivityTelemetry {
  final int messages;
  final int chars;
  final int memories;
  final int bridgeActions;
  final int attachments;
  final int tokens;

  const AgentActivityTelemetry({
    this.messages = 0,
    this.chars = 0,
    this.memories = 0,
    this.bridgeActions = 0,
    this.attachments = 0,
    this.tokens = 0,
  });

  AgentActivityTelemetry copyWith({
    int? messages,
    int? chars,
    int? memories,
    int? bridgeActions,
    int? attachments,
    int? tokens,
  }) {
    return AgentActivityTelemetry(
      messages: messages ?? this.messages,
      chars: chars ?? this.chars,
      memories: memories ?? this.memories,
      bridgeActions: bridgeActions ?? this.bridgeActions,
      attachments: attachments ?? this.attachments,
      tokens: tokens ?? this.tokens,
    );
  }
}

enum AgentCompanionMood {
  idle,
  curious,
  focused,
  routing,
  waiting,
  proud,
  bridging,
}

enum AgentCompanionAction {
  standing,
  wandering,
  reading,
  pointing,
  bouncing,
  spinning,
}

class AgentActivitySnapshot {
  final AgentActivityStage stage;
  final AgentActivityTelemetry telemetry;
  final bool pulse;
  final bool active;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final int tick;

  const AgentActivitySnapshot({
    this.stage = AgentActivityStage.understanding,
    this.telemetry = const AgentActivityTelemetry(),
    this.pulse = false,
    this.active = false,
    this.mood = AgentCompanionMood.idle,
    this.action = AgentCompanionAction.standing,
    this.tick = 0,
  });

  AgentActivitySnapshot copyWith({
    AgentActivityStage? stage,
    AgentActivityTelemetry? telemetry,
    bool? pulse,
    bool? active,
    AgentCompanionMood? mood,
    AgentCompanionAction? action,
    int? tick,
  }) {
    return AgentActivitySnapshot(
      stage: stage ?? this.stage,
      telemetry: telemetry ?? this.telemetry,
      pulse: pulse ?? this.pulse,
      active: active ?? this.active,
      mood: mood ?? this.mood,
      action: action ?? this.action,
      tick: tick ?? this.tick,
    );
  }

  static AgentCompanionMood moodForStage(AgentActivityStage stage) {
    if (stage == AgentActivityStage.understanding) {
      return AgentCompanionMood.curious;
    }
    if (stage == AgentActivityStage.context) return AgentCompanionMood.focused;
    if (stage == AgentActivityStage.routing) return AgentCompanionMood.routing;
    if (stage == AgentActivityStage.waiting) return AgentCompanionMood.waiting;
    if (stage == AgentActivityStage.composing) return AgentCompanionMood.proud;
    if (stage == AgentActivityStage.bridge) return AgentCompanionMood.bridging;
    return AgentCompanionMood.idle;
  }

  static AgentCompanionAction actionForStage(AgentActivityStage stage) {
    if (stage == AgentActivityStage.context) {
      return AgentCompanionAction.reading;
    }
    if (stage == AgentActivityStage.routing) {
      return AgentCompanionAction.pointing;
    }
    if (stage == AgentActivityStage.waiting) {
      return AgentCompanionAction.bouncing;
    }
    if (stage == AgentActivityStage.bridge) {
      return AgentCompanionAction.spinning;
    }
    return AgentCompanionAction.wandering;
  }
}
