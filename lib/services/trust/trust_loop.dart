// trust_loop.dart
// [刀 6 K6.4 2026-09-08 Blue loop 鐵則] 信任 loop 引擎——看得到的循環。
//
// 鐵則：「做事→回報→檢討→升級→再做事，使用者都要看得到」
//
// 引擎掛在 BudgetLedger 上：
//   做事   = ledger.record()（付費動作發生）
//   回報   = LoopEvent(kind: report)——「剛剛做了 X」即時推送 UI
//   檢討   = settle 時自動評：成功→稱讚自己；失敗→記教訓（推 UI）
//   升級   = 信任分數跨級（新手→成長中→中信任→高信任）→ 慶祝事件＋
//            （系統面）羅盤記一筆 trust tier 變更
//
// 使用者看到的三個介面（都吃同一個事件流）：
//   1. 對話頁底部跑馬燈（K6.4）
//   2. TrustMeterCard（K6.1——訂閱刷新）
//   3. 托盤選單（K6.3——摘要）
//
// 重要的事情記記憶／系統的事情記羅盤：
//   - 教訓（失敗原因）→ BrainContainer 記憶（本刀先進事件流；記憶寫入列
//     刀 6 後續——需走既有 memory pipeline，不開旁門）
//   - tier 升級 → 羅盤規則（search.singleEngine 同款 seedRule 模式）

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/budget_ledger.dart';
import 'package:bridge_app/services/trust/trust_score.dart';

/// loop 事件——UI 層唯一的消費單位
class TrustLoopEvent {
  final String kind; // report / review / upgrade / downgrade
  final String message; // 人話（直接顯示）
  final DateTime at;

  const TrustLoopEvent({
    required this.kind,
    required this.message,
    required this.at,
  });
}

/// 信任 loop 引擎——單例
class TrustLoop {
  TrustLoop._();
  static final TrustLoop instance = TrustLoop._();

  final _events = <TrustLoopEvent>[];
  final _controller = StreamController<TrustLoopEvent>.broadcast();
  Stream<TrustLoopEvent> get stream => _controller.stream;

  String? _lastTier; // 升級偵測（跨級比較）
  bool _wired = false;

  /// 掛上 BudgetLedger（冪等——App 啟動時呼叫一次）
  void wire() {
    if (_wired) return;
    _wired = true;
    BudgetLedger.instance.addListener(_onLedgerChanged);
  }

  void _onLedgerChanged() {
    _review(); // fire-and-forget 檢討（不 await——UI 不等它）
  }

  /// 檢討：讀最新狀態 → 生成事件（回報/檢討/升級）
  Future<void> _review() async {
    try {
      final stats = await BudgetLedger.instance.todayStats();
      final dupes = await BudgetLedger.instance.duplicatePromptsToday();
      final inputs = TrustScoreInputs(
        total: stats.total,
        ok: stats.ok,
        failed: stats.failed,
        duplicates: dupes,
      );
      final score = computeTrustScore(inputs);

      // 升級/降級偵測（tier 跨級才有事件——不 spam）
      if (_lastTier != null && _lastTier != score.label) {
        final up = _tierRank(score.label) > _tierRank(_lastTier!);
        _emit(TrustLoopEvent(
          kind: up ? 'upgrade' : 'downgrade',
          message: up
              ? '🏅 信任升級：$_lastTier → ${score.label}（成功率 ${(inputs.successRate * 100).round()}%）'
              : '📉 信任回落：$_lastTier → ${score.label}——我會更謹慎',
          at: DateTime.now(),
        ));
        // [系統的事情記羅盤] tier 變更記羅盤（走 CompassStore seedRule 同款
        // append-only 模式——本刀先 log，寫入羅盤與 K6.5 一起接）
        debugPrint('[TrustLoop] tier 變更：$_lastTier → ${score.label}');
      }
      _lastTier = score.label;
    } catch (e) {
      debugPrint('[TrustLoop] 檢討失敗（fail-open）: $e');
    }
  }

  /// 外部推送回報事件（例如 PaidActionGate 攔截時）
  void report(String message) {
    _emit(TrustLoopEvent(
      kind: 'report',
      message: message,
      at: DateTime.now(),
    ));
  }

  void _emit(TrustLoopEvent e) {
    _events.add(e);
    if (_events.length > 100) _events.removeAt(0); // 環形
    _controller.add(e);
    debugPrint('[TrustLoop:${e.kind}] ${e.message}');
  }

  /// 事件歷史（UI 回放用）
  List<TrustLoopEvent> get history => List.unmodifiable(_events);

  int _tierRank(String label) => switch (label) {
        '高信任' => 3,
        '中信任' => 2,
        '成長中' => 1,
        _ => 0,
      };
}
