import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/flow_step.dart';
import '../models/project_door.dart';

class ProjectDoorStore {
  static const keyActiveProjectDoor = 'bridge_active_project_door_v0';
  static const keyProjectDoorList = 'bridge_project_doors_v0';

  const ProjectDoorStore();

  Future<ProjectDoor?> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActiveProjectDoor);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final door = ProjectDoor.fromJson(Map<String, dynamic>.from(decoded));
      return door.isValid ? door : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<ProjectDoor>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyProjectDoorList);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ProjectDoor.fromJson(Map<String, dynamic>.from(item)))
          .where((door) => door.isValid)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<ProjectDoor> saveActive(ProjectDoor door) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = door.copyWith(updatedAt: DateTime.now());
    await prefs.setString(
      keyActiveProjectDoor,
      jsonEncode(normalized.toJson()),
    );

    final all = List<ProjectDoor>.of(await loadAll());
    final index = all.indexWhere((item) => item.id == normalized.id);
    if (index >= 0) {
      all[index] = normalized;
    } else {
      all.add(normalized);
    }
    await prefs.setString(
      keyProjectDoorList,
      jsonEncode(all.map((item) => item.toJson()).toList()),
    );
    return normalized;
  }

  /// D11: 儲存門到 list（不影響 active 門）
  Future<ProjectDoor> save(ProjectDoor door) async {
    final all = List<ProjectDoor>.of(await loadAll());
    final normalized = door.copyWith(updatedAt: DateTime.now());
    final index = all.indexWhere((item) => item.id == normalized.id);
    if (index >= 0) {
      all[index] = normalized;
    } else {
      all.add(normalized);
    }
    await _persistAll(all);
    // 如果這是 active 門，也同步更新
    await _syncActive(normalized);
    return normalized;
  }

  Future<void> clearActive({String? id}) async {
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      final current = await loadActive();
      if (current != null && current.id != id) return;
    }
    await prefs.remove(keyActiveProjectDoor);
  }

  /// [Sprint 11] 綁定門與對話
  Future<ProjectDoor?> bindConversation(String doorId, String conversationId) async {
    final all = await loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null; // [Sprint 11 以西結審查 R1] 門不存在時回傳 null，不回傳錯誤的門
    final updated = all[index].copyWith(conversationId: conversationId);
    all[index] = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyProjectDoorList, jsonEncode(all.map((d) => d.toJson()).toList()));
    // 如果這是 active 門，也更新 active
    final active = await loadActive();
    if (active?.id == doorId) {
      await prefs.setString(keyActiveProjectDoor, jsonEncode(updated.toJson()));
    }
    return updated;
  }

  /// [Sprint 11] 用 conversationId 找門
  Future<ProjectDoor?> loadByConversationId(String conversationId) async {
    final all = await loadAll();
    for (final door in all) {
      if (door.conversationId == conversationId) return door;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════
  // [Sprint 18b] 水流步驟 CRUD
  // ═══════════════════════════════════════════════════

  /// 新增水流步驟到指定門
  Future<ProjectDoor?> addFlowStep(String doorId, FlowStep step) async {
    final all = await loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final door = all[index];
    final newSteps = [...door.flowSteps, step.copyWith(order: door.flowSteps.length)];
    final updated = door.copyWith(flowSteps: newSteps, updatedAt: DateTime.now());
    all[index] = updated;
    await _persistAll(all);
    await _syncActive(updated);
    return updated;
  }

  /// 更新水流步驟
  Future<ProjectDoor?> updateFlowStep(
    String doorId,
    String stepId, {
    String? title,
    String? description,
    String? status,
    List<String>? linkedAssetIds,
    List<String>? linkedMemoryIds,
  }) async {
    final all = await loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final door = all[index];
    final stepIndex = door.flowSteps.indexWhere((s) => s.id == stepId);
    if (stepIndex < 0) return null;

    final oldStep = door.flowSteps[stepIndex];
    final newStep = oldStep.copyWith(
      title: title,
      description: description,
      status: status,
      linkedAssetIds: linkedAssetIds,
      linkedMemoryIds: linkedMemoryIds,
      completedAt: status == FlowStep.statusDone
          ? (oldStep.completedAt ?? DateTime.now())
          : (status != null ? null : oldStep.completedAt),
    );
    final newSteps = List<FlowStep>.of(door.flowSteps);
    newSteps[stepIndex] = newStep;
    final updated = door.copyWith(flowSteps: newSteps, updatedAt: DateTime.now());
    all[index] = updated;
    await _persistAll(all);
    await _syncActive(updated);
    return updated;
  }

  /// 刪除水流步驟
  Future<ProjectDoor?> removeFlowStep(String doorId, String stepId) async {
    final all = await loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final door = all[index];
    final newSteps = door.flowSteps.where((s) => s.id != stepId).toList();
    final updated = door.copyWith(flowSteps: newSteps, updatedAt: DateTime.now());
    all[index] = updated;
    await _persistAll(all);
    await _syncActive(updated);
    return updated;
  }

  /// 更新門的看板狀態
  Future<ProjectDoor?> updateDoorStatus(String doorId, String status) async {
    final all = await loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final updated =
        all[index].copyWith(status: status, updatedAt: DateTime.now());
    all[index] = updated;
    await _persistAll(all);
    await _syncActive(updated);
    return updated;
  }

  /// 建立分岔門（帶入 parentDoorId 和部分上下文）
  Future<ProjectDoor> forkDoor(
    String parentDoorId, {
    required String title,
    required String sourceIntent,
    List<String>? intakeQuestions,
    List<String>? requiredBridges,
  }) async {
    final parent = (await loadAll())
        .where((d) => d.id == parentDoorId)
        .firstOrNull;
    final now = DateTime.now();
    final door = ProjectDoor(
      id: 'project-door-${now.microsecondsSinceEpoch}',
      title: title,
      sourceIntent: sourceIntent,
      currentFlow: '目標定義',
      intakeQuestions: intakeQuestions ??
          parent?.intakeQuestions ??
          const [],
      requiredBridges: requiredBridges ?? parent?.requiredBridges ?? const [],
      createdAt: now,
      updatedAt: now,
      status: ProjectDoor.statusActive,
      secondBrainEntryId: 'second-brain-project-door-${now.microsecondsSinceEpoch}',
      parentDoorId: parentDoorId,
      linkedAssetIds: parent?.linkedAssetIds ?? const [],
      linkedMemoryIds: parent?.linkedMemoryIds ?? const [],
    );
    await saveActive(door);
    return door;
  }

  // ── 內部 helper ──────────────────────────────────────

  /// P7: 刪除專案門
  Future<void> deleteDoor(String doorId) async {
    final all = await loadAll();
    all.removeWhere((d) => d.id == doorId);
    await _persistAll(all);
    // 如果刪除的是 active 門，清掉 active
    final active = await loadActive();
    if (active?.id == doorId) {
      await clearActive(id: doorId);
    }
  }

  Future<void> _persistAll(List<ProjectDoor> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyProjectDoorList,
      jsonEncode(all.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> _syncActive(ProjectDoor door) async {
    final active = await loadActive();
    if (active?.id == door.id) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        keyActiveProjectDoor,
        jsonEncode(door.toJson()),
      );
    }
  }
}
