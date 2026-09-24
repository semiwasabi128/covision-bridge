// trust_score_test.dart
// [刀 6 K6.2] 信任公式單元測試——Blue 風格農場題材

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/trust/trust_score.dart';

void main() {
  group('computeTrustScore', () {
    test('空資料（少於 5 筆）→ 起步分 30% 不判斷', () {
      final s = computeTrustScore(const TrustScoreInputs(
          total: 0, ok: 0, failed: 0, duplicates: 0));
      expect(s.score, 0.30);
      expect(s.label, '資料收集中');
    });

    test('全成功零浪費 → 高信任', () {
      final s = computeTrustScore(const TrustScoreInputs(
          total: 10, ok: 10, failed: 0, duplicates: 0));
      // 0.30 + 0.65*1.0 - 0 = 0.95
      expect(s.score, closeTo(0.95, 0.001));
      expect(s.label, '高信任');
    });

    test('鹿角蕨澆水任務：8 成 6、零浪費 → 中信任以上', () {
      final s = computeTrustScore(const TrustScoreInputs(
          total: 8, ok: 6, failed: 2, duplicates: 0));
      // 0.30 + 0.65*0.75 = 0.7875
      expect(s.score, closeTo(0.7875, 0.001));
      expect(s.label, '中信任');
    });

    test('同 prompt 重複浪費會扣分', () {
      final clean = computeTrustScore(const TrustScoreInputs(
          total: 10, ok: 10, failed: 0, duplicates: 0));
      final wasteful = computeTrustScore(const TrustScoreInputs(
          total: 10, ok: 10, failed: 0, duplicates: 4));
      expect(wasteful.score, lessThan(clean.score));
      // 0.30 + 0.65 - 0.25*0.4 = 0.85
      expect(wasteful.score, closeTo(0.85, 0.001));
    });

    test('分數鉗制在 0~1', () {
      final worst = computeTrustScore(const TrustScoreInputs(
          total: 10, ok: 0, failed: 10, duplicates: 10));
      expect(worst.score, greaterThanOrEqualTo(0.0));
      expect(worst.score, lessThanOrEqualTo(1.0));
    });

    test('whyHuman 公式透明——數字都看得到', () {
      final s = computeTrustScore(const TrustScoreInputs(
          total: 20, ok: 18, failed: 2, duplicates: 2));
      // 0.30 + 0.65*0.9 - 0.25*0.1 = 0.855 → 86%（捨入）
      expect(s.whyHuman, contains('90%')); // 成功率
      expect(s.whyHuman, contains('86%')); // 最終分
    });

    test('新手等級：失敗多於成功', () {
      final s = computeTrustScore(const TrustScoreInputs(
          total: 10, ok: 2, failed: 8, duplicates: 2));
      // 0.30 + 0.65*0.2 - 0.25*0.2 = 0.38
      expect(s.score, closeTo(0.38, 0.001));
      expect(s.label, '新手');
    });
  });
}
