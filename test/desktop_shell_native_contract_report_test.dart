import 'dart:io';

import 'package:bridge_app/services/desktop_shell_native_contract_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes current macOS Runner native bridge contract', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    final report = const DesktopShellNativeContractReportService()
        .inspectSource(source);

    expect(report.schema, 'bridge.desktop.shell.native_contract.v1');
    expect(report.canRunNativeBridgeContract, isTrue);
    expect(report.blockedCount, 0);
    expect(report.items.map((item) => item.id), contains('method-inspect'));
    expect(report.items.map((item) => item.id), contains('method-syncRuntime'));
    expect(
      report.items.map((item) => item.id),
      contains('method-hardwareProfile'),
    );
    expect(
      report.items.map((item) => item.id),
      contains('snapshot-statusText'),
    );
    expect(
      report.items.map((item) => item.id),
      contains('command-window.always-on-top'),
    );
    expect(report.toJson()['readyCount'], report.items.length);
  });

  test('reports missing required native contract token', () {
    final report = const DesktopShellNativeContractReportService()
        .inspectSource('''
import Cocoa
class MainFlutterWindow {}
''');

    expect(report.canRunNativeBridgeContract, isFalse);
    expect(report.blockedCount, greaterThan(1));
    expect(
      report.items.firstWhere((item) => item.id == 'method-channel').detail,
      contains('bridge.desktop_shell.macos.v1'),
    );
  });
}
