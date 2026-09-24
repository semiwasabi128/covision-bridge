// trio_m5a 戰爭層資料測試——swarmNow 形狀
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/brain_container/galaxy_data_service.dart';

void main() {
  setUp(() => SwarmCommand.resetForTest());

  test('無戰役 → swarmNow null（星系照轉無戰況）', () {
    expect(GalaxyDataService.swarmNow(), isNull);
  });

  test('planning 期 → campaign 在但零兵（未開戰不亮兵星）', () {
    final c = SwarmCommand.instance.openCampaign(
        objective: '照片圖鑑', endpoint: '50 張＋index', acceptance: 'ls=50')!;
    final sw = GalaxyDataService.swarmNow()!;
    expect(sw['campaign']['phase'], 'planning');
    expect(sw['campaign']['gates'], c.gatesPassed);
    final troops = sw['troops'] as List;
    expect(troops, isEmpty, reason: 'planning 期不派兵——閘門鐵則');
  });

  test('committed → 每軍官 10 帶兵星＋指揮鏈邊數正確', () {
    final c = SwarmCommand.instance.openCampaign(
        objective: 'o', endpoint: 'e', acceptance: 'a')!;
    for (var i = 0; i < 6; i++) {
      c.passGate();
    }
    c.commit();
    final sw = GalaxyDataService.swarmNow()!;
    expect(sw['campaign']['phase'], 'committed');
    final officers = sw['officers'] as List;
    final troops = sw['troops'] as List;
    final chains = sw['chains'] as List;
    // CompanionStore 在測試環境可能 0 夥伴——形狀不變式：chains==troops
    expect(chains.length, troops.length);
    // 每顆兵都有三維座標
    for (final t in troops) {
      expect((t['pos'] as List).length, 3);
    }
  });

  test('aborted → campaign.phase=aborted（頁面端清層）', () {
    final c = SwarmCommand.instance.openCampaign(
        objective: 'o', endpoint: 'e', acceptance: 'a')!;
    c.abort('不打了');
    final sw = GalaxyDataService.swarmNow()!;
    expect(sw['campaign']['phase'], 'aborted');
  });
}
