// memory_decay_service.dart
// 記憶衰減管理 — 演算法層
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
//
// 衰減策略（借鑑艾賓浩斯遺忘曲線 + Transurfing 空間變異概念）：
//
// 1. 記憶有「活躍度分數」(vitality)，由以下因素決定：
//    - base = importance（1-5，使用者設定）
//    - timeDecay = 隨時間衰減（半衰期由 importance 決定）
//    - accessBoost = 每次被檢索 +1（access_count）
//    - connectionBoost = 有強連結的記憶衰減更慢
//
// 2. 半衰期（天）by importance：
//    importance 5 → 90 天（核心記憶，三個月半衰）
//    importance 4 → 45 天
//    importance 3 → 21 天（預設，約三週）
//    importance 2 → 10 天
//    importance 1 → 5 天（瑣事，一週內半衰）
//
// 3. 衰減動作：
//    a. vitality < 0.3 且 importance > 1 → 降級 importance -= 1
//    b. vitality < 0.15 且 importance == 1 → 歸檔 archived = 1
//    c. 連結 dormant：超過 60 天未被強化的連結 → dormant = 1
//
// 4. 執行時機：由 cron 或 app 啟動時呼叫（不在每次寫入/檢索時跑）

import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:flutter/foundation.dart';

class MemoryDecayService {
  final BrainDatabase database;

  MemoryDecayService({required this.database});

  /// 執行一次衰減週期。
  ///
  /// 回傳 [DecayResult] 摘要，包含降級/歸檔/休眠的數量。
  /// 此方法應定期呼叫（例如每天一次），不在每次記憶寫入時跑。
  Future<DecayResult> runDecayCycle() async {
    final db = database.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    int demoted = 0;
    int archived = 0;
    int connectionsDormant = 0;

    try {
      // Phase 1: 記憶衰減降級
      //
      // 對每條未歸檔記憶計算 vitality：
      // vitality = (importance / 5) * exp(-elapsedDays / halfLifeDays)
      //          + min(accessCount * 0.1, 0.5)
      //
      // SQL 不方便做 exp()，所以批次取回 Dart 端計算後再 UPDATE。
      final memories = db.select(
        'SELECT id, importance, created_at, updated_at, access_count '
        'FROM memories WHERE archived = 0 AND chunk_index = 0',
      );

      final toDemote = <String>[];
      final toArchive = <String>[];

      for (final row in memories) {
        final id = row['id'] as String;
        final importance = row['importance'] as int;
        final createdAt = row['created_at'] as int;
        final updatedAt = row['updated_at'] as int;
        final accessCount = row['access_count'] as int;

        final vitality = _calculateVitality(
          importance: importance,
          createdAt: createdAt,
          updatedAt: updatedAt,
          accessCount: accessCount,
          now: now,
        );

        if (vitality < 0.15 && importance <= 1) {
          toArchive.add(id);
        } else if (vitality < 0.3 && importance > 1) {
          toDemote.add(id);
        }
      }

      // 執行降級
      if (toDemote.isNotEmpty) {
        for (final id in toDemote) {
          db.execute(
            'UPDATE memories SET importance = importance - 1, updated_at = ? '
            'WHERE id = ? AND importance > 1',
            [now, id],
          );
        }
        demoted = toDemote.length;
      }

      // 執行歸檔
      if (toArchive.isNotEmpty) {
        for (final id in toArchive) {
          db.execute(
            'UPDATE memories SET archived = 1, updated_at = ? WHERE id = ?',
            [now, id],
          );
        }
        archived = toArchive.length;
      }

      // Phase 2: 連結休眠
      // 超過 60 天未被強化的非休眠連結 → dormant = 1
      final sixtyDaysAgo = now - (60 * 24 * 60 * 60 * 1000);
      db.execute(
        'UPDATE connections SET dormant = 1 '
        'WHERE dormant = 0 AND last_reinforced_at < ? '
        'AND user_marked = 0',
        [sixtyDaysAgo],
      );
      // 取得影響行數
      final dormantRows = db.select(
        'SELECT changes() as affected',
      );
      connectionsDormant =
          dormantRows.isEmpty ? 0 : (dormantRows.first['affected'] as int? ?? 0);

      debugPrint(
        '[Decay] 降級=$demoted, 歸檔=$archived, '
        '連結休眠=$connectionsDormant',
      );
    } catch (e) {
      debugPrint('[Decay] 衰減週期失敗: $e');
    }

    return DecayResult(
      demoted: demoted,
      archived: archived,
      connectionsDormant: connectionsDormant,
    );
  }

  /// 計算單條記憶的活躍度分數 (0.0 ~ 1.0+)。
  ///
  /// 公式：
  ///   halfLifeDays = importance * importance * 3.6  (importance 5 → 90 天)
  ///   elapsedDays = (now - updatedAt) / 86400000
  ///   timeFactor = exp(-elapsedDays / halfLifeDays)
  ///   accessBoost = min(accessCount * 0.1, 0.5)
  ///   vitality = (importance / 5) * timeFactor + accessBoost
  double _calculateVitality({
    required int importance,
    required int createdAt,
    required int updatedAt,
    required int accessCount,
    required int now,
  }) {
    // 半衰期：importance 越高，衰減越慢
    // 5→90d, 4→57.6d, 3→32.4d, 2→14.4d, 1→3.6d
    final halfLifeDays = importance * importance * 3.6;

    // 從最後更新時間算起經過的天數
    final elapsedMs = now - updatedAt;
    final elapsedDays = elapsedMs / 86400000.0;

    // 時間衰減因子（指數衰減）
    final timeFactor = _exp(-elapsedDays / halfLifeDays);

    // 存取加成（最多 +0.5）
    final accessBoost = (accessCount * 0.1).clamp(0.0, 0.5);

    // 基礎活躍度 = 重要性正規化 × 時間因子
    final base = (importance / 5.0) * timeFactor;

    return base + accessBoost;
  }

  /// 泰勒展開近似 exp(x)，避免引入 dart:math 的 exp 依賴問題。
  /// 精度足夠（x 通常在 -3 ~ 0 範圍，7 項展開誤差 < 1e-6）。
  double _exp(double x) {
    if (x > 0) {
      // 正數：用倒數技巧
      return 1.0 / _exp(-x);
    }
    // 負數：泰勒展開
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 10; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  /// 被檢索時呼叫：增加存取計數、刷新更新時間。
  ///
  /// 在 MemoryRetrievalPipeline 命中記憶後呼叫。
  Future<void> onMemoryAccessed(String memoryId) async {
    final db = database.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'UPDATE memories SET access_count = access_count + 1, updated_at = ? '
      'WHERE id = ?',
      [now, memoryId],
    );
  }

  /// 被檢索時呼叫：強化連結。
  ///
  /// 連結被走過（connection expansion 命中）時，
  /// reinforcement_count + 1, last_reinforced_at = now, dormant = 0。
  Future<void> onConnectionReinforced(String connectionId) async {
    final db = database.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      'UPDATE connections SET reinforcement_count = reinforcement_count + 1, '
      'last_reinforced_at = ?, dormant = 0 WHERE id = ?',
      [now, connectionId],
    );
  }
}

/// 衰減週期結果摘要。
class DecayResult {
  /// 降級的記憶數（importance -= 1）
  final int demoted;

  /// 歸檔的記憶數（archived = 1）
  final int archived;

  /// 休眠的連結數（dormant = 1）
  final int connectionsDormant;

  const DecayResult({
    required this.demoted,
    required this.archived,
    required this.connectionsDormant,
  });

  @override
  String toString() =>
      'DecayResult(demoted=$demoted, archived=$archived, connectionsDormant=$connectionsDormant)';
}
