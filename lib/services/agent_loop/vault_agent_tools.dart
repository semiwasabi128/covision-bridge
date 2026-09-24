// vault_agent_tools.dart
// Agent Vault 工具 — 讓原生 Agent能搜尋資料庫、送條目到畫布
// [教練 Agent 2026-07-22] Phase 4
//
// 兩個工具：
// 1. vault_search — 搜尋 Vault 條目（全文/語意/標籤）
// 2. vault_send_to_canvas — 將 Vault 條目送到畫布

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/vault/vault_service.dart';
import 'package:flutter/foundation.dart';

/// VaultSearchTool — 搜尋資料庫條目
///
/// Agent 可用全文、語意或標籤搜尋 Vault。
/// 回傳最多 10 筆結果（id + 摘要 + 標籤）。
class VaultSearchTool extends AgentTool {
  @override
  String get name => 'vault_search';

  @override
  String get description =>
      '搜尋向量資料庫（第二大腦）中的記憶和知識條目。'
      '支援全文搜尋、語意搜尋和標籤篩選。'
      '回傳條目 ID、摘要、標籤和類型。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'query',
      description: '搜尋關鍵字',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'mode',
      description: '搜尋模式：fullText（全文，預設）/ semantic（語意）/ tag（標籤）',
      required: false,
      defaultValue: 'fullText',
    ),
    const AgentToolParamSpec(
      name: 'limit',
      description: '最大結果數（預設 10）',
      required: false,
      defaultValue: '10',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final query = args['query'] as String? ?? '';
      final modeStr = args['mode'] as String? ?? 'fullText';
      final limit = int.tryParse(args['limit']?.toString() ?? '10') ?? 10;

      final mode = switch (modeStr) {
        'semantic' => VaultSearchMode.semantic,
        'tag' => VaultSearchMode.tag,
        _ => VaultSearchMode.fullText,
      };

      final results = await VaultService.instance.search(
        mode: mode,
        query: query,
        limit: limit,
      );

      if (results.isEmpty) {
        return AgentToolResult.success('搜尋 "$query" 沒有結果。');
      }

      // 格式化結果
      final lines = <String>[];
      lines.add('找到 ${results.length} 筆結果：\n');
      for (var i = 0; i < results.length; i++) {
        final e = results[i];
        final tags = e.tags.isNotEmpty ? ' [${e.tags.join(",")}]' : '';
        lines.add('${i + 1}. [${e.typeLabel}] ${e.summary}$tags');
        lines.add('   ID: ${e.id}');
        lines.add('');
      }

      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      debugPrint('[VaultSearchTool] 失敗: $e');
      return AgentToolResult.failure('搜尋失敗: $e');
    }
  }
}

/// VaultSendToCanvasTool — 將 Vault 條目送到畫布
///
/// 需要與 McpCanvasExecutor 配合，透過 canvas_add_node 建立 input 節點。
/// 這個工具讓 Agent 可以：搜尋 → 找到 → 送至畫布，一氣呵成。
class VaultSendToCanvasTool extends AgentTool {
  final void Function(String vaultId, String content, String source)?
      onSendToCanvas;

  VaultSendToCanvasTool({this.onSendToCanvas});

  @override
  String get name => 'vault_send_to_canvas';

  @override
  String get description =>
      '將向量資料庫中的條目送到畫布上，作為工作流的輸入節點。'
      '使用前需先透過 vault_search 取得條目 ID。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'vault_id',
      description: 'Vault 條目 ID（從 vault_search 結果取得）',
      required: true,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final vaultId = args['vault_id'] as String?;
      if (vaultId == null || vaultId.isEmpty) {
        return AgentToolResult.failure('缺少必要參數：vault_id');
      }

      // 取得條目
      final entry = await VaultService.instance.getEntry(vaultId);
      if (entry == null) {
        return AgentToolResult.failure('找不到 ID 為 $vaultId 的條目。');
      }

      // 透過回呼送至畫布
      if (onSendToCanvas != null) {
        onSendToCanvas!(entry.id, entry.summary, entry.source);
      }

      return AgentToolResult.success(
        '已將條目送至畫布：[${entry.typeLabel}] ${entry.summary}',
      );
    } catch (e) {
      debugPrint('[VaultSendToCanvasTool] 失敗: $e');
      return AgentToolResult.failure('送至畫布失敗: $e');
    }
  }
}

/// VaultGetTagsTool — 取得所有標籤及其數量
///
/// 讓 Agent 知道資料庫中有哪些標籤可以用來篩選。
class VaultGetTagsTool extends AgentTool {
  @override
  String get name => 'vault_get_tags';

  @override
  String get description =>
      '列出向量資料庫中所有標籤及其條目數量。'
      '用於了解資料庫的知識分布。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final tags = await VaultService.instance.getAllTags();
      if (tags.isEmpty) {
        return AgentToolResult.success('資料庫中尚無標籤。');
      }

      final sorted = tags.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final lines = <String>['共 ${sorted.length} 個標籤：\n'];
      for (final entry in sorted) {
        lines.add('  #${entry.key} (${entry.value})');
      }

      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      return AgentToolResult.failure('取得標籤失敗: $e');
    }
  }
}
