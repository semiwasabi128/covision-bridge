// [小葵 2026-09-21] 對話衛生——自動命名行為鎖（Blue 令：列表禁未命名）
// 9/21 教訓：測試沿用了 194 則歷史的舊對話 → context 負擔 → astra $9。
// 修復配套：自動命名要「早」（第 1 則 user 訊息）且「清楚」（12 字上限）。
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/controllers/chat_controller.dart';

void main() {
  late ChatController c;
  setUp(() => c = ChatController());

  group('extractTitleFromText（12 字政策）', () {
    test('短句保留原樣', () {
      expect(c.extractTitleFromText('咖啡排程測試'), '咖啡排程測試');
    });

    test('開頭助詞被剝掉', () {
      final t = c.extractTitleFromText('請問小葵的生日是哪一天');
      expect(t, isNot(contains('請問')));
    });

    test('超過 12 字截到 12（不是 7）', () {
      final t = c.extractTitleFromText('幫我把排程任務系統整個重新測試一輪好嗎');
      expect(t.length, 12, reason: '政策上限 12 字——改回 7 會讓這題失敗（回歸鎖）');
    });

    test('空字串 → 未命名對話（誠實 fallback）', () {
      expect(c.extractTitleFromText('   '), '未命名對話');
    });
  });
}
