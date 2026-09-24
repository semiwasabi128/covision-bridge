// trio_m4c 成本試算測試——分解成分＋歷史均量
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/swarm_cost.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';

void main() {
  setUp(() => SwarmCommand.resetForTest());

  test('試算表分解成分（數×量×單價）——不給總額糊弄', () {
    final sheet = SwarmCostEstimator.estimate(
      legionSpecs: [
        (name: '研究軍', troops: 10, turns: 5, provider: 'glm'),
        (name: '撰寫軍', troops: 8, turns: 6, provider: 'openai'),
      ],
      budgetCap: 5.0,
    );
    // 兩行明細都在
    expect(sheet.lines.length, 2);
    // 分解可驗：10兵×5輪×3000tok(粗估)/1M×$1 = $0.15
    final glm = sheet.lines.first;
    expect(glm.moneyUsd, closeTo(10 * 5 * 3000 / 1e6 * 1.0, 0.001));
    // openai：8×6×3000/1M×$8 = $1.44
    final oai = sheet.lines.last;
    expect(oai.moneyUsd, closeTo(8 * 6 * 3000 / 1e6 * 8.0, 0.001));
    // 合計=成分和
    expect(sheet.totalMoneyUsd, closeTo(glm.moneyUsd + oai.moneyUsd, 0.001));
    // 文字含上限與失敗半徑
    final text = sheet.breakdown();
    expect(text, contains('上限'));
    expect(text, contains('失敗半徑'));
    expect(text, contains('粗估')); // 無歷史時誠實標粗估
  });

  test('本地兵團零 token 費', () {
    final sheet = SwarmCostEstimator.estimate(
      legionSpecs: [(name: '本地軍', troops: 100, turns: 10, provider: 'local')],
    );
    expect(sheet.totalMoneyUsd, 0.0,
        reason: '本地模型燒電費不燒 token——錢只隨腦規模化');
  });

  test('試算表寫進戰役（G5 產物）', () {
    final sheet = SwarmCostEstimator.estimate(
      legionSpecs: [(name: 'A軍', troops: 5, turns: 4, provider: 'glm')],
    );
    final c = SwarmCommand.instance.openCampaign(
      objective: 'o', endpoint: 'e', acceptance: 'a')!;
    c.cost = SwarmCostEstimator.toCostEstimate(sheet);
    expect(c.cost!.moneyCost, sheet.totalMoneyUsd);
    expect(c.cost!.budgetCap, isNull);
  });
}
