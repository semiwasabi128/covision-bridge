// [Sprint 18b tests] FlowStep + ProjectDoor model + ProjectDoorStore
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bridge_app/models/flow_step.dart';
import 'package:bridge_app/models/project_door.dart';
import 'package:bridge_app/services/project_door_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FlowStep', () {
    test('create generates proper defaults', () {
      final step = FlowStep.create(
        doorId: 'door-1',
        title: '定義目標',
      );
      expect(step.id, isNotEmpty);
      expect(step.doorId, 'door-1');
      expect(step.title, '定義目標');
      expect(step.status, FlowStep.statusPending);
      expect(step.order, 0);
      expect(step.linkedAssetIds, isEmpty);
      expect(step.linkedMemoryIds, isEmpty);
    });

    test('toJson / fromJson roundtrip', () {
      final now = DateTime(2026, 7, 8, 12, 0);
      final step = FlowStep(
        id: 'flow-1',
        doorId: 'door-1',
        title: '定義目標',
        description: '確認 MVP 範圍',
        status: FlowStep.statusDone,
        order: 0,
        createdAt: now,
        updatedAt: now,
        completedAt: now,
        linkedAssetIds: ['asset-1'],
        linkedMemoryIds: ['mem-1'],
      );
      final json = step.toJson();
      final restored = FlowStep.fromJson(json);
      expect(restored.id, step.id);
      expect(restored.title, step.title);
      expect(restored.description, step.description);
      expect(restored.status, FlowStep.statusDone);
      expect(restored.isDone, isTrue);
      expect(restored.linkedAssetIds, ['asset-1']);
      expect(restored.linkedMemoryIds, ['mem-1']);
      expect(restored.completedAt, isNotNull);
    });

    test('copyWith updates status and completedAt', () {
      final step = FlowStep.create(doorId: 'door-1', title: '步驟');
      final updated = step.copyWith(status: FlowStep.statusDone);
      expect(updated.status, FlowStep.statusDone);
      expect(updated.isDone, isTrue);
    });

    test('status flags', () {
      final pending = FlowStep.create(doorId: 'd', title: 't');
      expect(pending.isDone, isFalse);
      expect(pending.isBlocked, isFalse);
      expect(pending.isInProgress, isFalse);

      final done = pending.copyWith(status: FlowStep.statusDone);
      expect(done.isDone, isTrue);

      final blocked = pending.copyWith(status: FlowStep.statusBlocked);
      expect(blocked.isBlocked, isTrue);

      final inProgress = pending.copyWith(status: FlowStep.statusInProgress);
      expect(inProgress.isInProgress, isTrue);
    });
  });

  group('ProjectDoor — Sprint 18b extensions', () {
    test('flowSteps default empty', () {
      final door = ProjectDoor.create(title: '測試', sourceIntent: '意圖');
      expect(door.flowSteps, isEmpty);
      expect(door.parentDoorId, isNull);
      expect(door.linkedAssetIds, isEmpty);
      expect(door.linkedMemoryIds, isEmpty);
    });

    test('kanbanStatus mapping', () {
      final active = ProjectDoor.create(title: 'A', sourceIntent: 'i')
          .copyWith(status: ProjectDoor.statusActive);
      expect(active.kanbanStatus, ProjectDoor.statusActive);

      final intake = ProjectDoor.create(title: 'A', sourceIntent: 'i');
      expect(intake.kanbanStatus, ProjectDoor.statusActive);

      final waiting = active.copyWith(status: ProjectDoor.statusWaiting);
      expect(waiting.kanbanStatus, ProjectDoor.statusWaiting);

      final completed = active.copyWith(status: ProjectDoor.statusCompleted);
      expect(completed.kanbanStatus, ProjectDoor.statusCompleted);
    });

    test('flowProgress calculations', () {
      final door = ProjectDoor.create(title: 'A', sourceIntent: 'i').copyWith(
        flowSteps: [
          FlowStep.create(doorId: 'd', title: 's1')
              .copyWith(status: FlowStep.statusDone),
          FlowStep.create(doorId: 'd', title: 's2')
              .copyWith(status: FlowStep.statusPending),
          FlowStep.create(doorId: 'd', title: 's3')
              .copyWith(status: FlowStep.statusDone),
        ],
      );
      expect(door.totalFlowCount, 3);
      expect(door.completedFlowCount, 2);
      expect(door.flowProgress, closeTo(2 / 3, 0.01));
    });

    test('toJson / fromJson preserves flowSteps', () {
      final door = ProjectDoor.create(title: 'A', sourceIntent: 'i').copyWith(
        flowSteps: [
          FlowStep.create(doorId: 'd', title: 's1'),
        ],
        parentDoorId: 'parent-1',
        linkedAssetIds: ['asset-a'],
        linkedMemoryIds: ['mem-b'],
      );
      final json = door.toJson();
      final restored = ProjectDoor.fromJson(json);
      expect(restored.flowSteps.length, 1);
      expect(restored.flowSteps.first.title, 's1');
      expect(restored.parentDoorId, 'parent-1');
      expect(restored.linkedAssetIds, ['asset-a']);
      expect(restored.linkedMemoryIds, ['mem-b']);
    });
  });

  group('ProjectDoorStore — Sprint 18b flow step CRUD', () {
    final store = const ProjectDoorStore();

    test('addFlowStep appends to door', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final step = FlowStep.create(doorId: door.id, title: '步驟 1');
      door = (await store.addFlowStep(door.id, step))!;
      expect(door.flowSteps.length, 1);
      expect(door.flowSteps.first.title, '步驟 1');
      expect(door.flowSteps.first.order, 0);
    });

    test('updateFlowStep changes status', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final step = FlowStep.create(doorId: door.id, title: '步驟 1');
      door = (await store.addFlowStep(door.id, step))!;
      final stepId = door.flowSteps.first.id;

      door = (await store.updateFlowStep(door.id, stepId,
          status: FlowStep.statusDone))!;
      expect(door.flowSteps.first.status, FlowStep.statusDone);
      expect(door.flowSteps.first.isDone, isTrue);
      expect(door.flowSteps.first.completedAt, isNotNull);
    });

    test('removeFlowStep deletes step', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final step = FlowStep.create(doorId: door.id, title: '步驟 1');
      door = (await store.addFlowStep(door.id, step))!;
      expect(door.flowSteps.length, 1);

      door = (await store.removeFlowStep(door.id, step.id))!;
      expect(door.flowSteps, isEmpty);
    });

    test('updateDoorStatus changes kanban column', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      door = (await store.updateDoorStatus(door.id, ProjectDoor.statusCompleted))!;
      expect(door.status, ProjectDoor.statusCompleted);
      expect(door.kanbanStatus, ProjectDoor.statusCompleted);
    });

    test('forkDoor creates child with parent context', () async {
      final parent = await store.saveActive(
          ProjectDoor.create(title: '父專案', sourceIntent: '原始意圖'));
      final child = await store.forkDoor(
        parent.id,
        title: '子專案',
        sourceIntent: '分岔意圖',
      );
      expect(child.parentDoorId, parent.id);
      expect(child.title, '子專案');
      expect(child.status, ProjectDoor.statusActive);

      // 確認 child 也被存入
      final all = await store.loadAll();
      expect(all.any((d) => d.id == child.id), isTrue);
    });

    test('addFlowStep on non-existent door returns null', () async {
      final result = await store.addFlowStep(
        'non-existent',
        FlowStep.create(doorId: 'non-existent', title: 't'),
      );
      expect(result, isNull);
    });

    test('multiple flow steps maintain order', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '多步驟門', sourceIntent: '意圖'));
      for (var i = 0; i < 3; i++) {
        final step = FlowStep.create(doorId: door.id, title: '步驟 ${i + 1}');
        door = (await store.addFlowStep(door.id, step))!;
      }
      expect(door.flowSteps.length, 3);
      expect(door.flowSteps[0].order, 0);
      expect(door.flowSteps[1].order, 1);
      expect(door.flowSteps[2].order, 2);
    });
  });
}
