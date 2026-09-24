// Smoke test for ProviderProfileStore custom policy methods
// 確認 activatePolicy / deactivatePolicy / getActivePolicy / applyOverrides /
// resolveActiveStrategy / getAllPolicies / createPolicy 都能跑
//
// flutter_test 會自動 mock path_provider，給 in-memory temp dir
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_profile_store.dart';
import 'package:bridge_app/services/agent_loop/custom_routing_policy.dart';

void main() {
  // 初始化 Flutter binding，讓 path_provider plugin 可以拿到 in-memory mock
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProviderProfileStore custom policy', () {
    late ProviderProfileStore store;

    setUp(() async {
      store = ProviderProfileStore.instance;
      await store.initialize();
    });

    test('createPolicy → getAllPolicies → getActivePolicy', () async {
      final policy = CustomRoutingPolicy(
        id: 'crp_test_001',
        name: 'Test 5-turn kimi',
        description: '降輪數',
        createdAt: DateTime.now(),
        provider: 'kimi',
        model: 'kimi-k3',
        isActive: false,  // 建立時不啟用
        overrides: {'maxTurns': 5},
      );

      await store.createPolicy(policy);
      final all = await store.getAllPolicies();
      expect(all.any((p) => p.id == 'crp_test_001'), true);

      // 尚未啟用，getActivePolicy 應回 null
      final activeBefore = await store.getActivePolicy('kimi', 'kimi-k3');
      expect(activeBefore, null);
    });

    test('activatePolicy → 自動停用同 scope 舊的', () async {
      // 先建一個 active
      final oldPolicy = CustomRoutingPolicy(
        id: 'crp_old',
        name: 'Old',
        description: '',
        createdAt: DateTime.now(),
        provider: 'kimi',
        model: 'kimi-k3',
        isActive: true,
        overrides: {'maxTurns': 5},
      );
      await store.createPolicy(oldPolicy);

      // 再建一個新的，activate 它
      final newPolicy = CustomRoutingPolicy(
        id: 'crp_new',
        name: 'New',
        description: '',
        createdAt: DateTime.now(),
        provider: 'kimi',
        model: 'kimi-k3',
        isActive: false,
        overrides: {'maxTurns': 8},
      );
      await store.createPolicy(newPolicy);
      await store.activatePolicy('crp_new');

      // 新的該是 active
      final activeAfter = await store.getActivePolicy('kimi', 'kimi-k3');
      expect(activeAfter?.id, 'crp_new');

      // 舊的應該被自動停用
      final all = await store.getAllPolicies();
      final oldPolicyAfter = all.firstWhere((p) => p.id == 'crp_old');
      expect(oldPolicyAfter.isActive, false);
    });

    test('applyOverrides: maxTurns→suggestedMaxTurns 映射；apiParams 覆寫已停用', () async {
      // 拿一個真實的內建 profile
      final base = await store.getProfile('kimi', 'kimi-k3');
      // 套用 custom overrides
      final merged = store.applyOverrides(base, {
        'maxTurns': 5,
        'apiParams': {'temperature': 0.7},
      });

      // maxTurns override → 映射到 suggestedMaxTurns
      expect(merged.suggestedMaxTurns, 5);
      // [modelFollowUser 鐵則] 政策不得覆寫 apiParams（日誌會警告並忽略）
      // ——模型參數跟著使用者設定走，policy 只管行為參數。
      expect(merged.apiParams['temperature'], isNot(0.7));
    });

    test('applyOverrides: forceToolUse 反推 unlimited', () async {
      final base = await store.getProfile('openai', 'gpt-5.4');
      // forceToolUse=false → unlimited=true
      final merged = store.applyOverrides(base, {'forceToolUse': false});
      expect(merged.unlimited, true);
    });

    test('resolveActiveStrategy: 沒 policy 時回傳內建 profile', () async {
      final strategy = await store.resolveActiveStrategy('kimi', 'kimi-k3');
      expect(strategy.provider, 'kimi');
      expect(strategy.model, 'kimi-k3');
      // kimi-k3 內建是 tier2
      expect(strategy.tier.name, 'tier2');
    });

    test('deactivatePolicy → getActivePolicy 回 null', () async {
      final policy = CustomRoutingPolicy(
        id: 'crp_deact',
        name: 'Deact',
        description: '',
        createdAt: DateTime.now(),
        provider: 'openai',
        model: 'gpt-5.4',
        isActive: true,
        overrides: {'maxTurns': 10},
      );
      await store.createPolicy(policy);
      await store.activatePolicy('crp_deact');

      // 確認 active
      var active = await store.getActivePolicy('openai', 'gpt-5.4');
      expect(active, isNotNull);

      // 停用
      await store.deactivatePolicy('crp_deact');
      active = await store.getActivePolicy('openai', 'gpt-5.4');
      expect(active, null);
    });

    test('custom policy 影響 getProfile', () async {
      final policy = CustomRoutingPolicy(
        id: 'crp_apply',
        name: 'Apply',
        description: '',
        createdAt: DateTime.now(),
        provider: 'openai',
        model: 'gpt-5.4',
        isActive: false,
        overrides: {'maxTurns': 3},
      );
      await store.createPolicy(policy);
      await store.activatePolicy('crp_apply');

      final profile = await store.getProfile('openai', 'gpt-5.4');
      expect(profile.suggestedMaxTurns, 3);  // 套用了 override
    });
  });
}