// swarm_map.dart
// [TRIO M4 2026-09-22] G4 作戰地圖——把計畫渲染成畫布骨架
//
// 軍官節點（大）＋兵節點（小）＋指揮鏈連線，開戰前先看見戰場。
// 用 headless CanvasController＋annotation 節點（TaskDispatcher 同配方），
// 地圖是「給人看的骨架」——不是執行圖；執行期的實況在 L2 星系（M5）。
library;

import 'package:flutter/material.dart' show Offset;
import 'package:bridge_app/services/canvas_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart';

/// 一個軍的定義（作戰計畫的結構化呈現）
class SwarmLegion {
  final String name; // 軍名（如「研究軍」）
  final String mission; // 任務
  final int troops; // 兵力
  const SwarmLegion({required this.name, required this.mission, required this.troops});
}

/// 渲染作戰地圖——回傳畫布 id
///
/// 佈局：軍官橫列頂部，各軍往下展開兵格（每軍一列）。
/// 節點用 annotation（文字卡）——作戰地圖是計畫骨架非工作流。
Future<String> renderSwarmMap({
  required String campaignId,
  required String objective,
  required List<SwarmLegion> legions,
  String? conversationId,
}) async {
  final canvas = await CanvasStore.create(
    title: '〔作戰地圖〕$objective',
    conversationId: conversationId,
  );

  final entityGraph = EntityGraphService.withSqliteCanvasStore(
    memoryStore: MemoryStore(),
    doorStore: ProjectDoorStore(),
    assetStore: DigitalAssetRegistryStore(),
  );
  final ctrl = CanvasController(
    entityGraph: entityGraph,
    canvasId: canvas.id,
  );

  try {
    // 指揮部（主節點）——頂部中央
    final totalTroops = legions.fold<int>(0, (s, l) => s + l.troops);
    await ctrl.addAnnotation(
      const Offset(400, 60),
      '⚔️ 指揮部\n目標：$objective\n總兵力：$totalTroops 兵 / ${legions.length} 軍',
    );

    // 各軍——橫列
    for (var i = 0; i < legions.length; i++) {
      final l = legions[i];
      final x = 120.0 + i * 260;
      // 軍官節點（大卡）
      await ctrl.addAnnotation(
        Offset(x, 220),
        '🎖️ ${l.name}（軍官）\n任務：${l.mission}\n兵力：${l.troops} 兵',
      );
      // 兵格——每 5 兵一張卡（10 兵畫 10 個小點太碎；5 兵格=2 張）
      final cells = (l.troops / 5).ceil();
      for (var c = 0; c < cells; c++) {
        final from = c * 5 + 1;
        final to = (c + 1) * 5 > l.troops ? l.troops : (c + 1) * 5;
        await ctrl.addAnnotation(
          Offset(x + 10, 340 + c * 90),
          '兵 $from-$to：待命',
        );
      }
    }
    return canvas.id;
  } finally {
    // 地圖畫完即存檔——controller 用完釋放（畫布由 CanvasStore 持久化）
    ctrl.dispose();
  }
}
