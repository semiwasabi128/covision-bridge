import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/voice/companion_voice_settings.dart';
import 'package:bridge_app/services/voice/voice_engine.dart';

void main() {
  group('VoiceEngine companion settings contract', () {
    test('settings can define primary, secondary and blend values', () {
      final settings = CompanionVoiceSettings(
        companionId: 'c1',
        primaryVoice: 'zm_yunxi',
        secondaryVoice: 'zf_xiaobei',
        voiceBlend: 0.35,
        baseSpeed: 1.4,
        emotionEnabled: false,
        emotionSensitivity: 0.8,
        enabledEmotions: {'neutral'},
        timeAware: false,
        emotionMemory: false,
        emotionSpeedCoupling: false,
      );

      expect(settings.isValid, isTrue);
      expect(settings.primaryVoice, 'zm_yunxi');
      expect(settings.secondaryVoice, 'zf_xiaobei');
      expect(settings.voiceBlend, 0.35);
    });

    test('engine lifecycle may replace an initial fallback engine safely', () {
      VoiceEngine makeEngine({CompanionVoiceSettings? settings}) => VoiceEngine(
            onSpeak: (_) {},
            onStopSpeaking: () async {},
            settings: settings,
          );

      final fallback = makeEngine();
      final configured = makeEngine(
        settings: CompanionVoiceSettings.defaultsFor('c1'),
      );

      expect(fallback, isNot(same(configured)));
      fallback.dispose();
      configured.dispose();
    });
  });
}
