import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/door_decision_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DoorDecisionStore.pendingReturn.value = null;
  });

  test('door decision store saves and restores pending return door', () async {
    const store = DoorDecisionStore();
    const pending = DoorDecisionPendingReturn(
      decisionId: 'door-1',
      title: 'adapter 支線',
      chosenLabel: '先走主線',
      deferredLabel: '先進支線',
      returnPrompt: '回到 adapter 支線。',
      sourceSummary: '主線與支線都合理。',
      createdAtMs: 123,
    );

    await store.savePendingReturn(pending);

    final restored = await store.loadPendingReturn();
    expect(restored, isNotNull);
    expect(restored!.decisionId, 'door-1');
    expect(restored.deferredLabel, '先進支線');
    expect(
      DoorDecisionStore.pendingReturn.value?.returnPrompt,
      contains('adapter'),
    );
  });

  test('door decision store clears matching pending return door', () async {
    const store = DoorDecisionStore();
    const pending = DoorDecisionPendingReturn(
      decisionId: 'door-1',
      title: 'adapter 支線',
      chosenLabel: '先走主線',
      deferredLabel: '先進支線',
      returnPrompt: '回到 adapter 支線。',
      sourceSummary: '主線與支線都合理。',
      createdAtMs: 123,
    );

    await store.savePendingReturn(pending);
    await store.clearPendingReturn(decisionId: 'door-1');

    expect(await store.loadPendingReturn(), isNull);
    expect(DoorDecisionStore.pendingReturn.value, isNull);
  });
}
