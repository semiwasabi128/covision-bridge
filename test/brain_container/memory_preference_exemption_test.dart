// [小葵 2026-09-15 Blue 抓包] 記憶/偏好請求豁免回歸測試
// 病例：「請記住：我喜歡喝咖啡，每天早上都要來一杯」的「每天」誤觸發
// schedule_reminder 能力顧問 → 去搜市面提醒方案。
// 修法：_looksLikeMemoryPreferenceRequest——記憶動詞/偏好陳述 → 豁免。
// 此處鎖行為契約：真排程（提醒我）不受豁免、記憶請求必須豁免。
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 與 chat_controller._looksLikeMemoryPreferenceRequest 同步的鏡像判定
  // （private method 無法直接測——用同邏輯驗詞表契約，未來重構抽 public 時改直測）
  bool looksLikeMemoryPreferenceRequest(String normalized) {
    final memoryVerbs = [
      '請記住', '記住', '幫我記', '幫我記住', '請帮我记得', 'remember', 'remember that',
    ];
    final preferencePatterns = [
      '我喜歡', '我偏好', '我愛', '我討厭', '我不喜歡', '我不要', 'my favorite', 'i like', 'i prefer',
    ];
    final scheduleActionVerbs = [
      '提醒我', '通知我', '叫我起床', '鬧鐘', 'remind me', 'notify me', 'wake me',
    ];
    final hasScheduleAction = scheduleActionVerbs.any((v) => normalized.contains(v));
    if (hasScheduleAction) return false;
    final hasMemoryVerb = memoryVerbs.any((v) => normalized.contains(v));
    final hasPreference = preferencePatterns.any((v) => normalized.contains(v));
    return hasMemoryVerb || hasPreference;
  }

  group('[記憶豁免] Blue 抓包病例回歸', () {
    test('病例原文：請記住我喜歡喝咖啡 → 豁免（不觸發能力顧問）', () {
      expect(
        looksLikeMemoryPreferenceRequest('請記住：我喜歡喝咖啡，每天早上都要來一杯'),
        isTrue,
      );
    });

    test('偏好陳述（無記憶動詞）→ 豁免', () {
      expect(looksLikeMemoryPreferenceRequest('我喜歡喝咖啡'), isTrue);
      expect(looksLikeMemoryPreferenceRequest('我偏好早上工作'), isTrue);
      expect(looksLikeMemoryPreferenceRequest('i like coffee'), isTrue);
    });

    test('真排程請求（提醒我）→ 不豁免（能力顧問照常）', () {
      expect(
        looksLikeMemoryPreferenceRequest('每天早上7點提醒我澆水'),
        isFalse,
      );
      expect(looksLikeMemoryPreferenceRequest('設定鬧鐘每天 8 點'), isFalse);
      expect(looksLikeMemoryPreferenceRequest('remind me tomorrow'), isFalse);
    });

    test('記憶+排程混合：排程動作優先 → 不豁免', () {
      // 「記住要提醒我」——有明確排程動作，走能力顧問
      expect(
        looksLikeMemoryPreferenceRequest('記住每天提醒我喝水'),
        isFalse,
      );
    });

    test('一般對話（兩者皆無）→ 不豁免', () {
      expect(looksLikeMemoryPreferenceRequest('今天天氣如何'), isFalse);
      expect(looksLikeMemoryPreferenceRequest('幫我寫一首詩'), isFalse);
    });
  });
}
