// resource_lease.dart
// [TRIO M1 2026-09-22] 資源租約——三條線不撞車的咽喉點。
//
// 撞車點 C2（AGENT_TRIO_COLLAB_SPEC §二）：獨佔資源（flutter build、
// git 寫入、共享檔案）兩條線同時搶 → 互踩。我們親身遇過
// "Waiting for another flutter command to release the startup lock"。
//
// 語意：
//   acquire(resource, holder) —— 取得租約；被佔則排隊等待（FIFO），
//                                不並行、不搶奪、不靜默失敗
//   release(resource, holder) —— 歸還（holder 不符則忽略，防誤釋）
//   tryAcquire —— 立即回傳（查詢式，不排隊）
//
// 防呆：
//   - holder 是 sessionId/agentId——帳可查（誰佔著、佔多久）
//   - acquire 可帶 timeout——逾時丟 LeaseTimeoutException（誠實失敗，
//     不無限等）
//   - release 別人持有的租約 → 忽略並 debugPrint（防 A 釋放 B 的鎖）
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

class LeaseTimeoutException implements Exception {
  final String resource;
  final String holder;
  LeaseTimeoutException(this.resource, this.holder);
  @override
  String toString() =>
      'LeaseTimeoutException: $holder 等待租約 $resource 逾時';
}

class _Waiter {
  final String holder;
  final Completer<void> completer;
  _Waiter(this.holder) : completer = Completer<void>();
}

/// 資源租約表（singleton——TaskDispatcher 同模式）
class ResourceLease {
  ResourceLease._();
  static ResourceLease? _instance;
  static ResourceLease get instance => _instance ??= ResourceLease._();

  @visibleForTesting
  static void resetForTest() => _instance = ResourceLease._();

  /// resource → 現任持有者
  final Map<String, String> _holders = {};

  /// resource → 排隊者（FIFO）
  final Map<String, List<_Waiter>> _queues = {};

  /// resource → 取得時間（帳可查：佔多久）
  final Map<String, DateTime> _acquiredAt = {};

  /// 現任持有者（唯讀；無人持有回 null）
  String? holderOf(String resource) => _holders[resource];

  /// 取得時間（稽查用）
  DateTime? acquiredAt(String resource) => _acquiredAt[resource];

  /// 排隊深度（測試/監控用）
  int queueLength(String resource) =>
      _queues[resource]?.length ?? 0;

  /// 查詢式取得——不排隊，立即回傳
  bool tryAcquire(String resource, String holder) {
    if (_holders.containsKey(resource)) return false;
    _grant(resource, holder);
    return true;
  }

  /// 排隊式取得——被佔則等待；FIFO 公平；逾時誠實失敗
  Future<void> acquire(
    String resource,
    String holder, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (!_holders.containsKey(resource)) {
      _grant(resource, holder);
      return;
    }
    final waiter = _Waiter(holder);
    _queues.putIfAbsent(resource, () => []).add(waiter);
    debugPrint('[ResourceLease] $holder 排隊等待 $resource '
        '（現任 ${_holders[resource]}，第 ${_queues[resource]!.length} 位）');
    try {
      await waiter.completer.future.timeout(timeout);
    } on TimeoutException {
      // 逾時——把自己從佇列移除，誠實失敗
      _queues[resource]?.removeWhere((w) => identical(w, waiter));
      throw LeaseTimeoutException(resource, holder);
    }
  }

  void _grant(String resource, String holder) {
    _holders[resource] = holder;
    _acquiredAt[resource] = DateTime.now();
  }

  /// 歸還——只有現任持有者能釋放（防誤釋）；釋放後 FIFO 交接給下一位
  void release(String resource, String holder) {
    if (_holders[resource] != holder) {
      debugPrint('[ResourceLease] $holder 試圖釋放非自己持有的 '
          '$resource（現任 ${_holders[resource]}）——忽略');
      return;
    }
    _holders.remove(resource);
    _acquiredAt.remove(resource);
    final queue = _queues[resource];
    if (queue != null && queue.isNotEmpty) {
      final next = queue.removeAt(0);
      _grant(resource, next.holder);
      debugPrint('[ResourceLease] $resource 交接給 ${next.holder}');
      next.completer.complete();
    }
  }

  /// 持有者強制棄租（任務取消/失敗時的清場——dispatcher 呼叫）
  void releaseAllOf(String holder) {
    final owned = _holders.entries
        .where((e) => e.value == holder)
        .map((e) => e.key)
        .toList();
    for (final r in owned) {
      release(r, holder);
    }
    // 佇列裡的死排隊者也一併移除（holder 已死，等了也不會來）
    for (final q in _queues.values) {
      q.removeWhere((w) => w.holder == holder);
    }
  }
}
