import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_model_catalog_service.dart';

class LocalHardwareProfileStore {
  static const String keyProfile = 'bridge_local_hardware_profile_v1';

  const LocalHardwareProfileStore();

  Future<LocalHardwareProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyProfile);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return LocalHardwareProfile.fromJson(decoded);
      }
      if (decoded is Map) {
        return LocalHardwareProfile.fromJson(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> save(LocalHardwareProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyProfile, jsonEncode(profile.toJson()));
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyProfile);
  }
}
