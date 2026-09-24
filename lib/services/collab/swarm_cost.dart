// swarm_cost.dart
// [TRIO M4 2026-09-22] G5 成本試算——歷史均量為底，報數字必分解成分
//
// Blue 會計原則：試算表不給總額糊弄——金錢/時間/算力/失敗半徑四欄，
// 每欄分解成分（兵數×輪數×單價），資料源標明（歷史均量 vs 粗估單價）。
library;

import 'package:bridge_app/services/api_usage_tracker.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';

/// 每百萬 token 粗估單價（USD）——input/output 合併粗糙估計。
/// ★ 這是「粗估」非帳單——戰後對帳以 BudgetLedger 實際記錄為準。
const Map<String, double> kPricePerMTok = {
  'glm': 1.0,
  'openai': 8.0,
  'kimi': 1.2,
  'claude': 6.0,
  'gemini': 2.0,
  'local': 0.0, // 本地模型燒電費不燒 token 費
};

/// 單一軍的試算成分
class LegionCostLine {
  final String name;
  final int troops;
  final int turnsPerTroop; // 預估每兵輪數
  final String provider;
  final double tokensPerRequest; // 歷史均量（真值）或 fallback 估計
  final bool fromHistory; // tokensPerRequest 是否來自真實歷史
  final double moneyUsd;
  final Duration wallClock;

  const LegionCostLine({
    required this.name,
    required this.troops,
    required this.turnsPerTroop,
    required this.provider,
    required this.tokensPerRequest,
    required this.fromHistory,
    required this.moneyUsd,
    required this.wallClock,
  });
}

/// 一場戰役的完整試算
class CampaignCostSheet {
  final List<LegionCostLine> lines;
  final double totalMoneyUsd;
  final Duration totalWallClock;
  final double? budgetCap;
  final String failureRadius; // 文字描述（喊停已燒/重打全額）

  const CampaignCostSheet({
    required this.lines,
    required this.totalMoneyUsd,
    required this.totalWallClock,
    this.budgetCap,
    required this.failureRadius,
  });

  /// 分解明細文字（對話中呈現用——Blue 會計原則）
  String breakdown() {
    final buf = StringBuffer('📋 成本試算表\n');
    for (final l in lines) {
      buf.writeln('・${l.name}：${l.troops}兵 × ${l.turnsPerTroop}輪 × '
          '${l.tokensPerRequest.toStringAsFixed(0)} tok/req'
          '${l.fromHistory ? '（歷史均量）' : '（粗估）'}'
          ' [${l.provider}] = \$${l.moneyUsd.toStringAsFixed(2)}，'
          '${l.wallClock.inMinutes} 分');
    }
    buf.writeln('合計：\$${totalMoneyUsd.toStringAsFixed(2)}／'
        '${totalWallClock.inMinutes} 分');
    if (budgetCap != null) {
      buf.writeln('上限：\$${budgetCap!}（超出即停戰回報）');
    }
    buf.writeln('失敗半徑：$failureRadius');
    return buf.toString();
  }
}

/// 試算引擎
class SwarmCostEstimator {
  /// [legionSpecs] 每軍（名/兵數/輪數/provider）
  /// [secondsPerTurn] 每輪牆鐘秒數估計（並行下以最長軍為準的粗估）
  static CampaignCostSheet estimate({
    required List<({String name, int troops, int turns, String provider})>
        legionSpecs,
    double? budgetCap,
    int secondsPerTurn = 45,
  }) {
    final tracker = ApiUsageTracker.instance;

    final lines = <LegionCostLine>[];
    double totalMoney = 0;
    int maxSerialSeconds = 0; // 並行：瓶頸軍決定牆鐘

    for (final spec in legionSpecs) {
      // 歷史均量：該 provider 今日每請求平均 token（真值優先）
      var tokensPerReq = 0.0;
      var fromHistory = false;
      try {
        final today = tracker.getTodaySummary();
        final prov = today.where((p) => p.provider == spec.provider).toList();
        if (prov.isNotEmpty && prov.first.requestCount > 0) {
          tokensPerReq = prov.first.totalTokens / prov.first.requestCount;
          fromHistory = tokensPerReq > 0;
        }
      } catch (_) {}
      if (!fromHistory) {
        tokensPerReq = 3000; // 無歷史時的保守粗估
      }

      final price = kPricePerMTok[spec.provider] ?? 2.0;
      final requests = spec.troops * spec.turns;
      final money =
          requests * tokensPerReq / 1000000 * price; // 分解：數×量×單價
      final seconds = spec.turns * secondsPerTurn; // 軍內序列
      if (seconds > maxSerialSeconds) maxSerialSeconds = seconds;

      lines.add(LegionCostLine(
        name: spec.name,
        troops: spec.troops,
        turnsPerTroop: spec.turns,
        provider: spec.provider,
        tokensPerRequest: tokensPerReq,
        fromHistory: fromHistory,
        moneyUsd: money,
        wallClock: Duration(seconds: seconds),
      ));
      totalMoney += money;
    }

    // 失敗半徑：全額重打 = 2×；中停按已跑比例
    final failureRadius =
        '中途喊停按已跑比例計；全軍重打一次 = \$${(totalMoney * 2).toStringAsFixed(2)}';

    return CampaignCostSheet(
      lines: lines,
      totalMoneyUsd: totalMoney,
      totalWallClock: Duration(seconds: maxSerialSeconds),
      budgetCap: budgetCap,
      failureRadius: failureRadius,
    );
  }

  /// 把試算表寫進戰役（G5 產物）
  static CostEstimate toCostEstimate(CampaignCostSheet sheet) => CostEstimate(
        moneyCost: sheet.totalMoneyUsd,
        wallClock: sheet.totalWallClock,
        computeLoad: sheet.lines
            .map((l) => '${l.name}:${l.provider}×${l.troops}')
            .join(' '),
        failureRadius: sheet.failureRadius,
        budgetCap: sheet.budgetCap,
      );
}
