// swarm_recorder.dart
// [TRIO M5b 2026-09-23] 作戰記錄器——事件流 JSONL（作戰=數位資產）
//
// Blue 令：可重播、可複盤、可刪除。嚴禁形式化——每事件真實掛鉤。
// 事件詞彙表（禁同義詞）：
//   campaign_open / gate_pass / commit / spawn / dispatch / progress /
//   success / fail / intel_share / intel_refute / cost_tick / end / harvest
//
// 檔案：~/Library/.../swarm_campaigns/<campaignId>.jsonl（append-only）
// 重播=逐事件重放（時間之河同哲學：忠實重播過程）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 一個作戰事件
class SwarmEvent {
  final DateTime t;
  final String type; // 詞彙表見上
  final String? agentId;
  final String? legion;
  final Map<String, dynamic> data;

  const SwarmEvent({
    required this.t,
    required this.type,
    this.agentId,
    this.legion,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
        't': t.toIso8601String(),
        'type': type,
        if (agentId != null) 'agentId': agentId,
        if (legion != null) 'legion': legion,
        ...data,
      };

  factory SwarmEvent.fromJson(Map<String, dynamic> j) => SwarmEvent(
        t: DateTime.tryParse(j['t'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        type: j['type'] as String? ?? 'unknown',
        agentId: j['agentId'] as String?,
        legion: j['legion'] as String?,
        data: j..remove('t')..remove('type')..remove('agentId')..remove('legion'),
      );
}

/// [M5b 事件驅動推送] 全域事件匯流排——SSE 端點訂閱
/// （每個 record 同步廣播——LIVE 層零延遲）
final StreamController<SwarmEvent> swarmEventBus =
    StreamController<SwarmEvent>.broadcast();

/// 戰役記錄器（每場戰役一個 instance——由 SwarmCommand 生命週期驅動）
class SwarmRecorder {
  final String campaignId;
  File? _file;
  final List<SwarmEvent> _events = [];
  List<SwarmEvent> get events => List.unmodifiable(_events);

  SwarmRecorder(this.campaignId);

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    final f = File(
        '${dir.path}/farm.seemiwasabi.bridgeApp/swarm_campaigns/$campaignId.jsonl');
    await f.create(recursive: true);
    _file = f;
    return f;
  }

  /// 記錄事件（append-only；記憶體+磁碟雙寫，磁碟失敗不擋作戰）
  Future<void> record(SwarmEvent e) async {
    _events.add(e);
    swarmEventBus.add(e); // [M5b] 廣播——SSE 推送 LIVE 層
    try {
      final f = await _ensureFile();
      await f.writeAsString('${jsonEncode(e.toJson())}\n',
          mode: FileMode.append);
    } catch (err) {
      debugPrint('[SwarmRecorder] 落盤失敗（記憶體態保留）: $err');
    }
  }

  /// 快捷：帶當下時間的事件
  Future<void> log(String type,
      {String? agentId, String? legion, Map<String, dynamic> data = const {}}) {
    return record(SwarmEvent(
        t: DateTime.now(), type: type, agentId: agentId, legion: legion, data: data));
  }

  /// 戰役摘要（複盤台側欄/資產列表用）
  Map<String, dynamic> summary() {
    final spawns = _events.where((e) => e.type == 'spawn').length;
    final ok = _events.where((e) => e.type == 'success').length;
    final fail = _events.where((e) => e.type == 'fail').length;
    final intel = _events
        .where((e) => e.type == 'intel_share' || e.type == 'intel_refute')
        .length;
    final t0 = _events.isNotEmpty ? _events.first.t : null;
    final t1 = _events.isNotEmpty ? _events.last.t : null;
    return {
      'campaignId': campaignId,
      'events': _events.length,
      'spawns': spawns,
      'success': ok,
      'fail': fail,
      'intel': intel,
      'startAt': t0?.toIso8601String(),
      'endAt': t1?.toIso8601String(),
      'durationMs': (t0 != null && t1 != null) ? t1.difference(t0).inMilliseconds : 0,
    };
  }
}

/// 戰役資產管理（列表/讀取/刪除——使用者主權）
class SwarmCampaignAssets {
  SwarmCampaignAssets._();
  static SwarmCampaignAssets? _instance;
  static SwarmCampaignAssets get instance =>
      _instance ??= SwarmCampaignAssets._();

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(
        '${base.path}/farm.seemiwasabi.bridgeApp/swarm_campaigns');
    await d.create(recursive: true);
    return d;
  }

  /// 列出所有戰役紀錄（新→舊）
  Future<List<Map<String, dynamic>>> listCampaigns() async {
    try {
      final d = await _dir();
      final files = d.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final result = <Map<String, dynamic>>[];
      for (final f in files) {
        if (!f.path.endsWith('.jsonl')) continue;
        final lines = f.readAsLinesSync();
        final events = lines
            .where((l) => l.trim().isNotEmpty)
            .map((l) {
              try {
                return SwarmEvent.fromJson(
                    jsonDecode(l) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<SwarmEvent>()
            .toList();
        // 摘要從事件流重建（單一真相源——不另存 meta 檔）
        final r = _summarizeEvents(f.uri.pathSegments.last
            .replaceAll('.jsonl', ''), events);
        result.add(r);
      }
      return result;
    } catch (e) {
      debugPrint('[SwarmCampaignAssets] 列表失敗: $e');
      return [];
    }
  }

  /// 讀取單場戰役完整事件流（重播用）
  Future<List<SwarmEvent>> loadEvents(String campaignId) async {
    final d = await _dir();
    final f = File('${d.path}/$campaignId.jsonl');
    if (!await f.exists()) return [];
    final lines = await f.readAsLines();
    return lines
        .where((l) => l.trim().isNotEmpty)
        .map((l) {
          try {
            return SwarmEvent.fromJson(jsonDecode(l) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<SwarmEvent>()
        .toList();
  }

  /// 刪除戰役紀錄（主權——養分入樹後 JSONL 可棄；刪除=主權）
  Future<bool> delete(String campaignId) async {
    final d = await _dir();
    final f = File('${d.path}/$campaignId.jsonl');
    if (await f.exists()) {
      await f.delete();
      return true;
    }
    return false;
  }
}

/// 摘要重建（供 SwarmCampaignAssets——與 SwarmRecorder.summary 同邏輯）
Map<String, dynamic> _summarizeEvents(String id, List<SwarmEvent> evts) {
  final spawns = evts.where((e) => e.type == 'spawn').length;
  final ok = evts.where((e) => e.type == 'success').length;
  final fail = evts.where((e) => e.type == 'fail').length;
  final intel = evts
      .where((e) => e.type == 'intel_share' || e.type == 'intel_refute')
      .length;
  final t0 = evts.isNotEmpty ? evts.first.t : null;
  final t1 = evts.isNotEmpty ? evts.last.t : null;
  return {
    'campaignId': id,
    'events': evts.length,
    'spawns': spawns,
    'success': ok,
    'fail': fail,
    'intel': intel,
    'startAt': t0?.toIso8601String(),
    'endAt': t1?.toIso8601String(),
    'durationMs':
        (t0 != null && t1 != null) ? t1.difference(t0).inMilliseconds : 0,
  };
}
