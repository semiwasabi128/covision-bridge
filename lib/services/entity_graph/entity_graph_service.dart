// entity_graph_service.dart
// Entity Graph 路由層 — 在現有三個 Store 上面加抽象
// 建立日期: 2026-07-10
//
// 設計文件: entity-graph-service-design.md §2
//
// 職責：
// 1. 統一查詢入口（跨 Store）
// 2. 關聯管理（relations）
// 3. 畫布空間屬性管理（canvasProps）
//
// 底層 Store 完全不動——EntityGraphService 是包裝層。

import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/models/digital_asset.dart';
import 'package:bridge_app/models/entity_graph/canvas_props.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'package:bridge_app/models/flow_step.dart';
import 'package:bridge_app/services/canvas_state_store_sqlite.dart';
import 'package:bridge_app/models/project_door.dart';
import 'package:bridge_app/services/canvas_state_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_relation_store.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:flutter/foundation.dart';

class EntityGraphService {
  // ── 依賴注入 ──
  // MemoryStore 的方法是 static 的，但保留注入以符合設計文件介面，
  // 並在未來重構為非 static 時直接可用。
  // ignore: unused_field
  final MemoryStore _memoryStore;
  final ProjectDoorStore _doorStore;
  final DigitalAssetRegistryStore _assetStore;
  final EntityRelationStore _relationStore;
  final CanvasStateStore _canvasStateStore;

  // ── 建構 ──
  EntityGraphService({
    required MemoryStore memoryStore,
    required ProjectDoorStore doorStore,
    required DigitalAssetRegistryStore assetStore,
    EntityRelationStore? relationStore,
    CanvasStateStore? canvasStateStore,
  })  : _memoryStore = memoryStore,
        _doorStore = doorStore,
        _assetStore = assetStore,
        _relationStore = relationStore ?? const EntityRelationStore(),
        _canvasStateStore = canvasStateStore ?? const CanvasStateStore();
  // [教練 Agent 2026-08-26 搬遷令] default 換 SQLite 版——plist 整包 JSON →
  // 逐列 UPSERT + canvas_id 索引 + 原子交易。搬遷自動、失敗自動退回舊路徑。
  // 備援：舊 CanvasStateStore 保留（LegacyCanvasStateStore 同源邏輯）。
  factory EntityGraphService.withSqliteCanvasStore({
    required MemoryStore memoryStore,
    required ProjectDoorStore doorStore,
    required DigitalAssetRegistryStore assetStore,
    EntityRelationStore? relationStore,
  }) {
    return EntityGraphService(
      memoryStore: memoryStore,
      doorStore: doorStore,
      assetStore: assetStore,
      relationStore: relationStore,
      canvasStateStore: _sqliteCanvasStoreAdapter,
    );
  }

  /// SqliteCanvasStateStore 介面卡——它不是 CanvasStateStore 子類
  /// （避免檔案間循環依賴），這裡以 duck-typing 橋接同名方法。
  static final _sqliteCanvasStoreAdapter = _SqliteStoreAdapter();

  // ═══════════════════════════════════════════════════════════════
  // 核心 CRUD
  // ═══════════════════════════════════════════════════════════════

  /// 根據 ID 取得 Entity（自動路由到對應 Store）。
  ///
  /// 路由邏輯（§2.2）：
  /// - `project-door-*` → ProjectDoorStore
  /// - `digital-asset-*` → DigitalAssetRegistryStore
  /// - `flow-*` → ProjectDoorStore → 遍歷門的 flowSteps
  /// - 其他 → MemoryStore
  ///
  /// 回傳 null 如果 ID 不存在於任何 Store。
  Future<Entity?> getEntity(String id) async {
    final type = _inferType(id);

    switch (type) {
      case EntityType.door:
        final doors = await _doorStore.loadAll();
        final door = doors.where((d) => d.id == id).firstOrNull;
        if (door == null) return null;
        return _wrapDoor(door);

      case EntityType.asset:
        final assets = await _assetStore.getAll();
        final asset = assets.where((a) => a.id == id).firstOrNull;
        if (asset == null) return null;
        return _wrapAsset(asset);

      case EntityType.flowstep:
        // FlowStep 內嵌於 Door，需遍歷所有門
        final doors = await _doorStore.loadAll();
        for (final door in doors) {
          final step = door.flowSteps.where((s) => s.id == id).firstOrNull;
          if (step != null) {
            return _wrapFlowStep(step, door.id);
          }
        }
        return null;

      case EntityType.memory:
        final memory = await MemoryStore.getById(id);
        if (memory == null) return null;
        return _wrapMemory(memory);

      case EntityType.screencapture:
      case EntityType.annotation:
        // Phase 1.5 B3/B4 實作
        return null;
    }
  }

  /// 批量取得 Entity。
  Future<List<Entity>> getEntities(List<String> ids) async {
    final results = <Entity>[];
    for (final id in ids) {
      final entity = await getEntity(id);
      if (entity != null) {
        results.add(entity);
      }
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  // 關聯管理
  // ═══════════════════════════════════════════════════════════════

  /// 取得 Entity 的所有關聯。
  Future<List<EntityRelation>> getRelations(String entityId) async {
    return _relationStore.getRelations(entityId);
  }

  /// 取得反向關聯（誰引用了這個 Entity）。
  /// 例：哪些門引用了這條記憶？
  Future<List<EntityRelation>> getReverseRelations(String entityId) async {
    return _relationStore.getReverseRelations(entityId);
  }

  /// 建立關聯。
  Future<void> addRelation(EntityRelation relation) async {
    await _relationStore.add(relation);
  }

  /// [教練 Agent 2026-08-15 批量載入] 範本匯入用——多條 relation 一次寫入。
  Future<void> addRelationsBatch(List<EntityRelation> relations) async {
    for (final r in relations) {
      await _relationStore.add(r);
    }
  }

  /// [教練 Agent 2026-08-15 批量載入] 範本匯入用——多個 CanvasProps 一次寫入。
  /// 與逐次 setCanvasProps 的差別：呼叫端不 await 每一步，
  /// DB 端 store 內部 debounce/transaction 合併提交。
  Future<void> upsertCanvasPropsBatch(List<(String, CanvasProps)> items) async {
    for (final (id, props) in items) {
      await _canvasStateStore.set(id, props);
    }
  }

  /// 移除關聯。
  Future<void> removeRelation(
      String sourceId, String targetId, RelationType type) async {
    await _relationStore.remove(sourceId, targetId, type);
  }

  // ═══════════════════════════════════════════════════════════════
  // 畫布操作
  // ═══════════════════════════════════════════════════════════════

  /// 把 Entity 放到畫布上（加 CanvasProps）。
  /// 如果已有 CanvasProps 則更新位置。
  Future<void> addToCanvas(String entityId,
      {required double x, required double y, String? canvasId}) async {
    final existing = await _canvasStateStore.getAsync(entityId);
    if (existing != null) {
      // 更新位置，保留其他屬性
      await _canvasStateStore.set(
          entityId, existing.copyWith(x: x, y: y, canvasId: canvasId));
    } else {
      await _canvasStateStore.set(
          entityId,
          CanvasProps(
            x: x,
            y: y,
            origin: CanvasNodeOrigin.brain,
            canvasId: canvasId,
          ));
    }
  }

  /// 從畫布移除（移除 CanvasProps，Entity 本身不刪）。
  Future<void> removeFromCanvas(String entityId) async {
    await _canvasStateStore.remove(entityId);
  }

  /// 取得單一節點的 CanvasProps。
  Future<CanvasProps?> getCanvasNode(String entityId) async {
    return _canvasStateStore.getAsync(entityId);
  }

  /// 直接設定節點的 CanvasProps（覆寫）。
  Future<void> setCanvasProps(String entityId, CanvasProps props) async {
    await _canvasStateStore.set(entityId, props);
  }

  /// 更新節點的 CanvasProps（部分更新）。
  Future<void> updateCanvasProps(String entityId, CanvasProps props) async {
    await _canvasStateStore.set(entityId, props);
  }

  /// 清空指定畫布的所有節點（不影響其他畫布）。
  Future<void> clearCanvas(String? canvasId) async {
    if (canvasId == null) {
      await _canvasStateStore.clear();
      return;
    }
    final all = await _canvasStateStore.loadAll();
    for (final entry in all.entries) {
      if (entry.value.canvasId == canvasId) {
        await _canvasStateStore.remove(entry.key);
      }
    }
  }

  /// 取得指定畫布上的 Entity（有 CanvasProps 且 canvasId 匹配的）。
  /// 回傳 Entity + CanvasProps 的組合。
  Future<List<CanvasEntry>> getCanvasNodes({String? canvasId}) async {
    // [教練 Agent 2026-08-26 搬遷令] canvasId 下推到 SQL WHERE——
    // 舊路徑 loadAll() 全撈再記憶體過濾；新路徑直接吃 idx_canvas_nodes_canvas 索引。
    final canvasMap = await _canvasStateStore.loadAll(canvasId: canvasId);
    final entries = <CanvasEntry>[];

    for (final entry in canvasMap.entries) {
      final entity = await getEntity(entry.key);
      if (entity != null) {
        entries.add(CanvasEntry(entity: entity, props: entry.value));
      } else {
        // 沒有對應 Entity 的畫布節點（示範節點、手動新增的工作流節點）
        // 用 CanvasProps 中的資訊建立 fallback Entity（必須帶上 canvasProps，
        // 否則節點面板讀不到 nodeType，_onParamsChanged 也拿不到舊值）
        final props = entry.value;
        final title = props.params['title'] as String? ??
            (props.nodeType != null
                ? '${workflowNodeTypeLabel(props.nodeType!)} 節點'
                : '未命名節點');
        entries.add(CanvasEntry(
          entity: Entity(
            id: entry.key,
            type: props.nodeType != null
                ? EntityType.flowstep
                : EntityType.memory,
            title: title,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            source: EntitySource.human,
            tags: const [],
            relations: const [],
            canvasProps: props,
          ),
          props: props,
        ));
      }
    }

    return entries;
  }

  /// 更新畫布節點的視覺狀態（idle → done 等）。
  Future<void> updateCanvasVisualState(
      String entityId, CanvasVisualState state) async {
    final existing = await _canvasStateStore.getAsync(entityId);
    if (existing == null) {
      debugPrint('[EntityGraphService] updateCanvasVisualState: '
          'entity $entityId 不在畫布上');
      return;
    }
    await _canvasStateStore.set(
        entityId, existing.copyWith(visualState: state));
  }

  // ═══════════════════════════════════════════════════════════════
  // 搜尋
  // ═══════════════════════════════════════════════════════════════

  /// 跨 Store 搜尋 Entity。
  /// 搜尋範圍：title / content / tags。
  Future<List<Entity>> searchEntities(String query,
      {List<EntityType>? types}) async {
    final q = query.toLowerCase();
    final results = <Entity>[];
    final typeFilter = types ?? EntityType.values;

    // 搜 Memory
    if (typeFilter.contains(EntityType.memory)) {
      final memories = await MemoryStore.search(q);
      for (final memory in memories) {
        results.add(await _wrapMemoryAsync(memory));
      }
    }

    // 搜 Door
    if (typeFilter.contains(EntityType.door)) {
      final doors = await _doorStore.loadAll();
      for (final door in doors) {
        if (door.title.toLowerCase().contains(q) ||
            door.sourceIntent.toLowerCase().contains(q)) {
          results.add(await _wrapDoorAsync(door));
        }
      }
    }

    // 搜 Asset
    if (typeFilter.contains(EntityType.asset)) {
      final assets = await _assetStore.getAll();
      for (final asset in assets) {
        if (asset.title.toLowerCase().contains(q) ||
            asset.summary.toLowerCase().contains(q) ||
            asset.tags.any((t) => t.toLowerCase().contains(q))) {
          results.add(await _wrapAssetAsync(asset));
        }
      }
    }

    return results;
  }

  /// 按標籤篩選。
  Future<List<Entity>> getByTag(String tag,
      {List<EntityType>? types}) async {
    final tagLower = tag.toLowerCase();
    final results = <Entity>[];
    final typeFilter = types ?? EntityType.values;

    // Memory
    if (typeFilter.contains(EntityType.memory)) {
      try {
        final memories = await MemoryStore.search(tagLower);
        for (final memory in memories) {
          if (memory.tags.any((t) => t.toLowerCase().contains(tagLower))) {
            results.add(await _wrapMemoryAsync(memory));
          }
        }
      } catch (_) {}
    }

    // Door（Door 目前沒有 tags 欄位，跳過）
    // Asset
    if (typeFilter.contains(EntityType.asset)) {
      final assets = await _assetStore.getAll();
      for (final asset in assets) {
        if (asset.tags.any((t) => t.toLowerCase().contains(tagLower)) ||
            asset.purposeTags.any((t) => t.toLowerCase().contains(tagLower)) ||
            asset.creativeTags.any((t) => t.toLowerCase().contains(tagLower))) {
          results.add(await _wrapAssetAsync(asset));
        }
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  // 遷移輔助
  // ═══════════════════════════════════════════════════════════════

  /// 從現有交叉引用匯入關聯。
  /// 掃描所有 ProjectDoor 的 linkedAssetIds / linkedMemoryIds，
  /// 自動建立 references 關聯。
  /// 只需呼叫一次（首次啟用 Entity Graph 時）。
  /// 回傳匯入的關聯數量。
  Future<int> importExistingRelations() async {
    final doors = await _doorStore.loadAll();
    final relations = <EntityRelation>[];

    for (final door in doors) {
      // Door → Memory（references）
      for (final memoryId in door.linkedMemoryIds) {
        relations.add(EntityRelation(
          sourceId: door.id,
          targetId: memoryId,
          type: RelationType.references,
        ));
      }
      // Door → Asset（references）
      for (final assetId in door.linkedAssetIds) {
        relations.add(EntityRelation(
          sourceId: door.id,
          targetId: assetId,
          type: RelationType.references,
        ));
      }
      // Door → FlowStep（contains）
      for (final step in door.flowSteps) {
        relations.add(EntityRelation(
          sourceId: door.id,
          targetId: step.id,
          type: RelationType.contains,
        ));
        // FlowStep → Asset（references）
        for (final assetId in step.linkedAssetIds) {
          relations.add(EntityRelation(
            sourceId: step.id,
            targetId: assetId,
            type: RelationType.references,
          ));
        }
        // FlowStep → Memory（references）
        for (final memoryId in step.linkedMemoryIds) {
          relations.add(EntityRelation(
            sourceId: step.id,
            targetId: memoryId,
            type: RelationType.references,
          ));
        }
      }
    }

    // 批次寫入（add 有去重邏輯，重複呼叫安全）
    await _relationStore.addAll(relations);
    return relations.length;
  }

  // ═══════════════════════════════════════════════════════════════
  // ID 路由
  // ═══════════════════════════════════════════════════════════════

  /// 根據 ID 前綴判斷 Entity 類型，路由到對應 Store。
  EntityType _inferType(String id) {
    if (id.startsWith('project-door-')) return EntityType.door;
    if (id.startsWith('digital-asset-')) return EntityType.asset;
    if (id.startsWith('flow-')) return EntityType.flowstep;
    if (id.startsWith('screen-')) return EntityType.screencapture;
    if (id.startsWith('annotation-')) return EntityType.annotation;
    // Memory 沒有固定前綴 → 預設為 memory
    return EntityType.memory;
  }

  // ═══════════════════════════════════════════════════════════════
  // Wrapper 方法 — 底層 Model → Entity
  // ═══════════════════════════════════════════════════════════════

  /// Memory → Entity
  Entity _wrapMemory(Memory memory) {
    return Entity(
      id: memory.id,
      type: EntityType.memory,
      title: memory.content, // Memory 沒有 title 欄位，用 content
      createdAt: memory.createdAt,
      updatedAt: memory.updatedAt,
      companionId: memory.companionId,
      source: memory.source == MemorySource.chat
          ? EntitySource.human
          : EntitySource.agent,
      tags: memory.tags,
      relations: const [], // 由 _relationStore 查詢
      canvasProps: null, // 同步版無法查 async，用 _wrapMemoryAsync
      underlying: memory,
    );
  }

  /// Memory → Entity（async 版，含 CanvasProps）
  Future<Entity> _wrapMemoryAsync(Memory memory) async {
    final canvasProps = await _canvasStateStore.getAsync(memory.id);
    final relations = await _relationStore.getRelations(memory.id);
    return Entity(
      id: memory.id,
      type: EntityType.memory,
      title: memory.content,
      createdAt: memory.createdAt,
      updatedAt: memory.updatedAt,
      companionId: memory.companionId,
      source: memory.source == MemorySource.chat
          ? EntitySource.human
          : EntitySource.agent,
      tags: memory.tags,
      relations: relations,
      canvasProps: canvasProps,
      underlying: memory,
    );
  }

  /// ProjectDoor → Entity
  Entity _wrapDoor(ProjectDoor door) {
    return Entity(
      id: door.id,
      type: EntityType.door,
      title: door.title,
      createdAt: door.createdAt,
      updatedAt: door.updatedAt,
      companionId: null, // Door 沒有 companionId
      source: EntitySource.human, // Door 目前都由人建
      tags: const [],
      relations: const [],
      canvasProps: null,
      underlying: door,
    );
  }

  /// ProjectDoor → Entity（async 版，含 CanvasProps + relations）
  Future<Entity> _wrapDoorAsync(ProjectDoor door) async {
    final canvasProps = await _canvasStateStore.getAsync(door.id);
    final relations = await _relationStore.getRelations(door.id);
    return Entity(
      id: door.id,
      type: EntityType.door,
      title: door.title,
      createdAt: door.createdAt,
      updatedAt: door.updatedAt,
      companionId: null,
      source: EntitySource.human,
      tags: const [],
      relations: relations,
      canvasProps: canvasProps,
      underlying: door,
    );
  }

  /// DigitalAsset → Entity
  Entity _wrapAsset(DigitalAsset asset) {
    return Entity(
      id: asset.id,
      type: EntityType.asset,
      title: asset.title,
      createdAt: asset.createdAt,
      updatedAt: asset.updatedAt,
      companionId: null,
      source: EntitySource.human,
      tags: asset.tags,
      relations: const [],
      canvasProps: null,
      underlying: asset,
    );
  }

  /// DigitalAsset → Entity（async 版，含 CanvasProps + relations）
  Future<Entity> _wrapAssetAsync(DigitalAsset asset) async {
    final canvasProps = await _canvasStateStore.getAsync(asset.id);
    final relations = await _relationStore.getRelations(asset.id);
    return Entity(
      id: asset.id,
      type: EntityType.asset,
      title: asset.title,
      createdAt: asset.createdAt,
      updatedAt: asset.updatedAt,
      companionId: null,
      source: EntitySource.human,
      tags: asset.tags,
      relations: relations,
      canvasProps: canvasProps,
      underlying: asset,
    );
  }

  /// FlowStep → Entity
  Entity _wrapFlowStep(FlowStep step, String parentDoorId) {
    return Entity(
      id: step.id,
      type: EntityType.flowstep,
      title: step.title,
      createdAt: step.createdAt,
      updatedAt: step.updatedAt,
      companionId: null,
      source: EntitySource.human,
      tags: const [],
      relations: [
        EntityRelation(
          sourceId: parentDoorId,
          targetId: step.id,
          type: RelationType.contains,
        )
      ],
      canvasProps: null,
      underlying: step,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// [教練 Agent 2026-08-26 搬遷令] SQLite store 介面卡
// ═══════════════════════════════════════════════════════════════
/// SqliteCanvasStateStore（canvas_state_store_sqlite.dart）與
/// CanvasStateStore 方法同名但非繼承——此介面卡把它橋成
/// CanvasStateStore 介面，讓 EntityGraphService 無痛換底層。
class _SqliteStoreAdapter implements CanvasStateStore {
  final _inner = SqliteCanvasStateStore();

  @override
  Future<CanvasProps?> getAsync(String entityId) => _inner.getAsync(entityId);

  @override
  Future<void> set(String entityId, CanvasProps props) =>
      _inner.set(entityId, props);

  @override
  Future<void> remove(String entityId) => _inner.remove(entityId);

  @override
  Future<Map<String, CanvasProps>> loadAll({String? canvasId}) =>
      _inner.loadAll(canvasId: canvasId);

  @override
  Future<void> clear() => _inner.clear();
}
