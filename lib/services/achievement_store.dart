import 'package:shared_preferences/shared_preferences.dart';

class AchievementDefinition {
  final String id;
  final String title;
  final String description;
  final int xp;

  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.xp,
  });
}

class AchievementUnlock {
  final AchievementDefinition achievement;
  final bool isNew;

  const AchievementUnlock({required this.achievement, required this.isNew});
}

class AchievementStore {
  static const String _keyUnlockedIds = 'bridge_achievement_ids_v1';

  static const AchievementDefinition companionPackFirstImport =
      AchievementDefinition(
        id: 'semi_dao.companion_pack.first_import',
        title: '山門初啟',
        description: '第一次從角色包召喚夥伴加入 SemiDAO 綠洲。',
        xp: 25,
      );

  static const AchievementDefinition firstBridgeOpened = AchievementDefinition(
    id: 'semi_dao.bridge.first_opened',
    title: '第一座橋已開通',
    description: '第一次讓手機、桌面與夥伴進入同一條橋樑通道。',
    xp: 50,
  );

  static const List<AchievementDefinition> all = [
    companionPackFirstImport,
    firstBridgeOpened,
  ];

  static Future<AchievementUnlock> unlockCompanionPackFirstImport() {
    return unlock(companionPackFirstImport);
  }

  static Future<AchievementUnlock> unlockFirstBridgeOpened() {
    return unlock(firstBridgeOpened);
  }

  static Future<AchievementUnlock> unlock(
    AchievementDefinition achievement,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final unlocked = prefs.getStringList(_keyUnlockedIds) ?? const [];
    if (unlocked.contains(achievement.id)) {
      return AchievementUnlock(achievement: achievement, isNew: false);
    }

    await prefs.setStringList(_keyUnlockedIds, [...unlocked, achievement.id]);
    return AchievementUnlock(achievement: achievement, isNew: true);
  }

  static Future<bool> isUnlocked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyUnlockedIds) ?? const []).contains(id);
  }

  static Future<Set<String>> getUnlockedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyUnlockedIds) ?? const []).toSet();
  }

  static Future<List<AchievementDefinition>> getUnlockedAchievements() async {
    final unlockedIds = await getUnlockedIds();
    return all
        .where((achievement) => unlockedIds.contains(achievement.id))
        .toList();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUnlockedIds);
  }
}
