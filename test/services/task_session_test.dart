// task_session_test.dart
// [隊友訊息流 C1 2026-09-08] TaskSession 模型 + Store 持久化測試
// 設計稿驗收：C1「單元測試：建 session/持久化/round-trip」

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/tasks/task_session.dart';
import 'package:bridge_app/services/tasks/task_session_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('task_session_test');
    TaskSessionStore.debugSetStorageDirectory(tmpDir);
  });

  tearDown(() async {
    TaskSessionStore.debugSetStorageDirectory(null);
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  group('TaskSession 模型', () {
    test('create → dispatched 初始態', () {
      final s = TaskSession.create(
        conversationId: 'conv-1',
        companionId: 'comp-1',
        workCanvasId: 'canvas-1',
        title: '整理農場週報',
        instruction: '幫我把這週農場照片整理成週報',
      );
      expect(s.status, TaskStatus.dispatched);
      expect(s.isActive, isTrue);
      expect(s.id, startsWith('task-'));
    });

    test('狀態機：合法流轉 dispatched→working→awaitingReview→delivered', () {
      var s = TaskSession.create(
        conversationId: 'c', companionId: 'p',
        workCanvasId: 'w', title: 't', instruction: 'i',
      );
      s = s.transitionTo(TaskStatus.working);
      expect(s.status, TaskStatus.working);
      s = s.transitionTo(TaskStatus.awaitingReview);
      expect(s.status, TaskStatus.awaitingReview);
      s = s.transitionTo(TaskStatus.delivered);
      expect(s.status, TaskStatus.delivered);
      expect(s.isActive, isFalse);
      expect(s.finishedAt, isNotNull);
    });

    test('狀態機：awaitingReview 可打回 working（「修改」）', () {
      var s = TaskSession.create(
        conversationId: 'c', companionId: 'p',
        workCanvasId: 'w', title: 't', instruction: 'i',
      ).transitionTo(TaskStatus.working).transitionTo(TaskStatus.awaitingReview);
      s = s.transitionTo(TaskStatus.working);
      expect(s.status, TaskStatus.working);
    });

    test('狀態機：非法流轉直接丟（寧炸不靜默）', () {
      final s = TaskSession.create(
        conversationId: 'c', companionId: 'p',
        workCanvasId: 'w', title: 't', instruction: 'i',
      );
      expect(
        () => s.transitionTo(TaskStatus.delivered),
        throwsArgumentError,
      );
      final delivered = s
          .transitionTo(TaskStatus.working)
          .transitionTo(TaskStatus.delivered);
      expect(() => delivered.transitionTo(TaskStatus.working),
          throwsArgumentError);
    });

    test('JSON round-trip', () {
      final s = TaskSession.create(
        conversationId: 'conv-1', companionId: 'comp-1',
        workCanvasId: 'canvas-1', title: '週報', instruction: '做週報',
      ).transitionTo(TaskStatus.working).copyWith(
        steps: [
          TaskStep(id: 's1', tool: 'canvas_place',
              summary: '放了 3 個節點',
              at: DateTime.fromMillisecondsSinceEpoch(1000)),
        ],
        deliverables: [
          const TaskDeliverable(kind: 'image', ref: '/tmp/a.png', caption: '圖卡'),
        ],
      );
      final restored = TaskSession.fromJson(s.toJson());
      expect(restored.id, s.id);
      expect(restored.status, TaskStatus.working);
      expect(restored.steps.length, 1);
      expect(restored.steps.first.tool, 'canvas_place');
      expect(restored.deliverables.first.kind, 'image');
      expect(restored.deliverables.first.ref, '/tmp/a.png');
    });
  });

  group('TaskSessionStore', () {
    test('save → getAll round-trip + updatedAt 排序', () async {
      final a = TaskSession.create(
        conversationId: 'c1', companionId: 'p',
        workCanvasId: 'w', title: 'A', instruction: 'i',
      );
      await Future.delayed(const Duration(milliseconds: 20));
      final b = TaskSession.create(
        conversationId: 'c2', companionId: 'p',
        workCanvasId: 'w', title: 'B', instruction: 'i',
      );
      await TaskSessionStore.save(a);
      await TaskSessionStore.save(b);

      final all = await TaskSessionStore.getAll();
      expect(all.length, 2);
      expect(all.first.id, b.id); // 較新的在前
      expect(all.last.id, a.id);
    });

    test('getActive 過濾終態', () async {
      final active = TaskSession.create(
        conversationId: 'c1', companionId: 'p',
        workCanvasId: 'w', title: 'A', instruction: 'i',
      );
      final done = TaskSession.create(
        conversationId: 'c2', companionId: 'p',
        workCanvasId: 'w', title: 'B', instruction: 'i',
      ).transitionTo(TaskStatus.working).transitionTo(TaskStatus.delivered);
      await TaskSessionStore.save(active);
      await TaskSessionStore.save(done);

      final act = await TaskSessionStore.getActive();
      expect(act.length, 1);
      expect(act.first.id, active.id);
    });

    test('損壞檔案→備份還原', () async {
      final s = TaskSession.create(
        conversationId: 'c', companionId: 'p',
        workCanvasId: 'w', title: 'X', instruction: 'i',
      );
      await TaskSessionStore.save(s);
      // 第二次 save 觸發 rolling backup → 備份檔內容=第二次寫入前狀態（只有 X）
      final s2 = TaskSession.create(
        conversationId: 'c', companionId: 'p',
        workCanvasId: 'w', title: 'Y', instruction: 'i',
      );
      await TaskSessionStore.save(s2);

      final file = File('${tmpDir.path}/task_sessions.json');
      expect(await file.exists(), isTrue);
      // 弄壞主檔
      await file.writeAsString('{broken json!!!');

      final restored = await TaskSessionStore.getAll();
      // 還原到備份時點（X 存活；Y 是壞掉那次寫入之後才有的，誠實遺失）
      expect(restored.length, 1);
      expect(restored.first.title, 'X');
    });

    test('delete', () async {
      final s = TaskSession.create(
        conversationId: 'c', companionId: 'p',
        workCanvasId: 'w', title: 'Z', instruction: 'i',
      );
      await TaskSessionStore.save(s);
      await TaskSessionStore.delete(s.id);
      expect(await TaskSessionStore.getAll(), isEmpty);
    });
  });
}
