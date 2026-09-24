// intel_tools.dart
// [TRIO M2 2026-09-22] 情報工具組——agent 的情報讀寫介面
//
//   intel_share   寫入：工作中發現坑/線索/外部情報/成果預告
//   intel_read    讀取：拿別人未消化的情報（派工後先讀再動工）
//   intel_refute 推翻：發現情報有誤——標記而非抹除
library;

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/collab/intel_pool.dart';
import 'package:bridge_app/services/companion_store.dart';

/// 當前 agent 身份——registry 不帶身份，從 CompanionStore 活躍夥伴取
/// （與 chat_controller 切夥伴同一真相源；fallback 'unknown' 誠實標記）
String _currentAgentId() =>
    CompanionStore().activeCompanionId ?? 'unknown';

/// 寫入情報
class IntelShareTool extends AgentTool {
  @override
  String get name => 'intel_share';

  @override
  String get description =>
      '把工作中發現的情報寫進共享情報池，讓其他夥伴不用重踩。'
      '種類：pit=坑（會踩雷的警告）、lead=線索（值得追的方向）、'
      'external=外部情報（網路/文件查到的事）、preview=成果預告';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'kind',
            description: '情報種類：pit/lead/external/preview（禁同義詞）',
            required: true),
        AgentToolParamSpec(
            name: 'content', description: '情報內容（一句話講清楚）', required: true),
        AgentToolParamSpec(
            name: 'session_id', description: '關聯任務 sessionId（選填）'),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final kindStr = args['kind'] as String? ?? '';
    final kind = IntelKind.values
        .where((k) => k.name == kindStr)
        .firstOrNull;
    if (kind == null) {
      return AgentToolResult.failure(
          'kind 必須是 pit/lead/external/preview 其中之一（收到：$kindStr）');
    }
    final content = (args['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) {
      return AgentToolResult.failure('content 不可為空');
    }
    final entry = await IntelPool.instance.share(
      fromAgent: _currentAgentId(),
      kind: kind,
      content: content,
      relatedSession: args['session_id'] as String?,
    );
    return AgentToolResult.success(
        '已入池［${kind.label}］：${entry.id}——其他夥伴派工前會看到');
  }
}

/// 讀取未消化情報
class IntelReadTool extends AgentTool {
  @override
  String get name => 'intel_read';

  @override
  String get description =>
      '讀共享情報池裡其他夥伴留下、你還沒消化的情報。'
      '建議動工前先讀——甲踩過的坑你不用再踩。讀完自動標記消化';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'kind',
            description: '只看某種類：pit/lead/external/preview（選填，全讀略過）'),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final me = _currentAgentId();
    final kindFilter = args['kind'] as String?;
    var list = await IntelPool.instance.unconsumedBy(me);
    if (kindFilter != null && kindFilter.isNotEmpty) {
      final k = IntelKind.values
          .where((x) => x.name == kindFilter)
          .firstOrNull;
      if (k != null) list = list.where((e) => e.kind == k).toList();
    }
    if (list.isEmpty) {
      return AgentToolResult.success('情報池沒有你要消化的事（空池或已讀完）');
    }
    // 讀取即消化——讀過就標記（讀了不用再讀）
    for (final e in list) {
      await IntelPool.instance.markConsumed(e.id, me);
    }
    final buf = StringBuffer();
    for (final e in list) {
      buf.writeln('［${e.kind.label}］${e.content}');
      buf.writeln('  （${e.fromAgent} 留下，'
          '${e.createdAt.month}/${e.createdAt.day}）');
    }
    return AgentToolResult.success(
        '讀到 ${list.length} 筆情報（已標記消化）：\n$buf');
  }
}

/// 推翻情報——錯誤情報不抹除，標記取代
class IntelRefuteTool extends AgentTool {
  @override
  String get name => 'intel_refute';

  @override
  String get description =>
      '推翻情報池裡的一筆情報（發現它錯了/過期了）。'
      '需要 intel_read 回覆中的情報編號（intel- 開頭）。情報不會被刪除，'
      '只會被標記推翻（誰推翻的可考）';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
            name: 'intel_id',
            description: '情報編號（intel- 開頭，從 intel_read 結果拿）',
            required: true),
        AgentToolParamSpec(name: 'reason', description: '推翻理由', required: true),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final id = args['intel_id'] as String? ?? '';
    final reason = args['reason'] as String? ?? '';
    if (id.isEmpty || reason.isEmpty) {
      return AgentToolResult.failure('intel_id 與 reason 都必填');
    }
    final exists = IntelPool.instance.entries.any((e) => e.id == id);
    if (!exists) {
      return AgentToolResult.failure('找不到情報 $id（可能已被推翻或不存在）');
    }
    await IntelPool.instance.refute(id, _currentAgentId());
    return AgentToolResult.success('已推翻 $id（理由：$reason）——'
        '原文保留在池中，誰推翻的可考');
  }
}
