// intel_pool.dart
// [TRIO M2 2026-09-22] 共享情報池——甲踩過的坑，乙不用再踩。
//
// 設計（AGENT_TRIO_COLLAB_SPEC §三層二）：
//   - 輕量 JSON Lines 檔（每行一筆，append-only——主權鐵則：只加不刪，
//     錯誤情報用 refute 標記而非抹除）
//   - 欄位：id / fromAgent / kind / content / relatedSession / createdAt /
//     consumedBy（誰已消化過）
//   - kind 詞彙表（禁同義詞）：pit（坑）/ lead（線索）/ external（外部情報）/
//     preview（成果預告）
//   - 寫入時機：agent 工作中主動 intel_share ＋任務收尾自動摘要
//   - 消費時機：會議前全量注入；新任務派工時注入相關
//
// 帳可查（鐵則三）：誰寫的、什麼時候、跟哪個任務有關——全可考。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 情報種類——詞彙表，禁同義詞
enum IntelKind { pit, lead, external, preview }

extension IntelKindLabel on IntelKind {
  String get label => switch (this) {
        IntelKind.pit => '坑',
        IntelKind.lead => '線索',
        IntelKind.external => '外部情報',
        IntelKind.preview => '成果預告',
      };
}

class IntelEntry {
  final String id;
  final String fromAgent;
  final IntelKind kind;
  final String content;
  final String? relatedSession;
  final DateTime createdAt;
  final List<String> consumedBy; // 已消化的 agent（不重複注入）
  final String? refutedBy; // 被誰推翻（錯誤情報不抹除，標記取代）

  const IntelEntry({
    required this.id,
    required this.fromAgent,
    required this.kind,
    required this.content,
    this.relatedSession,
    required this.createdAt,
    this.consumedBy = const [],
    this.refutedBy,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromAgent': fromAgent,
        'kind': kind.name,
        'content': content,
        'relatedSession': relatedSession,
        'createdAt': createdAt.toIso8601String(),
        'consumedBy': consumedBy,
        'refutedBy': refutedBy,
      };

  factory IntelEntry.fromJson(Map<String, dynamic> j) => IntelEntry(
        id: j['id'] as String,
        fromAgent: j['fromAgent'] as String,
        kind: IntelKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => IntelKind.lead,
        ),
        content: j['content'] as String,
        relatedSession: j['relatedSession'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        consumedBy:
            (j['consumedBy'] as List?)?.cast<String>().toList() ?? const [],
        refutedBy: j['refutedBy'] as String?,
      );
}

/// 共享情報池（singleton——TaskDispatcher 同模式）
class IntelPool extends ChangeNotifier {
  IntelPool._();
  static IntelPool? _instance;
  static IntelPool get instance => _instance ??= IntelPool._();

  @visibleForTesting
  static void resetForTest() => _instance = IntelPool._();

  File? _file;
  final List<IntelEntry> _entries = [];
  bool _loaded = false;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/farm.seemiwasabi.bridgeApp/intel_pool.jsonl');
    return _file!;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final lines = await f.readAsLines();
        _entries.clear();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            _entries.add(IntelEntry.fromJson(
                jsonDecode(line) as Map<String, dynamic>));
          } catch (_) {
            // 單行壞損不拖垮整池（append-only 檔的寬容讀）
          }
        }
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[IntelPool] 載入失敗（fail-open 空池起動）: $e');
      _loaded = true;
    }
  }

  /// 唯讀快照（refuted 的不進快照——被推翻的情報不算數）
  List<IntelEntry> get entries => List.unmodifiable(
      _entries.where((e) => e.refutedBy == null));

  /// 寫入情報（agent 主動 share 或收尾自動摘要）
  Future<IntelEntry> share({
    required String fromAgent,
    required IntelKind kind,
    required String content,
    String? relatedSession,
  }) async {
    await _ensureLoaded();
    final entry = IntelEntry(
      id: 'intel-${DateTime.now().millisecondsSinceEpoch}-'
          '${_entries.length}',
      fromAgent: fromAgent,
      kind: kind,
      content: content,
      relatedSession: relatedSession,
      createdAt: DateTime.now(),
    );
    _entries.add(entry);
    try {
      final f = await _ensureFile();
      await f.create(recursive: true);
      await f.writeAsString('${jsonEncode(entry.toJson())}\n',
          mode: FileMode.append);
    } catch (e) {
      debugPrint('[IntelPool] 落盤失敗（記憶體態保留）: $e');
    }
    notifyListeners();
    return entry;
  }

  /// 標記消化——consumedBy 加人；已消化者不再重複注入
  Future<void> markConsumed(String intelId, String agentId) async {
    await _ensureLoaded();
    final i = _entries.indexWhere((e) => e.id == intelId);
    if (i < 0) return;
    final e = _entries[i];
    if (e.consumedBy.contains(agentId)) return;
    _entries[i] = IntelEntry(
      id: e.id,
      fromAgent: e.fromAgent,
      kind: e.kind,
      content: e.content,
      relatedSession: e.relatedSession,
      createdAt: e.createdAt,
      consumedBy: [...e.consumedBy, agentId],
      refutedBy: e.refutedBy,
    );
    await _rewriteFile();
    notifyListeners();
  }

  /// 推翻情報——錯誤情報不抹除，refute 標記取代（主權鐵則：永不刪）
  Future<void> refute(String intelId, String byAgent) async {
    await _ensureLoaded();
    final i = _entries.indexWhere((e) => e.id == intelId);
    if (i < 0) return;
    final e = _entries[i];
    _entries[i] = IntelEntry(
      id: e.id,
      fromAgent: e.fromAgent,
      kind: e.kind,
      content: e.content,
      relatedSession: e.relatedSession,
      createdAt: e.createdAt,
      consumedBy: e.consumedBy,
      refutedBy: byAgent,
    );
    await _rewriteFile();
    notifyListeners();
  }

  /// 給某 agent 的「未消化」情報（派工注入/會議前注入用）
  /// ——自己寫的不算（自己的情報自己知道）
  Future<List<IntelEntry>> unconsumedBy(String agentId,
      {int limit = 20}) async {
    await _ensureLoaded();
    return entries
        .where((e) =>
            e.fromAgent != agentId && !e.consumedBy.contains(agentId))
        .take(limit)
        .toList();
  }

  Future<void> _rewriteFile() async {
    try {
      final f = await _ensureFile();
      await f.create(recursive: true);
      final buf = StringBuffer();
      for (final e in _entries) {
        buf.writeln(jsonEncode(e.toJson()));
      }
      await f.writeAsString(buf.toString());
    } catch (e) {
      debugPrint('[IntelPool] 重寫失敗（記憶體態保留）: $e');
    }
  }
}
