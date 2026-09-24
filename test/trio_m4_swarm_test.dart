// trio_m4_swarm_test.dart
// [TRIO M4 2026-09-22] 開戰閘門驗收——六關狀態機＋守衛
//
// 劇本：
//   S1 planning 期 spawn 被硬拒絕（含誠實原因）
//   S2 六關逐一過 → commit 成功 → spawn 放行
//   S3 五關就想 commit → 拒絕（缺一不可）
//   S4 棄案零殘留——abort 後 spawn 回覆「已收兵」
//   S5 兵力上限 100
//   S6 無戰役時 spawn 放行（既有小規模功能不被誤傷）
//   S7 一次一場——活躍戰役中開新戰役回 null
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';

void main() {
  setUp(() {
    SwarmCommand.resetForTest();
  });

  SwarmCampaign _open() => SwarmCommand.instance.openCampaign(
        objective: '把 50 份農場照片整理成圖鑑',
        endpoint: '輸出資料夾內有 50 張編號圖＋index.md',
        acceptance: 'ls 檔案數=50 且 index.md 列出全部',
      )!;

  test('S1 planning 期 spawn 硬拒絕（誠實原因）', () {
    _open();
    final denial = SwarmCommand.instance.assertMaySpawn(troopCount: 10);
    expect(denial, isNotNull);
    expect(denial, contains('六關'));
    expect(denial, contains('0/6'));
  });

  test('S2 六關過→commit→spawn 放行', () {
    final c = _open();
    for (var i = 0; i < 6; i++) {
      c.passGate();
    }
    expect(c.gatesPassed, 6);
    expect(c.commit(), isTrue);
    expect(c.phase, SwarmPhase.committed);
    expect(SwarmCommand.instance.assertMaySpawn(troopCount: 30), isNull,
        reason: '開戰後 30 兵在限內——放行');
  });

  test('S3 五關就想開戰→拒絕（缺一不可）', () {
    final c = _open();
    for (var i = 0; i < 5; i++) {
      c.passGate();
    }
    expect(c.commit(), isFalse, reason: '六關缺一——不可開戰');
    expect(SwarmCommand.instance.assertMaySpawn(troopCount: 5), isNotNull);
  });

  test('S4 棄案零殘留——abort 後 spawn 回「已收兵」', () {
    final c = _open();
    c.passGate();
    c.abort('不打了');
    expect(c.phase, SwarmPhase.aborted);
    final denial = SwarmCommand.instance.assertMaySpawn(troopCount: 10);
    expect(denial, contains('已收兵'));
  });

  test('S5 兵力上限 100', () {
    final c = _open();
    for (var i = 0; i < 6; i++) {
      c.passGate();
    }
    c.commit();
    final denial = SwarmCommand.instance.assertMaySpawn(troopCount: 101);
    expect(denial, contains('上限'), reason: 'span of control 上限被守護');
    expect(SwarmCommand.instance.assertMaySpawn(troopCount: 100), isNull);
  });

  test('S6 無戰役 spawn 放行（小規模既有功能不誤傷）', () {
    expect(SwarmCommand.instance.assertMaySpawn(troopCount: 3), isNull);
  });

  test('S7 一次一場——活躍戰役中開新戰役回 null', () {
    _open();
    final second = SwarmCommand.instance.openCampaign(
      objective: '另一場',
      endpoint: 'x',
      acceptance: 'y',
    );
    expect(second, isNull, reason: '先打完或棄案才能開下一場');
  });
}
