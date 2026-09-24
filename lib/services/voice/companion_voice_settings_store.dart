// Companion Voice Settings Store — 持久化層
//
// [教練 Agent 2026-08-03] Phase 1 (C1)
//
// 使用 SharedPreferences 儲存（每個夥伴一個 key）
// Key 格式：voice_settings_{companionId}
//
// 為什麼選 SharedPreferences（不是 SQLite）：
// - 1 個夥伴的語音設定只有 ~200 bytes JSON
// - 讀寫都是 O(1)，無需查詢
// - 程式碼極簡（30 行 vs SQLite 200+ 行）
// - 之後要遷移 SQLite 也容易（把 JSON 拆成欄位就好）
//
// 同步載入：loadSync() — 適合已在 UI build 階段需要
// 異步載入：load() — 適合背景任務

import 'package:shared_preferences/shared_preferences.dart';
import 'companion_voice_settings.dart';

class CompanionVoiceSettingsStore {
  static const _keyPrefix = 'voice_settings_';

  /// 載入夥伴的語音設定（無資料回傳預設值）
  static Future<CompanionVoiceSettings> load(String companionId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_keyPrefix$companionId');
    if (jsonStr == null) {
      return CompanionVoiceSettings.defaultsFor(companionId);
    }
    try {
      final settings = CompanionVoiceSettings.fromJsonString(jsonStr);
      // 驗證資料完整性，壞掉回傳預設
      return settings.isValid
          ? settings
          : CompanionVoiceSettings.defaultsFor(companionId);
    } catch (e) {
      // 解析失敗 → 回傳預設
      return CompanionVoiceSettings.defaultsFor(companionId);
    }
  }

  /// 同步載入 cache（需先呼叫 SharedPreferences.setMockInitialValues 或已經初始化過）
  /// 註：SharedPreferences 沒有真正的 sync API，這裡用 getInstance() 取得 cache
  /// 首次呼叫前需先 await getInstance()，否則 cache 為空會回傳預設值
  static CompanionVoiceSettings loadSync(String companionId) {
    final prefs = SharedPreferences.getInstance();
    // 這是 async 的 Future<SharedPreferences>，但 getInstance() 會回傳同步 cache
    // 第一次呼叫前若未 await，會拋例外 — 改用 try-catch 安全處理
    try {
      final p = prefs as SharedPreferences;
      final jsonStr = p.getString('$_keyPrefix$companionId');
      if (jsonStr == null) {
        return CompanionVoiceSettings.defaultsFor(companionId);
      }
      return CompanionVoiceSettings.fromJsonString(jsonStr);
    } catch (e) {
      return CompanionVoiceSettings.defaultsFor(companionId);
    }
  }

  /// 儲存
  static Future<void> save(CompanionVoiceSettings settings) async {
    if (!settings.isValid) {
      throw ArgumentError('Invalid settings: $settings');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_keyPrefix${settings.companionId}',
      settings.toJsonString(),
    );
  }

  /// 刪除
  static Future<void> delete(String companionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$companionId');
  }

  /// 載入所有夥伴的語音設定（用於批次管理）
  /// 回傳 Map<companionId, settings>
  static Future<Map<String, CompanionVoiceSettings>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, CompanionVoiceSettings>{};

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_keyPrefix)) continue;
      final companionId = key.substring(_keyPrefix.length);
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) continue;
      try {
        final settings = CompanionVoiceSettings.fromJsonString(jsonStr);
        if (settings.isValid) {
          result[companionId] = settings;
        }
      } catch (e) {
        // 跳過壞資料
      }
    }

    return result;
  }
}
