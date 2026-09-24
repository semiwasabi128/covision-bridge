/// BridgeTransport — 連線層抽象介面
///
/// 定義手機與桌面之間的通訊契約，讓未來可以插不同底層。
/// 目前實作：LanWebSocketTransport（S20）
/// 未來實作：RemoteTunnelTransport, 使用者toothRelayTransport（S22+）
///
/// Sprint 16 建立，S20 接入實作。
abstract class BridgeTransport {
  /// 連線狀態變化 stream
  Stream<BridgeConnectionState> get connectionState;

  /// 目前是否已連線且 ready
  bool get isConnected;

  /// 連線到桌面端點
  Future<void> connect(BridgeEndpoint endpoint);

  /// 斷線
  Future<void> disconnect();

  /// 發送請求並等待回應
  Future<BridgeResponse> send(BridgeRequest request);

  /// 監聽桌面主動推播（任務完成、通知、記憶更新等）
  Stream<BridgePushMessage> get pushStream;
}

/// 連線端點描述
class BridgeEndpoint {
  final String host;
  final int port;
  final String? pairingCode;
  final TransportType type;

  const BridgeEndpoint({
    required this.host,
    required this.port,
    this.pairingCode,
    required this.type,
  });
}

/// 傳輸類型
enum TransportType {
  lan,       // 區域網路 WebSocket（已實作）
  remote,    // 遠端隧道（未來）
  bluetooth, // 藍牙中繼（未來）
}

/// 連線狀態
enum BridgeConnectionState {
  disconnected,
  connecting,
  handshaking,
  ready,
  error,
}

/// 請求模型
class BridgeRequest {
  final String command;
  final Map<String, dynamic> payload;

  const BridgeRequest({required this.command, this.payload = const {}});
}

/// 回應模型
class BridgeResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  const BridgeResponse({
    required this.success,
    this.data,
    this.error,
  });

  factory BridgeResponse.ok(Map<String, dynamic> data) =>
      BridgeResponse(success: true, data: data);

  factory BridgeResponse.fail(String error) =>
      BridgeResponse(success: false, error: error);
}

/// 桌面主動推播給手機的訊息
class BridgePushMessage {
  final String type;
  final Map<String, dynamic> payload;

  const BridgePushMessage({required this.type, this.payload = const {}});
}
