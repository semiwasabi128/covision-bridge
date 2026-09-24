import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bridge_action.dart';

class PendingBridgeTask {
  final String id;
  final String title;
  final String request;
  final String missing;
  final String route;
  final String routeLabel;
  final String iconName;
  final DateTime createdAt;
  final String? conversationId;
  final BridgeAction? bridgeAction;

  const PendingBridgeTask({
    required this.id,
    required this.title,
    required this.request,
    required this.missing,
    required this.route,
    required this.routeLabel,
    required this.iconName,
    required this.createdAt,
    this.conversationId,
    this.bridgeAction,
  });

  factory PendingBridgeTask.create({
    required String title,
    required String request,
    required String missing,
    required String route,
    required String routeLabel,
    required String iconName,
    String? conversationId,
    BridgeAction? bridgeAction,
  }) {
    final now = DateTime.now();
    return PendingBridgeTask(
      id: 'bridge-task-${now.microsecondsSinceEpoch}',
      title: title,
      request: request,
      missing: missing,
      route: route,
      routeLabel: routeLabel,
      iconName: iconName,
      createdAt: now,
      conversationId: conversationId,
      bridgeAction: bridgeAction,
    );
  }

  factory PendingBridgeTask.fromJson(Map<String, dynamic> json) {
    final actionJson = json['bridgeAction'];
    return PendingBridgeTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      request: json['request']?.toString() ?? '',
      missing: json['missing']?.toString() ?? '',
      route: json['route']?.toString() ?? '/chat',
      routeLabel: json['routeLabel']?.toString() ?? '回到任務',
      iconName: json['iconName']?.toString() ?? 'hub',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      conversationId: json['conversationId']?.toString(),
      bridgeAction: actionJson is Map
          ? BridgeAction.fromJson(Map<String, dynamic>.from(actionJson))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'request': request,
      'missing': missing,
      'route': route,
      'routeLabel': routeLabel,
      'iconName': iconName,
      'createdAt': createdAt.toIso8601String(),
      if (conversationId != null) 'conversationId': conversationId,
      if (bridgeAction != null) 'bridgeAction': bridgeAction!.toJson(),
    };
  }

  bool get isValid =>
      id.trim().isNotEmpty &&
      title.trim().isNotEmpty &&
      request.trim().isNotEmpty &&
      missing.trim().isNotEmpty;
}

class PendingBridgeTaskStore {
  static const keyActiveTask = 'bridge_pending_bridge_task_v0';

  const PendingBridgeTaskStore();

  Future<PendingBridgeTask?> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActiveTask);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final task = PendingBridgeTask.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return task.isValid ? task : null;
    } catch (_) {
      return null;
    }
  }

  Future<PendingBridgeTask> save(PendingBridgeTask task) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyActiveTask, jsonEncode(task.toJson()));
    return task;
  }

  Future<void> clear({String? taskId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (taskId != null) {
      final current = await loadActive();
      if (current != null && current.id != taskId) return;
    }
    await prefs.remove(keyActiveTask);
  }
}
