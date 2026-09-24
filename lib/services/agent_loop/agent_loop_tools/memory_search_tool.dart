/// 大腦容器 + 向量資料庫混合搜尋工具
///
/// 讓 Agent 使用完整的十階段搜尋管線（Cerebras Knowledge 啟發）：
/// FTS+語意 → Project scope → RRF(+IDF) → Reranker → Dedup+Cap
/// → 圖譜展開 → Context expansion → Synthesis LLM
///
/// 回傳：綜合答案（synthesizedAnswer）+ 記憶/檔案命中列表
/// 如果本地模型可用，還會包含 LLM 生成的附引用綜合答案。

import '../agent_tool.dart';
import '../../vector_db/hybrid_search_service.dart';

class MemorySearchTool extends AgentTool {
  final dynamic _brainContainerService;

  MemorySearchTool(this._brainContainerService);

  @override
  String get name => 'memory_search';

  @override
  String get description =>
      '搜尋使用者的長期記憶與向量資料庫（大腦容器 + 圖書館）。'
      '使用混合搜尋：全文搜尋(FTS5) + 語意搜尋(向量) + RRF 融合 + Reranker 重排。'
      '回傳綜合答案（含引用來源）+ 相關記憶 + 相關檔案列表。\n'
      '適用場景：\n'
      '- 使用者問「之前說過什麼」「我之前提過什麼」等回顧性問題\n'
      '- 使用者要找檔案、筆記、文件\n'
      '- 使用者問「有沒有關於 X 的資料」\n'
      '- 需要跨記憶和檔案做綜合查詢';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'query',
          description: '搜尋關鍵字或自然語言問題',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'limit',
          description: '每邊最大命中數（預設 20）',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'project_id',
          description: '限定搜尋範圍到指定專案（可選）',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) {
      return AgentToolResult.failure('query 參數為空');
    }

    final limit = int.tryParse(args['limit']?.toString() ?? '') ?? 20;
    final projectId = args['project_id']?.toString();

    try {
      // 使用 HybridSearchService 的完整十階段搜尋管線
      final results = await HybridSearchService.instance.search(
        query: query,
        mode: SearchMode.hybrid,
        limit: limit,
        projectId: projectId,
      );

      if (results.isEmpty) {
        return AgentToolResult.success('沒有找到與「$query」相關的記憶或檔案。');
      }

      // 組裝結果
      final buffer = StringBuffer();

      // 優先顯示 Synthesis LLM 的綜合答案
      if (results.synthesizedAnswer != null &&
          results.synthesizedAnswer!.isNotEmpty) {
        buffer.writeln('## 綜合答案');
        buffer.writeln(results.synthesizedAnswer);
        buffer.writeln();
      }

      // 記憶命中
      if (results.memoryHits.isNotEmpty) {
        buffer.writeln('## 相關記憶 (${results.memoryHits.length})');
        for (var i = 0; i < results.memoryHits.length; i++) {
          final hit = results.memoryHits[i];
          final preview = hit.content.length > 150
              ? '${hit.content.substring(0, 150)}...'
              : hit.content;
          buffer.writeln(
              '${i + 1}. [${hit.room}] (分數: ${hit.score.toStringAsFixed(3)}) $preview');
        }
        buffer.writeln();
      }

      // 檔案命中
      if (results.assetHits.isNotEmpty) {
        buffer.writeln('## 相關檔案 (${results.assetHits.length})');
        for (var i = 0; i < results.assetHits.length; i++) {
          final hit = results.assetHits[i];
          final summary = hit.summary ?? hit.title ?? hit.fileName;
          buffer.writeln(
              '${i + 1}. ${hit.fileName} (分數: ${hit.score.toStringAsFixed(3)})');
          if (summary != hit.fileName) {
            buffer.writeln('   摘要: $summary');
          }
        }
        buffer.writeln();
      }

      // 交叉引用
      if (results.crossLinks.isNotEmpty) {
        buffer.writeln('## 記憶↔檔案關聯 (${results.crossLinks.length})');
        for (final link in results.crossLinks.take(5)) {
          buffer.writeln(
              '- 記憶 ${link.memoryId} ↔ 檔案 ${link.assetId} (${link.linkType})');
        }
      }

      return AgentToolResult.success(buffer.toString().trim());
    } catch (e) {
      // Fallback：如果 HybridSearchService 失敗，嘗試舊路徑
      try {
        final result = await _brainContainerService.getFormattedContext(query);
        if (result != null && result.toString().isNotEmpty) {
          return AgentToolResult.success(result.toString());
        }
      } catch (_) {}

      return AgentToolResult.failure('搜尋失敗：$e');
    }
  }
}
