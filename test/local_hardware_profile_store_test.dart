import 'dart:convert';

import 'package:bridge_app/services/local_hardware_profile_store.dart';
import 'package:bridge_app/services/local_model_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('store saves and loads local hardware profile', () async {
    SharedPreferences.setMockInitialValues({});

    const store = LocalHardwareProfileStore();
    const profile = LocalHardwareProfile(
      source: 'test',
      ramGb: 32,
      vramGb: 8,
      chipLabel: 'Test Mac · 32GB',
      desktopConnected: true,
    );

    await store.save(profile);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.source, 'test');
    expect(loaded.ramGb, 32);
    expect(loaded.vramGb, 8);
    expect(loaded.chipLabel, 'Test Mac · 32GB');
    expect(loaded.desktopConnected, isTrue);
  });

  test('store returns null when saved payload is invalid', () async {
    SharedPreferences.setMockInitialValues({
      LocalHardwareProfileStore.keyProfile: '{broken',
    });

    final loaded = await const LocalHardwareProfileStore().load();

    expect(loaded, isNull);
  });

  test('store resets saved hardware profile', () async {
    SharedPreferences.setMockInitialValues({
      LocalHardwareProfileStore.keyProfile: jsonEncode({
        'source': 'saved',
        'ramGb': 16,
        'chipLabel': 'Saved Machine',
        'desktopConnected': true,
      }),
    });

    const store = LocalHardwareProfileStore();
    expect(await store.load(), isNotNull);

    await store.reset();

    expect(await store.load(), isNull);
  });
}
