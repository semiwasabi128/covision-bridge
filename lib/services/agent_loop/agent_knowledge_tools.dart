// agent_knowledge_tools.dart
// Agent 本地知識庫工具 — Phase E
// [教練 Agent 2026-07-22]
//
// 3 個工具：
// 1. agent_search_knowledge — 搜尋本地知識庫（scripts + memories）
// 2. agent_save_script — 儲存新腳本到知識庫
// 3. agent_save_memory — 儲存記憶點到知識庫

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart';
import 'package:flutter/foundation.dart';

/// AgentSearchKnowledgeTool — 搜尋本地知識庫
///
/// 讓 Agent 能搜尋自己累積的腳本和記憶，
/// 實現「本地優先」策略：先查本地 → 有匹配就直接用 → 沒有才走 LLM 推理。
class AgentSearchKnowledgeTool extends AgentTool {
  @override
  String get name => 'agent_search_knowledge';

  @override
  String get description =>
      '搜尋 Agent 的本地知識庫，包含腳本（SOP/範本/快捷序列）和記憶點（教訓/偏好/模式）。'
      '用於在回答前先查本地是否有相關經驗或流程可以直接套用。'
      '回傳標題、摘要和類型。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'query',
      description: '搜尋關鍵字（如「畫布工作流」「記憶整理」「IG 發文」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'limit',
      description: '最大結果數（預設 5）',
      required: false,
      defaultValue: '5',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final query = args['query'] as String? ?? '';
      final limit = int.tryParse(args['limit']?.toString() ?? '5') ?? 5;

      if (query.trim().isEmpty) {
        return AgentToolResult.failure('搜尋關鍵字不能為空');
      }

      final scripts = AgentKnowledgeService.instance.searchScripts(query, limit: limit);
      final memories = AgentKnowledgeService.instance.searchMemories(query, limit: 3);

      if (scripts.isEmpty && memories.isEmpty) {
        return AgentToolResult.success('本地知識庫中沒有找到與「$query」相關的內容。');
      }

      final lines = <String>[];
      if (scripts.isNotEmpty) {
        lines.add('找到 ${scripts.length} 個相關腳本：\n');
        for (var i = 0; i < scripts.length; i++) {
          final s = scripts[i];
          final cat = s.category != null ? ' [${s.category}]' : '';
          lines.add('${i + 1}. ${s.title}$cat');
          lines.add('   ${s.snippet}');
          lines.add('   ID: ${s.id}');
          lines.add('');
        }
      }

      if (memories.isNotEmpty) {
        lines.add('找到 ${memories.length} 個相關記憶：\n');
        for (var i = 0; i < memories.length; i++) {
          final m = memories[i];
          lines.add('${i + 1}. ${m.title}');
          lines.add('   ${m.snippet}');
          lines.add('   ID: ${m.id}');
          lines.add('');
        }
      }

      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      debugPrint('[AgentSearchKnowledgeTool] 失敗: $e');
      return AgentToolResult.failure('搜尋知識庫失敗: $e');
    }
  }
}

/// AgentSaveScriptTool — 儲存新腳本到知識庫
///
/// 讓 Agent 能把學到的新流程、SOP、範本存起來，
/// 下次遇到類似需求時可以直接套用。
class AgentSaveScriptTool extends AgentTool {
  @override
  String get name => 'agent_save_script';

  @override
  String get description =>
      '將新的腳本/SOP/範本儲存到本地知識庫。'
      '用於把成功的流程或學到的經驗固化為可重用的腳本。'
      '儲存後下次遇到類似需求可以直接搜尋套用。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'title',
      description: '腳本標題（簡短，如「畫布工作流建立流程」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'content',
      description: '腳本內容（Markdown 格式，包含步驟和原則）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'description',
      description: '腳本描述（一行說明這個腳本做什麼）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'tags',
      description: '標籤（逗號分隔，如「canvas, workflow, sop」）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'category',
      description: '分類（SOP / Skill / Snippet / Tool Config）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'trigger_keywords',
      description: '觸發關鍵字（逗號分隔，讓搜尋更容易命中）',
      required: false,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final title = args['title'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      final description = args['description'] as String?;
      final tags = args['tags'] as String?;
      final category = args['category'] as String?;
      final triggerKeywords = args['trigger_keywords'] as String?;

      if (title.trim().isEmpty || content.trim().isEmpty) {
        return AgentToolResult.failure('標題和內容不能為空');
      }

      final id = AgentKnowledgeService.instance.createScript(
        title: title,
        description: description,
        content: content,
        tags: tags,
        category: category,
        triggerKeywords: triggerKeywords,
        source: 'agent',
      );

      return AgentToolResult.success(
        '已儲存腳本「$title」到本地知識庫。\nID: $id\n下次遇到類似需求時可以用 agent_search_knowledge 搜尋套用。',
      );
    } catch (e) {
      debugPrint('[AgentSaveScriptTool] 失敗: $e');
      return AgentToolResult.failure('儲存腳本失敗: $e');
    }
  }
}

/// AgentSaveMemoryTool — 儲存記憶點到知識庫
///
/// 讓 Agent 能把學到的教訓、使用者偏好、發現的模式存起來，
/// 形成長期記憶，避免重複犯錯。
class AgentSaveMemoryTool extends AgentTool {
  @override
  String get name => 'agent_save_memory';

  @override
  String get description =>
      '將記憶點（教訓/偏好/模式/里程碑）儲存到本地知識庫。'
      '用於記錄從互動中學到的經驗，避免重複犯錯。'
      '記憶點會在未來相關對話中被自動檢索和引用。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'title',
      description: '記憶標題（簡短，如「使用者偏好暗色介面」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'content',
      description: '記憶內容（詳細描述這個教訓或偏好）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'tags',
      description: '標籤（逗號分隔，如「ui, preference, dark_mode」）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'memory_type',
      description: '記憶類型（lesson / preference / pattern / milestone）',
      required: false,
      defaultValue: 'lesson',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final title = args['title'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      final tags = args['tags'] as String?;
      final memoryType = args['memory_type'] as String? ?? 'lesson';

      if (title.trim().isEmpty || content.trim().isEmpty) {
        return AgentToolResult.failure('標題和內容不能為空');
      }

      final id = AgentKnowledgeService.instance.createMemory(
        title: title,
        content: content,
        tags: tags,
        memoryType: memoryType,
      );

      return AgentToolResult.success(
        '已儲存記憶點「$title」到本地知識庫。\nID: $id\n這個記憶會在未來相關對話中被自動檢索。',
      );
    } catch (e) {
      debugPrint('[AgentSaveMemoryTool] 失敗: $e');
      return AgentToolResult.failure('儲存記憶失敗: $e');
    }
  }
}
