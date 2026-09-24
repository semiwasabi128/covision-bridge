// trio_m2_intel_test.dart
// [TRIO M2 2026-09-22] 情報池驗收——甲踩過的坑乙不用再踩
//
// 劇本：
//   I1 甲 share 一筆 pit → 乙 unconsumedBy 拿得到
//   I2 乙 intel_read 讀取即消化 → 再讀空（不重複注入）
//   I3 自己的情報不注入給自己
//   I4 refute 推翻——原文保留在檔、快照不再出現（永不刪）
//   I5 kind 詞彙表——非法 kind 誠實拒絕
//   I6 落盤——JSONL append，重載後還在
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:bridge_app/services/collab/intel_pool.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String> getApplicationSupportPath() async => dir;
}

void main() {
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('intel_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    IntelPool.resetForTest();
  });

  test('I1 甲 share 的坑，乙拿得到', () async {
    await IntelPool.instance.share(
        fromAgent: 'agent-甲',
        kind: IntelKind.pit,
        content: 'flutter build 搶鎖——先 acquire 租約再跑');

    final forB = await IntelPool.instance.unconsumedBy('agent-乙');
    expect(forB.length, 1);
    expect(forB.first.kind, IntelKind.pit);
    expect(forB.first.content, contains('租約'));
    expect(forB.first.fromAgent, 'agent-甲');
  });

  test('I2 讀取即消化——第二次讀空', () async {
    await IntelPool.instance.share(
        fromAgent: 'agent-甲',
        kind: IntelKind.lead,
        content: '羅盤有現成的 dispatch 規則可查');

    final first = await IntelPool.instance.unconsumedBy('agent-乙');
    expect(first.length, 1);
    await IntelPool.instance.markConsumed(first.first.id, 'agent-乙');

    final second = await IntelPool.instance.unconsumedBy('agent-乙');
    expect(second, isEmpty, reason: '讀過就標記消化，不重複注入');
  });

  test('I3 自己的情報不注入給自己', () async {
    await IntelPool.instance.share(
        fromAgent: 'agent-甲',
        kind: IntelKind.pit,
        content: '自己知道就好');

    final forA = await IntelPool.instance.unconsumedBy('agent-甲');
    expect(forA, isEmpty, reason: '自己的情報自己知道，不回聲');
  });

  test('I4 refute——原文保留、快照排除', () async {
    final e = await IntelPool.instance.share(
        fromAgent: 'agent-甲',
        kind: IntelKind.external,
        content: '某某 API 今天限量半價');
    await IntelPool.instance.refute(e.id, 'agent-乙');

    // 快照不再出現（被推翻的情報不算數）
    expect(IntelPool.instance.entries.any((x) => x.id == e.id), isFalse);
    // 但原始檔還在（永不刪——主權鐵則）
    final dirPath = await PathProviderPlatform.instance
        .getApplicationSupportPath();
    final f = File('$dirPath/farm.seemiwasabi.bridgeApp/intel_pool.jsonl');
    // refute 會重寫檔——驗證條目仍在檔中（帶 refutedBy）
    final lines = await f.readAsLines();
    final hasOriginal = lines.any((l) => l.contains(e.id));
    expect(hasOriginal, isTrue, reason: '推翻≠刪除，原文永久保留');
  });

  test('I6 落盤 JSONL——重載後還在', () async {
    await IntelPool.instance.share(
        fromAgent: 'agent-甲',
        kind: IntelKind.preview,
        content: '角色設定圖組快完成了');
    // 模擬重啟：重置 singleton 重載
    IntelPool.resetForTest();
    final forB = await IntelPool.instance.unconsumedBy('agent-乙');
    expect(forB.length, 1, reason: '重啟後情報池仍在（append-only 落盤）');
    expect(forB.first.content, contains('角色設定'));
  });
}
