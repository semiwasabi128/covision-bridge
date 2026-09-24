// agent_status_store.dart
// [TRIO M1 2026-09-22] 狀態單一真相源——D1（PHASE_G_TIMELINE §3.6）落地。
//
// 鐵則（詞彙表跟 Orca 借概念，禁用同義詞）：
//   live         —— 正在執行（引擎回報心跳）
//   unverifiable —— 無法驗證（App 重啟後 session 還在但 Loop 已斷；
//                    斷線 ≠ 死亡）
//   exited       —— 已離場（delivered / failed / cancelled，帶原因）
//
// 寫入方：TaskDispatcher（狀態轉移時）；未來 agent_loop / bridge-cli / cron。
// 讀取方：sidebar / 任務卡 / 懸浮窗 / 系統列 /（未來手機）——全部只訂閱，
// 不複製狀態。10 人 100 人同一套。
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Agent 生命三態——禁用同義詞（斷線≠死亡）
enum AgentRunState { live, unverifiable, exited }

class AgentStatus {
  final String agentId;
  final AgentRunState state;
  final String? sessionId; // 關聯任務（同一 agent 可輪替多任務）
  final String? detail; // exited 帶原因；live 帶任務標題
  final DateTime at;

  const AgentStatus({
    required this.agentId,
    required this.state,
    this.sessionId,
    this.detail,
    required this.at,
  });

  AgentStatus copyWith({
    AgentRunState? state,
    String? sessionId,
    String? detail,
    DateTime? at,
  }) =>
      AgentStatus(
        agentId: agentId,
        state: state ?? this.state,
        sessionId: sessionId ?? this.sessionId,
        detail: detail ?? this.detail,
        at: at ?? this.at,
      );

  @override
  String toString() =>
      'AgentStatus($agentId, ${state.name}, session=${sessionId ?? '-'}, '
      'detail=${detail ?? '-'}, at=$at)';
}

/// 狀態單一真相源（singleton——TaskDispatcher 同模式）
class AgentStatusStore extends ChangeNotifier {
  AgentStatusStore._();
  static AgentStatusStore? _instance;
  static AgentStatusStore get instance => _instance ??= AgentStatusStore._();

  /// [測試用] 重置 singleton（CausalLedger.resetForTest 慣例）
  @visibleForTesting
  static void resetForTest() => _instance = AgentStatusStore._();

  final Map<String, AgentStatus> _byAgent = {};

  /// 廣播流——非 Widget 讀取者（未來 CLI / 手機 relay）訂閱這個
  final _controller = StreamController<AgentStatus>.broadcast();
  Stream<AgentStatus> get changes => _controller.stream;

  /// 唯讀快照（Widget 用 ChangeNotifier；非 Widget 用 changes 流）
  List<AgentStatus> get snapshot => List.unmodifiable(_byAgent.values);

  AgentStatus? statusOf(String agentId) => _byAgent[agentId];

  /// 冪等寫入——同一狀態重複寫不觸發事件（防抖）
  void _put(AgentStatus status) {
    final prev = _byAgent[status.agentId];
    if (prev != null &&
        prev.state == status.state &&
        prev.sessionId == status.sessionId &&
        prev.detail == status.detail) {
      return;
    }
    _byAgent[status.agentId] = status;
    _controller.add(status);
    notifyListeners();
  }

  /// Agent 開始執行任務
  void setLive(String agentId, {String? sessionId, String? detail}) =>
      _put(AgentStatus(
        agentId: agentId,
        state: AgentRunState.live,
        sessionId: sessionId,
        detail: detail,
        at: DateTime.now(),
      ));

  /// 無法驗證（App 重啟、Loop 斷線但 session 殘留）
  void setUnverifiable(String agentId, {String? sessionId, String? detail}) =>
      _put(AgentStatus(
        agentId: agentId,
        state: AgentRunState.unverifiable,
        sessionId: sessionId,
        detail: detail,
        at: DateTime.now(),
      ));

  /// 已離場（delivered / failed / cancelled——detail 帶原因）
  void setExited(String agentId, {String? sessionId, String? detail}) =>
      _put(AgentStatus(
        agentId: agentId,
        state: AgentRunState.exited,
        sessionId: sessionId,
        detail: detail,
        at: DateTime.now(),
      ));

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}
