// receipts_search_service.dart
// [收據搜尋 第 3 刀 RC1 2026-09-08]
// 五域聯合搜尋：對話 / 記憶 / 資產 / 任務。
// 設計稿：docs/specs/2026-09-08-receipts-search.md
//
// 設計要點：
// - 記憶+資產委託 HybridSearchService（既有 FTS+semantic+RRF 引擎，不重造）
// - 對話/任務 in-memory 掃描（量小：對話數百、任務數十）
// - 結果附 ReceiptHop——「搜尋結果是空間座標不是連結」的實體
// - 各域上限 8、防抖由 UI 層負責（service 無狀態）

import 'package:flutter/foundation.dart';
import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/conversation_store.dart';
import 'package:bridge_app/services/tasks/task_session.dart';
import 'package:bridge_app/services/tasks/task_session_store.dart';
import 'package:bridge_app/services/vector_db/hybrid_search_service.dart'
    show MemoryHit, AssetHit;
import 'package:bridge_app/services/vault/vault_search_facade.dart';

/// 搜尋域
enum ReceiptDomain { conversation, memory, asset, task }

/// 跳轉座標——點下結果後要去哪
class ReceiptHop {
  final ReceiptDomain domain;
  final String targetId; // conversationId / memoryId / assetId / taskId
  final String? messageId; // 對話域：跳到那則訊息
  final String? workCanvasId; // 任務域：跳工作畫布

  const ReceiptHop({
    required this.domain,
    required this.targetId,
    this.messageId,
    this.workCanvasId,
  });
}

/// 對話命中——附 excerpt 與命中訊息 ID（跳到現場的證據）
class ConversationHit {
  final String conversationId;
  final String title;
  final String excerpt; // 命中訊息摘要（前 80 字）
  final String? messageId; // 命中的那則訊息（title 命中則 null）
  final DateTime updatedAt;

  const ConversationHit({
    required this.conversationId,
    required this.title,
    required this.excerpt,
    this.messageId,
    required this.updatedAt,
  });

  ReceiptHop get hop => ReceiptHop(
        domain: ReceiptDomain.conversation,
        targetId: conversationId,
        messageId: messageId,
      );
}

/// 任務命中
class TaskHit {
  final TaskSession session;

  const TaskHit(this.session);

  ReceiptHop get hop => ReceiptHop(
        domain: ReceiptDomain.task,
        targetId: session.id,
        workCanvasId: session.workCanvasId,
      );
}

/// 聯合結果
class ReceiptsResults {
  final List<ConversationHit> conversations;
  final List<MemoryHit> memories;
  final List<AssetHit> assets;
  final List<TaskHit> tasks;

  const ReceiptsResults({
    this.conversations = const [],
    this.memories = const [],
    this.assets = const [],
    this.tasks = const [],
  });

  bool get isEmpty =>
      conversations.isEmpty && memories.isEmpty && assets.isEmpty && tasks.isEmpty;

  int get totalHits =>
      conversations.length + memories.length + assets.length + tasks.length;
}

/// 聯合搜尋服務（單例）
class ReceiptsSearchService {
  ReceiptsSearchService._();
  static final ReceiptsSearchService instance = ReceiptsSearchService._();

  // [Blue 令 2026-09-12 對齊] 全域搜尋=向量資料庫同款視角——
  // 每域上限對齊 vault（100）。之前 8 筆是聯合搜尋時代的舊設計，
  // Blue 實測「結果沒對齊」的真兇。
  static const int perDomainLimit = 100;

  /// 五域並行聯合搜尋
  Future<ReceiptsResults> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const ReceiptsResults();

    // 並行：記憶+資產（vault 同款 facade）∥ 對話 ∥ 任務
    final results = await Future.wait([
      _searchBrain(q),
      _searchConversations(q),
      _searchTasks(q),
    ]);
    final brain = results[0] as (List<MemoryHit>, List<AssetHit>);

    return ReceiptsResults(
      memories: brain.$1.take(perDomainLimit).toList(),
      assets: brain.$2.take(perDomainLimit).toList(),
      conversations: (results[1] as List<ConversationHit>).take(perDomainLimit).toList(),
      tasks: (results[2] as List<TaskHit>).take(perDomainLimit).toList(),
    );
  }

  /// 記憶+資產 → [S4 統一令] VaultSearchFacade（與 vault 同一套程式碼）
  /// 預設 fullText（快——與 vault 一致）；單域結果直接用。
  Future<(List<MemoryHit>, List<AssetHit>)> _searchBrain(String q) async {
    try {
      final entries = await VaultSearchFacade.instance.search(
        query: q,
        mode: VaultFacadeMode.fullText,
        limit: perDomainLimit,
      );
      final memories = <MemoryHit>[];
      final assets = <AssetHit>[];
      for (final e in entries) {
        if (e.agent == 'asset_index') {
          assets.add(AssetHit(
            id: e.id,
            filePath: e.content,
            fileName: e.content,
            assetKind: 'file',
            score: 1.0,
          ));
        } else {
          memories.add(MemoryHit(
            id: e.id,
            content: e.content,
            room: e.room,
            score: 1.0,
          ));
        }
      }
      return (memories, assets);
    } catch (e) {
      debugPrint('[ReceiptsSearch] 大腦域搜尋失敗（fail-open 空結果）: $e');
      return (<MemoryHit>[], <AssetHit>[]);
    }
  }

  /// 對話——in-memory 掃描 title + 訊息內容（含交付卡）
  Future<List<ConversationHit>> _searchConversations(String q) async {
    try {
      final convs = await ConversationStore.getAll();
      final lower = q.toLowerCase();
      final hits = <ConversationHit>[];

      for (final conv in convs) {
        // ① title 命中
        if (conv.title.toLowerCase().contains(lower)) {
          hits.add(ConversationHit(
            conversationId: conv.id,
            title: conv.title,
            excerpt: conv.messages.isNotEmpty
                ? _excerpt(conv.messages.last.content)
                : '（空對話）',
            messageId: conv.messages.isNotEmpty ? conv.messages.last.id : null,
            updatedAt: conv.updatedAt,
          ));
          continue;
        }
        // ② 訊息內容命中（由新到舊掃，命中即停——最近的上下文最相關）
        for (final m in conv.messages.reversed) {
          if (m.content.toLowerCase().contains(lower)) {
            hits.add(ConversationHit(
              conversationId: conv.id,
              title: conv.title,
              excerpt: _excerpt(m.content),
              messageId: m.id,
              updatedAt: conv.updatedAt,
            ));
            break;
          }
        }
      }

      hits.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return hits;
    } catch (e) {
      debugPrint('[ReceiptsSearch] 對話域搜尋失敗（fail-open）: $e');
      return [];
    }
  }

  /// 任務——title/instruction/summary/deliverables caption
  Future<List<TaskHit>> _searchTasks(String q) async {
    try {
      final tasks = await TaskSessionStore.getAll();
      final lower = q.toLowerCase();
      return tasks
          .where((t) =>
              t.title.toLowerCase().contains(lower) ||
              t.instruction.toLowerCase().contains(lower) ||
              (t.finalSummary ?? '').toLowerCase().contains(lower) ||
              t.deliverables.any((d) => d.caption.toLowerCase().contains(lower)))
          .map(TaskHit.new)
          .toList();
    } catch (e) {
      debugPrint('[ReceiptsSearch] 任務域搜尋失敗（fail-open）: $e');
      return [];
    }
  }

  String _excerpt(String content) {
    final c = content.replaceAll('\n', ' ').trim();
    return c.length > 80 ? '${c.substring(0, 80)}…' : c;
  }
}
