import 'dart:convert';

import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = DesktopBridgePairingContractService();

  test('builds a stable pairing contract draft for app and desktop', () {
    final contract = service.buildContract(
      config: const DesktopCompanionShellConfig(),
      environmentReport: const DesktopShellEnvironmentReportService()
          .previewReport(),
      nativeShellConnected: false,
      generatedAt: DateTime.utc(2026, 6, 3, 10),
    );

    expect(contract.readyForMobilePairing, isFalse);
    expect(contract.label, '配對契約草案已建立');
    expect(contract.pairingCode, startsWith('BRIDGE-'));
    expect(contract.toJson()['schema'], 'bridge.desktop.pairing_contract.v1');
    expect(contract.toPrettyJson(), contains('ws://127.0.0.1:8790/bridge'));
  });

  test('waits for local gateway after native shell connects', () {
    final contract = service.buildContract(
      config: const DesktopCompanionShellConfig(),
      environmentReport: const DesktopShellEnvironmentReportService()
          .fromSignals(
            flutterAvailable: true,
            fullXcodeAvailable: true,
            swiftParsePassed: true,
            macosBuildPassed: true,
          ),
      nativeShellConnected: true,
      generatedAt: DateTime.utc(2026, 6, 3, 10),
    );

    expect(contract.readyForMobilePairing, isFalse);
    expect(contract.label, '等待本機 Gateway 啟動');
    expect(contract.nextAction, contains('本機 Gateway'));
  });

  test(
    'marks mobile pairing ready when native shell and gateway are ready',
    () {
      final contract = service.buildContract(
        config: const DesktopCompanionShellConfig(
          runtimeChannel: 'bridge.test',
        ),
        environmentReport: const DesktopShellEnvironmentReportService()
            .fromSignals(
              flutterAvailable: true,
              fullXcodeAvailable: true,
              swiftParsePassed: true,
              macosBuildPassed: true,
            ),
        nativeShellConnected: true,
        localGatewayReady: true,
        pairingCode: 'BRIDGE-123456',
        generatedAt: DateTime.utc(2026, 6, 3, 10),
      );

      expect(contract.readyForMobilePairing, isTrue);
      expect(contract.label, '可進行手機配對');
      final json = jsonDecode(contract.toPrettyJson()) as Map<String, dynamic>;
      expect(json['transport']['pairingCode'], 'BRIDGE-123456');
      expect(json['runtimeChannel'], 'bridge.test');
    },
  );
}
