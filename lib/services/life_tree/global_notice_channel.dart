// [小葵 2026-09-21] 全域確認通道——Blue 拍板「確認類訊息走全域對話」
//
// 她的提問（夢境結論卡 escalate_to_user、propose 待確認）不塞彈窗、
// 不干擾工作對話——走全域對話（Quick Assistant 同源的獨立對話），
// 使用者可以反問、討論、忽略。
//
// 通道設計（三層，fail-open）：
// 1. UI 在場 → QuickAssistantManager 開面板＋推 assistant 訊息
// 2. UI 不在場（背景/無 context）→ MCP /global_notice HTTP 端點
//    （Hermes 小葵 cron / App 內部服務可打）
// 3. 都不可用 → 存 compass_meta 待認領（下次 UI 起來認領補推）

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../compass/compass_store.dart';

/// 全域確認通道
class GlobalNoticeChannel {
  GlobalNoticeChannel._();
  static final GlobalNoticeChannel instance = GlobalNoticeChannel._();

  /// 推播一則需要使用者確認的訊息（全域對話，非彈窗）。
  /// [kind] dream_escalate / dream_propose / generic
  /// 回傳 true=已送達 UI。
  bool push({
    required String title,
    required String body,
    String kind = 'generic',
    String? sourceId,
  }) {
    try {
      // 排程入佇列（compass_meta——UI 起來認領；MCP 端點即時推）
      final store = CompassStore.instance;
      final q = _loadQueue(store);
      q.add({
        'title': title,
        'body': body,
        'kind': kind,
        if (sourceId != null) 'source_id': sourceId,
        'at': DateTime.now().toIso8601String(),
        'delivered': false,
      });
      // 佇列上限 20（防無限長——舊的擠掉）
      while (q.length > 20) {
        q.removeAt(0);
      }
      store.setMeta('global_notice_queue', jsonEncode(q));
      debugPrint('[GlobalNotice] 已入全域對話佇列：$title');
      return true;
    } catch (e) {
      debugPrint('[GlobalNotice] 入佇列失敗（fail-open）: $e');
      return false;
    }
  }

  /// UI 認領：回傳未送達的訊息並標記 delivered
  List<Map<String, dynamic>> claimPending() {
    try {
      final store = CompassStore.instance;
      final q = _loadQueue(store);
      final pending =
          q.where((m) => m['delivered'] != true).toList();
      if (pending.isEmpty) return const [];
      for (final m in q) {
        if (m['delivered'] != true) m['delivered'] = true;
      }
      store.setMeta('global_notice_queue', jsonEncode(q));
      return pending;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _loadQueue(CompassStore store) {
    try {
      final raw = store.getMeta('global_notice_queue');
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
