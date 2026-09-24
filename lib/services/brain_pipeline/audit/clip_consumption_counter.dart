// clip_consumption_counter.dart
// Sprint 8 — 偵測使用者訊息中的短影音消費時間並累計
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 規則版偵測——不需要 LLM，純關鍵字 + 正則。
// 偵測模式：
// 1. 時間量詞 + 短影音平台關鍵字：「刷了 2 小時 shorts」「看了 30 分鐘 TikTok」
// 2. 動詞 + 時間量詞（上下文有短影音關鍵字）：「又刷了 30 分鐘」
// 3. 純時間量詞 + 刷：「刷了 1 小時」「刷手機 2 小時」
//
// 支援的時間格式：
// - X 小時 / X 小時 / X hours / X hr
// - X 分鐘 / X 分 / X minutes / X min
// - X 秒 / X seconds / X sec

import 'audit_store.dart';

/// 偵測使用者訊息中的短影音消費時間。
///
/// 規則版偵測，純正則 + 關鍵字，不需要 LLM。
/// 命中時把秒數累加到 [AuditStore]。
class ClipConsumptionCounter {
  final AuditStore _store;

  ClipConsumptionCounter(this._store);

  /// 短影音平台關鍵字
  static const _platformKeywords = [
    'shorts', 'tiktok', 'youtube shorts', 'reels',
    '短影音', '短片', '抖音', 'ig 影片', 'ig影片',
  ];

  /// 刷手機相關動詞
  static const _scrollVerbs = ['刷', '滑', '看', '逛'];

  /// 從使用者訊息偵測 clip 消費時間，回傳偵測到的秒數（0 = 未偵測到）。
  /// 同時寫入 AuditStore。
  int detectAndRecord(String message) {
    final seconds = detect(message);
    if (seconds > 0) {
      _store.addClipConsumptionSeconds(seconds);
    }
    return seconds;
  }

  /// 純偵測，不寫入 store。回傳偵測到的秒數。
  int detect(String message) {
    final lower = message.toLowerCase();
    final hasPlatform = _platformKeywords.any((k) => lower.contains(k));
    final hasScrollVerb = _scrollVerbs.any((v) => message.contains(v));

    // 條件 1：有平台關鍵字 → 找時間
    // 條件 2：有刷手機動詞 + 時間量詞（如「刷了 2 小時」）
    if (!hasPlatform && !hasScrollVerb) return 0;

    // 正則：抓「數字 + 時間單位」
    // 中文：X 小時 / X 分鐘 / X 分 / X 秒
    // 英文：X hours / X hr / X minutes / X min / X seconds / X sec
    final timeRegex = RegExp(
      r'(\d+(?:\.\d+)?)\s*'
      r'(小時|小時|分鐘|分鐘|分鐘|分|秒'
      r'|hours?|hrs?|minutes?|mins?|seconds?|secs?)',
      caseSensitive: false,
    );

    int totalSeconds = 0;
    for (final match in timeRegex.allMatches(message)) {
      final amount = double.tryParse(match.group(1)!) ?? 0;
      final unit = match.group(2)!.toLowerCase();

      if (unit.contains('小時') || unit.contains('hour') || unit.contains('hr')) {
        totalSeconds += (amount * 3600).round();
      } else if (unit.contains('分鐘') || unit.contains('minute') || unit.contains('min')) {
        totalSeconds += (amount * 60).round();
      } else if (unit.contains('秒') || unit.contains('second') || unit.contains('sec')) {
        totalSeconds += amount.round();
      } else if (unit == '分') {
        // 單獨「分」——可能是分鐘
        totalSeconds += (amount * 60).round();
      }
    }

    // 如果有平台關鍵字或刷手機動詞，且有時間量詞，就算 clip 消費
    if (totalSeconds > 0 && (hasPlatform || hasScrollVerb)) {
      return totalSeconds;
    }

    return 0;
  }

  /// 今天的累計秒數是否超過警示門檻（60 分鐘 = 3600 秒）
  bool get isOverLimit => _store.clipConsumptionSecondsToday >= 3600;
}
