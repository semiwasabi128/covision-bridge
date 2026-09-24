// cross_reference_service.dart
// [教練 Agent 2026-07-25] 記憶↔檔案交叉引用管理
//
// 管理 memory_asset_links 表的 CRUD 操作。
// 三種 link_type：
// - referenced：記憶提到了某個檔案（Agent 自動偵測）
// - inspired：檔案啟發了某條記憶（使用者手動 / Agent 建議）
// - produced_from：Agent 產出基於某些檔案（Agent 自動建立）
//
// 設計文件：B+-Hybrid-GraphRAG-大腦與圖書館協同架構.md §5.2

import 'dart:convert';

import 'package:bridge_app/services/brain_container/brain_container_service.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
import 'package:flutter/foundation.dart';

/// 交叉引用類型
enum CrossLinkType {
  /// 記憶提到了某個檔案 — Agent 自動偵測
  referenced,
  /// 檔案啟發了某條記憶 — 使用者手動 / Agent 建議
  inspired,
  /// Agent 產出基於某些檔案 — Agent 自動建立
  producedFrom,
}

/// 交叉引用記錄
class CrossLink {
  final String id;
  final String memoryId;
  final String assetId;
  final CrossLinkType linkType;
  final String? note;
  final DateTime createdAt;

  const CrossLink({
    required this.id,
    required this.memoryId,
    required this.assetId,
    required this.linkType,
    this.note,
    required this.createdAt,
  });

  String get linkTypeLabel => switch (linkType) {
        CrossLinkType.referenced => '提及',
        CrossLinkType.inspired => '啟發',
        CrossLinkType.producedFrom => '產出來源',
      };
}

/// 交叉引用服務（單例）
///
/// 管理 memory_asset_links 表，提供：
/// 1. 建立引用（自動去重）
/// 2. 查詢記憶的關聯檔案
/// 3. 查詢檔案的關聯記憶
/// 4. 刪除引用
class CrossReferenceService {
  static final CrossReferenceService instance = CrossReferenceService._();
  CrossReferenceService._();

  /// 建立交叉引用
  ///
  /// 使用 INSERT OR IGNORE 自動去重（UNIQUE 約束）。
  Future<void> createLink({
    required String memoryId,
    required String assetId,
    required CrossLinkType linkType,
    String? note,
  }) async {
    try {
      final db = BrainDatabase.instance.db;
      final id = _generateId(memoryId, assetId, linkType);
      final linkTypeStr = switch (linkType) {
        CrossLinkType.referenced => 'referenced',
        CrossLinkType.inspired => 'inspired',
        CrossLinkType.producedFrom => 'produced_from',
      };

      db.execute(
        'INSERT OR IGNORE INTO memory_asset_links '
        '(id, memory_id, asset_id, link_type, note, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          id,
          memoryId,
          assetId,
          linkTypeStr,
          note,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    } catch (e) {
      debugPrint('[CrossRef] createLink 失敗: $e');
    }
  }

  /// 批次建立交叉引用
  Future<void> createLinks({
    required String memoryId,
    required List<String> assetIds,
    required CrossLinkType linkType,
  }) async {
    for (final assetId in assetIds) {
      await createLink(
        memoryId: memoryId,
        assetId: assetId,
        linkType: linkType,
      );
    }
  }

  /// 查詢某條記憶關聯的所有檔案
  Future<List<CrossLink>> getLinksByMemory(String memoryId) async {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT id, memory_id, asset_id, link_type, note, created_at '
        'FROM memory_asset_links WHERE memory_id = ? '
        'ORDER BY created_at DESC',
        [memoryId],
      );
      return rows.map(_rowToCrossLink).toList();
    } catch (e) {
      debugPrint('[CrossRef] getLinksByMemory 失敗: $e');
      return [];
    }
  }

  /// 查詢某個檔案關聯的所有記憶
  Future<List<CrossLink>> getLinksByAsset(String assetId) async {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT id, memory_id, asset_id, link_type, note, created_at '
        'FROM memory_asset_links WHERE asset_id = ? '
        'ORDER BY created_at DESC',
        [assetId],
      );
      return rows.map(_rowToCrossLink).toList();
    } catch (e) {
      debugPrint('[CrossRef] getLinksByAsset 失敗: $e');
      return [];
    }
  }

  /// 查詢多條記憶的所有關聯檔案（批次查詢，用於圖譜展開）
  Future<Map<String, List<CrossLink>>> getLinksByMemories(
    List<String> memoryIds,
  ) async {
    if (memoryIds.isEmpty) return {};
    try {
      final db = BrainDatabase.instance.db;
      final placeholders = memoryIds.map((_) => '?').join(',');
      final rows = db.select(
        'SELECT id, memory_id, asset_id, link_type, note, created_at '
        'FROM memory_asset_links WHERE memory_id IN ($placeholders) '
        'ORDER BY created_at DESC',
        memoryIds,
      );

      final result = <String, List<CrossLink>>{};
      for (final row in rows) {
        final link = _rowToCrossLink(row);
        final mid = row['memory_id'] as String;
        result.putIfAbsent(mid, () => []).add(link);
      }
      return result;
    } catch (e) {
      debugPrint('[CrossRef] getLinksByMemories 失敗: $e');
      return {};
    }
  }

  /// 查詢多個檔案的所有關聯記憶（批次查詢，用於圖譜展開）
  Future<Map<String, List<CrossLink>>> getLinksByAssets(
    List<String> assetIds,
  ) async {
    if (assetIds.isEmpty) return {};
    try {
      final db = BrainDatabase.instance.db;
      final placeholders = assetIds.map((_) => '?').join(',');
      final rows = db.select(
        'SELECT id, memory_id, asset_id, link_type, note, created_at '
        'FROM memory_asset_links WHERE asset_id IN ($placeholders) '
        'ORDER BY created_at DESC',
        assetIds,
      );

      final result = <String, List<CrossLink>>{};
      for (final row in rows) {
        final link = _rowToCrossLink(row);
        final aid = row['asset_id'] as String;
        result.putIfAbsent(aid, () => []).add(link);
      }
      return result;
    } catch (e) {
      debugPrint('[CrossRef] getLinksByAssets 失敗: $e');
      return {};
    }
  }

  /// 刪除單一引用
  Future<void> deleteLink(String linkId) async {
    try {
      final db = BrainDatabase.instance.db;
      db.execute(
        'DELETE FROM memory_asset_links WHERE id = ?',
        [linkId],
      );
    } catch (e) {
      debugPrint('[CrossRef] deleteLink 失敗: $e');
    }
  }

  /// 刪除某條記憶的所有引用
  Future<void> deleteLinksByMemory(String memoryId) async {
    try {
      final db = BrainDatabase.instance.db;
      db.execute(
        'DELETE FROM memory_asset_links WHERE memory_id = ?',
        [memoryId],
      );
    } catch (e) {
      debugPrint('[CrossRef] deleteLinksByMemory 失敗: $e');
    }
  }

  /// 取得所有交叉引用的數量
  Future<int> getTotalLinkCount() async {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select('SELECT COUNT(*) as count FROM memory_asset_links');
      return (rows.first['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════
  // 自動偵測 — Agent 寫記憶時自動建立 referenced 引用
  // ═══════════════════════════════════════════════════

  /// 自動偵測記憶內容中提到的檔案，建立 referenced 引用
  ///
  /// 用檔名匹配：如果記憶內容中出現某個檔案的檔名，
  /// 就自動建立一條 referenced 引用。
  ///
  /// [memoryId] — 新寫入的記憶 ID
  /// [memoryContent] — 記憶內容
  /// [availableAssetIds] — 可匹配的檔案 {檔名: assetId}
  Future<int> autoDetectReferences({
    required String memoryId,
    required String memoryContent,
    required Map<String, String> fileNameToAssetId,
  }) async {
    if (fileNameToAssetId.isEmpty) return 0;

    var count = 0;
    final contentLower = memoryContent.toLowerCase();

    for (final entry in fileNameToAssetId.entries) {
      final fileName = entry.key.toLowerCase();
      final assetId = entry.value;

      // 檔名出現在記憶內容中 → 建立引用
      if (contentLower.contains(fileName)) {
        await createLink(
          memoryId: memoryId,
          assetId: assetId,
          linkType: CrossLinkType.referenced,
        );
        count++;
      }
    }

    if (count > 0) {
      debugPrint('[CrossRef] 自動偵測到 $count 個檔案引用 (memory: $memoryId)');
    }

    return count;
  }

  /// [教練 Agent 2026-07-28] Phase 5 決策 5：用向量相似度自動關聯記憶↔檔案
  ///
  /// 記憶產生時呼叫：
  /// 1. embedQuery(memoryContent) → 768 維向量
  /// 2. vector_full_scan asset_index → 找最近鄰
  /// 3. 相似度 > 0.50 → INSERT memory_asset_links (link_type='referenced')
  ///    [教練 Agent 2026-08-21] 重嵌後校準：真匹配 0.55-0.69、噪音頂 0.35
  ///    （230 條記憶全量實測），0.75 是假向量時代的舊值會全擋。
  ///
  /// 安全降級：模型不可用 / vector_init 未執行 → 靜默跳過
  Future<int> autoLinkByVector({
    required String memoryId,
    required String memoryContent,
  }) async {
    if (!BrainContainerService.instance.isInitialized) return 0;

    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) return 0;

    try {
      // 1. 生成記憶的 embedding
      final queryVector = await embedder.embedQuery(memoryContent);
      final vectorJson = jsonEncode(queryVector);

      // 2. vector_full_scan 找 asset_index 最近鄰
      final db = BrainDatabase.instance.db;
      final results = db.select(
        "SELECT a.id, v.distance "
        "FROM asset_index a "
        "JOIN vector_full_scan('asset_index', 'embedding', vector_as_f32(?), 20) AS v "
        "  ON a.rowid = v.rowid "
        "WHERE a.index_status = 'indexed' AND a.embedding IS NOT NULL "
        "ORDER BY v.distance ASC "
        "LIMIT 10",
        [vectorJson, 20],
      );

      if (results.isEmpty) return 0;

      // 3. 相似度 > 0.75 → 建立連結
      var count = 0;
      for (final row in results) {
        final distance = (row['distance'] as num?)?.toDouble() ?? 1.0;
        final similarity = (1.0 - (distance / 2.0)).clamp(0.0, 1.0);

        if (similarity > 0.50) {
          final assetId = row['id'] as String;
          await createLink(
            memoryId: memoryId,
            assetId: assetId,
            linkType: CrossLinkType.referenced,
          );
          count++;
        }
      }

      if (count > 0) {
        debugPrint('[CrossRef] 向量自動關聯: $count 個檔案 (memory: $memoryId)');
      }
      return count;
    } catch (e) {
      debugPrint('[CrossRef] 向量自動關聯失敗（靜默跳過）: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════
  // 內部方法
  // ═══════════════════════════════════════════════════

  CrossLink _rowToCrossLink(Map<String, dynamic> row) {
    final linkTypeStr = row['link_type'] as String? ?? 'referenced';
    final linkType = switch (linkTypeStr) {
      'referenced' => CrossLinkType.referenced,
      'inspired' => CrossLinkType.inspired,
      'produced_from' => CrossLinkType.producedFrom,
      _ => CrossLinkType.referenced,
    };

    return CrossLink(
      id: row['id'] as String,
      memoryId: row['memory_id'] as String,
      assetId: row['asset_id'] as String,
      linkType: linkType,
      note: row['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
    );
  }

  /// 生成確定性 ID（memoryId + assetId + linkType 的 hash）
  String _generateId(String memoryId, String assetId, CrossLinkType linkType) {
    final linkTypeStr = switch (linkType) {
      CrossLinkType.referenced => 'referenced',
      CrossLinkType.inspired => 'inspired',
      CrossLinkType.producedFrom => 'produced_from',
    };
    final combined = '${memoryId}_${assetId}_$linkTypeStr';
    return 'xref_${combined.hashCode.abs()}';
  }
}
