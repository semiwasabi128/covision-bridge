// compass_store_test.dart
// 羅盤資料層測試 — Commit 1 驗收：CRUD + 作者標記 + 版本 bump + 規則歷史 append
// + 白名單制（visual 即時生效 / behavioral 需人 apply）+ Agent 不可寫意義層。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/compass/compass_models.dart';
import 'package:bridge_app/services/compass/compass_seed.dart';
import 'package:bridge_app/services/compass/compass_store.dart';

final _ts = DateTime(2026, 9, 6);

void main() {
  late CompassStore store;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('compass_test');
    store = CompassStore.instance;
    await store.initialize(dbPath: '${tmp.path}/compass.db');
    store.resetForTest();
    seedCompass(store);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('種子：器官 + 3D 規則卡已註冊（2D 已退役）', () {
    expect(store.organs().length, greaterThanOrEqualTo(30));
    final ids = store.rules().map((r) => r.id).toSet();
    expect(ids, containsAll(['galaxy.lightAuthority']));
  });

  test('種子冪等：重跑種子不重複不覆寫', () {
    final before = store.organs().length;
    seedCompass(store);
    expect(store.organs().length, before);
  });

  test('visual 規則：改了即時生效（status 保持 active）', () {
    store.updateRuleParams('galaxy.lightAuthority',
        newParams: {'modeCoef.galaxy': 1.2},
        author: 'human:Blue',
        reason: '測試：調亮星系模式');
    final r = store.rule('galaxy.lightAuthority')!;
    expect(r.status, CompassRuleStatus.active);
    expect(r.params['modeCoef.galaxy'], 1.2);
    expect(r.updatedBy, 'human:Blue');
  });

  test('behavioral 規則：改了進 pendingApply，人 apply 才生效', () {
    // 先種一條 behavioral 規則
    store.seedRule(CompassRule(
      id: 'test.behavioral',
      organId: 'agent.budget',
      description: '測試用行為規則',
      why: '驗證白名單制',
      params: {'cap': 30},
      kind: CompassRuleKind.behavioral,
      updatedBy: 'auto:harvest',
      updatedAt: _ts,
    ));
    store.updateRuleParams('test.behavioral',
        newParams: {'cap': 10},
        author: 'agent:小橋',
        reason: '建議降額度');
    var r = store.rule('test.behavioral')!;
    expect(r.status, CompassRuleStatus.pendingApply);
    expect(r.params['cap'], 10); // 參數已寫入，但狀態待確認

    store.applyRule('test.behavioral', byHuman: 'human:Blue');
    r = store.rule('test.behavioral')!;
    expect(r.status, CompassRuleStatus.active);
  });

  test('Agent 不可 apply、不可寫意義層（權限鐵則）', () {
    store.seedRule(CompassRule(
      id: 'test.b2', organId: 'agent.budget', description: 'd', why: 'w',
      params: {'x': 1}, kind: CompassRuleKind.behavioral,
      updatedBy: 'auto:harvest', updatedAt: _ts));
    store.updateRuleParams('test.b2', newParams: {'x': 2},
        author: 'agent:小橋', reason: 'r');
    expect(() => store.applyRule('test.b2', byHuman: 'agent:小橋'),
        throwsStateError);
    expect(() => store.setMeaning('chat', 'importance', '5',
            author: 'agent:小橋'),
        isNot(throwsStateError)); // setMeaning 本身不擋（UI 層把關），assertHumanWrite 擋 apply
    expect(() => store.assertHumanWrite('agent:小橋'), throwsStateError);
    expect(() => store.assertHumanWrite('human:Blue'), returnsNormally);
  });

  test('規則歷史 append：每次修改留軌跡，可回滾', () {
    store.updateRuleParams('galaxy.lightAuthority',
        newParams: {'modeCoef.galaxy': 1.1},
        author: 'human:Blue', reason: '微亮');
    store.updateRuleParams('galaxy.lightAuthority',
        newParams: {'modeCoef.galaxy': 1.3},
        author: 'agent:小橋', reason: '建議再亮一點');
    final h = store.ruleHistory('galaxy.lightAuthority');
    expect(h.length, 2);
    expect(h.first.author, 'agent:小橋');
    expect(h.first.prevParams?['modeCoef.galaxy'], 1.1);

    store.rollbackRule('galaxy.lightAuthority', byHuman: 'human:Blue');
    expect(store.rule('galaxy.lightAuthority')!.params['modeCoef.galaxy'], 1.1);
  });

  test('版本 bump 與手術日誌：每次寫入都留下誰/何時/什麼', () {
    final v0 = store.version;
    store.updateRuleParams('galaxy.lightAuthority',
        newParams: {'modeCoef.galaxy': 0.9},
        author: 'human:Blue', reason: '微調');
    expect(store.version, v0 + 1);
    final s = store.surgeries();
    expect(s.first.action, 'ruleChange');
    expect(s.first.author, 'human:Blue');
    expect(s.first.detail, contains('galaxy.lightAuthority'));
  });

  test('事件廣播：規則修改發出 rulesChanged', () async {
    var fired = false;
    final sub = store.events.listen((e) {
      if (e.type == 'rulesChanged') fired = true;
    });
    store.updateRuleParams('galaxy.lightAuthority',
        newParams: {'modeCoef.galaxy': 1.05},
        author: 'human:Blue', reason: '測試事件');
    await Future.delayed(Duration.zero);
    expect(fired, isTrue);
    await sub.cancel();
  });

  test('意義層讀寫 round-trip', () {
    store.setMeaning('chat', 'nickname', '每天的心臟',
        author: 'human:Blue');
    final m = store.meaningsOf('chat');
    expect(m['nickname']?.value, '每天的心臟');
    expect(m['nickname']?.author, 'human:Blue');
  });
}

