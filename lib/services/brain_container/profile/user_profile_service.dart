// user_profile_service.dart
// [小葵 2026-09-22 Blue 偷學令②] 使用者檔案（static/dynamic 分層）
// 借鏡 supermemory User Profiles：該全程知道的事不靠搜尋靠檔案常駐。
//
// 設計：視圖模式——profile 是 memories 表的推導視圖，不新增寫入路徑。
//   static  = 穩定事實（身份/偏好/長期事實，pattern 判定 + importance 加權）
//   dynamic = 近期動態（14 天內更新、未被取代/過期的記憶）
// 注入：api_service 每輟組 system prompt 時掛上（替代部分全量記憶的職責）。
// 刷新：啟動後延遲一次 + 隨衰減週期每日一次（同一時脈）。
//
// 零 LLM：全部規則判定，本地零成本。

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  // 快取（每日刷新一次；輪詢 injection 只讀快取——零 DB 查詢）
  List<String> _staticFacts = const [];
  List<String> _dynamicFacts = const [];
  DateTime _refreshedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// static 判定 patterns：第一級身份/偏好事實。
  /// 這些是「無論問什麼都該知道」的事（supermemory profile 的核心洞察：
  /// 名字偏好跟「規劃旅行」語意不相近——搜尋永遠搜不到，必須常駐）。
  static final RegExp _staticPattern = RegExp(
    r'(我叫|我的名字|叫我|我住|我搬|我的生日|我生日|我的工作|我是做|'
    r'我喜歡|我愛|我偏好|我不吃|我不喝|我討厭|我過敏|'
    r'我養|我的貓|我的狗|我女兒|我兒子|我的家人)',
  );

  /// dynamic 排除：純暫時事務（有 expires 的本來就會退場，不進檔案）。
  static const _dynamicWindowDays = 14;
  static const _staticCap = 15;
  static const _dynamicCap = 8;

  /// 是否已有快取（api_service 注入前判斷用）。
  bool get hasProfile => _staticFacts.isNotEmpty || _dynamicFacts.isNotEmpty;

  /// 推導並刷新快取。[db] 由呼叫端傳入（BrainDatabase.instance.db）。
  ///
  /// static：speaker=user、pattern 命中、未被取代、依 importance desc
  ///         取前 15（同內容性質的事實可能多筆——新的蓋舊的，superseded
  ///         機制已在 SQL 層保證只剩現行版）。
  /// dynamic：14 天內更新、非 static 性質、未過期未取代，最新 8 筆。
  Future<void> refresh(Database db) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final staticRows = db.select(
        'SELECT content FROM memories '
        'WHERE archived = 0 AND chunk_index = 0 '
        'AND superseded_by IS NULL '
        'AND (expires_at IS NULL OR expires_at > ?) '
        "AND speaker = 'user' "
        'AND importance >= 3 '
        'ORDER BY importance DESC, updated_at DESC LIMIT 60',
        [now],
      );
      final staticFacts = <String>[];
      final seen = <String>{};
      for (final row in staticRows) {
        final content = (row['content'] as String?)?.trim() ?? '';
        if (content.length < 4) continue;
        if (!_staticPattern.hasMatch(content)) continue;
        // 粗去重：前 12 字相同視為同主題（同主題新舊版已被 superseded 濾掉，
        // 這裡防的是「我喜歡喝咖啡」vs「我喜歡手沖咖啡」這種近親）
        final key = content.length <= 12 ? content : content.substring(0, 12);
        if (seen.contains(key)) continue;
        seen.add(key);
        staticFacts.add(content);
        if (staticFacts.length >= _staticCap) break;
      }

      final dynamicCutoff =
          now - _dynamicWindowDays * 24 * 60 * 60 * 1000;
      final dynamicRows = db.select(
        'SELECT content FROM memories '
        'WHERE archived = 0 AND chunk_index = 0 '
        'AND superseded_by IS NULL '
        'AND (expires_at IS NULL OR expires_at > ?) '
        'AND updated_at >= ? '
        'ORDER BY updated_at DESC LIMIT 40',
        [now, dynamicCutoff],
      );
      final dynamicFacts = <String>[];
      final seenD = <String>{};
      for (final row in dynamicRows) {
        final content = (row['content'] as String?)?.trim() ?? '';
        if (content.length < 4) continue;
        // static 已收錄的不重複進 dynamic
        if (staticFacts.contains(content)) continue;
        final key = content.length <= 12 ? content : content.substring(0, 12);
        if (seenD.contains(key)) continue;
        seenD.add(key);
        dynamicFacts.add(content);
        if (dynamicFacts.length >= _dynamicCap) break;
      }

      _staticFacts = List.unmodifiable(staticFacts);
      _dynamicFacts = List.unmodifiable(dynamicFacts);
      _refreshedAt = DateTime.now();
      debugPrint(
        '[UserProfile] 刷新: static=${_staticFacts.length}, '
        'dynamic=${_dynamicFacts.length}',
      );
    } catch (e) {
      debugPrint('[UserProfile] 刷新失敗（保留舊快取）: $e');
    }
  }

  /// 格式化注入字串。空 profile 回傳空字串（不佔 token）。
  String getFormattedProfile() {
    if (!hasProfile) return '';
    final buf = StringBuffer('【使用者檔案】');
    if (_staticFacts.isNotEmpty) {
      buf.write('\n（長期事實——任何對話都適用）');
      for (final f in _staticFacts) {
        buf.write('\n• $f');
      }
    }
    if (_dynamicFacts.isNotEmpty) {
      buf.write('\n（近期動態——最近兩週）');
      for (final f in _dynamicFacts) {
        buf.write('\n• $f');
      }
    }
    return buf.toString();
  }

  /// 快取年齡（分鐘）——呼叫端可判斷是否該刷新。
  int get cacheAgeMinutes =>
      DateTime.now().difference(_refreshedAt).inMinutes;
}
