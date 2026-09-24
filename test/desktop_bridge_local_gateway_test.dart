import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/desktop_bridge_gateway_protocol.dart';
import 'package:bridge_app/services/desktop_bridge_local_gateway.dart';
import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serves hello and runtime snapshot over loopback websocket', () async {
    final contract = _contract();
    final gateway = const DesktopBridgeLocalGateway();
    final handle = await gateway.start(
      pairingContract: contract,
      runtimePayloadProvider: _runtimePayload,
      config: const DesktopBridgeLocalGatewayConfig(port: 0),
    );
    addTearDown(handle.close);

    final socket = await WebSocket.connect(handle.endpoint.toString());
    addTearDown(socket.close);
    final messages = StreamIterator(socket);
    addTearDown(messages.cancel);

    socket.add(
      jsonEncode(
        DesktopBridgeGatewayRequest(
          id: 'hello-1',
          type: DesktopBridgeGatewayMessageType.hello,
          payload: {'pairingCode': contract.pairingCode},
        ).toJson(),
      ),
    );
    expect(await messages.moveNext(), isTrue);
    final hello = jsonDecode(messages.current as String) as Map;
    expect(hello['ok'], isTrue);
    expect(hello['type'], 'hello');
    expect(hello['payload']['runtimeChannel'], 'bridge.runtime.v1');

    socket.add(
      jsonEncode(
        const DesktopBridgeGatewayRequest(
          id: 'runtime-1',
          type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
        ).toJson(),
      ),
    );
    expect(await messages.moveNext(), isTrue);
    final runtime = jsonDecode(messages.current as String) as Map;
    expect(runtime['ok'], isTrue);
    expect(
      runtime['payload']['schema'],
      'bridge.desktop.gateway.runtime_snapshot.v1',
    );
    expect(
      runtime['payload']['runtimePayload']['runtime']['activeCompanionName'],
      '星槌',
    );
  });

  test('rejects non websocket requests on the bridge path', () async {
    final gateway = const DesktopBridgeLocalGateway();
    final handle = await gateway.start(
      pairingContract: _contract(),
      runtimePayloadProvider: _runtimePayload,
      config: const DesktopBridgeLocalGatewayConfig(port: 0),
    );
    addTearDown(handle.close);

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: handle.endpoint.host,
        port: handle.port,
        path: '/bridge',
      ),
    );
    final response = await request.close();

    expect(response.statusCode, HttpStatus.upgradeRequired);
  });

  // [小葵 2026-09-24 開源安全域] 攻擊面鎖：未配對連線跳過 hello 直送 taskRun，
  // 必須收到 error 回應且連線被關閉（配對閘門）。
  test('rejects unpaired socket that skips hello and sends taskRun', () async {
    final contract = _contract();
    final gateway = const DesktopBridgeLocalGateway();
    final handle = await gateway.start(
      pairingContract: contract,
      runtimePayloadProvider: _runtimePayload,
      config: const DesktopBridgeLocalGatewayConfig(port: 0),
    );
    addTearDown(handle.close);

    final socket = await WebSocket.connect(handle.endpoint.toString());
    addTearDown(socket.close);

    // 不送 hello，直接送 taskRun——舊版會被執行，新版必須被擋
    socket.add(
      jsonEncode(
        const DesktopBridgeGatewayRequest(
          id: 'attack-1',
          type: DesktopBridgeGatewayMessageType.taskRun,
          payload: {'task': 'steal_data'},
        ).toJson(),
      ),
    );

    // 第一個回應必須是 error（Pairing required...）
    final messages = StreamIterator(socket);
    addTearDown(messages.cancel);
    expect(await messages.moveNext(), isTrue);
    final reply = jsonDecode(messages.current as String) as Map;
    expect(reply['ok'], isFalse);
    expect(reply['error'], contains('Pairing required'));

    // 之後連線必須已被伺服器關閉——沒有第二則回應
    expect(await messages.moveNext(), isFalse);
  });

  // [小葵 2026-09-24 開源安全域] 錯誤配對碼也必須被擋
  test('rejects hello with wrong pairing code', () async {
    final contract = _contract();
    final gateway = const DesktopBridgeLocalGateway();
    final handle = await gateway.start(
      pairingContract: contract,
      runtimePayloadProvider: _runtimePayload,
      config: const DesktopBridgeLocalGatewayConfig(port: 0),
    );
    addTearDown(handle.close);

    final socket = await WebSocket.connect(handle.endpoint.toString());
    addTearDown(socket.close);

    socket.add(
      jsonEncode(
        const DesktopBridgeGatewayRequest(
          id: 'attack-2',
          type: DesktopBridgeGatewayMessageType.hello,
          payload: {'pairingCode': 'BRIDGE-000000'},
        ).toJson(),
      ),
    );

    final messages = StreamIterator(socket);
    addTearDown(messages.cancel);
    expect(await messages.moveNext(), isTrue);
    final reply = jsonDecode(messages.current as String) as Map;
    expect(reply['ok'], isFalse);
    // _hello 的協議層錯誤（配對碼不符）也走閘門：不 admitted、下一則訊息關線
    socket.add(
      jsonEncode(
        const DesktopBridgeGatewayRequest(
          id: 'attack-3',
          type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
        ).toJson(),
      ),
    );
    expect(await messages.moveNext(), isFalse);
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
