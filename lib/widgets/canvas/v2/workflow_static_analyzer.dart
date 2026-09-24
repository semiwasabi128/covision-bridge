// workflow_static_analyzer.dart
// [教練 Agent 2026-08-15 使用者 提案] 工作流靜態分析器——零 token 的 dry-run。
//
// 「測試」按鈕背後的引擎：不呼叫任何 LLM、不消耗 token，
// 純結構分析找斷流/邏輯問題。結果由 agent 在對話框裡與使用者互動解讀。
//
// 檢查項目：
// 1. 斷流：input 節點內容為空 → 整條鏈拿不到東西
// 2. 孤兒節點：沒有連入也沒有連出的節點（游离在流程外）
// 3. 缺 output：沒有任何 output 節點 → 跑完沒有出口
// 4. type mismatch：連線兩端型別不符（繞過 UI 驗證的舊資料）
// 5. prompt 未設：llm/imageGen/videoGen/musicGen 的 prompt 是空的
// 6. 循環：A→B→A（執行會死圈）
// 7. condition 分支懸空：true/false 出線一條都沒接

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/widgets/canvas/v2/node_connection.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart' show NodeTypePorts;

/// 單一檢查結果
class WorkflowIssue {
  final String severity; // 'error' | 'warn' | 'info'
  final String nodeId;   // 相關節點（可空）
  final String message;  // 人類可讀描述

  const WorkflowIssue(this.severity, this.nodeId, this.message);

  bool get isError => severity == 'error';
  bool get isWarn => severity == 'warn';

  Map<String, dynamic> toJson() => {'severity': severity, 'nodeId': nodeId, 'message': message};
}

/// 分析報告
class WorkflowAnalysisReport {
  final List<WorkflowIssue> issues;
  final int nodeCount;
  final int connectionCount;

  const WorkflowAnalysisReport(this.issues, this.nodeCount, this.connectionCount);

  bool get hasErrors => issues.any((i) => i.isError);
  bool get hasWarns => issues.any((i) => i.isWarn);
}

/// 靜態分析器
class WorkflowStaticAnalyzer {
  /// 執行分析（純結構，零 token）
  /// [allNodeIds] = 畫布上全部節點（含標注/非 workflow 節點）——
  /// 殘留連線檢查用。若不傳，退回 nodesData 的鍵。
  static WorkflowAnalysisReport analyze({
    required Map<String, dynamic> nodesData, // nodeId -> {nodeType, params, label}
    required List<NodeConnection> connections,
    Set<String>? allNodeIds,
  }) {
    final issues = <WorkflowIssue>[];
    final nodes = nodesData;
    final nodeUniverse = allNodeIds ?? nodes.keys.toSet();

    // 收集連線關係
    final hasIncoming = <String>{};
    final hasOutgoing = <String>{};
    for (final c in connections) {
      hasIncoming.add(c.toNodeId);
      hasOutgoing.add(c.fromNodeId);
    }

    String? label(String id) => nodes[id]?['label']?.toString();
    String? type(String id) => nodes[id]?['nodeType']?.toString();

    // 1. input 節點內容為空
    for (final id in nodes.keys) {
      if (type(id) == 'input') {
        final content = nodes[id]?['params']?['content']?.toString() ?? '';
        if (content.trim().isEmpty) {
          issues.add(WorkflowIssue('warn', id,
              '輸入節點「${label(id) ?? '輸入'}」的內容是空的——執行時這條鏈會拿到空字串。'));
        }
      }
    }

    // 2. 孤兒節點（單節點不算——input 本來就可能單獨存在等接線）
    for (final id in nodes.keys) {
      if (nodes.length <= 1) break;
      final t = type(id);
      if (t == null) continue; // 標注/塗鴉不算孤兒
      if (!hasIncoming.contains(id) && !hasOutgoing.contains(id)) {
        issues.add(WorkflowIssue('warn', id,
            '節點「${label(id) ?? id}」沒有任何連線——它是孤兒，不會被執行到。'));
      }
    }

    // 3. 缺 output
    final hasOutput = nodes.values.any((n) => n?['nodeType']?.toString() == 'output');
    if (!hasOutput && nodes.isNotEmpty) {
      issues.add(const WorkflowIssue(
          'error', '', '整個工作流沒有「輸出」節點——執行結果沒有出口。'));
    }

    // 4. 殘留連線（指向不存在的節點）
    // [教練 Agent 2026-08-15 使用者回饋修正] 用「全部節點」名單檢查（不只 workflow
    // 節點）——之前只拿 workflow 節點驗證，指向標注/塗鴉的連線被誤判
    // 「不存在」造成誤報。畫布操作本身不允許半接線，真正殘留極罕見。
    for (final c in connections) {
      if (!nodeUniverse.contains(c.toNodeId) ||
          !nodeUniverse.contains(c.fromNodeId)) {
        issues.add(WorkflowIssue('error', c.id,
            '有一條連線指向不存在的節點（殘留連線）——建議拔除。'));
      }
    }

    // 5. [教練 Agent 2026-08-15 使用者回饋修正] prompt 未設——
    // 任何節點只要有 prompt 欄位且值是空的，逐一列名提醒。
    // [使用者 二次回饋] 報告只顯示 input 空——因為模板載入的節點
    // params 可能只有 input 節點帶了 'content'。擴大檢查：
    // prompt 欄位「不存在」也算未設（模板沒填 prompt = 執行時空 prompt）。
    final promptNodes = <String>[];
    final placeholderOnlyNodes = <String>[]; // [使用者三次回饋] 純 {input} 佔位
    for (final id in nodes.keys) {
      final t = type(id);
      if (t == null) continue;
      // 有 prompt 概念的節點型別
      const promptTypes = [
        'llm', 'imageGen', 'videoGen', 'musicGen', 'tts', 'vision', 'tool'
      ];
      if (!promptTypes.contains(t)) continue;
      final params = nodes[id]?['params'];
      // [教練 Agent 2026-08-15 使用者 通盤檢討] TTS 的提示詞欄位叫 text 不叫
      // prompt——之前查 prompt 查不到就誤報「語音旁白 prompt 空」。
      final promptKey = (t == 'tts') ? 'text' : 'prompt';
      final prompt = params is Map ? params[promptKey]?.toString() ?? '' : '';
      final label_ = label(id) ?? t;
      if (prompt.trim().isEmpty) {
        promptNodes.add(label_);
      } else {
        // [教練 Agent 2026-08-15 使用者三次回饋] 純 {input} 佔位檢查——
        // prompt 移除 {input}/{text} 等佔位符與空白後沒剩半個字
        // = 使用者沒寫半句客製內容，全靠上游。列名提醒（比空低
        // 一級 severity：能跑，但生成結果不受控）。
        final stripped = prompt
            .replaceAll(RegExp(r'\{[^}]*\}'), '') // {input} {text} 等佔位符
            .replaceAll(RegExp(r'[\s:：，,。.~～\-—*#]+'), ''); // 標點/空白
        if (stripped.isEmpty) {
          placeholderOnlyNodes.add(label_);
        }
      }
    }
    if (promptNodes.isNotEmpty) {
      issues.add(WorkflowIssue('warn', '',
          '有 ${promptNodes.length} 個節點的提示詞（Prompt）是空的：${promptNodes.join('、')}——執行時上游文字會直接當 prompt 用，建議寫清楚要生成什麼。'));
    }
    if (placeholderOnlyNodes.isNotEmpty) {
      issues.add(WorkflowIssue('warn', '',
          '有 ${placeholderOnlyNodes.length} 個節點的提示詞只有 {input} 佔位、沒有實際內容：${placeholderOnlyNodes.join('、')}——能跑，但生成方向完全由上游決定，建議加上你要的風格/主題描述。'));
    }

    // 5.5 [教練 Agent 2026-08-15 使用者回饋] 輸入端全空檢查——
    // 拔掉一條線後節點仍有其他連線（出向），孤兒檢查抓不到。
    // 語意：節點「一條輸入都沒有」才是斷支線；多入口節點（vision
    // 的 prompt 可走卡片欄位）接了其中一個即可。
    final nodesWithIncoming = <String>{};
    for (final c in connections) {
      nodesWithIncoming.add(c.toNodeId);
    }
    final disconnectedNodes = <String>[];
    for (final id in nodes.keys) {
      final t = type(id);
      if (t == null) continue;
      if (t == 'merge' || t == 'output') continue; // 總成/合併可無輸入
      if (t == 'input' || t == 'schedule') continue; // 源頭節點：入口/排程天生無輸入
      if (nodesWithIncoming.contains(id)) continue;
      disconnectedNodes.add(label(id) ?? id);
    }
    if (disconnectedNodes.isNotEmpty) {
      issues.add(WorkflowIssue('error', '',
          '有 ${disconnectedNodes.length} 個節點的輸入端完全沒接線：${disconnectedNodes.join('、')}——這條支線執行不到，請接上來源。'));
    }

    // 6. 循環偵測（DFS）
    final adj = <String, List<String>>{};
    for (final c in connections) {
      adj.putIfAbsent(c.fromNodeId, () => []).add(c.toNodeId);
    }
    final visiting = <String>{};
    final visited = <String>{};
    void dfs(String id) {
      if (visited.contains(id)) return;
      visiting.add(id);
      for (final next in adj[id] ?? const <String>[]) {
        if (visiting.contains(next)) {
          issues.add(WorkflowIssue('error', next,
              '偵測到循環：「${label(next) ?? next}」參與了一個 A→B→A 的迴圈——執行會永遠停不下來。'));
          return;
        }
        dfs(next);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in nodes.keys) {
      dfs(id);
    }

    // 7. condition 分支懸空
    for (final id in nodes.keys) {
      if (type(id) == 'condition') {
        final outs = connections.where((c) => c.fromNodeId == id).toList();
        if (outs.isEmpty) {
          issues.add(WorkflowIssue('warn', id,
              '條件分支「${label(id) ?? '條件'}」的 true/false 都沒有接——條件判斷結果沒有去處。'));
        }
      }
    }

    return WorkflowAnalysisReport(issues, nodes.length, connections.length);
  }

  /// 把報告轉成給 agent 對話框的 system message
  static String toAgentMessage(WorkflowAnalysisReport report) {
    final buf = StringBuffer();
    if (report.issues.isEmpty) {
      buf.writeln('✅ 工作流靜態測試通過（${report.nodeCount} 節點、${report.connectionCount} 連線）——');
      buf.writeln('沒有發現斷流或邏輯問題。可以放心執行。');
      return buf.toString();
    }

    final errors = report.issues.where((i) => i.isError).toList();
    final warns = report.issues.where((i) => i.isWarn).toList();

    buf.writeln('🧪 工作流靜態測試結果（${report.nodeCount} 節點、${report.connectionCount} 連線）：');
    buf.writeln();
    if (errors.isNotEmpty) {
      buf.writeln('❌ 錯誤（${errors.length}）——這些不修，執行會出問題：');
      for (final e in errors) {
        buf.writeln('  • ${e.message}');
      }
      buf.writeln();
    }
    if (warns.isNotEmpty) {
      buf.writeln('⚠️ 提醒（${warns.length}）——建議看一下：');
      for (final w in warns) {
        buf.writeln('  • ${w.message}');
      }
    }
    return buf.toString();
  }
}
