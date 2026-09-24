import 'package:shared_preferences/shared_preferences.dart';

class BrainProgressSnapshot {
  final int xp;
  final int level;
  final int currentLevelXp;
  final int nextLevelXp;
  final double progress;

  const BrainProgressSnapshot({
    required this.xp,
    required this.level,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.progress,
  });

  int get remainingXp => nextLevelXp - currentLevelXp;
}

class BrainProgressChange {
  final BrainProgressSnapshot before;
  final BrainProgressSnapshot after;
  final int awardedXp;

  const BrainProgressChange({
    required this.before,
    required this.after,
    required this.awardedXp,
  });

  bool get didLevelUp => after.level > before.level;
}

class BrainProgressStore {
  static const String _keyXp = 'bridge_brain_xp';

  static Future<BrainProgressSnapshot> getSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return snapshotForXp(prefs.getInt(_keyXp) ?? 0);
  }

  static Future<BrainProgressChange> awardXp(int amount) async {
    final safeAmount = amount.clamp(0, 999).toInt();
    final prefs = await SharedPreferences.getInstance();
    final before = snapshotForXp(prefs.getInt(_keyXp) ?? 0);
    final after = snapshotForXp(before.xp + safeAmount);
    await prefs.setInt(_keyXp, after.xp);
    return BrainProgressChange(
      before: before,
      after: after,
      awardedXp: safeAmount,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyXp);
  }

  static BrainProgressSnapshot snapshotForXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    var level = 1;
    var spent = 0;
    var next = xpForLevel(level);

    while (safeXp >= spent + next) {
      spent += next;
      level += 1;
      next = xpForLevel(level);
    }

    final current = safeXp - spent;
    return BrainProgressSnapshot(
      xp: safeXp,
      level: level,
      currentLevelXp: current,
      nextLevelXp: next,
      progress: next == 0 ? 1 : current / next,
    );
  }

  static int xpForLevel(int level) {
    final safeLevel = level < 1 ? 1 : level;
    return 100 + ((safeLevel - 1) * 50);
  }
}
