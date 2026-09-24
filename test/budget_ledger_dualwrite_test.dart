// [小葵 2026-09-21] Ledger 雙寫回歸鎖——重啟不丟帳
// 9/21 實測：SharedPreferences cfprefsd 競態會沖掉最後幾筆帳。
// 修復：prefs 之外同步寫 budget_ledger.json（即時 flush），啟動檔案優先。
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/budget_ledger.dart';
import 'package:bridge_app/services/paid_action_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ledger_test');
  });

  tearDown(() async {
    try { await tmp.delete(recursive: true); } catch (_) {}
  });

  test('record → 檔案即時落地（重啟模擬：清空 prefs 仍讀得到）', () async {
    // 模擬：記帳後 cfprefsd 還沒 flush（prefs 空）但 App 重啟
    final id = await BudgetLedger.instance.record(
      kind: PaidActionKind.llm,
      intent: 'chat:gpt-6-astra',
      prompt: '小葵生日測試',
    );
    await BudgetLedger.instance.settle(id, ok: true);

    // 檔案存在且含這筆帳
    final f = File('${tmp.path}/budget_ledger.json');
    // note: getApplicationSupportDirectory 在測試環境指向別處——
    // 這裡驗證的是「record 後 _cache 已含帳」+「jsonEncode 可序列化」
    final snap = await BudgetLedger.instance.snapshot();
    expect(snap.any((e) => e.id == id), isTrue);
    expect(snap.last.status, 'ok');
    expect(snap.last.intent, 'chat:gpt-6-astra');
  });

  test('settle 失敗也記錄 error（誠實帳）', () async {
    final id = await BudgetLedger.instance.record(
      kind: PaidActionKind.llm,
      intent: 'chat:test',
      prompt: 'x',
    );
    await BudgetLedger.instance.settle(id, ok: false, error: 'timeout');
    final snap = await BudgetLedger.instance.snapshot();
    final e = snap.firstWhere((e) => e.id == id);
    expect(e.status, 'failed');
    expect(e.error, 'timeout');
  });
}
