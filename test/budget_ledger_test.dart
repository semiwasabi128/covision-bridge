// budget_ledger_test.dart
// [小葵 2026-08-21] 自律 Phase A——記帳本＋節流＋預算之眼實測
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/budget_ledger.dart';
import 'package:bridge_app/services/paid_action_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('記帳→結案→統計：成功與失敗誠實入帳', () async {
    SharedPreferences.setMockInitialValues({});
    await BudgetLedger.instance.resetForTest();
    final ledger = BudgetLedger.instance;
    final id1 = await ledger.record(
        kind: PaidActionKind.image, intent: 'generateImage', prompt: '海報 A');
    await ledger.settle(id1, ok: true);
    final id2 = await ledger.record(
        kind: PaidActionKind.image, intent: 'generateImage', prompt: '海報 B');
    await ledger.settle(id2, ok: false, error: '429');
    final stats = await ledger.todayStats();
    expect(stats.total, 2);
    expect(stats.ok, 1);
    expect(stats.failed, 1);
  });

  test('同 prompt 連續失敗計數（重試螺旋斷路器）', () async {
    SharedPreferences.setMockInitialValues({});
    await BudgetLedger.instance.resetForTest();
    final ledger = BudgetLedger.instance;
    for (var i = 0; i < 3; i++) {
      final id = await ledger.record(
          kind: PaidActionKind.image, intent: 'generateImage', prompt: '同樣的失敗');
      await ledger.settle(id, ok: false, error: 'timeout');
    }
    expect(await ledger.consecutiveFailuresFor('同樣的失敗'), 3);
    // 不同 prompt 不受影響
    expect(await ledger.consecutiveFailuresFor('全新的嘗試'), 0);
  });

  test('成功重置連續失敗計數', () async {
    SharedPreferences.setMockInitialValues({});
    await BudgetLedger.instance.resetForTest();
    final ledger = BudgetLedger.instance;
    final id1 = await ledger.record(
        kind: PaidActionKind.image, intent: 'x', prompt: 'P');
    await ledger.settle(id1, ok: false);
    final id2 = await ledger.record(
        kind: PaidActionKind.image, intent: 'x', prompt: 'P');
    await ledger.settle(id2, ok: true);
    expect(await ledger.consecutiveFailuresFor('P'), 0);
  });

  test('預算之眼輸出含額度與自律原則', () async {
    SharedPreferences.setMockInitialValues({});
    await BudgetLedger.instance.resetForTest();
    final eye = await PaidActionGate.instance.budgetEye();
    expect(eye, contains('[額度]'));
    expect(eye, contains('圖片 0/30'));
    expect(eye, contains('[自律原則]'));
  });

  test('浪費率：樣本不足回 0，失敗多則升高', () async {
    SharedPreferences.setMockInitialValues({});
    await BudgetLedger.instance.resetForTest();
    final ledger = BudgetLedger.instance;
    expect(await ledger.wasteRate(), 0); // 樣本不足
    for (var i = 0; i < 5; i++) {
      final id = await ledger.record(
          kind: PaidActionKind.music, intent: 'x', prompt: 'p$i');
      await ledger.settle(id, ok: i < 2); // 2 成功 3 失敗
    }
    expect(await ledger.wasteRate(), closeTo(0.6, 0.01));
  });
}
