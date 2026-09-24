import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transurfing_brain.dart';

class DoorDecisionStore {
  static const keyPendingReturn = 'door_decision_pending_return_v1';

  const DoorDecisionStore();

  static final ValueNotifier<DoorDecisionPendingReturn?> pendingReturn =
      ValueNotifier<DoorDecisionPendingReturn?>(null);

  Future<void> savePendingReturn(DoorDecisionPendingReturn pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPendingReturn, jsonEncode(pending.toJson()));
    pendingReturn.value = pending;
  }

  Future<DoorDecisionPendingReturn?> loadPendingReturn() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyPendingReturn);
    if (raw == null || raw.trim().isEmpty) {
      pendingReturn.value = null;
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        pendingReturn.value = null;
        return null;
      }
      final pending = DoorDecisionPendingReturn.fromJson(decoded);
      pendingReturn.value = pending;
      return pending;
    } catch (_) {
      pendingReturn.value = null;
      return null;
    }
  }

  Future<void> clearPendingReturn({String? decisionId}) async {
    final current = pendingReturn.value ?? await loadPendingReturn();
    if (decisionId != null &&
        current != null &&
        current.decisionId != decisionId) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyPendingReturn);
    pendingReturn.value = null;
  }
}
