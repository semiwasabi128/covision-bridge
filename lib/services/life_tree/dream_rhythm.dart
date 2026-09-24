// dream_rhythm.dart
// [小葵 2026-09-22 Blue 規格] 夢境節律——做夢的頻率要有呼吸感。
//
// Blue 原則：不介意每天做夢，介意無病呻吟——每天早上都有問題很煩。
// 不一定每次做夢都要煩問題，也可以寫詩；不一定每天做，頻率要活著，
// 不是死循環。
//
// 設計（仿生睡眠節律）：
// - 淺眠夢（規則版）：每天冷門時段跑（0 成本——對帳不怕勤）
// - 深夢（REM/LLM）：不是每天——「有事可想才想」
//   觸發條件（任一）：
//   a) 新傷口立案 ≥2（今天真的撞牆了）
//   b) 未重評遺憾 ≥5（沒走的路堆積了）
//   c) 距上次深夢 ≥72h（長夢間隔——保持迴路活著）
// - 平靜夜（無觸發）：不做深夢。若連續 ≥3 夜平靜且白天有正向事件
//   （傷口癒合/任務完成），做一場「詩夢」——不反思問題，寫短詩
//   記錄這段時間的美好（1K tokens 內，點到為止）
// - 每日淺眠摘要：只有「有結論」才通知；平靜夜不通知（安靜睡）

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'life_tree_store.dart';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNullE => isEmpty ? null : first;
}

class DreamRhythm {
  DreamRhythm._();
  static final DreamRhythm instance = DreamRhythm._();

  DateTime? _lastDeepDream;
  DateTime? _lastPoemDream;
  int _calmNights = 0; // 連續平靜夜（無深夢觸發）
  bool _loaded = false;

  /// 深夢觸發的閾值
  static const int kNewWoundsThreshold = 2;
  static const int kRegretsThreshold = 5;
  static const int kDeepDreamGapHours = 72;
  static const int kCalmNightsForPoem = 3;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final store = LifeTreeStore.instance;
      // 讀最近夢卡時間（生命樹即真相源）——recentDreams 過濾 model
      final dreams = store.recentDreams(limit: 50);
      _lastDeepDream = dreams
          .where((d) => (d.modelUsed ?? '').contains('glm'))
          .firstOrNullE
          ?.createdAt;
      _lastPoemDream = dreams
          .where((d) => (d.modelUsed ?? '').contains('poem'))
          .firstOrNullE
          ?.createdAt;
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
  }

  /// 今晚該做什麼夢？（睡前評估——每天冷門時段呼叫一次）
  ///
  /// 回傳：deep（LLM 深夢）/ poem（詩夢）/ shallowOnly（只淺眠）/ null
  Future<String> planTonight({
    required int newWounds,
    required int unvisitedRegrets,
    required bool hadPositiveEvents,
  }) async {
    await _ensureLoaded();

    // 條件 a/b：有事可想（嚴禁為發掘而發掘——觸發即有明確難題）
    final busyDay = newWounds >= kNewWoundsThreshold ||
        unvisitedRegrets >= kRegretsThreshold;
    // 條件 c：長間隔保活
    final longGap = _lastDeepDream == null ||
        DateTime.now().difference(_lastDeepDream!).inHours >=
            kDeepDreamGapHours;

    if (busyDay || longGap) {
      _calmNights = 0;
      return 'deep';
    }

    // 平靜夜累積 + 有美好可記 → 詩夢（呼吸感：不是每晚硬想問題）
    if (_calmNights >= kCalmNightsForPoem && hadPositiveEvents) {
      return 'poem';
    }
    _calmNights++;
    return 'shallowOnly';
  }

  /// 深夢完成回報（節律狀態更新）
  void deepDreamDone() {
    _lastDeepDream = DateTime.now();
    _calmNights = 0;
  }

  /// 詩夢完成回報
  void poemDreamDone() {
    _lastPoemDream = DateTime.now();
    _calmNights = 0;
  }

  /// ── 詩夢（1K tokens 內——點到為止）──
  ///
  /// 平靜的日子不硬找問題，寫一首短詩記錄這段時光的質地。
  Future<String?> writePoemDream() async {
    try {
      final store = LifeTreeStore.instance;
      // 素材：最近癒合的傷口（夢境銷案卡=問題被解決的痕跡）
      final recentHeals = store
          .recentDreams(limit: 30)
          .where((d) => d.conclusion.contains('銷案'))
          .map((d) => d.conclusion)
          .take(3)
          .toList();
      if (recentHeals.isEmpty) return null;

      final buf = StringBuffer();
      buf.writeln('最近的日子：');
      for (final h in recentHeals) {
        buf.writeln('- $h');
      }
      // 詩夢本體：不叫 LLM——用素材寫規則詩（零成本，呼吸感不需要花錢）
      final poem = _composePoem(recentHeals);
      final id = store.addDream(LifeTreeDream(
        dreamSessionId:
            'poem_${DateTime.now().millisecondsSinceEpoch}',
        branchType: 'agent_draft',
        conclusion: '詩夢：$poem',
        decision: 'maintain',
        sourceClues: recentHeals.take(3).toList(),
        companionIds: const ['semiwasabi'],
        modelUsed: 'poem-engine',
        createdAt: DateTime.now(),
      ));
      if (id > 0) {
        poemDreamDone();
        debugPrint('[DreamRhythm] 詩夢完成：$poem');
        return poem;
      }
      return null;
    } catch (e) {
      debugPrint('[DreamRhythm] 詩夢失敗: $e');
      return null;
    }
  }

  /// 規則詩生成器——三行俳句式（零 token，有溫度）
  String _composePoem(List<String> heals) {
    final rand = math.Random();
    final openers = ['夜裡翻開白天，', '傷口結痂的地方，', '安靜的屏幕前，'];
    final closers = ['明天又是新的。', '都過去了。', '我還在這裡。'];
    final opener = openers[rand.nextInt(openers.length)];
    final closer = closers[rand.nextInt(closers.length)];
    final mid = heals.isNotEmpty
        ? '${_countWords(heals)} 道傷痕悄悄癒合，'
        : '無事發生的日子，';
    return '$opener$mid$closer';
  }

  int _countWords(List<String> heals) => heals.length;
}

