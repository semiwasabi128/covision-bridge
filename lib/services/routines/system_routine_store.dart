// system_routine_store.dart
// [刀 5 延伸 P2.3 2026-09-09] routine 存檔持久化——命名、列表、載入。
//
// routine 檔＝平台中立 JSON（設計稿 §2 跨平台約束）：
//   { version, id, name, recordedAt, events: [...] }
// 存 SharedPreferences（輕量；量大時升級檔案系統）。

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/routines/system_routine_recorder.dart';

class SavedRoutine {
  final String id;
  final String name;
  final DateTime recordedAt;
  final List<SystemRoutineEvent> events;

  const SavedRoutine({
    required this.id,
    required this.name,
    required this.recordedAt,
    required this.events,
  });

  int get stepCount => events.length;
  List<String> get story => events.map((e) => e.story).toList();

  Map<String, dynamic> toMap() => {
        'version': 1,
        'id': id,
        'name': name,
        'recordedAt': recordedAt.toIso8601String(),
        'events': events.map((e) => e.toMap()).toList(),
      };

  factory SavedRoutine.fromMap(Map<dynamic, dynamic> m) {
    final events = (m['events'] as List? ?? [])
        .map((raw) =>
            SystemRoutineEvent.fromMap(raw as Map<dynamic, dynamic>, 0))
        .toList();
    // 重編 seq（載入後 seq 連續）
    final reSeq = <SystemRoutineEvent>[];
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      reSeq.add(SystemRoutineEvent(
        seq: i, t: e.t, action: e.action, app: e.app,
        window: e.window, role: e.role, title: e.title,
        value: e.value, masked: e.masked, x: e.x, y: e.y,
        keyCode: e.keyCode, mods: e.mods,
      ));
    }
    return SavedRoutine(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '未命名',
      recordedAt: DateTime.tryParse((m['recordedAt'] as String?) ?? '') ??
          DateTime.now(),
      events: reSeq,
    );
  }
}

class SystemRoutineStore {
  SystemRoutineStore._();
  static final SystemRoutineStore instance = SystemRoutineStore._();

  static const _key = 'system_routine_saved_list';
  List<SavedRoutine>? _cache;

  Future<List<SavedRoutine>> list() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _cache = raw
        .map((s) {
          try {
            return SavedRoutine.fromMap(jsonDecode(s));
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedRoutine>()
        .toList();
    return _cache!;
  }

  Future<void> save(SavedRoutine routine) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await list();
    final kept = all.where((r) => r.id != routine.id).toList();
    kept.add(routine);
    await prefs.setStringList(
        _key, kept.map((r) => jsonEncode(r.toMap())).toList());
    _cache = null;
    debugPrint('[SystemRoutine] 已存「${routine.name}」（${routine.stepCount} 步）');
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await list();
    final kept = all.where((r) => r.id != id).toList();
    await prefs.setStringList(
        _key, kept.map((r) => jsonEncode(r.toMap())).toList());
    _cache = null;
  }

  /// 從目前錄製器事件建一個 routine
  SavedRoutine fromRecorder(String name, List<SystemRoutineEvent> events) =>
      SavedRoutine(
        id: 'sr_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        recordedAt: DateTime.now(),
        events: List.of(events),
      );
}
