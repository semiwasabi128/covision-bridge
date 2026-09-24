// [小葵 2026-09-21] R1——生命樹雙主幹資料層
//
// Blue 2026-09-20 設計（已入 ledger）、2026-09-21 拍板動刀：
//   生命樹 = 夢境主幹 ⊕ 歷史主幹（雙幹合體）
//   夢境主幹：主枝幹=與使用者討論後結論(human_consensus)、
//             子枝幹=agents(≥2)討論後結論(agent_consensus)
//   歷史主幹：主枝幹=agent_causal_ledger 既有執行記錄、
//             子枝幹=agent 想過但未走的分支(thought_branch)
//
// 本檔是唯一寫入口（單一咽喉點模式，同 gate 家族）。
// 使用 package:sqlite3（與 BrainDatabase 同款同步 API）。
// 真相源：~/Library/Application Support/bridge_app/causal_ledger.db

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:sqlite3/sqlite3.dart';

/// 夢境主幹的結論卡
class LifeTreeDream {
  final int? id;
  final String? dreamSessionId;
  final String branchType; // human_consensus / agent_consensus
  final String conclusion;
  final String decision; // maintain / propose / escalate_to_user
  final List<String> sourceClues; // 議程線索（K1錯題/W4新藥/儀表紅燈）
  final List<String> companionIds;
  final String? modelUsed;
  final DateTime createdAt;
  final int? linkedLedgerId;

  const LifeTreeDream({
    this.id,
    this.dreamSessionId,
    required this.branchType,
    required this.conclusion,
    required this.decision,
    this.sourceClues = const [],
    this.companionIds = const [],
    this.modelUsed,
    required this.createdAt,
    this.linkedLedgerId,
  });
}

/// 歷史主幹的未走分支（「遺憾」——agent 想過但沒走的路）
class LifeTreeThoughtBranch {
  final int? id;
  final int ledgerId; // 源自哪筆執行記錄
  final String thought;
  final String? whyNotTaken;
  final DateTime createdAt;
  final DateTime? revisitedAt; // 夢境重評後填
  final String? revisitVerdict; // still_valid / superseded / worth_taking

  const LifeTreeThoughtBranch({
    this.id,
    required this.ledgerId,
    required this.thought,
    this.whyNotTaken,
    required this.createdAt,
    this.revisitedAt,
    this.revisitVerdict,
  });
}

/// 生命樹資料層——唯一寫入口
class LifeTreeStore {
  LifeTreeStore._();
  static final LifeTreeStore instance = LifeTreeStore._();

  // [小葵 2026-09-21 抓包修正] 測試路徑注入——測試曾因無法覆寫 HOME
  // 環境變數，直接把測試卡寫進真 causal_ledger.db（已清）。
  // 正解：測試用 override 指到暫存 DB，絕不碰真庫。
  @visibleForTesting
  static String? dbPathOverride;

  Database? _db;

  Database _open() {
    if (_db != null) return _db!;
    final String path;
    if (dbPathOverride != null) {
      path = dbPathOverride!; // 測試注入——絕不碰真庫
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      // 權威路徑：bridge_app（與 agent_causal_ledger 既有寫入者一致）
      path = '$home/Library/Application Support/bridge_app/causal_ledger.db';
      // fallback：farm 變體路徑（若權威不存在且 farm 存在）
      // 注意：兩者皆可能不存在（全新機）——_ensureTables 會建表
    }
    _db = sqlite3.open(path);
    _ensureTables(_db!);
    return _db!;
  }

  void _ensureTables(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS life_tree_dreams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dream_session_id TEXT,
        trunk TEXT NOT NULL DEFAULT 'dream',
        branch_type TEXT NOT NULL,
        conclusion TEXT NOT NULL,
        decision TEXT NOT NULL,
        source_clues TEXT,
        companion_ids TEXT,
        model_used TEXT,
        created_at TEXT NOT NULL,
        linked_ledger_id INTEGER
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS life_tree_thought_branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id INTEGER NOT NULL,
        thought TEXT NOT NULL,
        why_not_taken TEXT,
        revisited_at TEXT,
        revisit_verdict TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (ledger_id) REFERENCES agent_causal_ledger(id)
      )
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dream_trunk ON life_tree_dreams(trunk, branch_type)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tb_ledger ON life_tree_thought_branches(ledger_id)');
  }

  // ── 夢境主幹 ──────────────────────────────

  /// 寫入一張結論卡（fail-open：失敗留痕不擋任務）。回傳新 id（失敗 -1）。
  int addDream(LifeTreeDream dream) {
    try {
      final db = _open();
      db.execute(
        'INSERT INTO life_tree_dreams (dream_session_id, branch_type, conclusion, decision, source_clues, companion_ids, model_used, created_at, linked_ledger_id) VALUES (?,?,?,?,?,?,?,?,?)',
        [
          dream.dreamSessionId,
          dream.branchType,
          dream.conclusion,
          dream.decision,
          jsonEncode(dream.sourceClues),
          jsonEncode(dream.companionIds),
          dream.modelUsed,
          dream.createdAt.toIso8601String(),
          dream.linkedLedgerId,
        ],
      );
      return db.lastInsertRowId;
    } catch (e) {
      debugPrint('[LifeTree] addDream 失敗（fail-open）: $e');
      return -1;
    }
  }

  /// 夢境主幹最近結論卡（K5 議程讀歷史用）
  List<LifeTreeDream> recentDreams({int limit = 20}) {
    try {
      final rows = _open().select(
          'SELECT * FROM life_tree_dreams ORDER BY created_at DESC LIMIT ?',
          [limit]);
      return rows.map(_dreamFromRow).toList();
    } catch (e) {
      debugPrint('[LifeTree] recentDreams 失敗: $e');
      return const [];
    }
  }

  LifeTreeDream _dreamFromRow(Row row) => LifeTreeDream(
        id: row['id'] as int?,
        dreamSessionId: row['dream_session_id'] as String?,
        branchType: row['branch_type'] as String,
        conclusion: row['conclusion'] as String,
        decision: row['decision'] as String,
        sourceClues: _decodeList(row['source_clues']),
        companionIds: _decodeList(row['companion_ids']),
        modelUsed: row['model_used'] as String?,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        linkedLedgerId: row['linked_ledger_id'] as int?,
      );

  // ── 歷史主幹：未走分支 ──────────────────────

  /// 記下「agent 想過但未走的分支」。回傳新 id（失敗 -1）。
  int addThoughtBranch(LifeTreeThoughtBranch b) {
    try {
      final db = _open();
      db.execute(
        'INSERT INTO life_tree_thought_branches (ledger_id, thought, why_not_taken, created_at) VALUES (?,?,?,?)',
        [b.ledgerId, b.thought, b.whyNotTaken, b.createdAt.toIso8601String()],
      );
      return db.lastInsertRowId;
    } catch (e) {
      debugPrint('[LifeTree] addThoughtBranch 失敗（fail-open）: $e');
      return -1;
    }
  }

  /// 夢境重評：標記某未走分支的重訪結論（K5「重走沒走的路」）。回傳影響列數。
  int markRevisited(int branchId, String verdict) {
    try {
      final db = _open();
      db.execute(
        'UPDATE life_tree_thought_branches SET revisited_at = ?, revisit_verdict = ? WHERE id = ?',
        [DateTime.now().toIso8601String(), verdict, branchId],
      );
      // sqlite3 package 的 execute 不回列數——用 select 驗證已更新
      final row = db.select(
          'SELECT revisit_verdict FROM life_tree_thought_branches WHERE id = ?',
          [branchId]);
      return row.isNotEmpty && row.first['revisit_verdict'] == verdict ? 1 : 0;
    } catch (e) {
      debugPrint('[LifeTree] markRevisited 失敗: $e');
      return 0;
    }
  }

  /// 尚未被夢境重評的未走分支（K5 議程素材——「遺憾清單」）
  List<LifeTreeThoughtBranch> unrevisitedBranches({int limit = 10}) {
    try {
      final rows = _open().select(
          'SELECT * FROM life_tree_thought_branches WHERE revisited_at IS NULL ORDER BY created_at DESC LIMIT ?',
          [limit]);
      return rows.map(_tbFromRow).toList();
    } catch (e) {
      debugPrint('[LifeTree] unrevisitedBranches 失敗: $e');
      return const [];
    }
  }

  LifeTreeThoughtBranch _tbFromRow(Row row) => LifeTreeThoughtBranch(
        id: row['id'] as int?,
        ledgerId: row['ledger_id'] as int,
        thought: row['thought'] as String,
        whyNotTaken: row['why_not_taken'] as String?,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        revisitedAt: row['revisited_at'] == null
            ? null
            : DateTime.tryParse(row['revisited_at'] as String),
        revisitVerdict: row['revisit_verdict'] as String?,
      );

  List<String> _decodeList(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// 健康快照（R4 儀表用）：兩主幹規模
  Map<String, int> snapshot() {
    try {
      final db = _open();
      final d =
          db.select('SELECT COUNT(*) c FROM life_tree_dreams').first['c'] as int;
      final t = db
          .select('SELECT COUNT(*) c FROM life_tree_thought_branches')
          .first['c'] as int;
      final u = db
          .select(
              'SELECT COUNT(*) c FROM life_tree_thought_branches WHERE revisited_at IS NULL')
          .first['c'] as int;
      return {'dreams': d, 'thoughtBranches': t, 'unrevisited': u};
    } catch (e) {
      debugPrint('[LifeTree] snapshot 失敗: $e');
      return {'dreams': -1, 'thoughtBranches': -1, 'unrevisited': -1};
    }
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}
