// compass_rule_cache.dart
// 規則快取 — 渲染端的唯一入口。
//
// 治理：規則參數唯一權威 = CompassStore；本快取只讀。
// 收到 rulesChanged 事件 → 重讀 → 呼叫端 repaint（CustomPainter 參數化）。
// 快取失效即時（事件驅動），絕不快取過期值——「取代不累積」。
//
// [小葵 2026-09-07] 2D 圖譜退役——BrainEdgeRules（simGate/vein/xref
// 邊規則快照）隨之移除。galaxy（3D）規則改由 CompassGalaxyBridge
// 匯出 galaxy_rules.json 給 WebView，不經此快取。

import 'dart:async';

import 'compass_store.dart';

/// 全域規則快取（訂閱 store 事件自動刷新）
class CompassRuleCache {
  CompassRuleCache._();
  static final CompassRuleCache instance = CompassRuleCache._();

  StreamSubscription? _sub;
  final _changes = StreamController<void>.broadcast();

  /// 規則變更通知（渲染端訂閱後 repaint）
  Stream<void> get changes => _changes.stream;

  /// 掛上 store（App 啟動時呼叫一次；測試可傳 temp store）
  void attach(CompassStore store) {
    _sub?.cancel();
    _sub = store.events.listen((e) {
      if (e.type == 'rulesChanged') {
        _changes.add(null);
      }
    });
  }

  void detach() {
    _sub?.cancel();
    _sub = null;
  }
}
