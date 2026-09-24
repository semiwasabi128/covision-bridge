// canvas_state_store_sqlite.dart
// [教練 Agent 2026-08-26 使用者 搬遷令] 畫布節點持久化：SharedPreferences → SQLite
//
// 為什麼搬（上線等級儲存）：
// 1. SharedPreferences = 整包 JSON 讀寫——每改一個節點座標都重寫全部；
//    節點破千即卡，且無交易保護（寫到一半崩潰＝半套資料）。
// 2. SQLite = 逐列 UPSERT、原子交易、canvas_id 有索引——
//    getCanvasNodes(canvasId:) 從全撈過濾變成索引直查。
// 3. 跟大腦（memories/assets）同一個檔案——一個備份點、一個 VACUUM。
//
// 搬遷設計（安全第一）：
// - 首次啟動：讀 plist 舊資料 → 逐列 INSERT → 完成後 brain_meta 記
//   canvas_nodes_migrated=1 → plist 原 key 改存 __migrated__ 旗標（不刪，
//   保留 rollback 能力一個版本）。
// - 讀取：DB 為準；若未搬遷且 plist 有資料 → 先搬遷再回傳。
// - 寫入：一律寫 DB（plist 不再寫入）。
// - 失敗：任何環節炸 → 退回舊 CanvasStateStore 行為（App 不死）。

import 'dart:convert';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brain_container/brain_database.dart';

/// 舊 SharedPreferences key（唯讀相容）
const String _legacyKey = 'bridge_canvas_state_v0';

class SqliteCanvasStateStore {
  /// 舊實作（fallback 用）
  final _legacy = const LegacyCanvasStateStore();

  bool _migrationChecked = false;

  /// 搬遷冪等旗標（進程內）
  bool get migrationChecked => _migrationChecked;

  /// 確保搬遷已執行（首次呼叫觸發；之後 no-op）
  Future<void> ensureMigrated() async {
    if (_migrationChecked) return;
    _migrationChecked = true;
    try {
      final db = BrainDatabase.instance.db;
      final flag = db.select(
          "SELECT value FROM brain_meta WHERE key = 'canvas_nodes_migrated'");
      if (flag.isNotEmpty) return; // 已搬過

      // 讀 plist 舊資料
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null || raw.trim().isEmpty || raw == '__migrated__') {
        // 無舊資料——直接標記完成
        db.execute(
            "INSERT OR REPLACE INTO brain_meta(key, value) VALUES ('canvas_nodes_migrated', '1')");
        return;
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // 原子交易逐列搬
      db.execute('BEGIN');
      try {
        final stmt = db.prepare(
            'INSERT OR REPLACE INTO canvas_nodes(entity_id, canvas_id, node_type, props_json) VALUES (?, ?, ?, ?)');
        for (final entry in decoded.entries) {
          final propsMap = Map<String, dynamic>.from(entry.value as Map);
          final props = CanvasProps.fromJson(propsMap);
          final propsJson = jsonEncode(props.toJson());
          final canvasId = (props.canvasId ?? 'default');
          stmt.execute([entry.key, canvasId, props.nodeType?.name, propsJson]);
        }
        stmt.dispose();
        db.execute(
            "INSERT OR REPLACE INTO brain_meta(key, value) VALUES ('canvas_nodes_migrated', '1')");
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }

      // 搬遷成功——plist 舊 key 留 __migrated__ 旗標（不刪，保留 rollback）
      await prefs.setString(_legacyKey, '__migrated__');
    } catch (_) {
      // 搬遷失敗——讀寫路徑自動退回 legacy；下次啟動重試
      _migrationChecked = false;
    }
  }

  /// 取得某 Entity 的畫布屬性。null = 不在畫布上。
  Future<CanvasProps?> getAsync(String entityId) async {
    await ensureMigrated();
    try {
      final db = BrainDatabase.instance.db;
      final rows = db
          .select('SELECT props_json FROM canvas_nodes WHERE entity_id = ?', [
        entityId
      ]);
      if (rows.isEmpty) return null;
      return CanvasProps.fromJson(
          jsonDecode(rows.first['props_json'] as String) as Map<String, dynamic>);
    } catch (_) {
      return _legacy.getAsync(entityId);
    }
  }

  /// 設定某 Entity 的畫布屬性。
  Future<void> set(String entityId, CanvasProps props) async {
    await ensureMigrated();
    try {
      final db = BrainDatabase.instance.db;
      final propsJson = jsonEncode(props.toJson());
      // [v199 畫布失蹤根因令] 以前 null→'default' 的 fallback 造成：
      // 節點寫進 default 而非當前畫布（Blue 的０３節點全部失蹤）。
      // 現在 null 一律拒寫並大聲警告——bug 在源頭爆而不是默默吞。
      final canvasId = props.canvasId;
      if (canvasId == null) {
        debugPrint('[v199] ⚠️ canvasId=null 拒寫（呼叫端沒帶畫布 id）entity=$entityId');
        return;
      }
      db.prepare(
          'INSERT OR REPLACE INTO canvas_nodes(entity_id, canvas_id, node_type, props_json, updated_at) VALUES (?, ?, ?, ?, datetime(\'now\'))')
        ..execute([entityId, canvasId, props.nodeType?.name, propsJson])
        ..dispose();
    } catch (_) {
      await _legacy.set(entityId, props);
    }
  }

  /// 移除某 Entity 的畫布屬性。
  Future<void> remove(String entityId) async {
    await ensureMigrated();
    try {
      final db = BrainDatabase.instance.db;
      db.prepare('DELETE FROM canvas_nodes WHERE entity_id = ?')
        ..execute([entityId])
        ..dispose();
    } catch (_) {
      await _legacy.remove(entityId);
    }
  }

  /// 取得所有畫布節點的 Map（可指定 canvasId——走索引）。
  Future<Map<String, CanvasProps>> loadAll({String? canvasId}) async {
    await ensureMigrated();
    try {
      final db = BrainDatabase.instance.db;
      final rows = canvasId == null
          ? db.select('SELECT entity_id, props_json FROM canvas_nodes')
          : db.select(
              'SELECT entity_id, props_json FROM canvas_nodes WHERE canvas_id = ?',
              [canvasId]);
      return {
        for (final r in rows)
          r['entity_id'] as String: CanvasProps.fromJson(
              jsonDecode(r['props_json'] as String) as Map<String, dynamic>),
      };
    } catch (_) {
      final all = await _legacy.loadAll();
      if (canvasId == null) return all;
      return Map.fromEntries(
          all.entries.where((e) => e.value.canvasId == canvasId));
    }
  }

  /// 清除所有畫布狀態。
  Future<void> clear() async {
    await ensureMigrated();
    try {
      BrainDatabase.instance.db.execute('DELETE FROM canvas_nodes');
    } catch (_) {
      await _legacy.clear();
    }
  }
}

/// 舊 SharedPreferences 實作（保留原檔案邏輯，fallback 用）。
/// [教練 Agent 2026-08-26] 原行為 100% 保留——搬遷失敗時 App 退回舊路徑。
class LegacyCanvasStateStore {
  const LegacyCanvasStateStore();

  Future<CanvasProps?> getAsync(String entityId) async {
    final all = await _loadAll();
    return all[entityId];
  }

  Future<void> set(String entityId, CanvasProps props) async {
    final all = await _loadAll();
    all[entityId] = props;
    await _save(all);
  }

  Future<void> remove(String entityId) async {
    final all = await _loadAll();
    all.remove(entityId);
    await _save(all);
  }

  Future<Map<String, CanvasProps>> loadAll() async {
    return _loadAll();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey);
  }

  Future<Map<String, CanvasProps>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey);
    if (raw == null || raw.trim().isEmpty || raw == '__migrated__') return {};
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
      _legacyKey,
      jsonEncode(data.map((id, props) => MapEntry(id, props.toJson()))),
    );
  }
}
