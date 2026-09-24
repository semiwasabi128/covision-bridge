import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_adapter_registry.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_action_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter extends BridgeActionAdapter {
  _FakeAdapter({
    required this.adapterId,
    this.shouldFail = false,
  });

  final String adapterId;
  final bool shouldFail;
  int callCount = 0;

  @override
  String get id => adapterId;

  @override
  String get displayName => 'Fake $adapterId';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    callCount++;
    if (shouldFail) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '$adapterId 模擬失敗',
      );
    }
    return BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: '$adapterId 成功',
      metadata: {'provider': adapterId},
    );
  }
}

void main() {
  // [小葵 2026-09-14] BudgetLedger._ensureLoaded 內部用 SharedPreferences，
  // 需要 binding 初始化 + mock（原本缺這兩行導致這兩個測試長期紅燈）。
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('不存在的 provider 仍誠實回報未實作（原 gemini/minimax 版本已過時：adapter 已存在）', () async {
    final result = await BridgeActionExecutor().execute(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: '機器人大戰哥吉拉',
        provider: 'anthropic',
      ),
    );

    expect(result.status, BridgeActionStatus.unsupported);
    expect(result.message, contains('尚未實作「anthropic」'));
    expect(result.message, contains('額度不代表 Bridge 已能呼叫'));
    expect(result.metadata?['kind'], 'provider_adapter_unavailable');
    expect(result.metadata?['requestedProvider'], 'anthropic');
  });

  test('主權鐵則：指定 provider 失敗時不得靜默 fallback 到別家（9/13 事件回歸測試）', () async {
    final failing = _FakeAdapter(adapterId: 'minimax', shouldFail: true);
    // 這個 fake 在測試環境無法通過 StorageService.getToken（無 path_provider），
    // 所以 fallback 候選本身就是空的；failing adapter 必須被呼叫且只有它被呼叫。
    final registry = BridgeAdapterRegistry(adapters: [failing]);
    final result = await BridgeActionExecutor(registry: registry).execute(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: '小葵形象圖',
        provider: 'minimax',
      ),
    );

    expect(result.status, isNot(BridgeActionStatus.completed));
    expect(failing.callCount, 1);
    expect(result.message, contains('minimax 模擬失敗'));
  });
}
