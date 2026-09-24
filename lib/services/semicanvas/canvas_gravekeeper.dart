// canvas_gravekeeper.dart
// [教練 Agent 2026-08-26 使用者 三刀之一] 殭屍節點清掃員
//
// 2026-08-26 事件根因補刀：畫布刪除時節點（CanvasProps）沒有級聯刪除，
// 24 個歷史畫布累積 182 個殭屍節點躺在 SharedPreferences，
// 其中 4 個 imageGen 殭屍在跨畫布洩漏時被執行 → 28 張幽靈圖片。
//
// 本服務：比對 CanvasStore 活著的畫布 vs 節點的 canvasId，
// 屬於已死畫布的節點全清（連同 relations）。
// 啟動時自動跑一次（冪等），未來殭屍不會再累積。

import 'package:flutter/foundation.dart';

import '../entity_graph/entity_graph_service.dart';
import '../canvas_store.dart';
class CanvasGravekeeper {
  CanvasGravekeeper._();
  static final CanvasGravekeeper instance = CanvasGravekeeper._();

  /// 清掃孤兒節點。回傳 {removed: 清了幾個, kept: 留了幾個}。
  Future<Map<String, int>> sweep(EntityGraphService entityGraph) async {
    try {
      // 1. 活著的畫布 ID 集合
      final liveIds = (await CanvasStore.getAll()).map((c) => c.id).toSet();

      // 2. 全部節點
      final all = await entityGraph.getCanvasNodes();
      var removed = 0;
      var kept = 0;

      for (final entry in all) {
        final cid = entry.props.canvasId;
        // 留：屬於活著的畫布，或屬於 'default'（未存檔的暫存畫布）
        final isLive = cid == 'default' || liveIds.contains(cid);
        if (isLive) {
          kept++;
          continue;
        }
        // 殭屍：級聯刪 relations + CanvasProps
        final outRels = await entityGraph.getRelations(entry.entity.id);
        final inRels = await entityGraph.getReverseRelations(entry.entity.id);
        for (final rel in [...outRels, ...inRels]) {
          await entityGraph.removeRelation(rel.sourceId, rel.targetId, rel.type);
        }
        await entityGraph.removeFromCanvas(entry.entity.id);
        removed++;
      }

      if (removed > 0) {
        debugPrint('[CanvasGravekeeper] 清掃完成：移除 $removed 個殭屍節點，保留 $kept 個');
      }
      return {'removed': removed, 'kept': kept};
    } catch (e) {
      debugPrint('[CanvasGravekeeper] 清掃失敗（不阻擋啟動）：$e');
      return {'removed': -1, 'kept': -1};
    }
  }
}
