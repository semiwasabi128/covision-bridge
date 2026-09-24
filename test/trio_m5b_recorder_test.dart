// trio_m5b_recorder_test.dart
// [TRIO M5b 2026-09-23] 記錄器＋G0 出陣登記驗收
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:bridge_app/services/collab/swarm_recorder.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/collab/swarm_tools.dart';
import 'package:bridge_app/services/collab/swarm_tools.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String> getApplicationSupportPath() async => dir;
}

void main() {
  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('swarm_rec_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SwarmCommand.resetForTest();
  });

  test('R1 事件流落盤——JSONL 逐行可重播', () async {
    final r = SwarmRecorder('camp-test-1');
    await r.log('campaign_open', data: {'objective': 'x'});
    await r.log('gate_pass', data: {'gate': 'g2_intent'});
    await r.log('commit', data: {'cost': 1.5});
    await r.log('end', data: {'outcome': 'done'});

    // 重播=讀回事件流
    final events = await SwarmCampaignAssets.instance.loadEvents('camp-test-1');
    expect(events.length, 4);
    expect(events.first.type, 'campaign_open');
    expect(events.last.type, 'end');
    // 時間單調（非遞減）
    for (var i = 1; i < events.length; i++) {
      expect(!events[i].t.isBefore(events[i - 1].t), isTrue);
    }
  });

  test('R2 摘要——戰績統計從事件流重建', () async {
    final r = SwarmRecorder('camp-test-2');
    await r.log('campaign_open');
    await r.log('spawn', agentId: 't1', legion: '研究軍');
    await r.log('spawn', agentId: 't2', legion: '研究軍');
    await r.log('success', agentId: 't1');
    await r.log('fail', agentId: 't2');
    await r.log('intel_share', agentId: 't1');
    await r.log('end');
    final sum = r.summary();
    expect(sum['spawns'], 2);
    expect(sum['success'], 1);
    expect(sum['fail'], 1);
    expect(sum['intel'], 1);
  });

  test('R3 資產列表——列出歷史戰役', () async {
    final r = SwarmRecorder('camp-list-a');
    await r.log('campaign_open');
    await r.log('end');
    final list = await SwarmCampaignAssets.instance.listCampaigns();
    expect(list.any((c) => c['campaignId'] == 'camp-list-a'), isTrue);
    expect(list.first['campaignId'], 'camp-list-a');
  });

  test('R4 刪除——主權', () async {
    final r = SwarmRecorder('camp-del');
    await r.log('campaign_open');
    expect(await SwarmCampaignAssets.instance.delete('camp-del'), isTrue);
    expect(await SwarmCampaignAssets.instance.loadEvents('camp-del'), isEmpty);
  });

  test('G0 未登記 → swarm_open 被擋（出陣儀式）', () async {
    final r = await SwarmOpenTool().execute({
      'objective': 'o', 'endpoint': 'e', 'acceptance': 'a',
    });
    expect(r.success, isFalse, reason: '沒領裝備不能開戰役');
    expect(r.content, contains('G0'));
    expect(r.content, contains('羅盤'));
  });

  test('G0b 先領裝備（pending）→ open 配對成功', () async {
    // 先登記（pending 鑰）
    final m = await SwarmMusterTool().execute({
      'objective': '照片圖鑑',
      'toolkit': 'browse+vision+generate_image',
      'medkit': r'停損：$5；404 退回單兵模式',
    });
    expect(m.success, isTrue, reason: '登記本身不該被擋');
    // 後開戰役——pending 配對
    final r = await SwarmOpenTool().execute({
      'objective': 'o', 'endpoint': 'e', 'acceptance': 'a',
    });
    expect(r.success, isTrue, reason: '領過裝備→G0 過');
    // 戰役已過 G1
    expect(SwarmCommand.instance.active!.gatesPassed, 1);
  });
}
