// five_factor_rerank.dart
// [小葵 2026-09-09 Blue v2 檢索令] 五因素加權重排——Blue 的重要性順序：
//   1. 檔名 > 2. 資料夾路徑 > 3. 分類/主題 > 4. 任務血緣 > 5. 語意相似
//
// 設計稿 §3：
//   final_score = 0.30·name + 0.25·folder + 0.20·context + 0.15·task + 0.10·semantic
// name/folder/context/task = 0|1（查詢詞命中該欄位），semantic = 0-1。
// re-rank 層——不改召回，只改排序。權重可調（入羅盤規則）。

import '../vector_db/hybrid_search_service.dart';

class FiveFactorRerank {
  /// 對 AssetHit 列表加權重排。
  ///
  /// [query] 原始查詢（拆詞比對）
  /// [hits] 召回結果（含 semantic score）
  static List<AssetHit> rerank(String query, List<AssetHit> hits) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[\s,，、/]+'))
        .where((t) => t.length >= 2)
        .toList();
    if (terms.isEmpty || hits.isEmpty) return hits;

    final scored = <MapEntry<AssetHit, double>>[];
    for (final h in hits) {
      final name = h.fileName.toLowerCase();
      final folder = h.filePath.toLowerCase();
      final title = (h.title ?? '').toLowerCase();
      final summary = (h.summary ?? '').toLowerCase();

      // 因素1：檔名（含 title——display_title 是人話檔名）
      final nameHit = terms.any((t) => name.contains(t) || title.contains(t))
          ? 1.0
          : 0.0;
      // 因素2：資料夾路徑
      final folderHit = terms.any((t) => folder.contains(t)) ? 1.0 : 0.0;
      // 因素3：分類/主題（summary 帶 [分類:]/[主題:] 前綴——身份嵌入後有效）
      final contextHit = terms.any((t) => summary.contains(t)) ? 1.0 : 0.0;
      // 因素4：任務血緣（[任務: ...] 出現在 content/summary——召回端帶出）
      //   與 context 合併判定：身份段命中即算
      // 因素5：語意相似（已由召回端算好，夾在 0-1）
      final semantic = h.score.clamp(0.0, 1.0);

      final score = 0.30 * nameHit +
          0.25 * folderHit +
          0.20 * contextHit +
          0.15 * contextHit + // 任務段與分類段同在 summary 命中空間
          0.10 * semantic;

      // [小葵 2026-09-09 Blue 令] 類型層級——圖片最常被搜，排最上面；
      // 再來文字類（文章/有意義文字）；其他殿後。同層內按五因素分數。
      final tier = _typeTier(h);
      scored.add(MapEntry(h, tier * 1000 + score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  /// 類型層級：2=圖片/影像、1=文字（md/txt/doc…）、0=其他。
  /// tier*1000 保證壓過五因素分數（≤1.0）——類型分層嚴格優先。
  static int _typeTier(AssetHit h) {
    final kind = h.assetKind.toLowerCase();
    final name = h.fileName.toLowerCase();
    final isImage = kind.contains('image') ||
        ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic']
            .any((e) => name.endsWith(e));
    if (isImage) return 2;
    final isText = kind.contains('text') ||
        kind.contains('document') ||
        ['.md', '.txt', '.pdf', '.doc', '.docx', '.csv', '.json']
            .any((e) => name.endsWith(e));
    if (isText) return 1;
    return 0;
  }
}
