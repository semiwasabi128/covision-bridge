import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_companion_shell_config.dart';

class DesktopCompanionShellConfigStore {
  static const String _keyConfig = 'bridge_desktop_shell_config_v1';

  const DesktopCompanionShellConfigStore();

  Future<DesktopCompanionShellConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyConfig);
    if (raw == null || raw.isEmpty) {
      return const DesktopCompanionShellConfig();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DesktopCompanionShellConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return DesktopCompanionShellConfig.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on FormatException {
      return const DesktopCompanionShellConfig();
    }

    return const DesktopCompanionShellConfig();
  }

  Future<void> save(DesktopCompanionShellConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyConfig, jsonEncode(config.toJson()));
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyConfig);
  }
}
