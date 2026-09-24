// swarm_campaign.dart
// [TRIO M4 2026-09-22] 蜂群作戰戰役——開戰閘門狀態機
//
// Blue 9/22 兩道令（AGENT_TRIO_COLLAB_SPEC §六 v0.3）：
//   1. 以終為始：沒有可驗證終點的戰爭不開打（G1）
//   2. 打破砂鍋問到底：六關全過才 committed（G6 雙向零疑問）
//   3. 成本代價評估：帳算不清的不開戰（G5 試算表）
//
// 鐵則：**planning 期 delegate_batch 硬拒絕**——不是 prompt 叮嚀，
// 是程式碼擋住。committed 之前任何 spawn 都是違規。
library;

import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/collab/swarm_recorder.dart'; // [M5b] 記錄器

/// 戰役六關
enum SwarmGate {
  g1Endpoint, // 終點定義（以終為始）
  g2Intent, // 作戰意圖對齊
  g3Plan, // 作戰計畫
  g4Map, // 作戰地圖（畫布）
  g5Cost, // 戰術武器＋成本試算
  g6ZeroDoubt, // 雙向零疑問
}

extension SwarmGateLabel on SwarmGate {
  String get label => switch (this) {
        SwarmGate.g1Endpoint => '終點定義',
        SwarmGate.g2Intent => '意圖對齊',
        SwarmGate.g3Plan => '作戰計畫',
        SwarmGate.g4Map => '作戰地圖',
        SwarmGate.g5Cost => '成本試算',
        SwarmGate.g6ZeroDoubt => '雙向零疑問',
      };
}

/// 戰役生命週期
enum SwarmPhase { planning, committed, running, reviewing, done, aborted }

/// 成本試算表（G5）——四欄＋上限
class CostEstimate {
  final double moneyCost; // 金錢（雲端腦 token 費，美元）
  final Duration wallClock; // 牆鐘時間估計
  final String computeLoad; // 算力（DGX 佔用描述）
  final String failureRadius; // 失敗半徑（喊停已燒多少、重打全額多少）
  final double? budgetCap; // 花費上限（null = 未設）

  const CostEstimate({
    required this.moneyCost,
    required this.wallClock,
    required this.computeLoad,
    required this.failureRadius,
    this.budgetCap,
  });
}

/// 戰後對帳
class CostActual {
  final double moneySpent;
  final Duration wallClockActual;
  const CostActual({required this.moneySpent, required this.wallClockActual});
}

/// 一場蜂群戰役
class SwarmCampaign extends ChangeNotifier {
  final String id;
  final String objective; // 原始目標（使用者白話）
  final String endpoint; // G1：可驗證終點現實
  final String acceptance; // G1：驗收方式
  SwarmPhase phase = SwarmPhase.planning;

  /// 已過的關（按序累積——G3 過了代表 G1G2G3 都過了）
  int gatesPassed = 0;

  String? plan; // G3：作戰計畫（幾軍/任務/依賴/兵力）
  String? mapCanvasId; // G4：作戰地圖畫布
  CostEstimate? cost; // G5：試算表
  CostActual? actual; // 戰後對帳

  SwarmCampaign({
    required this.id,
    required this.objective,
    required this.endpoint,
    required this.acceptance,
  });

  bool get isCommitted => phase == SwarmPhase.committed ||
      phase == SwarmPhase.running ||
      phase == SwarmPhase.reviewing;

  /// 過下一關（gatesPassed+1）。六關全過 → 自動進 committed
  /// （committed 仍需使用者最後點頭——見 [commit]）
  void passGate() {
    if (phase != SwarmPhase.planning) return;
    gatesPassed = (gatesPassed + 1).clamp(0, SwarmGate.values.length);
    notifyListeners();
  }

  /// 全關通過後，使用者點頭開戰
  bool commit() {
    if (gatesPassed < SwarmGate.values.length) {
      debugPrint('[SwarmCampaign] 拒絕 commit——只過了 $gatesPassed/6 關');
      return false;
    }
    phase = SwarmPhase.committed;
    notifyListeners();
    return true;
  }

  /// 棄案（planning 任何時刻——零成本零殘留）
  void abort(String reason) {
    phase = SwarmPhase.aborted;
    debugPrint('[SwarmCampaign] $id 棄案：$reason');
    notifyListeners();
  }
}

/// 戰役指揮部（singleton）——同一時間只有一場活躍戰役
///
/// delegate_batch 的守衛在這裡：[assertMaySpawn]。
/// 沒有活躍戰役時 spawn 允許（單次小規模 delegate_batch 是既有功能，
/// 不該被閘門卡死——閘門管的是「蜂群作戰」）。
class SwarmCommand extends ChangeNotifier {
  SwarmCommand._();
  static SwarmCommand? _instance;
  static SwarmCommand get instance => _instance ??= SwarmCommand._();

  @visibleForTesting
  static void resetForTest() => _instance = SwarmCommand._();

  SwarmCampaign? _active;

  /// 活躍戰役（planning/committed/running/reviewing）
  SwarmCampaign? get active => _active;

  // [M5b] 戰役記錄器（作戰=數位資產——commit 起錄、全事件 append）
  final Map<String, SwarmRecorder> _recorders = {};
  SwarmRecorder recorderFor(String campaignId) =>
      _recorders.putIfAbsent(campaignId, () => SwarmRecorder(campaignId));

  /// 開新戰役（進 planning）——若已有活躍戰役先問（回 null 表示衝突）
  SwarmCampaign? openCampaign({
    required String objective,
    required String endpoint,
    required String acceptance,
  }) {
    if (_active != null && _active!.phase != SwarmPhase.done &&
        _active!.phase != SwarmPhase.aborted) {
      return null; // 一次一場——多目標先打完或棄案
    }
    _active = SwarmCampaign(
      id: 'swarm-${DateTime.now().millisecondsSinceEpoch}',
      objective: objective,
      endpoint: endpoint,
      acceptance: acceptance,
    );
    notifyListeners();
    return _active;
  }

  /// ★ 閘門守衛——delegate_batch 呼叫前必過此關
  ///
  /// 回傳 null = 允許 spawn；回傳字串 = 拒絕原因（誠實回給 LLM）
  String? assertMaySpawn({required int troopCount}) {
    final c = _active;
    if (c == null) return null; // 無戰役——小規模既有功能，放行

    switch (c.phase) {
      case SwarmPhase.planning:
        return '作戰計畫未過閘門（${c.gatesPassed}/6 關已過，phase=planning）。'
            '蜂群作戰中禁止派兵——請先完成六關：終點定義/意圖對齊/計畫/'
            '地圖/成本試算/雙向零疑問，由使用者點頭 commit 後才可 spawn。';
      case SwarmPhase.committed:
      case SwarmPhase.running:
        if (troopCount > 100) {
          return '兵力超過上限（請求 $troopCount，上限 100）——D1 指揮鏈 '
              'span of control 設計：單戰役兵力上限 100。';
        }
        return null; // 開戰了——放行
      case SwarmPhase.reviewing:
      case SwarmPhase.done:
      case SwarmPhase.aborted:
        return '戰役已收兵（phase=${c.phase.name}）——不可再派兵。'
            '新目標請開新戰役。';
    }
  }

  /// 戰役結案
  void closeCampaign({required CostActual actual}) {
    _active?.actual = actual;
    if (_active != null) _active!.phase = SwarmPhase.done;
    notifyListeners();
  }
}
