import 'package:bridge_app/services/achievement_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unlocks companion pack first import achievement once', () async {
    SharedPreferences.setMockInitialValues({});

    final first = await AchievementStore.unlockCompanionPackFirstImport();
    final second = await AchievementStore.unlockCompanionPackFirstImport();

    expect(first.isNew, isTrue);
    expect(first.achievement.title, '山門初啟');
    expect(first.achievement.xp, 25);
    expect(second.isNew, isFalse);
    expect(
      await AchievementStore.isUnlocked(
        AchievementStore.companionPackFirstImport.id,
      ),
      isTrue,
    );
  });

  test('clear removes unlocked achievements', () async {
    SharedPreferences.setMockInitialValues({});

    await AchievementStore.unlockCompanionPackFirstImport();
    await AchievementStore.clear();

    expect(
      await AchievementStore.isUnlocked(
        AchievementStore.companionPackFirstImport.id,
      ),
      isFalse,
    );
  });

  test('unlocks first bridge opened achievement once', () async {
    SharedPreferences.setMockInitialValues({});

    final first = await AchievementStore.unlockFirstBridgeOpened();
    final second = await AchievementStore.unlockFirstBridgeOpened();

    expect(first.isNew, isTrue);
    expect(first.achievement.title, '第一座橋已開通');
    expect(first.achievement.xp, 50);
    expect(second.isNew, isFalse);
    expect(
      await AchievementStore.isUnlocked(AchievementStore.firstBridgeOpened.id),
      isTrue,
    );
  });
}
