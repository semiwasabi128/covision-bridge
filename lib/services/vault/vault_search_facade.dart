// vault_search_facade.dart
// [收據搜尋 S4 2026-09-08 Blue 統一令] 唯一的搜尋管線。
//
// 「全域搜尋的搜尋方式就要和向量資料庫搜尋的方式一樣，用同一組程式碼，
// 一次調整，兩邊都生效。」——Blue 2026-09-08
//
// 架構：
//   VaultScreen（向量資料庫 UI）──┐
//                              ├──→ VaultSearchFacade.search() ──→ 單一真相
//   ReceiptsSearchService（全域搜尋）┘        │
//                                   ├─ fullText/semantic/tag → VaultService（SQL LIKE）
//                                   └─ hybrid → HybridSearchService（FTS+語義 RRF）
//
// 未來深化向量搜尋/標籤系統：只改這裡（或它下游），兩個入口同步生效。
// 效能鐵則：全域搜尋預設 fullText（與 vault 預設一致——快）；語義留給
// 使用者明確切換（vault UI 有模式切換；全域搜尋未來可加）。

import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/vault/vault_service.dart';
import 'package:bridge_app/services/vector_db/hybrid_search_service.dart';
/// 搜尋模式（vault UI 的四模式——唯一定義處）
enum VaultFacadeMode { fullText, semantic, tag, hybrid }

/// 統一搜尋 facade——所有搜尋入口的單一真相
class VaultSearchFacade {
  VaultSearchFacade._();
  static final VaultSearchFacade instance = VaultSearchFacade._();

  /// 統一搜尋入口。
  ///
  /// 回傳 [VaultEntry] 列表（memories + assets 統一格式：
  /// 資產的 `agent` 欄位 = 'asset_index'）。
  ///
  /// [mode] 預設 fullText（快——SQL LIKE，無嵌入推理）。
  Future<List<VaultEntry>> search({
    required String query,
    VaultFacadeMode mode = VaultFacadeMode.fullText,
    String? roomFilter,
    List<String>? tagFilter,
    int limit = 50,
  }) async {
    if (query.trim().isEmpty && (tagFilter == null || tagFilter.isEmpty)) {
      return [];
    }

    switch (mode) {
      case VaultFacadeMode.hybrid:
        try {
          final hybridResults = await HybridSearchService.instance.search(
            query: query,
            mode: SearchMode.hybrid,
            limit: limit,
          );
          return _hybridToEntries(hybridResults);
        } catch (e) {
          debugPrint('[VaultSearchFacade] hybrid 失敗，降級 fullText: $e');
          return _vaultSearch(query, VaultSearchMode.fullText, roomFilter,
              tagFilter, limit);
        }

      case VaultFacadeMode.fullText:
        // [S4] fullText＝memories（VaultService LIKE）＋ assets（FTS 全文，
        // 無嵌入推理——快）。兩路並行合併，memories 與資產都能找到。
        try {
          final results = await Future.wait([
            _vaultSearch(query, VaultSearchMode.fullText, roomFilter,
                tagFilter, limit),
            HybridSearchService.instance
                .search(query: query, mode: SearchMode.fullText, limit: limit)
                .then((r) => r.assetHits)
                .catchError((e) {
              debugPrint('[VaultSearchFacade] 資產 FTS 失敗（fail-open）: $e');
              return <AssetHit>[];
            }),
          ]);
          final memories = results[0] as List<VaultEntry>;
          final assetHits = results[1] as List<AssetHit>;
          final now = DateTime.now();
          final assets = assetHits
              .map((h) => VaultEntry(
                    id: h.id,
                    content: h.title ?? h.fileName,
                    room: 'bridges',
                    subCategory: '',
                    agent: 'asset_index',
                    source: '',
                    project: '',
                    tags: const ['檔案'],
                    importance: 0,
                    createdAt: now,
                    updatedAt: now,
                    accessCount: 0,
                    archived: false,
                  ))
              .toList();
          return [...memories, ...assets];
        } catch (e) {
          debugPrint('[VaultSearchFacade] fullText 失敗（fail-open）: $e');
          return [];
        }

      case VaultFacadeMode.semantic:
      case VaultFacadeMode.tag:
        return _vaultSearch(query, _toVaultMode(mode), roomFilter, tagFilter,
            limit);
    }
  }

  Future<List<VaultEntry>> _vaultSearch(
    String query,
    VaultSearchMode mode,
    String? roomFilter,
    List<String>? tagFilter,
    int limit,
  ) async {
    try {
      return await VaultService.instance.search(
        mode: mode,
        query: query,
        roomFilter: roomFilter,
        tagFilter: tagFilter,
        limit: limit,
      );
    } catch (e) {
      debugPrint('[VaultSearchFacade] VaultService.search 失敗（fail-open）: $e');
      return [];
    }
  }

  /// HybridSearchResults → VaultEntry（轉換邏輯唯一化——原在 vault_screen）
  List<VaultEntry> _hybridToEntries(HybridSearchResults r) {
    final entries = <VaultEntry>[];
    final now = DateTime.now();
    for (final hit in r.memoryHits) {
      entries.add(VaultEntry(
        id: hit.id,
        content: hit.content,
        room: hit.room,
        subCategory: '',
        agent: '',
        source: '',
        project: '',
        tags: const [],
        importance: 0,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
      ));
    }
    for (final hit in r.assetHits) {
      entries.add(VaultEntry(
        id: hit.id,
        content: hit.fileName,
        room: 'bridges',
        // [小葵 2026-09-09 Blue v2 檢索令] 資料夾分組用——完整相對路徑
        subCategory: hit.filePath,
        agent: 'asset_index', // 資產標記——下游（全域搜尋 hop）以此判斷 domain
        source: '',
        project: '',
        tags: const ['檔案'],
        importance: 0,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
      ));
    }
    return entries;
  }

  VaultSearchMode _toVaultMode(VaultFacadeMode m) => switch (m) {
        VaultFacadeMode.fullText => VaultSearchMode.fullText,
        VaultFacadeMode.semantic => VaultSearchMode.semantic,
        VaultFacadeMode.tag => VaultSearchMode.tag,
        VaultFacadeMode.hybrid => VaultSearchMode.fullText, // 不可達（上面攔截）
      };
}
