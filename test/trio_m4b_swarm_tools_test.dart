// trio_m4b 工具組測試——六關按序推進
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
    final tmp = await Directory.systemTemp.createTemp('m4b_muster');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SwarmCommand.resetForTest();
    // [M5b] G0 出陣登記——pending 鑰預領（舊流程測試不因新閘門失真）
    await SwarmMusterRoll.instance.register(
      campaignId: SwarmMusterTool.pendingMusterKey,
      objective: '測試戰役',
      endpoint: '',
      toolkit: 'test',
      medkit: 'test',
      byHuman: 'test',
    );
  });

  test('工具組完整流程：open→六關→commit（跳關被擋）', () async {
    final open = await SwarmOpenTool().execute({
      'objective': '整理照片',
      'endpoint': '50 張編號圖＋index.md',
      'acceptance': 'ls 檔案數=50',
    });
    expect(open.success, isTrue);

    // G3 跳關（G2 還沒過）→ 擋
    final skip = await SwarmGatePassTool().execute({
      'gate': 'g3_plan',
      'artifact': '計畫',
    });
    expect(skip.success, isFalse, reason: '跳關必須被擋');
    expect(skip.content, contains('跳關'));

    // 按序：G2→G3→G4→G5→G6
    for (final gate in ['g2_intent', 'g3_plan', 'g4_map', 'g5_cost', 'g6_zero_doubt']) {
      final artifact = (gate == 'g3_plan' || gate == 'g5_cost') ? '產物' : '';
      final r = await SwarmGatePassTool().execute({'gate': gate, 'artifact': artifact});
      expect(r.success, isTrue, reason: '$gate 應該能過');
    }

    // 未點頭 commit → 擋
    final noNod = await SwarmCommitTool().execute({'user_confirmed': 'false'});
    expect(noNod.success, isFalse);

    // 點頭 → 開戰
    final go = await SwarmCommitTool().execute({'user_confirmed': 'true'});
    expect(go.success, isTrue);
    expect(SwarmCommand.instance.active!.phase, SwarmPhase.committed);
    // 開戰後 spawn 放行
    expect(SwarmCommand.instance.assertMaySpawn(troopCount: 30), isNull);
  });

  test('endpoint 空白 → 以終為始鐵則擋下', () async {
    final r = await SwarmOpenTool().execute({
      'objective': '做點什麼',
      'endpoint': '',
      'acceptance': '隨便',
    });
    expect(r.success, isFalse, reason: '沒有可驗證終點的戰爭不開打');
  });

  test('abort 後 status 反映', () async {
    await SwarmOpenTool().execute({
      'objective': 'x', 'endpoint': 'y', 'acceptance': 'z',
    });
    final r = await SwarmAbortTool().execute({'reason': '不打了'});
    expect(r.success, isTrue);
    expect(SwarmCommand.instance.active!.phase, SwarmPhase.aborted);
  });
}
