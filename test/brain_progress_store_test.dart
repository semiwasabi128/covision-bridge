import 'package:bridge_app/services/brain_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('calculates level progress from xp', () {
    final level1 = BrainProgressStore.snapshotForXp(75);
    expect(level1.level, 1);
    expect(level1.currentLevelXp, 75);
    expect(level1.nextLevelXp, 100);
    expect(level1.progress, 0.75);

    final level2 = BrainProgressStore.snapshotForXp(125);
    expect(level2.level, 2);
    expect(level2.currentLevelXp, 25);
    expect(level2.nextLevelXp, 150);
  });

  test('awards xp and reports level up', () async {
    SharedPreferences.setMockInitialValues({'bridge_brain_xp': 95});

    final change = await BrainProgressStore.awardXp(15);

    expect(change.before.level, 1);
    expect(change.after.level, 2);
    expect(change.didLevelUp, isTrue);
    expect(change.after.xp, 110);
  });
}
