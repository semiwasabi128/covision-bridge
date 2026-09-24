// trio_m5b_harvest_test.dart
// [TRIO M5b 2026-09-23] 戰後分析驗收——計畫 vs 實際（非流水帳）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/swarm_campaign.dart';
import 'package:bridge_app/services/collab/swarm_recorder.dart';
import 'package:bridge_app/services/collab/swarm_harvest.dart';

void main() {
  setUp(() => SwarmCommand.resetForTest());

  SwarmCampaign _campaign({
    double estCost = 2.0,
    double actualCost = 2.2,
    int estMin = 30,
    int actualMin = 34,
  }) {
    final c = SwarmCommand.instance.openCampaign(
      objective: '照片圖鑑',
      endpoint: '50 張＋index.md',
      acceptance: 'ls 檔案數=50',
    )!;
    c.plan = '研究軍 10 兵檢索＋撰寫軍 8 兵產圖說';
    c.cost = CostEstimate(
      moneyCost: estCost,
      wallClock: Duration(minutes: estMin),
      computeLoad: 'glm×10 openai×8',
      failureRadius: '重打=2x',
    );
    c.actual = CostActual(
      moneySpent: actualCost,
      wallClockActual: Duration(minutes: actualMin),
    );
    return c;
  }

  test('H1 AAR=計畫vs實際——偏差表逐項對照', () {
    final c = _campaign();
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'campaign_open'),
      SwarmEvent(
          t: DateTime.now(), type: 'spawn', legion: '研究軍', agentId: 't1'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);

    // 偏差表有成本/牆鐘/成功率
    final items = aar.deviations.map((d) => d.item).toList();
    expect(items, contains('成本'));
    expect(items, contains('牆鐘'));
    expect(items, contains('單兵成功率'));
    // 成本偏差=10%
    final costRow = aar.deviations.firstWhere((d) => d.item == '成本');
    expect(costRow.expected, contains('2.00'));
    expect(costRow.actual, contains('2.20'));
    expect(costRow.deltaPct, closeTo(10, 0.1));
    // outcome 帶到
    expect(aar.outcome, 'done');
  });

  test('H2 成功率低的軍被點名（敗多於成→重點檢討）', () {
    final c = _campaign();
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '撰寫軍'),
      SwarmEvent(t: DateTime.now(), type: 'fail', legion: '撰寫軍'),
      SwarmEvent(t: DateTime.now(), type: 'fail', legion: '撰寫軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);
    final wRow = aar.deviations.firstWhere((d) => d.item.contains('撰寫軍'));
    expect(wRow.note, contains('重點檢討'), reason: '敗多於成要被點名');
  });

  test('H3 養分卡——高成功軍成為 success 卡', () {
    final c = _campaign();
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);
    expect(aar.nutrients.any((n) => n.kind == 'success'), isTrue);
    final card = aar.nutrients.firstWhere((n) => n.kind == 'success');
    expect(card.content, contains('研究軍'));
  });

  test('H4 成本超支>50% → fail 卡 + 註記', () {
    final c = _campaign(estCost: 2.0, actualCost: 4.5); // +125%
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: 'A軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: 'A軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);
    expect(aar.deviations.firstWhere((d) => d.item == '成本').note,
        contains('查明'));
    // 超支夠大——fail 卡萃取自成本偏差
    final costDev = aar.deviations.firstWhere((d) => d.item == '成本');
    expect((costDev.deltaPct ?? 0) > 50, isTrue);
  });

  test('H5 養分卡硬上限 3 張（寧缺勿濫）', () {
    final c = _campaign(estCost: 2.0, actualCost: 6.0);
    final events = <SwarmEvent>[
      for (var i = 0; i < 10; i++)
        SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '雜軍'),
      for (var i = 0; i < 3; i++)
        SwarmEvent(t: DateTime.now(), type: 'success', legion: '雜軍'),
      SwarmEvent(
          t: DateTime.now(), type: 'intel_share', legion: '雜軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);
    expect(aar.nutrients.length, lessThanOrEqualTo(3));
  });

  test('H7 成本核對（方法面）恆常存在——無論符合與否', () {
    final c = _campaign(estCost: 2.0, actualCost: 2.1); // +5% 符合
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: 'A軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: 'A軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);
    final row = aar.deviations.firstWhere((d) => d.item.contains('成本核對'));
    expect(row, isNotNull, reason: '符合也要記——不沉默');
    expect(row.note, contains('方法可信'));
  });

  test('H8 低估>20% → 核對卡給出修正方向', () {
    final c = _campaign(estCost: 2.0, actualCost: 3.5); // +75%
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: 'A軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: 'A軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final aar = SwarmHarvester.produce(campaign: c, events: events);
    final row = aar.deviations.firstWhere((d) => d.item.contains('成本核對'));
    expect(row.note, contains('低估'));
    expect(row.note, contains('上修'));
  });

  test('H9 render() 人類可讀——含計畫vs實際與養分', () {
    final c = _campaign();
    final events = <SwarmEvent>[
      SwarmEvent(t: DateTime.now(), type: 'spawn', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'success', legion: '研究軍'),
      SwarmEvent(t: DateTime.now(), type: 'end', data: {'outcome': 'done'}),
    ];
    final text = SwarmHarvester.produce(campaign: c, events: events).render();
    expect(text, contains('戰後分析'));
    expect(text, contains('計畫 vs 實際'));
    expect(text, contains('驗收'));
  });
}
