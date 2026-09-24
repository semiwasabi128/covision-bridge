// canvas_state_store.dart
// 畫布節點空間屬性的持久化儲存（SharedPreferences JSON）
// 建立日期: 2026-07-10
//
// 設計文件: entity-graph-service-design.md §4
//
// 格式：Map<entityId, CanvasProps JSON>
// 儲存於 SharedPreferences。
// CanvasNode 目前無持久化，位置是 runtime state。
// Entity Graph 需要位置持久化——此 Store 解決這個問題。

import 'dart:convert';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CanvasStateStore {
  static const String _key = 'bridge_canvas_state_v0';

  const CanvasStateStore();

  /// 取得某 Entity 的畫布屬性。null = 不在畫布上。
  Future<CanvasProps?> getAsync(String entityId) async {
    final all = await _loadAll();
    return all[entityId];
  }

  /// 設定某 Entity 的畫布屬性（放到畫布上或更新位置）。
  Future<void> set(String entityId, CanvasProps props) async {
    final all = await _loadAll();
    all[entityId] = props;
    await _save(all);
  }

  /// 移除某 Entity 的畫布屬性（從畫布移除，Entity 本身不刪）。
  Future<void> remove(String entityId) async {
    final all = await _loadAll();
    all.remove(entityId);
    await _save(all);
  }

  /// 取得所有畫布節點的 Map。
  /// 供 EntityGraphService.getCanvasNodes() 使用。
  /// [教練 Agent 2026-08-26 搬遷令] 加 canvasId 參數（記憶體過濾——新 store 是 SQL WHERE）。
  Future<Map<String, CanvasProps>> loadAll({String? canvasId}) async {
    final all = await _loadAll();
    if (canvasId == null) return all;
    return Map.fromEntries(
        all.entries.where((e) => e.value.canvasId == canvasId));
  }

  /// 清除所有畫布狀態（測試用）。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<Map<String, CanvasProps>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((id, json) {
        final m = Map<String, dynamic>.from(json as Map);
        return MapEntry(id, CanvasProps.fromJson(m));
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, CanvasProps> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(data.map((id, props) => MapEntry(id, props.toJson()))),
    );
  }
}
