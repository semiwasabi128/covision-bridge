// Companion Voice Settings 單元測試
//
// [小葵 2026-08-03] Phase 1 (C1) 驗收

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/voice/companion_voice_settings.dart';
import 'package:bridge_app/services/voice/companion_voice_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CompanionVoiceSettings', () {
    test('預設值正確', () {
      final s = CompanionVoiceSettings.defaultsFor('c1');
      expect(s.companionId, 'c1');
      expect(s.primaryVoice, 'zf_xiaoxiao');
      expect(s.secondaryVoice, null);
      expect(s.voiceBlend, 1.0);
      expect(s.baseSpeed, 1.0);
      expect(s.emotionSpeedCoupling, true);
      expect(s.emotionEnabled, true);
      expect(s.emotionSensitivity, 0.5);
      expect(s.enabledEmotions, {'amused', 'neutral', 'sleepiness'});
      expect(s.timeAware, true);
      expect(s.emotionMemory, true);
      expect(s.isValid, true);
    });

    test('序列化 → 反序列化 → 內容相同', () {
      final original = CompanionVoiceSettings(
        companionId: 'c1',
        primaryVoice: 'zf_xiaobei',
        secondaryVoice: 'zm_yunjian',
        voiceBlend: 0.7,
        baseSpeed: 1.2,
        emotionSpeedCoupling: false,
        emotionEnabled: true,
        emotionSensitivity: 0.8,
        enabledEmotions: {'amused', 'anger'},
        timeAware: false,
        emotionMemory: true,
      );

      final jsonStr = original.toJsonString();
      final restored = CompanionVoiceSettings.fromJsonString(jsonStr);

      expect(restored.companionId, original.companionId);
      expect(restored.primaryVoice, original.primaryVoice);
      expect(restored.secondaryVoice, original.secondaryVoice);
      expect(restored.voiceBlend, original.voiceBlend);
      expect(restored.baseSpeed, original.baseSpeed);
      expect(restored.emotionSpeedCoupling, original.emotionSpeedCoupling);
      expect(restored.emotionSensitivity, original.emotionSensitivity);
      expect(restored.enabledEmotions, original.enabledEmotions);
      expect(restored.timeAware, original.timeAware);
    });

    test('邊界值：語速 0.5 跟 2.0 合法', () {
      final s1 = CompanionVoiceSettings(companionId: 'c', baseSpeed: 0.5);
      expect(s1.isValid, true);
      final s2 = CompanionVoiceSettings(companionId: 'c', baseSpeed: 2.0);
      expect(s2.isValid, true);
    });

    test('邊界值：語速 < 0.5 或 > 2.0 不合法', () {
      final s1 = CompanionVoiceSettings(companionId: 'c', baseSpeed: 0.4);
      expect(s1.isValid, false);
      final s2 = CompanionVoiceSettings(companionId: 'c', baseSpeed: 2.1);
      expect(s2.isValid, false);
    });

    test('邊界值：混合比例 0.0~1.0', () {
      expect(CompanionVoiceSettings(companionId: 'c', voiceBlend: 0.0).isValid, true);
      expect(CompanionVoiceSettings(companionId: 'c', voiceBlend: 1.0).isValid, true);
      expect(CompanionVoiceSettings(companionId: 'c', voiceBlend: 1.1).isValid, false);
      expect(CompanionVoiceSettings(companionId: 'c', voiceBlend: -0.1).isValid, false);
    });

    test('邊界值：情緒敏感度 0.0~1.0', () {
      expect(CompanionVoiceSettings(companionId: 'c', emotionSensitivity: 0.0).isValid, true);
      expect(CompanionVoiceSettings(companionId: 'c', emotionSensitivity: 1.0).isValid, true);
      expect(CompanionVoiceSettings(companionId: 'c', emotionSensitivity: -0.1).isValid, false);
    });

    test('邊界值：至少要有一個情緒', () {
      final s = CompanionVoiceSettings(companionId: 'c', enabledEmotions: {});
      expect(s.isValid, false);
    });

    test('邊界值：情緒必須是 5 種之一', () {
      final s = CompanionVoiceSettings(
        companionId: 'c',
        enabledEmotions: {'amused', 'unknown_emotion'},
      );
      expect(s.isValid, false);
    });

    test('不支援的聲音不合法', () {
      final s = CompanionVoiceSettings(companionId: 'c', primaryVoice: 'en_male_001');
      expect(s.isValid, false);
    });

    test('copyWith 正確', () {
      final s = CompanionVoiceSettings.defaultsFor('c1');
      final s2 = s.copyWith(baseSpeed: 1.5, primaryVoice: 'zf_xiaobei');
      expect(s2.companionId, 'c1'); // 不變
      expect(s2.baseSpeed, 1.5);
      expect(s2.primaryVoice, 'zf_xiaobei');
      // 其他欄位保持原值
      expect(s2.emotionEnabled, s.emotionEnabled);
    });

    test('copyWith 把 secondaryVoice 設為 null', () {
      final s = CompanionVoiceSettings(companionId: 'c', secondaryVoice: 'zf_xiaobei');
      final s2 = s.copyWith(secondaryVoice: null);
      expect(s2.secondaryVoice, null);
    });
  });

  group('CompanionVoiceSettingsStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('儲存 → 載入 → 內容相同', () async {
      final original = CompanionVoiceSettings(
        companionId: 'c1',
        primaryVoice: 'zm_yunxi',
        baseSpeed: 1.3,
      );

      await CompanionVoiceSettingsStore.save(original);
      final loaded = await CompanionVoiceSettingsStore.load('c1');

      expect(loaded.primaryVoice, 'zm_yunxi');
      expect(loaded.baseSpeed, 1.3);
      expect(loaded.companionId, 'c1');
    });

    test('無資料 → 回傳預設值', () async {
      final loaded = await CompanionVoiceSettingsStore.load('nonexistent');
      expect(loaded.companionId, 'nonexistent');
      expect(loaded.primaryVoice, 'zf_xiaoxiao'); // 預設
    });

    test('壞資料 → 回傳預設值', () async {
      SharedPreferences.setMockInitialValues({
        'voice_settings_c1': 'not valid json{{{',
      });
      final loaded = await CompanionVoiceSettingsStore.load('c1');
      expect(loaded.primaryVoice, 'zf_xiaoxiao'); // 預設
    });

    test('刪除 → 載入回預設值', () async {
      await CompanionVoiceSettingsStore.save(
        CompanionVoiceSettings(companionId: 'c1', primaryVoice: 'zf_xiaobei'),
      );
      await CompanionVoiceSettingsStore.delete('c1');
      final loaded = await CompanionVoiceSettingsStore.load('c1');
      expect(loaded.primaryVoice, 'zf_xiaoxiao');
    });

    test('loadAll 回傳所有夥伴的設定', () async {
      await CompanionVoiceSettingsStore.save(
        CompanionVoiceSettings(companionId: 'a', primaryVoice: 'zf_xiaoxiao'),
      );
      await CompanionVoiceSettingsStore.save(
        CompanionVoiceSettings(companionId: 'b', primaryVoice: 'zm_yunjian'),
      );

      final all = await CompanionVoiceSettingsStore.loadAll();
      expect(all.length, 2);
      expect(all['a']!.primaryVoice, 'zf_xiaoxiao');
      expect(all['b']!.primaryVoice, 'zm_yunjian');
    });

    test('無效資料不列入 loadAll', () async {
      SharedPreferences.setMockInitialValues({
        'voice_settings_valid': '{"companionId":"valid","primaryVoice":"zf_xiaoxiao","voiceBlend":1.0,"baseSpeed":1.0,"emotionEnabled":true,"emotionSensitivity":0.5,"enabledEmotions":["amused","neutral","sleepiness"],"emotionSpeedCoupling":true,"timeAware":true,"emotionMemory":true}',
        'voice_settings_bad_speed': '{"companionId":"bad","primaryVoice":"zf_xiaoxiao","voiceBlend":1.0,"baseSpeed":5.0,"emotionEnabled":true,"emotionSensitivity":0.5,"enabledEmotions":["amused","neutral","sleepiness"],"emotionSpeedCoupling":true,"timeAware":true,"emotionMemory":true}',
      });

      final all = await CompanionVoiceSettingsStore.loadAll();
      expect(all.length, 1); // 只有 valid
      expect(all['valid'], isNotNull);
      expect(all['bad_speed'], isNull);
    });
  });
}
