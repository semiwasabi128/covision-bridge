// swarm_harvest.dart
// [TRIO M5b 2026-09-23] 戰後分析——計畫 vs 實際（Blue 令：貼合作戰計畫
// 與預期作戰收益，不是死的固定格式，不是流水帳）
//
// 形狀：AfterActionReport（AAR）
//   1. 計畫側：G3 計畫（legions/兵力/依賴）＋G5 試算（成本/時間/收益預期）
//   2. 實際側：SwarmRecorder 事件流統計（各軍實績/實際成本/實際耗時）
//   3. 偏差表：逐項 expected vs actual＋delta＋歸因（數據自帶，敘事由指揮官補）
//   4. 收益判定：endpoint 達成與否（end 事件 outcome）＋acceptance 對照
//   5. 三養分卡：從「最大偏差」萃取（成功/失敗/遺憾）——不是逐事件流水
//
// 入樹：AAR 走 LifeTreeStore 既有寫入口（歷史樹=戰役卡；反思素材=養分卡）
// ——入樹前問 Blue（主權拍板 2026-09-23）。
library;

import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/collab/swarm_recorder.dart';
import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/causal/causal_ledger_service.dart' show CausalEntry, CausalLedger;
import 'package:bridge_app/services/life_tree/life_tree_store.dart';

/// 單行偏差（expected vs actual）
class DeviationRow {
  final String item; // 項目（如「研究軍 成功率」「總成本」「牆鐘」）
  final String expected; // 計畫/試算值
  final String actual; // 實際值
  final double? deltaPct; // 偏差百分比（可算才給）
  final String note; // 歸因線索（事件數據；結論由指揮官統籌）

  const DeviationRow({
    required this.item,
    required this.expected,
    required this.actual,
    this.deltaPct,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'item': item,
        'expected': expected,
        'actual': actual,
        if (deltaPct != null) 'deltaPct': deltaPct,
        'note': note,
      };
}

/// 養分卡（≤3/戰役——從最大偏差萃取，非流水帳）
class NutrientCard {
  final String kind; // success / fail / regret
  final String content;
  final String evidence; // 事件證據（哪個偏差撐起這張卡）

  const NutrientCard({
    required this.kind,
    required this.content,
    required this.evidence,
  });

  Map<String, dynamic> toJson() =>
      {'kind': kind, 'content': content, 'evidence': evidence};
}

/// 戰後分析報告（AAR）
class AfterActionReport {
  final String campaignId;
  final String objective;
  final String endpoint;
  final String acceptance;
  final Map<String, dynamic> planSummary; // G3+G5 計畫側
  final Map<String, dynamic> actualSummary; // 事件流實際側
  final List<DeviationRow> deviations; // 偏差表
  final String? outcome; // end 事件 outcome（done/aborted/…）
  final List<NutrientCard> nutrients; // ≤3

  const AfterActionReport({
    required this.campaignId,
    required this.objective,
    required this.endpoint,
    required this.acceptance,
    required this.planSummary,
    required this.actualSummary,
    required this.deviations,
    this.outcome,
    required this.nutrients,
  });

  Map<String, dynamic> toJson() => {
        'campaignId': campaignId,
        'objective': objective,
        'endpoint': endpoint,
        'acceptance': acceptance,
        'plan': planSummary,
        'actual': actualSummary,
        'deviations': deviations.map((d) => d.toJson()).toList(),
        'outcome': outcome,
        'nutrients': nutrients.map((n) => n.toJson()).toList(),
      };

  /// 複盤台呈現文字（星系側欄/對話注入用）
  String render() {
    final b = StringBuffer('📋 戰後分析（$campaignId）\n');
    b.writeln('目標：$objective');
    b.writeln('終點：$endpoint');
    b.writeln('驗收：$acceptance');
    b.writeln('結局：${outcome ?? '未收兵'}');
    b.writeln('\n── 計畫 vs 實際 ──');
    for (final d in deviations) {
      final delta = d.deltaPct == null
          ? ''
          : '（${d.deltaPct! >= 0 ? '+' : ''}${d.deltaPct!.toStringAsFixed(0)}%）';
      b.writeln('・${d.item}：${d.expected} → ${d.actual}$delta ${d.note}');
    }
    if (nutrients.isNotEmpty) {
      b.writeln('\n── 養分（入樹前需 Blue 點頭）──');
      for (final n in nutrients) {
        b.writeln('・[${n.kind}] ${n.content}');
      }
    }
    return b.toString();
  }
}

/// 戰後分析器——把計畫、試算、事件流對齊成 AAR
class SwarmHarvester {
/// [Blue 9/23 令] 成本核對：不只對數字，複盤「當初計算的方式」是否可信。
/// 無論符合或不符合都產出核對卡（入歷史樹＋反思樹——不沉默）。
static DeviationRow costMethodRow(SwarmCampaign c) {
  final est = c.cost;
  final act = c.actual;
  if (est == null || act == null) {
    return const DeviationRow(
      item: '成本核對',
      expected: '（無試算——本場未過 G5 就開打，方法面缺失）',
      actual: '（無對帳）',
      note: '流程違規信號：成本方法本身沒被建立',
    );
  }
  final pct = est.moneyCost > 0
      ? (act.moneySpent - est.moneyCost) / est.moneyCost * 100
      : null;
  String verdict;
  if (pct == null) {
    verdict = '試算為零成本（本地兵團）——無法對數字，方法可信度=免驗';
  } else if (pct.abs() <= 20) {
    verdict = '方法可信（偏差 ≤20%）——歷史均量估法維持';
  } else if (pct > 20) {
    verdict = '方法低估（+${pct.toStringAsFixed(0)}%）——下場試算把'
        '「每兵輪數」或「單請求 token 均量」上修';
  } else {
    verdict = '方法高估（${pct.toStringAsFixed(0)}%）——可放寬兵力或加輪數';
  }
  return DeviationRow(
    item: '成本核對（方法面）',
    expected: '試算 \$${est.moneyCost.toStringAsFixed(2)}'
        '（${est.failureRadius.contains('重打') ? '含失敗半徑條目' : '未含失敗半徑'}）',
    actual: '實際 \$${act.moneySpent.toStringAsFixed(2)}',
    deltaPct: pct,
    note: verdict,
  );
}

  /// 產出 AAR（純數據層——敘事統籌由指揮官 LLM 在此之上補，形狀不變）
  static AfterActionReport produce({
    required SwarmCampaign campaign,
    required List<SwarmEvent> events,
  }) {
    // ── 實際側統計 ──
    final spawns = events.where((e) => e.type == 'spawn').length;
    final ok = events.where((e) => e.type == 'success').length;
    final fail = events.where((e) => e.type == 'fail').length;
    final intelShares = events
        .where((e) => e.type == 'intel_share' || e.type == 'intel_refute')
        .length;
    final endEvent = events.where((e) => e.type == 'end').lastOrNull;
    final t0 = events.isNotEmpty ? events.first.t : null;
    final t1 = events.isNotEmpty ? events.last.t : null;
    final durationMs =
        (t0 != null && t1 != null) ? t1.difference(t0).inMilliseconds : 0;

    // per-legion 戰績（貼合計畫的軍團結構）
    final legions = <String, Map<String, int>>{};
    for (final e in events) {
      if (e.legion == null) continue;
      final l = legions.putIfAbsent(
          e.legion!, () => {'spawns': 0, 'success': 0, 'fail': 0});
      if (e.type == 'spawn') l['spawns'] = (l['spawns'] ?? 0) + 1;
      if (e.type == 'success') l['success'] = (l['success'] ?? 0) + 1;
      if (e.type == 'fail') l['fail'] = (l['fail'] ?? 0) + 1;
    }

    final actual = {
      'events': events.length,
      'spawns': spawns,
      'success': ok,
      'fail': fail,
      'intel': intelShares,
      'durationMs': durationMs,
      'legions': legions.map((k, v) => MapEntry(k, v)),
      'actualCostUsd': campaign.actual?.moneySpent,
    };

    // ── 偏差表（expected=計畫/試算；actual=事件流）──
    final dev = <DeviationRow>[];

    // [Blue 9/23 令] 成本核對（方法面）恆常第一行——無論符合與否都記錄，
    // 入歷史樹與反思樹的流程（見 SwarmHarvester.writeToLifeTree）
    dev.add(costMethodRow(campaign));

    // 成本：G5 試算 vs 戰後對帳
    final est = campaign.cost;
    final act = campaign.actual;
    if (est != null && act != null) {
      final pct = est.moneyCost > 0
          ? (act.moneySpent - est.moneyCost) / est.moneyCost * 100
          : null;
      dev.add(DeviationRow(
        item: '成本',
        expected: '\$${est.moneyCost.toStringAsFixed(2)}',
        actual: '\$${act.moneySpent.toStringAsFixed(2)}',
        deltaPct: pct,
        note: pct != null && pct > 50 ? '超出試算一半以上——查明哪軍超支' : '',
      ));
      dev.add(DeviationRow(
        item: '牆鐘',
        expected: '${est.wallClock.inMinutes} 分',
        actual: '${act.wallClockActual.inMinutes} 分',
        deltaPct: est.wallClock.inMinutes > 0
            ? (act.wallClockActual.inMinutes - est.wallClock.inMinutes) /
                est.wallClock.inMinutes *
                100
            : null,
      ));
    }

    // 成功率：計畫隱含（派兵即預期全成功）vs 實際
    if (spawns > 0) {
      final rate = ok / spawns * 100;
      dev.add(DeviationRow(
        item: '單兵成功率',
        expected: '100%（計畫即預期達成）',
        actual: '${rate.toStringAsFixed(0)}%（$ok/$spawns）',
        deltaPct: rate - 100,
        note: fail > 0 ? '失敗 $fail 次——失敗兵的 fail 事件帶原因' : '',
      ));
    }

    // 各軍戰績（貼合計畫結構——計畫有幾軍就列幾行）
    for (final entry in legions.entries) {
      final l = entry.value;
      final total = (l['success'] ?? 0) + (l['fail'] ?? 0);
      if (total == 0) continue;
      final rate = (l['success'] ?? 0) / total * 100;
      dev.add(DeviationRow(
        item: '${entry.key} 戰績',
        expected: '依計畫達成',
        actual: '${l['success'] ?? 0} 成 ${l['fail'] ?? 0} 敗'
            '（${rate.toStringAsFixed(0)}%）',
        note: (l['fail'] ?? 0) > (l['success'] ?? 0) ? '敗多於成——重點檢討對象' : '',
      ));
    }

    // ── 三養分卡（從最大偏差萃取——嚴禁流水帳）──
    final nutrients = <NutrientCard>[];
    // 1. 成功經驗：最佳軍（成功率最高且有成績）
    String? bestLegion;
    var bestRate = -1.0;
    legions.forEach((name, l) {
      final total = (l['success'] ?? 0) + (l['fail'] ?? 0);
      if (total == 0) return;
      final rate = (l['success'] ?? 0) / total * 100;
      if (rate > bestRate) {
        bestRate = rate;
        bestLegion = name;
      }
    });
    if (bestLegion != null && bestRate >= 80) {
      nutrients.add(NutrientCard(
        kind: 'success',
        content: '$bestLegion 打法有效（成功率 ${bestRate.toStringAsFixed(0)}%）'
            '——下次同型任務沿用其配置',
        evidence: '${bestLegion} 戰績行',
      ));
    }
    // 2. 失敗經驗：最痛偏差（成本超支>50% 或失敗率>30%）
    final costOver = dev.where((d) => (d.deltaPct ?? 0) > 50).toList();
    if (costOver.isNotEmpty) {
      nutrients.add(NutrientCard(
        kind: 'fail',
        content: '${costOver.first.item} 偏差 ${costOver.first.deltaPct!.toStringAsFixed(0)}%'
            '（${costOver.first.expected}→${costOver.first.actual}）'
            '——試算方法或執行控制要修',
        evidence: costOver.first.item,
      ));
    } else if (spawns > 0 && fail / spawns > 0.3) {
      nutrients.add(NutrientCard(
        kind: 'fail',
        content: '單兵失敗率 ${(fail / spawns * 100).toStringAsFixed(0)}%——'
            '高於三成，武器試射（G4）或兵力配置有問題',
        evidence: '單兵成功率行',
      ));
    }
    // 3. 遺憾經驗：情報池有人分享沒人採用（想給的沒被用）
    if (intelShares > 0 && ok > 0) {
      // 粗信號：intel 事件數 vs success 引用（引用計數在 intel 事件 data）
      final adopted = events
          .where((e) => e.type == 'success' && (e.data['usedIntel'] == true))
          .length;
      if (adopted == 0) {
        nutrients.add(NutrientCard(
          kind: 'regret',
          content: '情報池分享 $intelShares 筆但無兵回報採用——'
              '派工注入（intel_read）可能沒落實，下場查',
          evidence: 'intel 事件 vs success 事件',
        ));
      }
    }

    // 收益判定
    final outcome = endEvent?.data['outcome'] as String?;

    return AfterActionReport(
      campaignId: campaign.id,
      objective: campaign.objective,
      endpoint: campaign.endpoint,
      acceptance: campaign.acceptance,
      planSummary: {
        'plan': campaign.plan,
        'estimatedCost': est?.moneyCost,
        'estimatedMinutes': est?.wallClock.inMinutes,
        'budgetCap': est?.budgetCap,
      },
      actualSummary: actual,
      deviations: dev,
      outcome: outcome,
      nutrients: nutrients.take(3).toList(), // 硬上限——寧缺勿濫
    );
  }

  // ═══ [Blue 9/23 令] 入樹：無論符合或不符合都記錄歷史樹與反思樹 ═══
  // 歷史樹（agent_causal_ledger）：戰役卡＋成本核對卡
  // 反思樹（life_tree_dreams 議程素材）：三養分卡＋成本方法結論
  /// 把 AAR 寫進生命樹（入樹前需 Blue 點頭——主權拍板）
  static Future<bool> writeToLifeTree(AfterActionReport aar) async {
    try {
      // 1. 歷史樹：戰役執行卡
      
      CausalLedger.instance.record(CausalEntry(
        toolName: 'swarm_campaign',
        intervention: aar.objective,
        contextDigest: '終點:${aar.endpoint}｜驗收:${aar.acceptance}',
        observedOutcome: '結局:${aar.outcome ?? "?"}｜'
            '實際:${(aar.actualSummary['success'] ?? 0)}成'
            '${(aar.actualSummary['fail'] ?? 0)}敗｜'
            '成本:${aar.deviations.where((d) => d.item == '成本核對（方法面）').firstOrNull?.note ?? "?"}',
        success: aar.outcome == 'done',
        companionId: 'swarm_commander',
        at: DateTime.now(),
      ));
      // 2. 反思樹：養分卡入夢境議程素材（LifeTreeStore.addDream
      //    是夢境結論寫入口；議程素材走 sourceClues）
      final store = LifeTreeStore.instance;
      store.addDream(LifeTreeDream(
        dreamSessionId: 'swarm_${aar.campaignId}',
        branchType: 'agent_consensus',
        conclusion: aar.nutrients.map((n) => '[${n.kind}] ${n.content}').join('；')
            .isEmpty ? '（無養分卡——本場無顯著偏差）'
            : aar.nutrients.map((n) => '[${n.kind}] ${n.content}').join('；'),
        decision: 'maintain',
        sourceClues: [
          '成本核對:${aar.deviations.where((d) => d.item == '成本核對（方法面）').firstOrNull?.note ?? "無"}',
          '戰役:${aar.campaignId}',
        ],
        companionIds: const ['swarm_commander'],
        createdAt: DateTime.now(),
      ));
      return true;
    } catch (e) {
      debugPrint('[SwarmHarvest] 入樹失敗（fail-open）: $e');
      return false;
    }
  }
}

