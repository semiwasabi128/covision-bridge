// bridge_service.dart
// [Step 4 2026-08-09] 橋的統一管理
//
// 職責：
// 1. 水流完成時自動建橋（記錄 source → flowsTo + bridgeNote）
// 2. 門開啟時自動建橋（記錄母水流 → 門 → returnTo）
// 3. 提供統一查詢入口：所有橋、從某條水流出來的橋、回到某條水流的橋
// 4. 廣播 bridgeFormed 事件（Step 5）
//
// 設計原則：
// - 不新建 DB table——橋的資料存在 TransurfingEngine 的 StreamState 和 DoorRecord 裡
// - BridgeService 是「查詢和索引層」，在 Engine 之上提供方便的 API
// - 自動觸發：Engine 的 completeActiveStream 和 openDoor 內部呼叫

import 'package:flutter/foundation.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';

import 'brain_container_service.dart'; // [Step 6] 寫入 bridges 記憶
import 'transurfing_engine.dart';
import 'transurfing_event.dart';
import '../../models/brain_container/brain_room.dart';

/// 一座橋——連接兩條水流（或水流與門）的接續路徑
///
/// 橋不是獨立的資料結構，而是從 StreamState 和 DoorRecord 中提取的索引視圖。
/// 每座橋記錄：從哪裡來（source）、到哪裡去（target）、怎麼接續（bridgeNote）。
class BridgeRecord {
  /// 橋的 ID（自動生成）
  final String id;

  /// 來源——水流 ID 或門 ID
  final String sourceId;

  /// 來源類型
  final BridgeEndpointType sourceType;

  /// 去向——水流 ID、門 ID、或 'system'
  final String targetId;

  /// 去向類型
  final BridgeEndpointType targetType;

  /// 接續資訊——從這座橋回來時需要知道的關鍵資訊
  final String? note;

  /// 建立時間
  final DateTime createdAt;

  /// 來源標題（方便顯示）
  final String sourceTitle;

  /// 去向標題（方便顯示）
  final String targetTitle;

  const BridgeRecord({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.targetId,
    required this.targetType,
    this.note,
    required this.createdAt,
    required this.sourceTitle,
    required this.targetTitle,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'sourceType': sourceType.name,
        'targetId': targetId,
        'targetType': targetType.name,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'sourceTitle': sourceTitle,
        'targetTitle': targetTitle,
      };

  @override
  String toString() =>
      'Bridge($sourceTitle → $targetTitle${note != null ? ': $note' : ''})';
}

/// 橋的兩端類型
enum BridgeEndpointType {
  /// 水流
  stream,

  /// 門
  door,

  /// 系統（匯入海洋）
  system,
}

/// [Step 4] 橋的統一管理 Service
///
/// 在 TransurfingEngine 之上提供橋的查詢和索引。
/// 不自己存儲資料——每次查詢都從 Engine 的最新狀態提取。
class BridgeService {
  BridgeService._();
  static final BridgeService instance = BridgeService._();

  final TransurfingEngine _engine = TransurfingEngine.instance;

  /// 取得所有橋（從已完成 + 已分流的水流 + 所有門提取）
  List<BridgeRecord> get allBridges {
    final bridges = <BridgeRecord>[];

    for (final stream in _engine.allStreams) {
      // 已完成的水流 → 匯入到 system 或另一條水流
      if (stream.phase == StreamPhase.completed && stream.flowsTo != null) {
        bridges.add(BridgeRecord(
          id: 'bridge_${stream.id}',
          sourceId: stream.id,
          sourceType: BridgeEndpointType.stream,
          targetId: stream.flowsTo!,
          targetType: stream.flowsTo == 'system'
              ? BridgeEndpointType.system
              : BridgeEndpointType.stream,
          note: stream.bridgeNote,
          createdAt: stream.completedAt ?? stream.lastActiveAt,
          sourceTitle: stream.title,
          targetTitle: stream.flowsTo == 'system'
              ? '系統'
              : _engine.allStreams
                      .where((s) => s.id == stream.flowsTo)
                      .firstOrNull
                      ?.title ??
                  stream.flowsTo!,
        ));
      }

      // 已分流的水流 → 流向門
      if (stream.phase == StreamPhase.branched && stream.flowsTo != null) {
        bridges.add(BridgeRecord(
          id: 'bridge_${stream.id}',
          sourceId: stream.id,
          sourceType: BridgeEndpointType.stream,
          targetId: stream.flowsTo!,
          targetType: BridgeEndpointType.door,
          note: stream.bridgeNote,
          createdAt: stream.lastActiveAt,
          sourceTitle: stream.title,
          targetTitle: _engine.allDoors
                  .where((d) => d.id == stream.flowsTo)
                  .firstOrNull
                  ?.title ??
              stream.flowsTo!,
        ));
      }
    }

    // 門 → 回到母水流
    for (final door in _engine.allDoors) {
      bridges.add(BridgeRecord(
        id: 'bridge_${door.id}',
        sourceId: door.id,
        sourceType: BridgeEndpointType.door,
        targetId: door.returnToStreamId,
        targetType: BridgeEndpointType.stream,
        note: '門「${door.title}」完成後回到此水流',
        createdAt: door.createdAt,
        sourceTitle: door.title,
        targetTitle: _engine.allStreams
                .where((s) => s.id == door.returnToStreamId)
                .firstOrNull
                ?.title ??
            door.returnToStreamId,
      ));
    }

    bridges.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return bridges;
  }

  /// 從某條水流出來的橋
  List<BridgeRecord> bridgesFrom(String streamId) {
    return allBridges.where((b) => b.sourceId == streamId).toList();
  }

  /// 回到某條水流的橋
  List<BridgeRecord> bridgesTo(String streamId) {
    return allBridges.where((b) => b.targetId == streamId).toList();
  }

  /// [Step 5] 水流完成時自動建橋並廣播事件
  ///
  /// 由 TransurfingEngine.completeActiveStream() 內部呼叫，
  /// 或由 chat_controller 在確認完成時呼叫。
  void onStreamCompleted(StreamState stream) {
    final bridge = BridgeRecord(
      id: 'bridge_${stream.id}',
      sourceId: stream.id,
      sourceType: BridgeEndpointType.stream,
      targetId: stream.flowsTo ?? 'system',
      targetType: stream.flowsTo == 'system' || stream.flowsTo == null
          ? BridgeEndpointType.system
          : BridgeEndpointType.stream,
      note: stream.bridgeNote,
      createdAt: stream.completedAt ?? DateTime.now(),
      sourceTitle: stream.title,
      targetTitle: stream.flowsTo == 'system' || stream.flowsTo == null
          ? '系統'
          : _engine.allStreams
                  .where((s) => s.id == stream.flowsTo)
                  .firstOrNull
                  ?.title ??
              '未知',
    );

    debugPrint('[BridgeService] 橋建成：$bridge');

    // [Step 6] 寫入 bridges 記憶 → ConnectionDetector 自動建立 bridgeTie 連結
    _writeBridgeMemory(bridge);

    // [Step 5] 廣播 bridgeFormed 事件
    TransurfingEventBroadcaster.instance.broadcast(
      TransurfingEvent(
        type: TransurfingEventType.bridgeFormed,
        title: '${bridge.sourceTitle} → ${bridge.targetTitle}',
        bridgeNote: bridge.note,
      ),
    );
  }

  /// [Step 5] 門開啟時自動建橋並廣播事件
  void onDoorOpened(DoorRecord door) {
    final parentStream = _engine.allStreams
        .where((s) => s.id == door.parentStreamId)
        .firstOrNull;

    final bridge = BridgeRecord(
      id: 'bridge_${door.id}',
      sourceId: door.id,
      sourceType: BridgeEndpointType.door,
      targetId: door.returnToStreamId,
      targetType: BridgeEndpointType.stream,
      note: '門「${door.title}」從「${parentStream?.title ?? '未知'}」分出',
      createdAt: door.createdAt,
      sourceTitle: door.title,
      targetTitle: parentStream?.title ?? door.returnToStreamId,
    );

    debugPrint('[BridgeService] 門橋建成：$bridge');

    // [Step 6] 寫入 bridges 記憶 → ConnectionDetector 自動建立 bridgeTie 連結
    _writeBridgeMemory(bridge);

    TransurfingEventBroadcaster.instance.broadcast(
      TransurfingEvent(
        type: TransurfingEventType.bridgeFormed,
        title: '🚪 ${bridge.sourceTitle} → ${bridge.targetTitle}',
        bridgeNote: bridge.note,
      ),
    );
  }

  /// [Step 6] 將橋寫入 bridges 房間記憶
  ///
  /// 這樣 ConnectionDetector 的 _detectTransurfingTies 會自動偵測到
  /// 新的 bridges 記憶，並建立 bridgeTie 連結到語意最相關的記憶。
  /// 同時 BrainContainer 的 _onMemoryWritten 不會對 bridges 做水流狀態變更，
  /// 所以不會產生循環。
  void _writeBridgeMemory(BridgeRecord bridge) {
    // 異步寫入，不阻塞 Engine 流程
    Future(() async {
      try {
        final svc = BrainContainerService.instance;
        if (!svc.isInitialized) return;
        final content = '橋：${bridge.sourceTitle} → ${bridge.targetTitle}'
            '${bridge.note != null ? '\n${bridge.note}' : ''}';
        // 先用 writeMemory 寫入（extraction pipeline 會分類）
        final ok = await svc.writeMemory(
          content: content,
          agent: 'transurfing',
          tags: ['bridge', bridge.sourceType.name, bridge.targetType.name],
          speaker: MemorySpeaker.agent, // [出處戳] 橋記憶=系統產出
        );
        if (ok) {
          // 手動把最近的這條記憶的 room 改為 bridges
          svc.overrideLatestMemoryRoom(BrainRoom.bridges);
          debugPrint('[BridgeService] bridges 記憶已寫入：${bridge.sourceTitle}');
        }
      } catch (e) {
        debugPrint('[BridgeService] bridges 記憶寫入失敗: $e');
      }
    });
  }
}
