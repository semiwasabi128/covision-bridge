// causal_fork_service.dart
// [因果引擎 L4 2026-09-12] 狀態分叉——可執行的反事實。
//
// Pearl 第 3 階（counterfactual）：LLM 最弱的一階。
// 設計稿 §5：快照 → fork A/B → 各自干預 → diff = 可執行的反事實。
//
// 誠實邊界（數學）：
// - 可分叉域：App 內部狀態（畫布 JSON）——可序列化、可重演
// - 不可分叉域：外部世界——凍結為快照值並標記「邊界外」
// - 分叉只是模擬：diff 結果標等級 3（反事實模擬），永不如實測硬
//
// 回收：fork 結果寫入 causal_ledger（companion_id='causal_fork'），
// 畫布本身快照後即還原——不留殭屍（記憶體治理前車之鑑）。

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'causal_ledger_service.dart';

/// 一次狀態分叉的完整記錄
@immutable
class ForkDiff {
  final String forkId;
  final DateTime at;
  final String intervention; // A 線執行的干預（do 運算子）
  final String baselineDescription; // B 線（對照）描述
  final Map<String, dynamic> snapshotBefore; // 快照（分叉點的世界）
  final List<String> diffLines; // A/B 差異
  final bool diverged; // 是否產生差異

  const ForkDiff({
    required this.forkId,
    required this.at,
    required this.intervention,
    required this.baselineDescription,
    required this.snapshotBefore,
    required this.diffLines,
    required this.diverged,
  });

  String get report {
    final buf = StringBuffer();
    buf.writeln('反事實分叉報告（fork $forkId｜${at.month}/${at.day}）');
    buf.writeln('分叉點快照：${snapshotBefore.length} 個頂層欄位');
    buf.writeln('A 線（干預）：$intervention');
    buf.writeln('B 線（對照）：$baselineDescription');
    buf.writeln(diverged
        ? '差異（A−B）：\n${diffLines.map((l) => '  - $l').join('\n')}'
        : '差異：無（干預未產生可觀測變化）');
    buf.writeln('證據等級：3 反事實模擬——分叉重演的推論，非實測');
    return buf.toString();
  }
}

/// 分叉執行的結果（A 線干預執行後的世界 vs B 線對照）
@immutable
class ForkOutcome {
  final Map<String, dynamic> worldAfterA; // A 線干預後的世界
  final Map<String, dynamic> worldAfterB; // B 線（快照原樣）
  const ForkOutcome({required this.worldAfterA, required this.worldAfterB});
}

class CausalForkService {
  CausalForkService._();
  static final CausalForkService instance = CausalForkService._();

  int _forkCounter = 0;
  final _activeForks = <String, ForkDiff>{};

  /// 比較兩個世界狀態的深層差異。
  /// 世界 = {'nodes': [...], 'connections': [...], ...}
  static ForkOutcome diffWorlds(
    Map<String, dynamic> before,
    Map<String, dynamic> afterA,
  ) {
    return ForkOutcome(worldAfterA: afterA, worldAfterB: before);
  }

  /// [L4 核心] 執行一次狀態分叉：
  /// 1. 快照當前世界（呼叫者供給 getState）
  /// 2. A 線：執行干預（呼叫者供給 intervene）→ 得到世界 A
  /// 3. B 線：快照原樣（= 不干預的平行世界）
  /// 4. diff(A, B) → 差異即干預的因果效應（在此模擬域內）
  /// 5. 還原世界（呼叫者供給 restore）——不留殭屍
  /// 6. 記帳（causal_ledger，等級 3 反事實模擬）
  Future<ForkDiff> run({
    required String intervention,
    required String baselineDescription,
    required Future<Map<String, dynamic>> Function() getState,
    required Future<Map<String, dynamic>> Function() intervene,
    required Future<void> Function(Map<String, dynamic> world) restore,
  }) async {
    final forkId = 'fork_${DateTime.now().millisecondsSinceEpoch}_${_forkCounter++}';

    // 1. 快照
    final before = await getState();

    // 2. A 線：干預
    final worldA = await intervene();

    // 3-4. diff：A 世界 vs 快照（B 線 = 不干預的世界）
    final diffs = _deepDiff(before, worldA);

    // 5. 還原
    await restore(before);

    // 6. 記帳（等級 3）
    final fd = ForkDiff(
      forkId: forkId,
      at: DateTime.now(),
      intervention: intervention,
      baselineDescription: baselineDescription,
      snapshotBefore: before,
      diffLines: diffs,
      diverged: diffs.isNotEmpty,
    );
    _activeForks[forkId] = fd;
    try {
      CausalLedger.instance.record(CausalEntry(
        toolName: 'causal_fork',
        intervention: intervention,
        contextDigest: 'L4 狀態分叉：$baselineDescription',
        observedOutcome: '[${fd.diverged ? '分叉差異' : '無差異'}] ${diffs.take(3).join('; ')}',
        success: true,
        at: DateTime.now(),
      ));
    } catch (_) {} // fail-open：分叉成功但不因記帳失敗而毀

    debugPrint('[CausalFork] $forkId 完成：${diffs.length} 項差異');
    return fd;
  }

  /// 深層 diff——找出 A 世界相對 B 世界的可觀測變化
  static List<String> _deepDiff(Map<String, dynamic> b, Map<String, dynamic> a) {
    final out = <String>[];
    final keys = {...b.keys, ...a.keys};
    for (final k in keys) {
      final bv = jsonEncode(b[k]);
      final av = jsonEncode(a[k]);
      if (bv != av) {
        // 節點層細化：找出新增/移除的節點 id
        if (k == 'nodes' && b[k] is List && a[k] is List) {
          final bIds = (b[k] as List).map((n) => (n as Map)['id']).toSet();
          final aIds = (a[k] as List).map((n) => (n as Map)['id']).toSet();
          final added = aIds.difference(bIds);
          final removed = bIds.difference(aIds);
          if (added.isNotEmpty) out.add('nodes +${added.length}（${added.take(3).join(',')}）');
          if (removed.isNotEmpty) out.add('nodes -${removed.length}（${removed.take(3).join(',')}）');
          // 內容變更的節點
          final changed = (a[k] as List).where((n) {
            final id = (n as Map)['id'];
            final old = (b[k] as List).where((m) => (m as Map)['id'] == id).toList();
            return old.isNotEmpty && jsonEncode(old.first) != jsonEncode(n);
          }).length;
          if (changed > 0) out.add('nodes ~$changed 內容變更');
        } else if (bv != av) {
          out.add('$k: ${_short(bv)} → ${_short(av)}');
        }
      }
    }
    return out;
  }

  static String _short(String s, [int n = 40]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
