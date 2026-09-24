// compass_tools.dart
// 羅盤的 Agent 工具——讓 Agent 能讀羅盤、提議改規則，但不可靜默覆寫。
//
// 治理（docs/specs/2026-09-06-compass-system.md §7）：
// - compass_read / propose_rule_change / read_organ / list_organs
// - Agent 走 propose（不直接 update）→ 寫入 compass_rule_changes 並標 author=agent
// - 行為規則的 propose 自動進 pendingApply；視覺規則的 propose 直接生效

import 'dart:async';
import 'dart:convert';

import 'compass_models.dart';
import 'compass_store.dart';

/// Agent 提議（不直接寫入 store；先寫入「待人決定」佇列）
class CompassProposal {
  final String id;
  final String ruleId;
  final Map<String, dynamic> newParams;
  final String author;
  final DateTime at;
  final String reason;
  final CompassRuleStatus resultingStatus;

  const CompassProposal({
    required this.id,
    required this.ruleId,
    required this.newParams,
    required this.author,
    required this.at,
    required this.reason,
    required this.resultingStatus,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleId': ruleId,
        'newParams': newParams,
        'author': author,
        'at': at.toIso8601String(),
        'reason': reason,
        'resultingStatus': resultingStatus.name,
      };
}

/// Agent 工具集合（給 agent_loop 註冊用）
class CompassAgentTools {
  final CompassStore store;
  final _proposals = <String, CompassProposal>{};
  final _proposalStream = StreamController<CompassProposal>.broadcast();

  CompassAgentTools(this.store);

  Stream<CompassProposal> get proposalStream => _proposalStream.stream;

  /// 列出所有器官（摘要）
  List<Map<String, dynamic>> listOrgans() {
    return store.organs().map((o) => {
          'id': o.id,
          'systemGroup': o.systemGroup,
          'name': o.name,
          'anchorOk': o.anchorOk,
          'ruleCount': store.rules(organId: o.id).length,
        }).toList();
  }

  /// 讀單一器官（含意義層 + 規則卡 + 陷阱）
  Map<String, dynamic>? readOrgan(String organId) {
    final organs = store.organs();
    final o = organs.firstWhere(
      (x) => x.id == organId,
      orElse: () => const CompassOrgan(
          id: '', systemGroup: '', name: ''),
    );
    if (o.id.isEmpty) return null;
    return {
      'organ': {
        'id': o.id,
        'systemGroup': o.systemGroup,
        'name': o.name,
        'anchorOk': o.anchorOk,
        'paths': o.facts.paths,
      },
      'meanings': store
          .meaningsOf(organId)
          .map((k, v) => MapEntry(k, {'value': v.value, 'author': v.author})),
      'rules': store.rules(organId: organId).map((r) => {
            'id': r.id,
            'description': r.description,
            'why': r.why,
            'params': r.params,
            'kind': r.kind.name,
            'status': r.status.name,
            'updatedBy': r.updatedBy,
            'updatedAt': r.updatedAt.toIso8601String(),
          }).toList(),
      'pitfalls': store.pitfalls(organId).map((p) => p.text).toList(),
    };
  }

  /// Agent 提議改規則（不直接覆寫）
  /// - visual 規則的提議 = 直接生效並廣播
  /// - behavioral 規則的提議 = 進 pendingApply 等人 apply
  /// 回傳 CompassProposal；UI 端訂閱 proposalStream 看到新提議
  CompassProposal proposeRuleChange({
    required String ruleId,
    required Map<String, dynamic> newParams,
    required String reason,
    required String agentAuthor,
  }) {
    if (!agentAuthor.startsWith('agent:')) {
      throw StateError('此方法僅限 agent 呼叫（$agentAuthor）');
    }
    final existing = store.rule(ruleId);
    if (existing == null) {
      throw StateError('規則 $ruleId 不存在');
    }

    final id = 'prop_${DateTime.now().millisecondsSinceEpoch}';
    final pending = CompassRuleStatus.pendingApply;

    // 視覺規則：Agent 提議 = 直接寫入 store（白名單制放行）
    if (existing.kind == CompassRuleKind.visual) {
      store.updateRuleParams(ruleId,
          newParams: newParams, author: agentAuthor, reason: reason);
      final p = CompassProposal(
        id: id,
        ruleId: ruleId,
        newParams: newParams,
        author: agentAuthor,
        at: DateTime.now(),
        reason: reason,
        resultingStatus: CompassRuleStatus.active,
      );
      _proposals[id] = p;
      _proposalStream.add(p);
      return p;
    }

    // 行為規則：寫入 store 但 pendingApply，等人 applyRule 才生效
    store.updateRuleParams(ruleId,
        newParams: newParams, author: agentAuthor, reason: reason);
    final p = CompassProposal(
      id: id,
      ruleId: ruleId,
      newParams: newParams,
      author: agentAuthor,
      at: DateTime.now(),
      reason: reason,
      resultingStatus: pending,
    );
    _proposals[id] = p;
    _proposalStream.add(p);
    return p;
  }

  /// 列出最近提議（供人類決定）
  List<Map<String, dynamic>> pendingProposals() {
    return _proposals.values
        .where((p) => p.resultingStatus == CompassRuleStatus.pendingApply)
        .map((p) => p.toJson())
        .toList()
        .reversed
        .toList();
  }

  /// JSON 摘要（注入 Agent system prompt 用；不超過 ~500 token）
  String summary() {
    final organs = store.organs();
    final rules = store.rules();
    return jsonEncode({
      'version': store.version,
      'organCount': organs.length,
      'ruleCount': rules.length,
      'pendingProposals': pendingProposals().length,
      'topRules': rules.take(8).map((r) => {
            'id': r.id,
            'params': r.params,
            'kind': r.kind.name,
          }).toList(),
    });
  }
}
