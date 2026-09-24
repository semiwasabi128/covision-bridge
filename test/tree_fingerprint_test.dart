// [小葵 2026-08-21] 樹指紋短路測試——24/7 記憶體治理。
// 驗證 fullScan(skipIfUnchanged:) 的三個語義：
// 1. 首次掃描照常執行（指紋記錄下來）
// 2. 沒變更時第二輪跳過（totalFiles=0）
// 3. 有新檔案時第二輪照常執行（偵測到變更）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/vector_db/asset_index_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('樹指紋：沒變更時第二輪 fullScan 跳過、有變更時照常執行', () async {
    final tmp = await Directory.systemTemp.createTemp('fingerprint_test');
    addTearDown(() => tmp.delete(recursive: true));

    // 佈置：兩個檔案
    await File('${tmp.path}/a.txt').writeAsString('hello');
    await Directory('${tmp.path}/sub').create();
    await File('${tmp.path}/sub/b.txt').writeAsString('world');

    final svc = AssetIndexService();

    // 第一輪：首次，照常執行
    final r1 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r1.totalFiles, greaterThan(0), reason: '首次必須全掃');

    // 第二輪：沒變更，跳過
    final r2 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r2.totalFiles, 0, reason: '沒變更必須跳過');

    // 第三輪：新增檔案 → 指紋變 → 全掃
    await File('${tmp.path}/c.txt').writeAsString('new');
    final r3 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r3.totalFiles, greaterThan(0), reason: '有變更必須全掃');

    // 第四輪：改檔案內容（size 變）→ 全掃
    await File('${tmp.path}/a.txt').writeAsString('hello world longer');
    final r4 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r4.totalFiles, greaterThan(0), reason: '修改檔案必須全掃');

    // 第五輪：刪檔案 → 全掃
    await File('${tmp.path}/sub/b.txt').delete();
    final r5 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r5.totalFiles, greaterThan(0), reason: '刪除檔案必須全掃');

    // 第六輪：又靜止 → 跳過
    final r6 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r6.totalFiles, 0, reason: '靜止後必須跳過');
  });

  test('死鏈清理：刪掉的檔案從 DB 移除', () async {
    final tmp = await Directory.systemTemp.createTemp('deadlink_test');
    addTearDown(() => tmp.delete(recursive: true));

    await File('${tmp.path}/keep.txt').writeAsString('keep');
    await File('${tmp.path}/drop.txt').writeAsString('drop');

    final svc = AssetIndexService();
    // 第一輪全掃（指紋記錄）。BrainContainer 未初始化 → DB 寫入跳過，
    // 這裡只驗指紋與掃描行為，不驗 DB（DB 路徑由 App 內整合測試覆蓋）
    final r1 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r1.totalFiles, 2);

    await File('${tmp.path}/drop.txt').delete();
    final r2 = await svc.fullScan(tmp.path, skipIfUnchanged: true);
    expect(r2.totalFiles, 1, reason: '刪檔後重掃只見 1 檔');
    expect(r2.records.map((r) => r.fileName), contains('keep.txt'));
  });
}
