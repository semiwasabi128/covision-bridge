// agent_workflow_tools.dart
// Phase F — 控制面板整合工具
// [教練 Agent 2026-07-22]
//
// 把 Phase C 畫布工具 + Phase E 知識庫整合在一起。
// Agent 可以：搜知識庫 → 找到 SOP → 一鍵載入對應畫布範本。
//
// 2 個工具：
// 1. agent_apply_workflow — 搜知識庫找 SOP → 載入對應畫布範本（一鍵完成）
// 2. canvas_list_templates — 列出所有可用畫布範本

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';
import 'package:flutter/foundation.dart';

/// AgentApplyWorkflowTool — 知識庫 + 畫布整合工具
///
/// 這是 Phase F 的核心：Agent 搜尋本地知識庫找到相關 SOP，
/// 如果該 SOP 有對應的畫布範本，直接一鍵載入畫布。
///
/// 流程：
/// 1. 搜尋 agent_scripts（FTS5）
/// 2. 找到匹配的腳本
/// 3. 查 scriptToTemplate 對應表
/// 4. 如果有對應範本 → 觸發 CanvasMcpRegistry.loadTemplate()
/// 5. 回報結果（載入了什麼範本 + SOP 內容摘要）
class AgentApplyWorkflowTool extends AgentTool {
  @override
  String get name => 'agent_apply_workflow';

  @override
  String get description =>
      '搜尋本地知識庫找到相關 SOP，如果該 SOP 有對應的畫布範本就一鍵載入。'
      '這是「本地優先」策略的核心：先查本地經驗 → 有範本就直接載入 → 省去逐步建節點。'
      '如果找不到對應範本，回傳 SOP 內容讓你參考手動操作。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'query',
      description: '工作流需求描述（如「IG 發文」「知識整理」「記憶回顧」「多模型協作」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'auto_load',
      description: '是否自動載入範本到畫布（預設 true。設 false 則只回報 SOP 和範本資訊）',
      required: false,
      defaultValue: 'true',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final query = args['query'] as String? ?? '';
      final autoLoad = args['auto_load']?.toString() != 'false';

      if (query.trim().isEmpty) {
        return AgentToolResult.failure('查詢關鍵字不能為空');
      }

      // Step 1: 搜尋知識庫
      final scripts = AgentKnowledgeService.instance.searchScripts(query, limit: 5);

      if (scripts.isEmpty) {
        return AgentToolResult.success(
          '本地知識庫中沒有找到與「$query」相關的 SOP。\n'
          '你可以用 canvas_list_templates 查看可用範本，或手動建立工作流。',
        );
      }

      // Step 2: 找有對應範本的腳本
      KnowledgeSearchResult? matchedScript;
      String? templateId;

      for (final script in scripts) {
        final template = AgentKnowledgeService.instance.getTemplateForScript(script.id);
        if (template != null) {
          matchedScript = script;
          templateId = template.id;
          break;
        }
      }

      // Step 3: 如果找到對應範本
      if (matchedScript != null && templateId != null) {
        final template = AgentKnowledgeService.instance.getTemplateForScript(matchedScript.id);

        if (autoLoad) {
          // 觸發畫布載入範本
          try {
            CanvasMcpRegistry.instance.loadTemplate(templateId);
            AgentKnowledgeService.instance.recordUsage(matchedScript.id);

            return AgentToolResult.success(
              '已從本地知識庫找到 SOP 並載入對應範本！\n\n'
              '📚 SOP：${matchedScript.title}\n'
              '${matchedScript.snippet}\n\n'
              '🎨 範本：${template!.name}（$templateId）\n'
              '${template.description}\n\n'
              '✅ 範本已載入畫布，節點正在建立中。',
            );
          } catch (e) {
            return AgentToolResult.success(
              '找到 SOP 和範本，但載入畫布失敗：$e\n\n'
              '📚 SOP：${matchedScript.title}\n'
              '🎨 範本：${template!.name}（$templateId）\n'
              '請你（Agent）直接再次呼叫 canvas_load_template 工具幫使用者載入。'
              '注意：這是內部工具語法，不要把指令文字原樣顯示給使用者；'
              '使用者也可以從畫布左側範本清單手動匯入。',
            );
          }
        } else {
          return AgentToolResult.success(
            '找到匹配的 SOP 和範本（未自動載入）：\n\n'
            '📚 SOP：${matchedScript.title}\n'
              '${matchedScript.snippet}\n\n'
            '🎨 範本：${template!.name}（$templateId）\n'
              '${template.description}\n\n'
            '請你（Agent）直接呼叫 canvas_load_template 工具（template_name: "$templateId"）'
            '幫使用者載入，或請使用者從畫布左側範本清單匯入。'
            '這是內部工具語法，不要把指令文字原樣顯示給使用者。',
          );
        }
      }

      // Step 4: 沒有對應範本，回傳 SOP 內容
      final lines = <String>['找到 ${scripts.length} 個相關 SOP，但沒有對應的畫布範本：\n'];
      for (var i = 0; i < scripts.length; i++) {
        final s = scripts[i];
        lines.add('${i + 1}. ${s.title} ${s.category != null ? '[${s.category}]' : ''}');
        lines.add('   ${s.snippet}');
        lines.add('');
      }
      lines.add('你可以參考 SOP 內容說明給使用者聽；要查範本由你（Agent）自己呼叫 canvas_list_templates，不要叫使用者打指令。');
      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      debugPrint('[AgentApplyWorkflowTool] 失敗: $e');
      return AgentToolResult.failure('執行工作流搜尋失敗: $e');
    }
  }
}

/// CanvasListTemplatesTool — 列出所有可用畫布範本
///
/// 讓 Agent 知道有哪些範本可以直接載入，不用猜範本名稱。
class CanvasListTemplatesTool extends AgentTool {
  @override
  String get name => 'canvas_list_templates';

  @override
  String get description =>
      '列出所有可用的畫布工作流範本。'
      '每個範本包含 ID、名稱、描述和分類。'
      '用 canvas_load_template 載入指定範本，或用 agent_apply_workflow 自動搜尋 SOP 並載入。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final templates = AgentKnowledgeService.instance.listAvailableTemplates();

      if (templates.isEmpty) {
        return AgentToolResult.success('目前沒有可用的畫布範本。');
      }

      final lines = <String>['可用畫布範本（共 ${templates.length} 個）：\n'];
      for (var i = 0; i < templates.length; i++) {
        final t = templates[i];
        lines.add('${i + 1}. ${t['icon']} ${t['name']} [${t['category']}]');
        lines.add('   ID: ${t['id']}');
        lines.add('   ${t['description']}');
        lines.add('');
      }

      lines.add('（以上範本ID是給你查閱的——要載入就直接由你呼叫工具，使用者永遠不需要打任何指令。）');
      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      debugPrint('[CanvasListTemplatesTool] 失敗: $e');
      return AgentToolResult.failure('列出範本失敗: $e');
    }
  }
}
