import 'package:bridge_app/services/desktop_bridge_gateway_protocol.dart';
import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const protocol = DesktopBridgeGatewayProtocol();

  test('accepts hello request when pairing code matches', () {
    final contract = _contract();
    final response = protocol.handleRequest(
      request: DesktopBridgeGatewayRequest(
        id: 'req-1',
        type: DesktopBridgeGatewayMessageType.hello,
        payload: {'pairingCode': contract.pairingCode},
      ),
      pairingContract: contract,
      runtimePayload: _runtimePayload(),
    );

    expect(response.ok, isTrue);
    expect(response.type, DesktopBridgeGatewayMessageType.hello);
    expect(response.payload['schema'], 'bridge.desktop.gateway.hello.v1');
    expect(response.payload['runtimeChannel'], 'bridge.runtime.v1');
  });

  test('rejects hello request when pairing code does not match', () {
    final response = protocol.handleRequest(
      request: const DesktopBridgeGatewayRequest(
        id: 'req-2',
        type: DesktopBridgeGatewayMessageType.hello,
        payload: {'pairingCode': 'BRIDGE-WRONG'},
      ),
      pairingContract: _contract(),
      runtimePayload: _runtimePayload(),
    );

    expect(response.ok, isFalse);
    expect(response.error, contains('Pairing code'));
  });

  test('returns runtime snapshot for paired client', () {
    final response = protocol.handleRequest(
      request: const DesktopBridgeGatewayRequest(
        id: 'req-3',
        type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
      ),
      pairingContract: _contract(),
      runtimePayload: _runtimePayload(),
    );

    expect(response.ok, isTrue);
    expect(
      response.payload['schema'],
      'bridge.desktop.gateway.runtime_snapshot.v1',
    );
    final runtimePayload = response.payload['runtimePayload'] as Map;
    expect(runtimePayload['schema'], 'bridge.companion.runtime.v1');
  });

  test('parses unknown request type as unsupported gateway error', () {
    final request = DesktopBridgeGatewayRequest.fromJson({
      'id': 'req-4',
      'type': 'unknownFutureType',
    });
    final response = protocol.handleRequest(
      request: request,
      pairingContract: _contract(),
      runtimePayload: _runtimePayload(),
    );

    expect(response.ok, isFalse);
    expect(response.type, DesktopBridgeGatewayMessageType.error);
  });
}

DesktopBridgePairingContract _contract() {
  return const DesktopBridgePairingContractService().buildContract(
    config: DesktopCompanionShellConfig(),
    environmentReport: DesktopShellEnvironmentReportService().fromSignals(
      flutterAvailable: true,
      fullXcodeAvailable: true,
      swiftParsePassed: true,
      macosBuildPassed: true,
    ),
    nativeShellConnected: true,
    localGatewayReady: true,
    generatedAt: DateTime.utc(2026, 6, 3, 10),
  );
}

Map<String, dynamic> _runtimePayload() {
  return {
    'schema': 'bridge.companion.runtime.v1',
    'runtime': {'activeCompanionName': '星槌', 'statusText': '自由待機'},
  };
}
