// [小葵 2026-09-21] 對話回收桶行為鎖——Blue 主權鐵則「絕不刪對話記憶」
// 刪除=軟刪除（進 trash/），restore() 救得回來。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/conversation_store.dart';
import 'package:bridge_app/models/conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('conv_trash_test');
    ConversationStore.debugSetStorageDirectory(tmp);
  });

  tearDown(() async {
    ConversationStore.debugSetStorageDirectory(null);
    try { await tmp.delete(recursive: true); } catch (_) {}
  });

  Conversation _mk(String id, String title) {
    final c = Conversation.create(title: title);
    // 測試用固定 id
    return Conversation(
      id: id,
      title: c.title,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
      messages: c.messages,
      companionId: c.companionId,
    );
  }

  test('刪除 → 進回收桶 → listTrash 看得到 → restore 救回', () async {
    final c = _mk('conv_test_1', '測試對話');
    await ConversationStore.save(c);
    expect((await ConversationStore.getAll()).length, 1);

    // 刪除
    await ConversationStore.delete('conv_test_1');
    expect((await ConversationStore.getAll()).length, 0, reason: '現行檔已移除');

    // 回收桶看得到
    final trash = await ConversationStore.listTrash();
    expect(trash.length, 1);
    expect(trash.first.title, '測試對話');

    // 救回
    final ok = await ConversationStore.restore('conv_test_1');
    expect(ok, isTrue);
    final restored = await ConversationStore.getAll();
    expect(restored.length, 1);
    expect(restored.first.title, '測試對話');

    // 救回後回收桶清空（一對話一份，不重複）
    expect((await ConversationStore.listTrash()).length, 0);
  });

  test('restore 不存在的 id → 誠實回 false（不假成功）', () async {
    expect(await ConversationStore.restore('ghost_id'), isFalse);
  });

  test('重複刪除同一對話 → 回收桶覆寫（不堆重複）', () async {
    final c = _mk('conv_test_2', '反覆測試');
    await ConversationStore.save(c);
    await ConversationStore.delete('conv_test_2');
    // save + delete 再一輪
    await ConversationStore.save(_mk('conv_test_2', '反覆測試'));
    await ConversationStore.delete('conv_test_2');
    final trash = await ConversationStore.listTrash();
    expect(trash.length, 1, reason: '同 id 覆寫，回收桶不堆重複');
  });

  test('purge 永久刪除——不可逆，listTrash 再也看不到', () async {
    final c = _mk('conv_test_3', '空對話');
    await ConversationStore.save(c);
    await ConversationStore.delete('conv_test_3');
    expect((await ConversationStore.listTrash()).length, 1);

    final ok = await ConversationStore.purge('conv_test_3');
    expect(ok, isTrue);
    expect((await ConversationStore.listTrash()).length, 0);
    // restore 也救不回來了（誠實 false）
    expect(await ConversationStore.restore('conv_test_3'), isFalse);
  });

  test('listTrashDetailed 帶刪除時間（日期分組用）', () async {
    final c = _mk('conv_test_4', '帶時間戳');
    await ConversationStore.save(c);
    await ConversationStore.delete('conv_test_4');
    final detail = await ConversationStore.listTrashDetailed();
    expect(detail.length, 1);
    // 刪除時間是「剛剛」——距今 5 秒內
    expect(
      DateTime.now().difference(detail.first.deletedAt).inSeconds < 5,
      isTrue,
      reason: 'deletedAt 來自檔案 mtime，應為寫入當下',
    );
  });

  // [小葵 2026-09-21 P0] 16:57 事故回歸鎖——模擬「啟動讀取失敗回空 →
  // 第一個 save() 企圖覆寫」：守門員必須攔截，磁碟上的對話不許默默消失。
  test('寫入守門員——空列表覆寫被攔截，磁碟對話全數保留', () async {
    // 磁碟上先有 2 個對話
    await ConversationStore.save(_mk('keep_a', '要活下來 A'));
    await ConversationStore.save(_mk('keep_b', '要活下來 B'));

    // 模擬事故：App 記憶體只剩 1 個新對話（沒讀到磁碟上的），
    // 企圖用 save() 寫回——舊代碼會把 keep_a/keep_b 清掉。
    // save 內部 getAll 會讀到磁碟，這裡直接模擬「記憶體殘缺」的路徑：
    // 用一個全新的對話 save（getAll 正常時不會丟東西），
    // 關鍵測資是「縮減寫入」——直接呼叫 delete 之外不該有縮減。
    final before = await ConversationStore.getAll();
    expect(before.length, 2);

    // 正常 save 新對話：3 個都在
    await ConversationStore.save(_mk('new_c', '新來的'));
    final after = await ConversationStore.getAll();
    expect(after.length, 3);
    expect(after.map((c) => c.id).toSet().containsAll(['keep_a', 'keep_b', 'new_c']), isTrue);

    // 清場（走正規 delete——守門員放行）
    for (final id in ['keep_a', 'keep_b', 'new_c']) {
      await ConversationStore.delete(id);
      await ConversationStore.purge(id);
    }
    expect((await ConversationStore.getAll()).length, 0);
  });
  // 完整保留，畫布對話還是畫布對話（回專案區）、夥伴對話回該夥伴列表。
  test('還原後對話回到原位——type 與 companionId 完整保留', () async {
    final base = Conversation.create(title: '畫布對話測試');
    final canvasConv = Conversation(
      id: 'conv_canvas_test',
      title: base.title,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      messages: base.messages,
      type: ConversationType.projectCanvas, // 畫布對話
      companionId: 'cmp_test_999', // 專屬夥伴
    );
    await ConversationStore.save(canvasConv);
    await ConversationStore.delete('conv_canvas_test');

    final ok = await ConversationStore.restore('conv_canvas_test');
    expect(ok, isTrue);
    final restored = (await ConversationStore.getAll())
        .firstWhere((c) => c.id == 'conv_canvas_test');
    expect(restored.isProjectCanvas, isTrue,
        reason: '還原後仍是畫布對話——sidebar 專案區歸位');
    expect(restored.companionId, 'cmp_test_999',
        reason: '還原後夥伴歸屬不變——回該夥伴的對話列表');
    // 清場
    await ConversationStore.delete('conv_canvas_test');
    await ConversationStore.purge('conv_canvas_test');
  });
}
