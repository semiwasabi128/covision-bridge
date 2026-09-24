// swarm_tools.dart
// [TRIO M4 2026-09-22] 蜂群作戰工具組——六關對話推進
//
// 軍官（App Agent）在對話輪中用這組工具推進開戰閘門：
//   swarm_open        開戰役（G1 終點定義必填——以終為始）
//   swarm_gate_pass   過一關（記錄該關產物：計畫/地圖/成本）
//   swarm_commit      六關全過後開戰（使用者點頭）
//   swarm_abort       棄案
//   swarm_status      查看戰役現況
library;

import 'dart:async';
import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/collab/swarm_muster.dart'; // [M5b] G0
import 'package:bridge_app/services/collab/swarm_harvest.dart'; // [M5b] AAR
import 'package:bridge_app/services/collab/swarm_recorder.dart'; // [M5b] 事件流

/// [M5b] 羅盤出陣登記——一戰役一筆（Blue 令：統一性質，不逐兵）
class SwarmMusterTool extends AgentTool {
  @override
  String get name => 'swarm_muster';

  @override
  String get description =>
      '羅盤出陣登記：帶著任務卡去羅盤領工具包跟藥包（一戰役一筆，'
      '統一登記不逐兵）。領了裝備 swarm_open 才能過 G0。'
      '工具包=這場仗要用的工具清單；藥包=出問題時的預備方案與停損線';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(name: 'campaign_id', description: '戰役 id（swarm_status 查）'),
        AgentToolParamSpec(
            name: 'objective', description: '任務目標（與戰役一致）', required: true),
        AgentToolParamSpec(
            name: 'toolkit', description: '工具包：這場仗要用的工具', required: true),
        AgentToolParamSpec(
            name: 'medkit', description: '藥包：預備方案＋停損線', required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final objective = (args['objective'] as String?)?.trim() ?? '';
    final toolkit = (args['toolkit'] as String?)?.trim() ?? '';
    final medkit = (args['medkit'] as String?)?.trim() ?? '';
    if (objective.isEmpty || toolkit.isEmpty || medkit.isEmpty) {
      return AgentToolResult.failure('objective / toolkit / medkit 都必填');
    }
    // campaign_id 可省——登記到「下一場」（open 時配對）
    final campaignId =
        (args['campaign_id'] as String?)?.trim() ?? pendingMusterKey;
    final m = await SwarmMusterRoll.instance.register(
      campaignId: campaignId,
      objective: objective,
      endpoint: '',
      toolkit: toolkit,
      medkit: medkit,
      byHuman: 'Blue',
    );
    return AgentToolResult.success(
        '🎒 出陣登記完成（羅盤）：\n工具包：$toolkit\n藥包：$medkit\n'
        '登記編號：${m.campaignId}');
  }

  /// 未開戰役時先登記的暫存鑰——open 時自動配對
  static const pendingMusterKey = '__pending__';
}

class SwarmOpenTool extends AgentTool {
  @override
  String get name => 'swarm_open';

  @override
  String get description =>
      '開啟一場蜂群作戰戰役（進入規劃期）。以終為始：必須先講清楚'
      '「打完長什麼樣」——可驗證的終點現實與驗收方式。'
      '沒有驗收方式的戰爭不開打。開好後規劃期六關逐步完成，'
      '完成前 delegate_batch 會被硬拒絕';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'objective',
            description: '原始目標（使用者的白話）',
            required: true),
        AgentToolParamSpec(
            name: 'endpoint',
            description: '可驗證的終點現實——交付物是什麼、在哪',
            required: true),
        AgentToolParamSpec(
            name: 'acceptance',
            description: '驗收方式——怎麼驗、成功判準',
            required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final objective = (args['objective'] as String?)?.trim() ?? '';
    final endpoint = (args['endpoint'] as String?)?.trim() ?? '';
    final acceptance = (args['acceptance'] as String?)?.trim() ?? '';
    if (objective.isEmpty || endpoint.isEmpty || acceptance.isEmpty) {
      return AgentToolResult.failure(
          'objective / endpoint / acceptance 三項都必填——'
          '終點與驗收方式不可空白（以終為始鐵則）');
    }
    final c = SwarmCommand.instance.openCampaign(
      objective: objective,
      endpoint: endpoint,
      acceptance: acceptance,
    );
    if (c == null) {
      final active = SwarmCommand.instance.active;
      return AgentToolResult.failure(
          '已有活躍戰役（${active?.id}，phase=${active?.phase.name}）——'
          '一次一場。先完成或 swarm_abort 棄案');
    }
    // [M5b G0] 羅盤出陣登記檢查——未領工具包+藥包不得出陣
    // （Blue 令：一戰役一筆統一登記；群任務先到羅盤領裝備是儀式）
    // 先查本戰役、再查 pending（先領裝備再開戰役的順序也成立）
    var muster = SwarmMusterRoll.instance.lookup(c.id) ??
        SwarmMusterRoll.instance.lookup(SwarmMusterTool.pendingMusterKey);
    if (muster != null && muster.campaignId != c.id) {
      // pending 登記轉移到本戰役（配對）
      muster = await SwarmMusterRoll.instance.register(
        campaignId: c.id,
        objective: muster.objective.isNotEmpty ? muster.objective : objective,
        endpoint: endpoint,
        toolkit: muster.toolkit,
        medkit: muster.medkit,
        byHuman: muster.byHuman,
      );
    }
    if (muster == null) {
      return AgentToolResult.failure(
          '⛔ G0 出陣登記未完成——先帶著任務卡去羅盤領工具包跟藥包'
          '（swarm_muster 工具登記），領了才能開戰役。'
          '這是集群作戰的出陣儀式，不省略。');
    }
    // G1（終點定義）在本步完成——objective/endpoint/acceptance 即產物
    c.passGate();
    // [M5b] 開錄——作戰是數位資產
    unawaited(SwarmCommand.instance.recorderFor(c.id)
        .log('campaign_open', data: {
      'objective': objective,
      'endpoint': endpoint,
      'acceptance': acceptance,
      'muster': muster.toJson(),
    }));
    return AgentToolResult.success(
        '戰役 ${c.id} 已開（planning）。\n目標：$objective\n'
        '終點：$endpoint\n驗收：$acceptance\n\n'
        '六關：G1 終點定義（本步已含）→ G2 意圖對齊 → G3 作戰計畫 → '
        'G4 作戰地圖 → G5 成本試算＋試射 → G6 雙向零疑問。\n'
        '每關與使用者對話確認後用 swarm_gate_pass 記錄。');
  }
}

class SwarmGatePassTool extends AgentTool {
  @override
  String get name => 'swarm_gate_pass';

  @override
  String get description =>
      '記錄通過一道開戰閘門（必須已與使用者確認該關內容）。'
      'gate: g2_intent=意圖對齊 / g3_plan=作戰計畫 / g4_map=作戰地圖 / '
      'g5_cost=成本試算（附試算表）/ g6_zero_doubt=雙向零疑問。'
      '嚴禁在使用者尚未點頭時跳關——違反等於任意開戰';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'gate',
            description: 'g2_intent/g3_plan/g4_map/g5_cost/g6_zero_doubt',
            required: true),
        AgentToolParamSpec(
            name: 'artifact', description: '該關產物摘要（計畫全文/地圖ID/試算表）'),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final c = SwarmCommand.instance.active;
    if (c == null) {
      return AgentToolResult.failure('沒有進行中的戰役——先 swarm_open');
    }
    if (c.phase != SwarmPhase.planning) {
      return AgentToolResult.failure(
          '戰役已在 ${c.phase.name}——不需要再過關');
    }
    final gateStr = args['gate'] as String? ?? '';
    final artifact = args['artifact'] as String? ?? '';

    // 關序必須按序——G1 已在 open 時完成
    final order = {
      'g2_intent': 2,
      'g3_plan': 3,
      'g4_map': 4,
      'g5_cost': 5,
      'g6_zero_doubt': 6,
    };
    final gateNum = order[gateStr];
    if (gateNum == null) {
      return AgentToolResult.failure(
          'gate 必須是 ${order.keys.join('/')}（G1 已在 swarm_open 完成）');
    }
    if (gateNum != c.gatesPassed + 1) {
      return AgentToolResult.failure(
          '跳關：現在應過第 ${c.gatesPassed + 1} 關，'
          '你給的是第 $gateNum 關（${SwarmGate.values[gateNum - 1].label}）。'
          '六關必須按序。');
    }
    // 關鍵關卡產物必填
    if (gateNum == 3 && artifact.isEmpty) {
      return AgentToolResult.failure('G3 作戰計畫需要 artifact（計畫全文）');
    }
    if (gateNum == 5 && artifact.isEmpty) {
      return AgentToolResult.failure(
          'G5 成本試算需要 artifact（試算表：金錢/時間/算力/失敗半徑）');
    }

    c.passGate();
    unawaited(SwarmCommand.instance.recorderFor(c.id).log('gate_pass',
        data: {'gate': gateStr, 'artifact': artifact}));
    if (gateNum == 3) c.plan = artifact;
    // g4_map / g5_cost 的 artifact 存 mapCanvasId / cost 由地圖工具與
    // 試算工具另行寫入（本工具記錄過關事實）

    return AgentToolResult.success(
        '✅ 第 $gateNum 關（${SwarmGate.values[gateNum - 1].label}）已過——'
        '進度 ${c.gatesPassed}/6。'
        '${c.gatesPassed >= 6 ? '\n六關全過！等使用者點頭後 swarm_commit 開戰。' : ''}');
  }
}

class SwarmCommitTool extends AgentTool {
  @override
  String get name => 'swarm_commit';

  @override
  String get description =>
      '開戰！六關全過且使用者明確點頭後呼叫。'
      '之後 delegate_batch 解鎖（兵力上限 100）';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'user_confirmed',
            description: '使用者是否已明確說開戰（true/false）——必填',
            required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final c = SwarmCommand.instance.active;
    if (c == null) {
      return AgentToolResult.failure('沒有進行中的戰役');
    }
    final confirmed = args['user_confirmed'] == true ||
        args['user_confirmed'].toString() == 'true';
    if (!confirmed) {
      return AgentToolResult.failure(
          'user_confirmed 必須為 true——使用者沒點頭就不能開戰'
          '（任意開戰都是災難）');
    }
    if (!c.commit()) {
      return AgentToolResult.failure(
          '六關未全過（${c.gatesPassed}/6）——不能開戰');
    }
    unawaited(SwarmCommand.instance.recorderFor(c.id).log('commit',
        data: {'endpoint': c.endpoint, 'cost': c.cost?.moneyCost}));
    return AgentToolResult.success(
        '⚔️ 戰役 ${c.id} 已開戰（committed）——delegate_batch 解鎖。'
        '終點：${c.endpoint}');
  }
}

class SwarmAbortTool extends AgentTool {
  @override
  String get name => 'swarm_abort';

  @override
  String get description => '棄案——planning 任何時刻使用者說不打了。零成本零殘留';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(name: 'reason', description: '棄案原因', required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final c = SwarmCommand.instance.active;
    if (c == null) {
      return AgentToolResult.failure('沒有進行中的戰役');
    }
    final reason = args['reason'] as String? ?? '';
    c.abort(reason);
    unawaited(SwarmCommand.instance.recorderFor(c.id)
        .log('end', data: {'outcome': 'aborted', 'reason': reason}));
    return AgentToolResult.success(
        '戰役 ${c.id} 已棄案（$reason）。此時還沒有任何兵被派出——'
        '零成本零殘留。');
  }
}

/// [M5b] 收兵——戰後分析→問 Blue→入樹→結案（兩段式：主權拍板）
class SwarmCloseTool extends AgentTool {
  @override
  String get name => 'swarm_close';

  @override
  String get description =>
      '收兵。第一段（無參數）：讀事件流產出 AAR 戰後分析（計畫vs實際+'
      '成本核對方法面+三養分卡），呈給使用者問「這場要入樹嗎」。'
      '第二段（settle + user_confirmed=true）：寫入歷史樹+反思樹、'
      '結案戰役、註銷出陣登記';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'action', description: 'report（預設）/ settle'),
        AgentToolParamSpec(
            name: 'user_confirmed',
            description: 'settle 時必填 true——使用者點頭入樹'),
        AgentToolParamSpec(
            name: 'money_spent',
            description: 'settle 時：實際花費（美元）——從 BudgetLedger/帳單讀'),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final c = SwarmCommand.instance.active;
    if (c == null) {
      return AgentToolResult.failure('沒有進行中的戰役');
    }
    final action = (args['action'] as String?) ?? 'report';
    final recorder = SwarmCommand.instance.recorderFor(c.id);

    if (action == 'report') {
      final events = recorder.events.isNotEmpty
          ? recorder.events
          : await SwarmCampaignAssets.instance.loadEvents(c.id);
      final aar = SwarmHarvester.produce(campaign: c, events: events);
      return AgentToolResult.success(aar.render() +
          '\n\n❓ 這場戰役要入生命樹嗎？（歷史樹+反思樹）'
          '\n點頭請回覆確認，我再 swarm_close settle');
    }

    // settle
    final confirmed = args['user_confirmed'] == true ||
        args['user_confirmed'].toString() == 'true';
    if (!confirmed) {
      return AgentToolResult.failure('使用者沒點頭不能入樹（主權拍板）');
    }
    final events = recorder.events.isNotEmpty
        ? recorder.events
        : await SwarmCampaignAssets.instance.loadEvents(c.id);
    final aar = SwarmHarvester.produce(campaign: c, events: events);

    // 實際成本：參數給的優先；否則從 cost_tick 事件流分解
    // （tokensToday 差值×假設單價——誠實標方法）
    double moneySpent;
    final given = double.tryParse('${args['money_spent'] ?? ''}');
    if (given != null) {
      moneySpent = given;
    } else {
      final ticks = events.where((e) => e.type == 'cost_tick').toList();
      final firstTok = ticks.isNotEmpty ? (ticks.first.data['tokensToday'] as num?)?.toDouble() : null;
      final lastTok = ticks.isNotEmpty ? (ticks.last.data['tokensToday'] as num?)?.toDouble() : null;
      final delta = (firstTok != null && lastTok != null) ? lastTok - firstTok : 0.0;
      moneySpent = delta / 1e6 * 2.0; // 粗估均價 $2/M——報數字標方法
    }
    final t0 = events.isNotEmpty ? events.first.t : DateTime.now();
    final t1 = events.isNotEmpty ? events.last.t : DateTime.now();

    // 結案（done + CostActual）
    SwarmCommand.instance.closeCampaign(
      actual: CostActual(
        moneySpent: moneySpent,
        wallClockActual: t1.difference(t0),
      ),
    );
    await recorder.log('end', data: {
      'outcome': 'done',
      'moneySpent': moneySpent,
    });
    await recorder.log('harvest', data: {
      'nutrients': aar.nutrients.map((n) => n.toJson()).toList(),
      'costCheck':
          aar.deviations.where((d) => d.item.contains('成本核對')).map((d) => d.note).join('/'),
    });

    // 入樹（歷史樹+反思樹——Blue 9/23 令：無論符合與否都記錄）
    final ok = await SwarmHarvester.writeToLifeTree(aar);
    // 註銷出陣登記（羅盤不積灰）
    await SwarmMusterRoll.instance.unregister(c.id);

    return AgentToolResult.success(
        '🏁 戰役 ${c.id} 已收兵結案。\n'
        '入樹：${ok ? '✅ 歷史樹+反思樹已寫入' : '⚠️ 入樹失敗（fail-open——AAR 已存 JSONL 可重播）'}\n'
        '實際成本：\$${moneySpent.toStringAsFixed(2)}'
        '${given == null ? '（cost_tick 分解估計）' : '（帳單實值）'}\n'
        '作戰紀錄：swarm_campaigns/${c.id}.jsonl（星系作戰模式可重播）');
  }
}

class SwarmStatusTool extends AgentTool {
  @override
  String get name => 'swarm_status';

  @override
  String get description => '查看當前戰役現況（關卡進度/終點/成本試算）';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final c = SwarmCommand.instance.active;
    if (c == null) {
      return AgentToolResult.success('目前沒有戰役。');
    }
    final buf = StringBuffer('戰役 ${c.id}（${c.phase.name}）\n');
    buf.writeln('目標：${c.objective}');
    buf.writeln('終點：${c.endpoint}');
    buf.writeln('驗收：${c.acceptance}');
    buf.writeln('關卡：${c.gatesPassed}/6');
    if (c.plan != null) buf.writeln('計畫：${c.plan}');
    final cost = c.cost;
    if (cost != null) {
      buf.writeln('試算：\$${cost.moneyCost} / ${cost.wallClock.inMinutes}分 / '
          '${cost.computeLoad}');
      if (cost.budgetCap != null) buf.writeln('上限：\$${cost.budgetCap}');
    }
    return AgentToolResult.success(buf.toString());
  }
}
