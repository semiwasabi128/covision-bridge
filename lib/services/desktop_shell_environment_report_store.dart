import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_shell_environment_report.dart';

class DesktopShellEnvironmentReportStore {
  static const String keyReport = 'bridge_desktop_shell_environment_report_v1';

  const DesktopShellEnvironmentReportStore();

  Future<DesktopShellEnvironmentReport?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyReport);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DesktopShellEnvironmentReport.fromJson(decoded);
      }
      if (decoded is Map) {
        return DesktopShellEnvironmentReport.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } on FormatException {
      return null;
    }

    return null;
  }

  Future<void> save(DesktopShellEnvironmentReport report) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyReport, jsonEncode(report.toJson()));
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyReport);
  }
}
