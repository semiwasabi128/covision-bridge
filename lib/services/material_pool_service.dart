// 素材池／素材包服務 — Material Pack Service
//
// [小葵 2026-08-29 Phase 1] Blue 的「便利店→購物車→調色盤」一條龍：
// 使用者在向量資料庫搜尋→預覽→挑選資產進素材池（購物車草稿）→
// 打包存檔成素材包（可重複載入、可綁定畫布專案）→
// 畫布/對話頁匯入當調色盤。
//
// 關鍵設計：
// - 素材池 = 素材包的「草稿狀態」（單一系統，不需要兩套）
// - 包只存「引用」（assetId + filePath），檔案系統是唯一真相——
//   刪包不刪檔，永遠不會弄亂使用者的檔案（便利店保證）
// - 持久化：material_packs.json（與 conversations.json 同模式）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 素材包內的單一素材引用
class MaterialItem {
  final String assetId; // asset_index 的 id
  final String filePath; // 顯示/開檔用（相對路徑或絕對路徑）
  final String fileName;
  final String? title;
  final String? note; // 使用者備註（選填）
  final int addedAt; // epoch ms

  const MaterialItem({
    required this.assetId,
    required this.filePath,
    required this.fileName,
    this.title,
    this.note,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'filePath': filePath,
        'fileName': fileName,
        'title': title,
        'note': note,
        'addedAt': addedAt,
      };

  factory MaterialItem.fromJson(Map<String, dynamic> j) => MaterialItem(
        assetId: j['assetId'] as String? ?? '',
        filePath: j['filePath'] as String? ?? '',
        fileName: j['fileName'] as String? ?? '',
        title: j['title'] as String?,
        note: j['note'] as String?,
        addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
      );
}

/// 素材包
class MaterialPack {
  final String id;
  String title;
  final int createdAt;
  int updatedAt;
  final List<MaterialItem> items;
  final String? canvasId; // 綁定畫布專案（null = 通用包，可跨專案用）

  MaterialPack({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<MaterialItem>? items,
    this.canvasId,
  }) : items = items ?? [];

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get itemCount => items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'canvasId': canvasId,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory MaterialPack.fromJson(Map<String, dynamic> j) => MaterialPack(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '未命名素材包',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        canvasId: j['canvasId'] as String?,
        items: [
          for (final it in (j['items'] as List? ?? []))
            MaterialItem.fromJson((it as Map).cast<String, dynamic>()),
        ],
      );
}

/// 素材池服務 — 單例
///
/// 職責：
/// 1. 維護「當前素材池」（草稿）——向量庫頁加入/移除/預覽
/// 2. 打包存檔（草稿 → 持久化素材包）/ 載入既有包續挑
/// 3. 列出/刪除素材包（供畫布/對話頁匯入）
class MaterialPoolService extends ChangeNotifier {
  MaterialPoolService._();
  static final MaterialPoolService instance = MaterialPoolService._();

  static const _fileName = 'material_packs.json';

  /// 當前素材池（草稿）——null = 沒有進行中的挑選
  MaterialPack? _draft;

  /// 已存檔的素材包
  List<MaterialPack> _packs = [];

  MaterialPack? get draft => _draft;
  List<MaterialPack> get packs => List.unmodifiable(_packs);
  int get draftCount => _draft?.itemCount ?? 0;

  bool get hasDraft => _draft != null && _draft!.itemCount > 0;

  File? _storageFile() {
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File(
        '$home/Library/Application Support/farm.semiwasabi.bridgeApp/bridge_state/$_fileName');
  }

  // ── 載入/持久化 ─────────────────────────────────────────

  Future<void> load() async {
    final f = _storageFile();
    if (f == null || !await f.exists()) return;
    try {
      final j = jsonDecode(await f.readAsString());
      final list = (j as List? ?? [])
          .map((e) => MaterialPack.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      _packs = list;
      notifyListeners();
    } catch (e) {
      debugPrint('[MaterialPool] load 失敗: $e');
    }
  }

  Future<void> _persist() async {
    final f = _storageFile();
    if (f == null) return;
    try {
      final j =
          jsonEncode(_packs.map((p) => p.toJson()).toList());
      await f.writeAsString(j);
    } catch (e) {
      debugPrint('[MaterialPool] persist 失敗: $e');
    }
  }

  // ── 素材池（草稿）操作 ───────────────────────────────────

  /// 開新草稿（若已有草稿且有內容，回傳 false＝先處理掉現有草稿）
  bool startNewDraft() {
    if (hasDraft) return false;
    _draft = MaterialPack(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      title: '未命名素材包',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    return true;
  }

  /// 把資產加入草稿。重複（同 assetId）不加，回傳是否成功。
  bool addToDraft({
    required String assetId,
    required String filePath,
    required String fileName,
    String? title,
  }) {
    if (_draft == null) {
      startNewDraft();
    }
    if (_draft == null) return false;
    if (_draft!.items.any((i) => i.assetId == assetId)) return false;
    _draft!.items.add(MaterialItem(
      assetId: assetId,
      filePath: filePath,
      fileName: fileName,
      title: title,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _draft!.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    return true;
  }

  /// 從草稿移除
  void removeFromDraft(String assetId) {
    if (_draft == null) return;
    _draft!.items.removeWhere((i) => i.assetId == assetId);
    _draft!.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// 清空草稿（不放進包庫）
  void discardDraft() {
    _draft = null;
    notifyListeners();
  }

  // ── 打包／素材包操作 ─────────────────────────────────────

  /// 打包存檔：草稿 → 素材包（固化）。回傳建立的包。
  MaterialPack? sealDraft({String? title, String? canvasId}) {
    if (_draft == null || _draft!.isEmpty) return null;
    _draft!.title = (title != null && title.isNotEmpty)
        ? title
        : _draft!.title;
    if (canvasId != null) {
      // 綁 canvas 需重建（final 欄位）——直接改 id 保留 items
      final bound = MaterialPack(
        id: _draft!.id,
        title: _draft!.title,
        createdAt: _draft!.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        items: _draft!.items,
        canvasId: canvasId,
      );
      _draft = null;
      _packs.add(bound);
      _persist();
      notifyListeners();
      return bound;
    }
    _draft!.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final sealed = _draft!;
    _draft = null;
    _packs.add(sealed);
    _persist();
    notifyListeners();
    return sealed;
  }

  /// 載入既有包進草稿（續挑）
  Future<void> loadPackAsDraft(String packId) async {
    final pack = _packs.where((p) => p.id == packId).firstOrNull;
    if (pack == null) return;
    _draft = MaterialPack(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      title: pack.title,
      createdAt: pack.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      items: [...pack.items],
    );
    notifyListeners();
  }

  /// 刪除素材包（不刪檔案——只是刪指標）
  Future<void> deletePack(String packId) async {
    _packs.removeWhere((p) => p.id == packId);
    await _persist();
    notifyListeners();
  }

  /// 取得單一素材包
  MaterialPack? getPack(String packId) =>
      _packs.where((p) => p.id == packId).firstOrNull;

  /// 依畫布取包（畫布調色盤用）
  List<MaterialPack> packsForCanvas(String canvasId) =>
      _packs.where((p) => p.canvasId == canvasId).toList();
}
