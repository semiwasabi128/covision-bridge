import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_task_routing_service.dart';

class TaskRoutingRuleStore {
  static const String keyRules = 'bridge_task_routing_rules_v1';

  const TaskRoutingRuleStore();

  Future<Map<String, TaskRoutingRuleMode>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyRules);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((key, value) {
        return MapEntry(
          key.toString(),
          TaskRoutingRuleModeX.fromName(value.toString()),
        );
      });
    } on FormatException {
      return const {};
    }
  }

  Future<void> save(Map<String, TaskRoutingRuleMode> rules) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = {
      for (final entry in rules.entries) entry.key: entry.value.name,
    };
    await prefs.setString(keyRules, jsonEncode(encoded));
  }

  Future<void> saveRule(String taskId, TaskRoutingRuleMode mode) async {
    final rules = Map<String, TaskRoutingRuleMode>.from(await load());
    if (mode == TaskRoutingRuleMode.auto) {
      rules.remove(taskId);
    } else {
      rules[taskId] = mode;
    }
    await save(rules);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyRules);
  }
}
