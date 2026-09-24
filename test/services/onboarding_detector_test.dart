// onboarding_detector_test.dart
// P0a: 測試桌面版 Agent 對話式 onboarding 偵測

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/onboarding_detector.dart';

void main() {
  setUp(() {
    // SharedPreferences mock — OnboardingDetector 用它記住 onboarding_shown flag
    // StorageService.detectAvailableProvider 用 FlutterSecureStorage，
    // 在測試環境中會 throw，所以只測不碰 StorageService 的方法。
    SharedPreferences.setMockInitialValues({});
  });

  group('OnboardingDetector — 歡迎訊息內容', () {
    test('buildWelcomeMessage contains provider recommendations', () {
      final status = const OnboardingStatus(
        isEmptyState: true,
        hasCompanion: false,
        onboardingShown: false,
      );
      final message = OnboardingDetector.buildWelcomeMessage(status);
      expect(message, contains('MiniMax'));
      expect(message, contains('https://platform.minimaxi.com/'));
      expect(message, contains('系統'));
      expect(message, contains('設定'));
    });

    test('buildWelcomeMessage mentions alternative providers', () {
      final status = const OnboardingStatus(
        isEmptyState: true,
        hasCompanion: false,
        onboardingShown: false,
      );
      final message = OnboardingDetector.buildWelcomeMessage(status);
      expect(message, contains('OpenAI'));
      expect(message, contains('Kimi'));
      expect(message, contains('GLM'));
    });

    test('buildSetupCompleteMessage includes provider display name', () {
      final message = OnboardingDetector.buildSetupCompleteMessage('minimax');
      expect(message, contains('MiniMax'));
      expect(message, contains('設定成功'));
    });

    test('buildNotYetSetupMessage guides user to settings', () {
      final message = OnboardingDetector.buildNotYetSetupMessage();
      expect(message, contains('MiniMax'));
      expect(message, contains('設定'));
      expect(message, contains('https://platform.minimaxi.com/'));
    });
  });

  group('OnboardingStatus — 狀態邏輯', () {
    test('shouldShowWelcome is true when empty and not shown', () {
      const status = OnboardingStatus(
        isEmptyState: true,
        hasCompanion: false,
        onboardingShown: false,
      );
      expect(status.shouldShowWelcome, isTrue);
    });

    test('shouldShowWelcome is false when already shown', () {
      const status = OnboardingStatus(
        isEmptyState: true,
        hasCompanion: false,
        onboardingShown: true,
      );
      expect(status.shouldShowWelcome, isFalse);
    });

    test('shouldShowWelcome is false when not empty state', () {
      const status = OnboardingStatus(
        isEmptyState: false,
        hasCompanion: true,
        onboardingShown: false,
        configuredProvider: 'minimax',
      );
      expect(status.shouldShowWelcome, isFalse);
    });

    test('recommendedProvider defaults to minimax', () {
      const status = OnboardingStatus(
        isEmptyState: true,
        hasCompanion: false,
        onboardingShown: false,
      );
      expect(status.recommendedProvider, 'minimax');
    });
  });

  group('OnboardingDetector — markShown', () {
    test('markShown sets the flag in SharedPreferences', () async {
      await OnboardingDetector.markShown();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('desktop_onboarding_shown_v1'), isTrue);
    });
  });
}
