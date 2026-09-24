// entity_graph_test.dart
// B1 EntityGraphService 路由層測試
// 建立日期: 2026-07-10
//
// 測試範圍：
// - EntityRelationStore CRUD
// - CanvasStateStore CRUD
// - EntityGraphService 路由（getEntity 各類型）
// - searchEntities
// - importExistingRelations
// - feature flag

import 'dart:convert';

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/models/digital_asset.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/flow_step.dart';
import 'package:bridge_app/models/project_door.dart';
import 'package:bridge_app/services/canvas_state_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/entity_relation_store.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ═══════════════════════════════════════════════════════════════
  // EntityRelationStore CRUD
  // ═══════════════════════════════════════════════════════════════

  group('EntityRelationStore', () {
    const store = EntityRelationStore();

    test('add and getAll', () async {
      expect(await store.getAll(), isEmpty);

      await store.add(const EntityRelation(
        sourceId: 'project-door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));

      final all = await store.getAll();
      expect(all.length, 1);
      expect(all.first.sourceId, 'project-door-1');
      expect(all.first.targetId, 'mem-1');
      expect(all.first.type, RelationType.references);
    });

    test('add is idempotent (dedup)', () async {
      const rel = EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      );
      await store.add(rel);
      await store.add(rel);
      expect(await store.getAll(), hasLength(1));
    });

    test('getRelations filters by sourceId', () async {
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'asset-1',
        type: RelationType.references,
      ));
      await store.add(const EntityRelation(
        sourceId: 'door-2',
        targetId: 'mem-1',
        type: RelationType.references,
      ));

      final door1Rels = await store.getRelations('door-1');
      expect(door1Rels, hasLength(2));
      expect(door1Rels.every((r) => r.sourceId == 'door-1'), isTrue);
    });

    test('getReverseRelations filters by targetId', () async {
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));
      await store.add(const EntityRelation(
        sourceId: 'door-2',
        targetId: 'mem-1',
        type: RelationType.references,
      ));
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-2',
        type: RelationType.references,
      ));

      final reverseRels = await store.getReverseRelations('mem-1');
      expect(reverseRels, hasLength(2));
      expect(reverseRels.every((r) => r.targetId == 'mem-1'), isTrue);
    });

    test('remove deletes matching relation', () async {
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'asset-1',
        type: RelationType.references,
      ));

      await store.remove('door-1', 'mem-1', RelationType.references);

      final all = await store.getAll();
      expect(all, hasLength(1));
      expect(all.first.targetId, 'asset-1');
    });

    test('addAll batch adds with dedup', () async {
      await store.add(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));

      await store.addAll([
        const EntityRelation(
          sourceId: 'door-1',
          targetId: 'mem-1',
          type: RelationType.references,
        ), // dup
        const EntityRelation(
          sourceId: 'door-1',
          targetId: 'mem-2',
          type: RelationType.references,
        ), // new
      ]);

      expect(await store.getAll(), hasLength(2));
    });

    test('clear removes all', () async {
      await store.add(const EntityRelation(
        sourceId: 'a',
        targetId: 'b',
        type: RelationType.relates,
      ));
      await store.clear();
      expect(await store.getAll(), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // CanvasStateStore CRUD
  // ═══════════════════════════════════════════════════════════════

  group('CanvasStateStore', () {
    const store = CanvasStateStore();

    test('getAsync returns null when not on canvas', () async {
      expect(await store.getAsync('entity-1'), isNull);
    });

    test('set and getAsync', () async {
      const props = CanvasProps(x: 100.0, y: 200.0);
      await store.set('entity-1', props);

      final retrieved = await store.getAsync('entity-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.x, 100.0);
      expect(retrieved.y, 200.0);
      expect(retrieved.width, 120.0); // default
      expect(retrieved.height, 80.0); // default
      expect(retrieved.visualState, CanvasVisualState.idle);
    });

    test('set preserves all fields after roundtrip', () async {
      const props = CanvasProps(
        x: 50.5,
        y: 75.3,
        width: 200.0,
        height: 150.0,
        visualState: CanvasVisualState.done,
        origin: CanvasNodeOrigin.brain,
        roleInWorkflow: CanvasNodeRole.task,
        agentAnnotationIds: ['ann-1', 'ann-2'],
      );
      await store.set('entity-1', props);

      final retrieved = await store.getAsync('entity-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.x, 50.5);
      expect(retrieved.y, 75.3);
      expect(retrieved.width, 200.0);
      expect(retrieved.height, 150.0);
      expect(retrieved.visualState, CanvasVisualState.done);
      expect(retrieved.origin, CanvasNodeOrigin.brain);
      expect(retrieved.roleInWorkflow, CanvasNodeRole.task);
      expect(retrieved.agentAnnotationIds, ['ann-1', 'ann-2']);
    });

    test('remove deletes canvas state', () async {
      const props = CanvasProps(x: 10.0, y: 20.0);
      await store.set('entity-1', props);
      expect(await store.getAsync('entity-1'), isNotNull);

      await store.remove('entity-1');
      expect(await store.getAsync('entity-1'), isNull);
    });

    test('loadAll returns all canvas entries', () async {
      await store.set('entity-1', const CanvasProps(x: 1, y: 1));
      await store.set('entity-2', const CanvasProps(x: 2, y: 2));

      final all = await store.loadAll();
      expect(all, hasLength(2));
      expect(all.keys, containsAll(['entity-1', 'entity-2']));
    });

    test('clear removes all', () async {
      await store.set('entity-1', const CanvasProps(x: 1, y: 1));
      await store.clear();
      expect(await store.loadAll(), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // EntityGraphService 路由
  // ═══════════════════════════════════════════════════════════════

  group('EntityGraphService routing', () {
    late EntityGraphService service;

    setUp(() async {
      service = EntityGraphService(
        memoryStore: MemoryStore(),
        doorStore: const ProjectDoorStore(),
        assetStore: const DigitalAssetRegistryStore(),
      );
    });

    test('getEntity returns null for non-existent door', () async {
      final entity = await service.getEntity('project-door-nonexistent');
      expect(entity, isNull);
    });

    test('getEntity routes door correctly', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '測試門', sourceIntent: '意圖'),
      );

      final entity = await service.getEntity(door.id);
      expect(entity, isNotNull);
      expect(entity!.type, EntityType.door);
      expect(entity.title, '測試門');
      expect(entity.underlying, isA<ProjectDoor>());
    });

    test('getEntity routes asset correctly', () async {
      const assetStore = DigitalAssetRegistryStore();
      final asset = await assetStore.registerAsset(
        title: '測試資產',
        kind: DigitalAssetKind.projectPlaybook,
        summary: '這是測試資產',
      );

      final entity = await service.getEntity(asset.id);
      expect(entity, isNotNull);
      expect(entity!.type, EntityType.asset);
      expect(entity.title, '測試資產');
      expect(entity.underlying, isA<DigitalAsset>());
    });

    test('getEntity routes flowstep correctly', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '測試門', sourceIntent: '意圖'),
      );
      final step = FlowStep.create(doorId: door.id, title: '步驟 1');
      await doorStore.addFlowStep(door.id, step);

      final entity = await service.getEntity(step.id);
      expect(entity, isNotNull);
      expect(entity!.type, EntityType.flowstep);
      expect(entity.title, '步驟 1');
      expect(entity.underlying, isA<FlowStep>());
      // FlowStep wrapper 應包含 contains 關聯
      expect(entity.relations, hasLength(1));
      expect(entity.relations.first.type, RelationType.contains);
      expect(entity.relations.first.sourceId, door.id);
      expect(entity.relations.first.targetId, step.id);
    });

    test('getEntity routes memory via fallback path', () async {
      // 在 SharedPreferences 中建立一個 memory object 快取
      // （模擬 SQLite 不可用的 fallback 路徑）
      final prefs = await SharedPreferences.getInstance();
      final memory = _createTestMemory(id: 'test-mem-1', content: '我住在台北');
      // Memory.toMap() 回傳的 Map 可直接 jsonEncode
      final cacheJson = '{"test-mem-1":${jsonEncode(memory.toMap())}}';
      await prefs.setString('bridge_memory_objects_v0', cacheJson);

      final entity = await service.getEntity('test-mem-1');
      expect(entity, isNotNull);
      expect(entity!.type, EntityType.memory);
      expect(entity.title, contains('台北'));
      expect(entity.underlying, isA<Memory>());
    });

    test('getEntity returns null for non-existent memory', () async {
      final entity = await service.getEntity('nonexistent-mem-id');
      expect(entity, isNull);
    });

    test('getEntities batch fetches multiple entities', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '批次門', sourceIntent: '意圖'),
      );

      final entities = await service.getEntities([door.id, 'nonexistent']);
      expect(entities, hasLength(1));
      expect(entities.first.id, door.id);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // EntityGraphService 關聯 + 畫布
  // ═══════════════════════════════════════════════════════════════

  group('EntityGraphService relations', () {
    late EntityGraphService service;

    setUp(() {
      service = EntityGraphService(
        memoryStore: MemoryStore(),
        doorStore: const ProjectDoorStore(),
        assetStore: const DigitalAssetRegistryStore(),
      );
    });

    test('addRelation and getRelations', () async {
      await service.addRelation(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));

      final rels = await service.getRelations('door-1');
      expect(rels, hasLength(1));
      expect(rels.first.targetId, 'mem-1');
    });

    test('getReverseRelations', () async {
      await service.addRelation(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));
      await service.addRelation(const EntityRelation(
        sourceId: 'door-2',
        targetId: 'mem-1',
        type: RelationType.references,
      ));

      final reverse = await service.getReverseRelations('mem-1');
      expect(reverse, hasLength(2));
    });

    test('removeRelation', () async {
      await service.addRelation(const EntityRelation(
        sourceId: 'door-1',
        targetId: 'mem-1',
        type: RelationType.references,
      ));
      await service.removeRelation('door-1', 'mem-1', RelationType.references);

      expect(await service.getRelations('door-1'), isEmpty);
    });
  });

  group('EntityGraphService canvas operations', () {
    late EntityGraphService service;

    setUp(() {
      service = EntityGraphService(
        memoryStore: MemoryStore(),
        doorStore: const ProjectDoorStore(),
        assetStore: const DigitalAssetRegistryStore(),
      );
    });

    test('addToCanvas and getCanvasNodes', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '畫布門', sourceIntent: '意圖'),
      );

      await service.addToCanvas(door.id, x: 100, y: 200);

      final nodes = await service.getCanvasNodes();
      expect(nodes, hasLength(1));
      expect(nodes.first.entity.id, door.id);
      expect(nodes.first.props.x, 100);
      expect(nodes.first.props.y, 200);
    });

    test('addToCanvas updates position if already on canvas', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '畫布門', sourceIntent: '意圖'),
      );

      await service.addToCanvas(door.id, x: 100, y: 200);
      await service.addToCanvas(door.id, x: 300, y: 400);

      final nodes = await service.getCanvasNodes();
      expect(nodes, hasLength(1));
      expect(nodes.first.props.x, 300);
      expect(nodes.first.props.y, 400);
    });

    test('removeFromCanvas', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '畫布門', sourceIntent: '意圖'),
      );

      await service.addToCanvas(door.id, x: 100, y: 200);
      expect(await service.getCanvasNodes(), hasLength(1));

      await service.removeFromCanvas(door.id);
      expect(await service.getCanvasNodes(), isEmpty);
    });

    test('updateCanvasVisualState', () async {
      const doorStore = ProjectDoorStore();
      final door = await doorStore.saveActive(
        ProjectDoor.create(title: '畫布門', sourceIntent: '意圖'),
      );

      await service.addToCanvas(door.id, x: 100, y: 200);
      await service.updateCanvasVisualState(door.id, CanvasVisualState.done);

      final nodes = await service.getCanvasNodes();
      expect(nodes.first.props.visualState, CanvasVisualState.done);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // searchEntities
  // ═══════════════════════════════════════════════════════════════

  group('EntityGraphService searchEntities', () {
    late EntityGraphService service;

    setUp(() {
      service = EntityGraphService(
        memoryStore: MemoryStore(),
        doorStore: const ProjectDoorStore(),
        assetStore: const DigitalAssetRegistryStore(),
      );
    });

    test('searches doors by title', () async {
      const doorStore = ProjectDoorStore();
      await doorStore.saveActive(
        ProjectDoor.create(title: 'SemiDAO 專案', sourceIntent: '建立角色'),
      );
      await doorStore.saveActive(
        ProjectDoor.create(title: '直播帶貨', sourceIntent: '賣商品'),
      );

      final results = await service.searchEntities('SemiDAO');
      expect(results, isNotEmpty);
      expect(results.every((e) => e.type == EntityType.door), isTrue);
      expect(results.any((e) => e.title.contains('SemiDAO')), isTrue);
    });

    test('searches assets by title and summary', () async {
      const assetStore = DigitalAssetRegistryStore();
      await assetStore.registerAsset(
        title: '直播腳本工作流',
        kind: DigitalAssetKind.workflowEngine,
        summary: '把直播帶貨目標拆成企劃步驟',
      );

      final results = await service.searchEntities('直播');
      expect(results, isNotEmpty);
      expect(results.any((e) => e.type == EntityType.asset), isTrue);
    });

    test('searches with type filter', () async {
      const doorStore = ProjectDoorStore();
      await doorStore.saveActive(
        ProjectDoor.create(title: '直播專案', sourceIntent: '意圖'),
      );

      // 只搜 asset → 不應找到 door
      final results = await service.searchEntities('直播',
          types: [EntityType.asset]);
      expect(results.every((e) => e.type == EntityType.asset), isTrue);
    });

    test('empty query returns empty', () async {
      final results = await service.searchEntities('');
      expect(results, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // importExistingRelations
  // ═══════════════════════════════════════════════════════════════

  group('EntityGraphService importExistingRelations', () {
    test('imports door→memory and door→asset references', () async {
      const doorStore = ProjectDoorStore();
      final door = ProjectDoor.create(
        title: '測試門',
        sourceIntent: '意圖',
      ).copyWith(
        linkedMemoryIds: const ['mem-1', 'mem-2'],
        linkedAssetIds: const ['digital-asset-1'],
        flowSteps: [
          FlowStep.create(doorId: 'temp', title: '步驟 1'),
        ],
      );
      await doorStore.saveActive(door);

      final service = EntityGraphService(
        memoryStore: MemoryStore(),
        doorStore: const ProjectDoorStore(),
        assetStore: const DigitalAssetRegistryStore(),
      );

      final count = await service.importExistingRelations();
      // 2 memory refs + 1 asset ref + 1 flowstep contains = 4
      expect(count, 4);

      // 驗證關聯確實建立
      final doorRels = await service.getRelations(door.id);
      expect(doorRels, hasLength(4)); // 2 mem + 1 asset + 1 flowstep

      final mem1Reverse = await service.getReverseRelations('mem-1');
      expect(mem1Reverse, hasLength(1));
      expect(mem1Reverse.first.sourceId, door.id);
      expect(mem1Reverse.first.type, RelationType.references);
    });

    test('importExistingRelations is idempotent', () async {
      const doorStore = ProjectDoorStore();
      final door = ProjectDoor.create(
        title: '測試門',
        sourceIntent: '意圖',
      ).copyWith(linkedMemoryIds: const ['mem-1']);
      await doorStore.saveActive(door);

      final service = EntityGraphService(
        memoryStore: MemoryStore(),
        doorStore: const ProjectDoorStore(),
        assetStore: const DigitalAssetRegistryStore(),
      );

      await service.importExistingRelations();
      await service.importExistingRelations(); // 第二次呼叫

      final doorRels = await service.getRelations(door.id);
      expect(doorRels, hasLength(1)); // 不重複
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Feature Flag
  // ═══════════════════════════════════════════════════════════════

  group('Entity Graph Feature Flag', () {
    test('defaults to false', () async {
      expect(await StorageService.isEntityGraphEnabled(), isFalse);
    });

    test('can be enabled and disabled', () async {
      await StorageService.setEntityGraphEnabled(true);
      expect(await StorageService.isEntityGraphEnabled(), isTrue);

      await StorageService.setEntityGraphEnabled(false);
      expect(await StorageService.isEntityGraphEnabled(), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Model serialization
  // ═══════════════════════════════════════════════════════════════

  group('Entity/CanvasProps serialization', () {
    test('CanvasProps toJson/fromJson roundtrip', () {
      const props = CanvasProps(
        x: 10.5,
        y: 20.3,
        width: 100.0,
        height: 60.0,
        visualState: CanvasVisualState.active,
        origin: CanvasNodeOrigin.file,
        roleInWorkflow: CanvasNodeRole.output,
        agentAnnotationIds: ['a', 'b'],
      );
      final json = props.toJson();
      final restored = CanvasProps.fromJson(json);

      expect(restored.x, props.x);
      expect(restored.y, props.y);
      expect(restored.width, props.width);
      expect(restored.height, props.height);
      expect(restored.visualState, props.visualState);
      expect(restored.origin, props.origin);
      expect(restored.roleInWorkflow, props.roleInWorkflow);
      expect(restored.agentAnnotationIds, props.agentAnnotationIds);
    });

    test('EntityRelation toJson/fromJson roundtrip', () {
      const rel = EntityRelation(
        sourceId: 'a',
        targetId: 'b',
        type: RelationType.depends,
      );
      final json = rel.toJson();
      final restored = EntityRelation.fromJson(json);

      expect(restored.sourceId, 'a');
      expect(restored.targetId, 'b');
      expect(restored.type, RelationType.depends);
    });

    test('CanvasProps copyWith', () {
      const props = CanvasProps(x: 1, y: 2);
      final updated = props.copyWith(x: 10, visualState: CanvasVisualState.done);

      expect(updated.x, 10);
      expect(updated.y, 2); // unchanged
      expect(updated.visualState, CanvasVisualState.done);
    });
  });
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

Memory _createTestMemory({required String id, required String content}) {
  final now = DateTime.now();
  return Memory(
    id: id,
    content: content,
    room: BrainRoom.stream,
    subCategory: '',
    agent: 'test',
    companionId: '',
    source: MemorySource.chat,
    project: '',
    tags: const [],
    importance: 3,
    createdAt: now,
    updatedAt: now,
    accessCount: 0,
    archived: false,
    chunkIndex: 0,
    totalChunks: 1,
  );
}
