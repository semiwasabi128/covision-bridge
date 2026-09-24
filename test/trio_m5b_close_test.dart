// trio_m5b_close_test.dart
// [TRIO M5b 2026-09-23] 收兵流程驗收——report→settle 兩段式（主權）
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/collab/swarm_tools.dart';
import 'package:bridge_app/services/collab/swarm_muster.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String> getApplicationSupportPath() async => dir;
}

void main() {
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('swarm_close_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SwarmCommand.resetForTest();
    await SwarmMusterRoll.instance.register(
      campaignId: SwarmMusterTool.pendingMusterKey,
      objective: '測試',
      endpoint: '',
      toolkit: 't',
      medkit: 'm',
      byHuman: 'test',
    );
  });

  test('C1 report 段——AAR 呈現＋問入樹（不結案）', () async {
    final c = SwarmCommand.instance.openCampaign(
        objective: 'o', endpoint: 'e', acceptance: 'a')!;
    for (var i = 0; i < 6; i++) {
      c.passGate();
    }
    c.commit();
    final r = await SwarmCloseTool().execute({});
    expect(r.success, isTrue);
    expect(r.content, contains('戰後分析'));
    expect(r.content, contains('入生命樹'));
    // 未結案
    expect(SwarmCommand.instance.active!.phase, SwarmPhase.committed);
  });

  test('C2 settle 沒點頭 → 擋', () async {
    final c = SwarmCommand.instance.openCampaign(
        objective: 'o', endpoint: 'e', acceptance: 'a')!;
    for (var i = 0; i < 6; i++) {
      c.passGate();
    }
    c.commit();
    final r = await SwarmCloseTool()
        .execute({'action': 'settle', 'user_confirmed': 'false'});
    expect(r.success, isFalse);
    expect(r.content, contains('主權'));
  });

  test('C3 settle 點頭 → 結案 done＋出陣登記註銷', () async {
    final c = SwarmCommand.instance.openCampaign(
        objective: 'o', endpoint: 'e', acceptance: 'a')!;
    for (var i = 0; i < 6; i++) {
      c.passGate();
    }
    c.commit();
    final r = await SwarmCloseTool().execute({
      'action': 'settle',
      'user_confirmed': 'true',
      'money_spent': '1.23',
    });
    expect(r.success, isTrue, reason: r.content);
    expect(SwarmCommand.instance.active!.phase, SwarmPhase.done);
    expect(SwarmCommand.instance.active!.actual!.moneySpent, 1.23);
    expect(r.content, contains('帳單實值'));
    // 出陣登記已註銷
    expect(SwarmMusterRoll.instance.lookup(c.id), isNull);
  });
}
