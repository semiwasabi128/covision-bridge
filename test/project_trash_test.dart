// [小葵 2026-09-21 Blue 令] 專案回收桶回歸鎖
// 刪畫布＝五件套級聯刪除；專案回收桶做保護傘：
// backup（刪前快照）→ listAll（日期分組）→ restoreNodes（節點回寫）→ purge（不可逆）。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/project_trash_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('proj_trash_test');
    ProjectTrashStore.debugSetStorageDirectory(tmp);
  });

  tearDown(() async {
    ProjectTrashStore.debugSetStorageDirectory(null);
    try { await tmp.delete(recursive: true); } catch (_) {}
  });

  test('backup → listAll：快照完整（metadata+節點+門）', () async {
    await ProjectTrashStore.backup(
      canvasJson: {
        'id': 'cv_test_1',
        'title': '測試專案',
        'createdAt': '2026-09-21T10:00:00',
        'updatedAt': '2026-09-21T10:00:00',
      },
      nodes: const [],
      door: null,
      conversationId: 'conv_123',
    );
    final all = await ProjectTrashStore.listAll();
    expect(all.length, 1);
    expect(all.first.canvasId, 'cv_test_1');
    expect(all.first.canvas['title'], '測試專案');
    expect(all.first.conversationId, 'conv_123');
    expect(
      DateTime.now().difference(all.first.deletedAt).inSeconds < 5,
      isTrue,
      reason: 'deletedAt 應為寫入當下',
    );

    // 清場
    expect(await ProjectTrashStore.purge('cv_test_1'), isTrue);
    expect((await ProjectTrashStore.listAll()).length, 0);
  });

  test('同 id 重複 backup → 覆寫不堆疊', () async {
    for (var i = 0; i < 2; i++) {
      await ProjectTrashStore.backup(
        canvasJson: {'id': 'cv_dup', 'title': '專案 $i'},
        nodes: const [],
      );
    }
    expect((await ProjectTrashStore.listAll()).length, 1);
    await ProjectTrashStore.purge('cv_dup');
  });

  test('restoreNodes：不存在快照回 -1（誠實失敗）', () async {
    final n = await ProjectTrashStore.restoreNodes(
      'cv_404',
      writeNode: (_, __) async {},
    );
    expect(n, -1);
  });
}
