import 'dart:convert';

import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_companion_shell_config_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('store saves and loads shell config', () async {
    SharedPreferences.setMockInitialValues({});

    const store = DesktopCompanionShellConfigStore();
    final config = const DesktopCompanionShellConfig().copyWith(
      alwaysOnTop: false,
      trayEnabled: false,
      launchAtLogin: true,
      width: 260,
      height: 320,
    );

    await store.save(config);
    final loaded = await store.load();

    expect(loaded.alwaysOnTop, isFalse);
    expect(loaded.trayEnabled, isFalse);
    expect(loaded.launchAtLogin, isTrue);
    expect(loaded.width, 260);
    expect(loaded.height, 320);
  });

  test('store falls back to defaults when saved payload is invalid', () async {
    SharedPreferences.setMockInitialValues({
      'bridge_desktop_shell_config_v1': '{broken',
    });

    final loaded = await const DesktopCompanionShellConfigStore().load();

    expect(loaded.alwaysOnTop, isTrue);
    expect(loaded.trayEnabled, isTrue);
    expect(loaded.width, 228);
  });

  test('store reads partially saved payloads safely', () async {
    SharedPreferences.setMockInitialValues({
      'bridge_desktop_shell_config_v1': jsonEncode({
        'alwaysOnTop': false,
        'width': 244,
      }),
    });

    final loaded = await const DesktopCompanionShellConfigStore().load();

    expect(loaded.alwaysOnTop, isFalse);
    expect(loaded.width, 244);
    expect(loaded.trayEnabled, isTrue);
    expect(loaded.runtimeChannel, 'bridge.runtime.v1');
  });
}
