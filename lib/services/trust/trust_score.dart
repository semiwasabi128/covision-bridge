// trust_score.dart
// [刀 6 K6.2 2026-09-08] 信任進度公式——純函式，透明可解釋。
//
// 公式（從七刀報告抄）：
//   額度 ∝ 透明度 × 自律紀錄 ÷ 打擾程度
//
// 三個輸入：
//   透明度      = 1.0（總是記——Phase A Ledger 強制走 gate 才有記錄，故「透明」
//                  是離散值：所有走 gate 的都計入；不走 gate 的不在此公式內）
//   自律紀錄    = ok / total       (0~1)
//   浪費率      = 重複prompt / total (0~1)
//
// 輸出 0~1（=0% ~ 100%）。

import 'dart:math';

class TrustScoreInputs {
  final int total; // 今日總筆數
  final int ok; // 成功
  final int failed; // 失敗
  final int duplicates; // 重複 prompt 數

  const TrustScoreInputs({
    required this.total,
    required this.ok,
    required this.failed,
    required this.duplicates,
  });

  double get successRate => total == 0 ? 1.0 : ok / total;
  double get wasteRate => total == 0 ? 0.0 : duplicates / total;
}

class TrustScore {
  final double score; // 0~1
  final String label; // 新手/成長中/中信任/高信任
  final String whyHuman; // 人話解釋（UI 顯示用）

  const TrustScore({
    required this.score,
    required this.label,
    required this.whyHuman,
  });
}

/// [刀 6] 信任進度核心公式。
///
/// 公式：
///   score = clamp(0, 1, 成功權重 × 成功率 − 浪費權重 × 浪費率 + 起步分)
///
/// 起步分 0.30：夥伴剛上線就有 30% 基礎信任（不是 0 起步）——Blue 哲學
/// 「完全的自由來自於完全的自律」，自律不是從懷疑開始。
/// 樣本不足（<5 筆）：起步分維持，UI 提示「資料收集中」。
TrustScore computeTrustScore(TrustScoreInputs i) {
  const successWeight = 0.65; // 成功率上限權重
  const wasteWeight = 0.25; // 浪費率上限權重（扣分）
  const base = 0.30; // 起步分

  if (i.total < 5) {
    return const TrustScore(
      score: base,
      label: '資料收集中',
      whyHuman: '少於 5 筆紀錄——等資料齊了再下判斷',
    );
  }

  final raw = base + successWeight * i.successRate - wasteWeight * i.wasteRate;
  final score = max(0.0, min(1.0, raw));
  final pct = (score * 100).round();

  String label;
  if (pct >= 90) {
    label = '高信任';
  } else if (pct >= 70) {
    label = '中信任';
  } else if (pct >= 50) {
    label = '成長中';
  } else {
    label = '新手';
  }

  final whyHuman =
      '基礎 ${(base * 100).round()}% + 成功率 ${(i.successRate * 100).round()}% × ${(successWeight * 100).round()}% '
      '− 浪費率 ${(i.wasteRate * 100).round()}% × ${(wasteWeight * 100).round()}% = ${pct}%';

  return TrustScore(score: score, label: label, whyHuman: whyHuman);
}
