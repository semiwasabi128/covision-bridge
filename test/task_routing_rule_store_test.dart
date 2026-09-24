import 'dart:convert';

import 'package:bridge_app/services/local_task_routing_service.dart';
import 'package:bridge_app/services/task_routing_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('store saves and loads task routing rules', () async {
    SharedPreferences.setMockInitialValues({});

    const store = TaskRoutingRuleStore();
    await store.saveRule('private-draft', TaskRoutingRuleMode.localFirst);
    await store.saveRule('quick-chat', TaskRoutingRuleMode.askEveryTime);

    final rules = await store.load();

    expect(rules['private-draft'], TaskRoutingRuleMode.localFirst);
    expect(rules['quick-chat'], TaskRoutingRuleMode.askEveryTime);
  });

  test('store removes auto rules from persisted overrides', () async {
    SharedPreferences.setMockInitialValues({
      TaskRoutingRuleStore.keyRules: jsonEncode({
        'private-draft': 'cloudFirst',
      }),
    });

    const store = TaskRoutingRuleStore();
    await store.saveRule('private-draft', TaskRoutingRuleMode.auto);

    expect(await store.load(), isEmpty);
  });

  test('store ignores invalid payload', () async {
    SharedPreferences.setMockInitialValues({
      TaskRoutingRuleStore.keyRules: '{broken',
    });

    expect(await const TaskRoutingRuleStore().load(), isEmpty);
  });
}
