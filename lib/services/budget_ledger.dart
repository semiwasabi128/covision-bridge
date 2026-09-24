// budget_ledger.dart
// [教練 Agent 2026-08-21] Agent 自律 Phase A——付費動作記帳本
// 「完全的自由來自於完全的自律」——自律的前提是看見自己。
// PaidActionGate 只計數（保險絲）；Ledger 記故事（意圖/成敗/重試），
// 供預算之眼（system prompt 注入）與自我節流（重試上限/重複偵測）查詢。
//
// 資料落地：SharedPreferences JSON（Phase A 輕量；量大再升 SQLite）。

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'paid_action_gate.dart';

/// 一筆付費動作的完整生命週期紀錄
class LedgerEntry {
  final String id;
  final PaidActionKind kind;
  final String intent; // 呼叫端申報的用途（工作流名/節點/任務）
  final String promptHash; // prompt 內容雜湊（重複偵測用）
  final DateTime at;
  final String status; // pending / ok / failed
  final String? error; // 失敗原因
  final String? companionId; // [刀 2 D2.1] 做這件事的夥伴（null=舊資料/非夥伴）

  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.intent,
    required this.promptHash,
    required this.at,
    this.status = 'pending',
    this.error,
    this.companionId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'intent': intent,
        'promptHash': promptHash,
        'at': at.toIso8601String(),
        'status': status,
        'error': error,
        if (companionId != null) 'companionId': companionId,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        kind: PaidActionKind.values.firstWhere((k) => k.name == j['kind']),
        intent: j['intent'] as String? ?? '',
        promptHash: j['promptHash'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        status: j['status'] as String? ?? 'pending',
        error: j['error'] as String?,
        companionId: j['companionId'] as String?,
      );
}

class BudgetLedger extends ChangeNotifier {
  BudgetLedger._();
  static final BudgetLedger instance = BudgetLedger._();

  static const _key = 'budget_ledger_entries';
  static const _maxEntries = 500; // 環形緩衝——足夠覆盤、不無限長大

  List<LedgerEntry> _cache = [];
  bool _loaded = false;

  Future<List<LedgerEntry>> _ensureLoaded() async {
    if (_loaded) return _cache;
    // [小葵 2026-09-21] 檔案優先——prefs 被 cfprefsd 競態沖掉時從檔案回填。
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/budget_ledger.json');
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _cache = list
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _loaded = true;
        return _cache;
      }
    } catch (e) {
      debugPrint('[BudgetLedger] 檔案讀取失敗，回退 prefs: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _cache = list
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _cache = [];
      }
    }
    _loaded = true;
    return _cache;
  }

  Future<void> _persist() async {
    final json = jsonEncode(_cache.map((e) => e.toJson()).toList());
    // 只留最近 _maxEntries 筆
    if (_cache.length > _maxEntries) {
      _cache = _cache.sublist(_cache.length - _maxEntries);
    }
    // [小葵 2026-09-21] 雙寫——9/21 實測抓到：SharedPreferences 落盤靠
    // cfprefsd 異步 flush，App 重啟時記憶體快取覆寫檔案會沖掉最後幾筆帳。
    // 對策： prefs 之外同步寫獨立檔案（即時 flush），啟動時以檔案為準回填。
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/budget_ledger.json');
      await f.writeAsString(
          jsonEncode(_cache.map((e) => e.toJson()).toList()),
          flush: true);
    } catch (e) {
      debugPrint('[BudgetLedger] 檔案寫入失敗（僅 prefs）: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json);
  }

  /// 記一筆（pending），回傳 entry id 供事後結案
  Future<String> record({
    required PaidActionKind kind,
    required String intent,
    required String prompt,
    String? companionId, // [刀 2 D2.1] 做這件事的夥伴
  }) async {
    await _ensureLoaded();
    final id =
        'led_${DateTime.now().millisecondsSinceEpoch}_${_cache.length}';
    final entry = LedgerEntry(
      id: id,
      kind: kind,
      intent: intent,
      promptHash: _hash(prompt),
      at: DateTime.now(),
      companionId: companionId,
    );
    _cache.add(entry);
    await _persist();
    notifyListeners(); // [K6.1] 訂閱刷新
    return id;
  }

  /// 結案（成功或失敗）
  Future<void> settle(String id, {required bool ok, String? error}) async {
    await _ensureLoaded();
    final i = _cache.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _cache[i] = LedgerEntry(
      id: _cache[i].id,
      kind: _cache[i].kind,
      intent: _cache[i].intent,
      promptHash: _cache[i].promptHash,
      at: _cache[i].at,
      status: ok ? 'ok' : 'failed',
      error: error,
    );
    await _persist();
    notifyListeners(); // [K6.1] 訂閱刷新（K6.4 跑馬燈也吃這個）
  }

  /// [K6.1] 完整快照（給 TrustMeter 渲染用）
  Future<List<LedgerEntry>> snapshot() async {
    await _ensureLoaded();
    return List.unmodifiable(_cache);
  }

  /// [K6.1] 重複 prompt 偵測（浪費率核心——同樣的事不該問兩次）
  Future<int> duplicatePromptsToday() async {
    await _ensureLoaded();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final hashes = <String, int>{};
    for (final e in _cache) {
      if (e.at.toIso8601String().substring(0, 10) != today) continue;
      hashes[e.promptHash] = (hashes[e.promptHash] ?? 0) + 1;
    }
    final dupes = hashes.values.where((n) => n > 1);
    var total = 0;
    for (final n in dupes) {
      total += n;
    }
    return total;
  }

  /// [刀 2 D2.1] 以夥伴為單位的審計統計——身份卡「工作實績」數據源。
  /// （全部歷史，不限今日——身份卡看的是這個成員的完整軌跡）
  Future<({int total, int ok, int failed})> statsFor(String companionId) async {
    await _ensureLoaded();
    final mine = _cache.where((e) => e.companionId == companionId).toList();
    return (
      total: mine.length,
      ok: mine.where((e) => e.status == 'ok').length,
      failed: mine.where((e) => e.status == 'failed').length,
    );
  }

  /// [刀 2 D2.1] 該夥伴最近 N 筆（Ledger BottomSheet 資料源）
  Future<List<LedgerEntry>> recentFor(String companionId, {int limit = 30}) async {
    await _ensureLoaded();
    final mine = _cache.where((e) => e.companionId == companionId).toList();
    if (mine.length <= limit) return List.unmodifiable(mine.reversed);
    return List.unmodifiable(mine.sublist(mine.length - limit).reversed);
  }

  // ── 自律查詢 API（預算之眼 + 自我節流） ──

  /// 同一 prompt 雜湊的連續失敗次數（重試上限用：≥2 必須換策略）
  Future<int> consecutiveFailuresFor(String prompt) async {
    await _ensureLoaded();
    final h = _hash(prompt);
    final samePrompt = _cache.where((e) => e.promptHash == h).toList();
    if (samePrompt.isEmpty) return 0;
    var n = 0;
    for (final e in samePrompt.reversed) {
      if (e.status == 'failed') {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  /// 今日近 N 筆摘要（預算之眼注入用）——「x/y 採用」格式
  Future<({int total, int ok, int failed})> todayStats() async {
    await _ensureLoaded();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todays = _cache
        .where((e) => e.at.toIso8601String().substring(0, 10) == today)
        .toList();
    return (
      total: todays.length,
      ok: todays.where((e) => e.status == 'ok').length,
      failed: todays.where((e) => e.status == 'failed').length,
    );
  }

  /// 昨日浪費率（失敗筆數/總筆數）——長期策略修正指標
  Future<double> wasteRate() async {
    await _ensureLoaded();
    final settled =
        _cache.where((e) => e.status != 'pending').toList();
    if (settled.length < 5) return 0; // 樣本不足不判
    final failed = settled.where((e) => e.status == 'failed').length;
    return failed / settled.length;
  }

  /// [教練 Agent 2026-08-21] 測試用——清空快取與持久層
  @visibleForTesting
  Future<void> resetForTest() async {
    _cache = [];
    _loaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  String _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}
