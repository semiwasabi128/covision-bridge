// entity_relation_store.dart
// Entity 關聯的持久化儲存（SharedPreferences JSON）
// 建立日期: 2026-07-10
//
// 設計文件: entity-graph-service-design.md §3
//
// 格式：List<{sourceId, targetId, type}>
// 查詢：
// - getRelations(id) → filter sourceId == id
// - getReverseRelations(id) → filter targetId == id

import 'dart:convert';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntityRelationStore {
  static const String _key = 'bridge_entity_relations_v0';

  const EntityRelationStore();

  /// 取得所有關聯。
  Future<List<EntityRelation>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((item) => EntityRelation(
                sourceId: item['sourceId'] as String,
                targetId: item['targetId'] as String,
                type: RelationType.values.byName(item['type'] as String),
                sourcePort: item['sourcePort'] as String?,
                targetPort: item['targetPort'] as String?,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 取得某 Entity 的所有出向關聯（sourceId == entityId）。
  Future<List<EntityRelation>> getRelations(String entityId) async {
    final all = await getAll();
    return all.where((r) => r.sourceId == entityId).toList();
  }

  /// 取得反向關聯（誰引用了這個 Entity，targetId == entityId）。
  Future<List<EntityRelation>> getReverseRelations(String entityId) async {
    final all = await getAll();
    return all.where((r) => r.targetId == entityId).toList();
  }

  /// 建立關聯。自動去重（相同 sourceId + targetId + type 不重複加入）。
  /// 如果已存在但新 relation 帶有 port 資訊，則覆蓋舊的。
  Future<void> add(EntityRelation relation) async {
    final all = List<EntityRelation>.of(await getAll());
    // 如果已存在，檢查是否需要更新 port 資訊
    final existingIdx = all.indexWhere((r) =>
        r.sourceId == relation.sourceId &&
        r.targetId == relation.targetId &&
        r.type == relation.type);
    if (existingIdx >= 0) {
      // 覆蓋為帶有 port 資訊的新版本
      all[existingIdx] = relation;
      await _save(all);
      return;
    }
    all.add(relation);
    await _save(all);
  }

  /// 批次建立關聯。自動去重。
  Future<void> addAll(List<EntityRelation> relations) async {
    final all = List<EntityRelation>.of(await getAll());
    for (final relation in relations) {
      if (!all.any((r) =>
          r.sourceId == relation.sourceId &&
          r.targetId == relation.targetId &&
          r.type == relation.type)) {
        all.add(relation);
      }
    }
    await _save(all);
  }

  /// 移除關聯。
  Future<void> remove(String sourceId, String targetId, RelationType type) async {
    final all = List<EntityRelation>.of(await getAll());
    all.removeWhere((r) =>
        r.sourceId == sourceId &&
        r.targetId == targetId &&
        r.type == type);
    await _save(all);
  }

  /// 清除所有關聯（測試用）。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _save(List<EntityRelation> relations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(relations
          .map((r) => {
                'sourceId': r.sourceId,
                'targetId': r.targetId,
                'type': r.type.name,
                if (r.sourcePort != null) 'sourcePort': r.sourcePort,
                if (r.targetPort != null) 'targetPort': r.targetPort,
              })
          .toList()),
    );
  }
}
