import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'storage_service.dart';

class AuthService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> isDeviceSupported() async {
    return await _localAuth.isDeviceSupported();
  }

  static Future<bool> canCheckBiometrics() async {
    return await _localAuth.canCheckBiometrics;
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    return await _localAuth.getAvailableBiometrics();
  }

  static Future<bool> authenticate() async {
    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: '請驗證身分以開啟橋樑',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: '橋樑計畫身份驗證',
            cancelButton: '取消',
            biometricHint: '使用生物識別驗證',
            biometricNotRecognized: '無法辨識，請再試一次',
            biometricSuccess: '驗證成功',
            deviceCredentialsRequiredTitle: '請設定裝置解鎖方式',
            deviceCredentialsSetupDescription: '需要裝置 PIN/密碼/圖案',
            goToSettingsButton: '前往設定',
            goToSettingsDescription: '請在系統設定中啟用生物識別',
          ),
          IOSAuthMessages(
            cancelButton: '取消',
            goToSettingsButton: '前往設定',
            goToSettingsDescription: '請在系統設定中啟用 Face ID / Touch ID',
            lockOut: '生物識別已鎖定，請使用密碼',
          ),
        ],
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> authenticateWithPasscode(String input) async {
    final saved = await StorageService.getPasscode();
    if (saved == null) return false;
    return saved == input;
  }

  static Future<bool> shouldRequireAuth() async {
    // [教練 Agent 2026-07-30] 開發階段加速——debug build 直接跳過驗證
    // 省去每次重開 App 都要按密碼/Touch ID 的時間
    if (kDebugMode) return false;

    final enabled = await StorageService.isAuthEnabled();
    if (!enabled) return false;
    return await StorageService.hasToken();
  }
}
