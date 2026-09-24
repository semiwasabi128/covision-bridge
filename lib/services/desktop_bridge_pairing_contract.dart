import 'dart:convert';
import 'dart:math';

import 'desktop_companion_shell_config.dart';
import 'desktop_shell_environment_report.dart';

enum DesktopBridgePairingCapabilityStatus { ready, pending, blocked }

class DesktopBridgePairingCapability {
  final String id;
  final String label;
  final String detail;
  final DesktopBridgePairingCapabilityStatus status;

  const DesktopBridgePairingCapability({
    required this.id,
    required this.label,
    required this.detail,
    required this.status,
  });

  Map<String, Object> toJson() {
    return {'id': id, 'label': label, 'detail': detail, 'status': status.name};
  }
}

class DesktopBridgePairingContract {
  final DateTime generatedAt;
  final String desktopName;
  final String runtimeChannel;
  final String localGatewayEndpoint;
  final String pairingCode;
  final bool nativeShellConnected;
  final bool localGatewayReady;
  final List<DesktopBridgePairingCapability> capabilities;

  const DesktopBridgePairingContract({
    required this.generatedAt,
    required this.desktopName,
    required this.runtimeChannel,
    required this.localGatewayEndpoint,
    required this.pairingCode,
    required this.nativeShellConnected,
    required this.localGatewayReady,
    required this.capabilities,
  });

  bool get readyForMobilePairing => nativeShellConnected && localGatewayReady;

  int get readyCount => capabilities
      .where(
        (item) => item.status == DesktopBridgePairingCapabilityStatus.ready,
      )
      .length;

  int get blockedCount => capabilities
      .where(
        (item) => item.status == DesktopBridgePairingCapabilityStatus.blocked,
      )
      .length;

  String get label {
    if (readyForMobilePairing) return '可進行手機配對';
    if (nativeShellConnected) return '等待本機 Gateway 啟動';
    if (blockedCount > 0) return '桌面環境需補齊';
    return '配對契約草案已建立';
  }

  String get nextAction {
    if (readyForMobilePairing) {
      return '手機 App 可讀取此配對契約，連到 Bridge Desktop Gateway。';
    }
    if (nativeShellConnected) {
      return '下一步接上 Bridge Desktop 內建本機 Gateway，讓手機端可以連入。';
    }
    if (blockedCount > 0) {
      return '先補齊桌面原生環境，再啟動 macOS Runner 與本機 Gateway。';
    }
    return '保留此契約格式，接著完成桌面端原生連線與本機 Gateway。';
  }

  Map<String, Object?> toJson() {
    return {
      'schema': 'bridge.desktop.pairing_contract.v1',
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'desktopName': desktopName,
      'label': label,
      'nextAction': nextAction,
      'runtimeChannel': runtimeChannel,
      'transport': {
        'localGatewayEndpoint': localGatewayEndpoint,
        'pairingCode': pairingCode,
        'nativeShellConnected': nativeShellConnected,
        'localGatewayReady': localGatewayReady,
        'readyForMobilePairing': readyForMobilePairing,
      },
      'summary': {
        'capabilities': capabilities.length,
        'ready': readyCount,
        'blocked': blockedCount,
      },
      'capabilities': [for (final item in capabilities) item.toJson()],
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

class DesktopBridgePairingContractService {
  const DesktopBridgePairingContractService();

  DesktopBridgePairingContract buildContract({
    required DesktopCompanionShellConfig config,
    required DesktopShellEnvironmentReport environmentReport,
    required bool nativeShellConnected,
    DateTime? generatedAt,
    String desktopName = 'Bridge Desktop',
    String localGatewayEndpoint = 'ws://127.0.0.1:8790/bridge',
    String? pairingCode,
    bool localGatewayReady = false,
  }) {
    return DesktopBridgePairingContract(
      generatedAt: generatedAt ?? DateTime.now().toUtc(),
      desktopName: desktopName,
      runtimeChannel: config.runtimeChannel,
      localGatewayEndpoint: localGatewayEndpoint,
      pairingCode: pairingCode ?? _pairingCodeFor(config.runtimeChannel),
      nativeShellConnected: nativeShellConnected,
      localGatewayReady: localGatewayReady,
      capabilities: [
        DesktopBridgePairingCapability(
          id: 'runtime-channel',
          label: 'Runtime Channel',
          detail: '同步夥伴狀態、表情、行為與工作文字。',
          status: DesktopBridgePairingCapabilityStatus.ready,
        ),
        DesktopBridgePairingCapability(
          id: 'native-shell',
          label: 'Native Shell',
          detail: nativeShellConnected
              ? 'macOS MethodChannel 已接上桌面外殼。'
              : '等待 macOS Runner 啟動並接上 MethodChannel。',
          status: nativeShellConnected
              ? DesktopBridgePairingCapabilityStatus.ready
              : environmentReport.blockedCount > 0
              ? DesktopBridgePairingCapabilityStatus.blocked
              : DesktopBridgePairingCapabilityStatus.pending,
        ),
        DesktopBridgePairingCapability(
          id: 'local-gateway',
          label: 'Local Gateway',
          detail: localGatewayReady
              ? '本機 Gateway 已可接受手機 App 連線。'
              : 'WebSocket Gateway 已可 smoke 驗證，等待接入常駐桌面流程。',
          status: localGatewayReady
              ? DesktopBridgePairingCapabilityStatus.ready
              : DesktopBridgePairingCapabilityStatus.pending,
        ),
        const DesktopBridgePairingCapability(
          id: 'pairing-contract',
          label: 'Pairing Contract',
          detail: '手機端、桌面端與未來穿戴裝置共用同一份配對封包格式。',
          status: DesktopBridgePairingCapabilityStatus.ready,
        ),
        // Sprint 19d: 新增 browser.automation 和 long_task.run 能力項
        DesktopBridgePairingCapability(
          id: 'browser.automation',
          label: 'Browser Automation',
          detail: '可用 Chrome 自動化操作網頁（導航、填表、截圖、下載）。',
          status: DesktopBridgePairingCapabilityStatus.ready,
        ),
        DesktopBridgePairingCapability(
          id: 'long_task.run',
          label: 'Long Task Runner',
          detail: '可在桌面端執行長任務，進度即時推播到手機。',
          status: DesktopBridgePairingCapabilityStatus.ready,
        ),
      ],
    );
  }

  /// [小葵 2026-09-24 開源安全域] 舊版＝runtimeChannel 的確定性雜湊——
  /// runtimeChannel 是公開常數，開源後任何人都能算出配對碼。
  /// 改 Random.secure()：每次建約都產生不可預測的隨機碼（格式 BRIDGE-XXXXXX 不變，
  /// 手機端輸入框 hint / QR 掃碼不受影響）。
  String _pairingCodeFor(String runtimeChannel) {
    final rnd = Random.secure();
    final code = List.generate(6, (_) => rnd.nextInt(10)).join();
    return 'BRIDGE-$code';
  }
}
