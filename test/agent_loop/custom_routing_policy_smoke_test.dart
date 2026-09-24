// Smoke test for CustomRoutingPolicy / ActiveStrategy / ProviderProfileStore
// 直接執行：dart test/agent_loop/custom_routing_policy_smoke_test.dart
//
// 目的：驗證三個檔案的公開 API（建構子、序列化、方法呼叫）真的能跑，
// 不只是靜態分析通過。

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/custom_routing_policy.dart';
import 'package:bridge_app/services/agent_loop/active_strategy.dart';
import 'package:bridge_app/services/agent_loop/agent_provider_profile.dart';

void main() {
  group('CustomRoutingPolicy', () {
    test('建構子 + copyWith(isActive: false)', () {
      final policy = CustomRoutingPolicy(
        id: 'crp_test_1',
        name: 'Test Policy',
        description: 'Smoke test',
        createdAt: DateTime(2026, 7, 30, 14, 23),
        provider: 'kimi',
        model: 'kimi-k3',
        isActive: true,
        overrides: {'maxTurns': 5, 'apiParams': {'temperature': 0.7}},
        taskRouting: {'kimi': {'allowedIntents': ['summarize']}},
        flowOverride: null,
      );

      expect(policy.id, 'crp_test_1');
      expect(policy.isActive, true);
      expect(policy.taskRouting, isNotNull);

      final deactivated = policy.copyWith(isActive: false);
      expect(deactivated.isActive, false);
      expect(deactivated.id, policy.id);  // 其他欄位不變
      expect(deactivated.taskRouting, policy.taskRouting);
    });

    test('toJson / fromJson round-trip', () {
      final original = CustomRoutingPolicy(
        id: 'crp_roundtrip',
        name: 'Roundtrip',
        description: 'Test',
        createdAt: DateTime.utc(2026, 7, 30, 14, 23),
        provider: 'openai',
        model: null,  // null model 也該正確序列化
        isActive: false,
        overrides: {'maxTurns': 8},
        taskRouting: null,
        flowOverride: null,
      );

      final json = original.toJson();
      // null model 不該出現在 JSON（節省空間）
      expect(json.containsKey('model'), false);
      // null taskRouting/flowOverride 不該出現
      expect(json.containsKey('taskRouting'), false);

      final restored = CustomRoutingPolicy.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.model, null);
      expect(restored.overrides['maxTurns'], 8);
      expect(restored.isActive, false);
    });

    test('fromJson 容錯：缺欄位用預設', () {
      final restored = CustomRoutingPolicy.fromJson({
        'id': 'crp_partial',
        // 其他欄位都缺
      });
      expect(restored.id, 'crp_partial');
      expect(restored.name, '');
      expect(restored.isActive, false);
      expect(restored.overrides, isEmpty);
      expect(restored.taskRouting, null);
    });
  });

  group('ActiveStrategy', () {
    test('建構子 + toString', () {
      final strategy = ActiveStrategy(
        unlimited: true,
        suggestedMaxTurns: 25,
        suggestedTaskChunkSize: 20,
        promptNudge: 'test nudge',
        apiParams: {'temperature': 0.3},
        provider: 'openai',
        model: 'gpt-5.4',
        tier: ProviderTier.tier1,
      );

      expect(strategy.unlimited, true);
      expect(strategy.tier, ProviderTier.tier1);
      expect(strategy.toString(), contains('openai/gpt-5.4'));
    });
  });
}