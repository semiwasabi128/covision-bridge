// brand_ladder_router.dart
//
// [小葵 2026-09-20 品牌階梯路由] GPT-6 任務從 4o 起步逐級升到 astra
//
// 緣起：9/19 gpt-6-astra 燒 $35 事件。問題不在於「用了旗艦」，而在於
// 「什麼都直接打旗艦」——簡單的 grep、讀檔、格式化翻譯也跑 astra，
// 每輪 ~30K tokens 重送，cache 命中率趨近 0。
//
// Blue 拍板的策略（09-20）：模型家族內部建階梯。
//   GPT-6 → 4o-mini（階梯 0）→ 4o（階梯 1）→ 5-mini（階梯 2）→ 5（階梯 3）→ astra（階梯 4）
//
// 工作原理（不限制 agent 的前提下）：
//   1. **預設 provider 模式**（使用者沒鎖特定 model）：
//      每輪根據「上輪表現信號」判斷是否升級——
//      信號 = 失敗/不確定/用盡工具 retry → 升一階。
//      默認從階梯 0（最便宜）起步，旗艦留給真正需要它的時刻。
//   2. **鎖定模型模式**（使用者挑了 astra）：
//      不動——Blue 拍板的事。鎖定 = 鎖定，路由層不介入。
//   3. **困難模式自啟**：信號強度（連續 2 次失敗）直接拉到階梯 4。
//
// 設計原則：
//   - 不限制任何調用——階梯只決定「主腦候選」，使用者隨時可手動改。
//   - 寫入 ledger（[小葵 計程車表]）：每次升級動作落地，方便 Blue 看見。
//   - fail-open：信號計算失敗 → 用階梯 0，絕不偷偷用旗艦。

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 一個模型家族的階梯定義。
/// 由低（cheap、準確率夠）到高（旗艦、cost 驚人）。
class BrandLadder {
  final String brand; // 'openai' / 'glm' / 'claude' / ...
  final List<String> rungs; // [cheap, ..., flagship]

  const BrandLadder({required this.brand, required this.rungs});

  /// 從 rungs 列表升一階（已是最高 → 返回自身）
  String? stepUp(String current) {
    final i = rungs.indexWhere(
      (m) => _fuzzyMatch(m, current),
    );
    if (i < 0 || i >= rungs.length - 1) return null;
    return rungs[i + 1];
  }

  /// 取階梯中最低階（便宜款）
  String get cheapest => rungs.first;

  /// 取階梯中最高階（旗艦）
  String get flagship => rungs.last;

  static bool _fuzzyMatch(String ladderEntry, String candidate) {
    final l = ladderEntry.toLowerCase();
    final c = candidate.toLowerCase();
    return c.startsWith(l) || l.startsWith(c.split('-').first);
  }
}

/// 預設品牌階梯表——把 Tier 概念換成「同品牌內升級序列」
const Map<String, BrandLadder> _defaultLadders = {
  'openai': BrandLadder(
    brand: 'openai',
    rungs: [
      'gpt-4o-mini', // 階 0 — 便宜、routine
      'gpt-4o', // 階 1 — 老牌可靠
      'gpt-5-mini', // 階 2 — reasoning 入門
      'gpt-5', // 階 3 — 強 reasoning
      'gpt-6-astra', // 階 4 — 旗艦，殺手鐧
    ],
  ),
  'glm': BrandLadder(
    brand: 'glm',
    rungs: [
      'glm-4.5', // 階 0
      'glm-5', // 階 1
      'glm-5.2', // 階 2
      'glm-5.3', // 階 3
    ],
  ),
  'claude': BrandLadder(
    brand: 'claude',
    rungs: [
      'claude-haiku-4-5', // 階 0
      'claude-sonnet-4-6', // 階 1
      'claude-opus-4-7', // 階 2
    ],
  ),
  'gemini': BrandLadder(
    brand: 'gemini',
    rungs: [
      'gemini-2.5-flash', // 階 0
      'gemini-3.5-flash', // 階 1
      'gemini-3.5-pro', // 階 2
    ],
  ),
};

/// 「任務信號」：上輪表現的客觀指標
///
/// 不是猜測，是真正可觀察的事實——
///   - 失敗次數（API error / 工具呼叫失敗）
///   - retry 深度（曾經重試幾次才成功）
///   - 輸出長度異常（太短=可能沒答好、太長=可能亂跑）
class TaskSignal {
  final bool lastCallFailed;
  final String? lastError;
  final int consecutiveFailures;
  final int? retryDepth;
  final int? lastOutputChars;

  const TaskSignal({
    this.lastCallFailed = false,
    this.lastError,
    this.consecutiveFailures = 0,
    this.retryDepth,
    this.lastOutputChars,
  });

  bool get shouldEscalate {
    // 連續 2 次失敗 → 升級
    // 5 次失敗 → 直接旗艦
    return consecutiveFailures >= 2;
  }

  bool get shouldJumpToFlagship {
    return consecutiveFailures >= 5;
  }
}

/// 階梯事件——給 UI 訂閱（藍 09-20：狀態文字要彈出）
enum BrandLadderEventKind {
  /// 起點（cheap）被選中（對話開始時）
  init,
  /// 升一階
  stepUp,
  /// 直衝旗艦（連敗 ≥5）
  jumpFlagship,
  /// 使用者鎖了 model，階梯不動
  userLocked,
  /// 沒有對應 provider 的階梯定義
  noLadder,
}

/// 階梯事件載體——人類可讀訊息 + 結構化資料
class BrandLadderEvent {
  final BrandLadderEventKind kind;
  final String provider;
  final String? fromModel;
  final String? toModel;
  final int? consecutiveFailures;
  final String? reason;

  const BrandLadderEvent({
    required this.kind,
    required this.provider,
    this.fromModel,
    this.toModel,
    this.consecutiveFailures,
    this.reason,
  });

  /// 人類可讀短訊——給狀態列顯示
  String get displayMessage {
    switch (kind) {
      case BrandLadderEventKind.init:
        return '📈 階梯起點：${toModel ?? "?"}（最便宜款）';
      case BrandLadderEventKind.stepUp:
        return '📈 連敗 ${consecutiveFailures ?? "?"} 次 → 升一階：'
            '${fromModel ?? "?"} → ${toModel ?? "?"}';
      case BrandLadderEventKind.jumpFlagship:
        return '📈 連敗 ${consecutiveFailures ?? "?"} 次（嚴重）→ 直衝旗艦：'
            '${toModel ?? "?"}';
      case BrandLadderEventKind.userLocked:
        return '🔒 你鎖定了 ${toModel ?? "?"}——階梯不動';
      case BrandLadderEventKind.noLadder:
        return '⚠️ $provider 沒有階梯定義，沿用原 model';
    }
  }
}

/// 品牌階梯路由器
class BrandLadderRouter {
  static final BrandLadderRouter instance = BrandLadderRouter._();
  BrandLadderRouter._();

  /// 每次 agent loop 輪計算後，把這次的 model 鎖進去。
  /// 下輪升級判斷從這裡讀取（而不是從使用者 prefs 重讀，避免每次都重設）。
  String? _activeModel;
  String? get activeModel => _activeModel;

  /// [藍 09-20] 狀態廣播——UI 訂閱這個 stream，階梯動作會即時彈出
  /// （對話視窗、計程車表延伸…等等都可訂閱）
  final StreamController<BrandLadderEvent> _eventController =
      StreamController<BrandLadderEvent>.broadcast();
  Stream<BrandLadderEvent> get events => _eventController.stream;

  /// [小葵 09-20] 取最近 N 個事件——UI 沒訂閱時也能查（例如初次進入對話）
  final List<BrandLadderEvent> _recent = [];
  List<BrandLadderEvent> recentEvents({int limit = 30}) {
    if (_recent.length <= limit) return List.unmodifiable(_recent);
    return List.unmodifiable(_recent.sublist(_recent.length - limit));
  }

  void _emit(BrandLadderEvent e) {
    _recent.add(e);
    if (_recent.length > 100) {
      _recent.removeRange(0, _recent.length - 100);
    }
    _eventController.add(e);
  }

  /// 重置到階梯起點（cheap）——對話開始、user 換新對話時呼叫
  void reset(String provider) {
    final ladder = _defaultLadders[provider];
    _activeModel = ladder?.cheapest;
    debugPrint('[BrandLadder] reset → ${_activeModel ?? "(no ladder for $provider)"}');
    if (_activeModel != null) {
      _emit(BrandLadderEvent(
        kind: BrandLadderEventKind.init,
        provider: provider,
        toModel: _activeModel,
        reason: 'reset / 對話開始',
      ));
    }
  }

  /// 註冊單輪結果，更新下一輪的候選模型
  ///
  /// [resolvedProvider] — 當前走的 provider（不是 model）
  /// [userLockedModel] — 使用者手動鎖定的 model（!= null 時不升級）
  /// [signal] — 本輪信號
  ///
  /// 回傳：下一輪要用的 model。null = 沿用（呼叫端繼續用現在的）。
  String? advance({
    required String resolvedProvider,
    String? userLockedModel,
    required String currentModel,
    required TaskSignal signal,
  }) {
    // 規則 1：使用者鎖了 → 不動
    if (userLockedModel != null && userLockedModel.trim().isNotEmpty) {
      _emit(BrandLadderEvent(
        kind: BrandLadderEventKind.userLocked,
        provider: resolvedProvider,
        toModel: userLockedModel.trim(),
        reason: 'user_locked → 階梯旁觀',
      ));
      return null;
    }

    final ladder = _defaultLadders[resolvedProvider];
    if (ladder == null) {
      debugPrint('[BrandLadder] no ladder for provider=$resolvedProvider');
      _emit(BrandLadderEvent(
        kind: BrandLadderEventKind.noLadder,
        provider: resolvedProvider,
        reason: '沒有階梯定義 → 沿用',
      ));
      return null;
    }

    final failed = signal.lastCallFailed;
    final consec = signal.consecutiveFailures;

    if (signal.shouldJumpToFlagship) {
      debugPrint(
        '[BrandLadder] $currentModel 連敗 $consec 次 → 旗艦 ${ladder.flagship}',
      );
      _activeModel = ladder.flagship;
      _emit(BrandLadderEvent(
        kind: BrandLadderEventKind.jumpFlagship,
        provider: resolvedProvider,
        fromModel: currentModel,
        toModel: _activeModel,
        consecutiveFailures: consec,
        reason: '嚴重連敗 → 旗艦',
      ));
      return _activeModel;
    }

    if (failed && consec >= 1) {
      final next = ladder.stepUp(currentModel);
      if (next != null && next != currentModel) {
        debugPrint('[BrandLadder] $currentModel 升一階 → $next');
        _activeModel = next;
        _emit(BrandLadderEvent(
          kind: BrandLadderEventKind.stepUp,
          provider: resolvedProvider,
          fromModel: currentModel,
          toModel: _activeModel,
          consecutiveFailures: consec,
          reason: '連敗升一階',
        ));
        return _activeModel;
      }
    }

    // 一切順利 → 不升（沿用）
    return null;
  }

  /// 強制升一階（供 UI「升級模型」按鈕或 debug 用）
  String? forceStepUp(String provider, String currentModel) {
    final ladder = _defaultLadders[provider];
    if (ladder == null) return null;
    final next = ladder.stepUp(currentModel);
    if (next != null) {
      _activeModel = next;
      _emit(BrandLadderEvent(
        kind: BrandLadderEventKind.stepUp,
        provider: provider,
        fromModel: currentModel,
        toModel: _activeModel,
        reason: '手動升階',
      ));
    }
    return next;
  }

  /// 清理（測試用）
  void dispose() {
    _eventController.close();
  }
}
