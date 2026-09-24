import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/services/pending_bridge_task_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pending bridge task store saves and restores active task', () async {
    const store = PendingBridgeTaskStore();
    final task = PendingBridgeTask.create(
      title: '開通音樂生成能力',
      request: '請生成一段適合讀書的音樂 30 秒',
      missing: '音樂生成 provider',
      route: '/golden-keys?returnTo=/chat',
      routeLabel: '設定生成能力',
      iconName: 'music_note',
      conversationId: 'conv-1',
      bridgeAction: const BridgeAction(
        type: BridgeActionType.generateMusic,
        prompt: '請生成一段適合讀書的音樂 30 秒',
      ),
    );

    await store.save(task);

    final restored = await store.loadActive();
    expect(restored, isNotNull);
    expect(restored!.title, '開通音樂生成能力');
    expect(restored.request, '請生成一段適合讀書的音樂 30 秒');
    expect(restored.bridgeAction?.type, BridgeActionType.generateMusic);
    expect(restored.bridgeAction?.prompt, '請生成一段適合讀書的音樂 30 秒');
  });

  test('pending bridge task store ignores broken payload', () async {
    SharedPreferences.setMockInitialValues({
      PendingBridgeTaskStore.keyActiveTask: '{broken',
    });

    expect(await const PendingBridgeTaskStore().loadActive(), isNull);
  });
}
