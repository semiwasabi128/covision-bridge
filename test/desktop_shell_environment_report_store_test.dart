import 'dart:convert';

import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:bridge_app/services/desktop_shell_environment_report_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('store saves and loads imported doctor report', () async {
    SharedPreferences.setMockInitialValues({});

    const store = DesktopShellEnvironmentReportStore();
    final report = const DesktopShellEnvironmentReportService().fromSignals(
      flutterAvailable: true,
      fullXcodeAvailable: false,
      swiftParsePassed: true,
      macosBuildPassed: false,
      xcodeSelectPath: '/Library/Developer/CommandLineTools',
    );

    await store.save(report);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.readyCount, 3);
    expect(loaded.blockedCount, 1);
    expect(
      loaded.items.map((item) => item.id),
      containsAll(['full-xcode', 'native-contract']),
    );
  });

  test('store returns null when saved payload is invalid', () async {
    SharedPreferences.setMockInitialValues({
      DesktopShellEnvironmentReportStore.keyReport: '{broken',
    });

    final loaded = await const DesktopShellEnvironmentReportStore().load();

    expect(loaded, isNull);
  });

  test('store resets saved environment report', () async {
    SharedPreferences.setMockInitialValues({
      DesktopShellEnvironmentReportStore.keyReport: jsonEncode({
        'schema': 'bridge.desktop.shell.environment.v1',
        'summary': 'saved',
        'items': const [],
      }),
    });

    const store = DesktopShellEnvironmentReportStore();
    expect(await store.load(), isNotNull);

    await store.reset();

    expect(await store.load(), isNull);
  });
}
