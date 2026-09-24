// lan_ip_detector.dart
// 偵測桌面端在區域網路中的實際 IP 位址，讓手機可以連入。
// Sprint 15a by 教練 Agent (CEO)

import 'dart:io';

/// 偵測本機在區域網路中的 IPv4 位址。
///
/// 遍歷所有網路介面，找到第一個非 loopback 的 IPv4 位址。
/// 回傳 null 如果找不到（例如沒有連上任何網路）。
class LanIpDetector {
  const LanIpDetector();

  /// 回傳第一個可用的 LAN IPv4 位址。
  Future<String?> detectLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // 過濾 link-local (169.254.x.x)
          if (!addr.isLinkLocal && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // ignore — 環境不支援
    }
    return null;
  }

  /// 回傳所有可用的 LAN IPv4 位址（多網卡環境）。
  Future<List<String>> detectAllLanIps() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLinkLocal && addr.type == InternetAddressType.IPv4) {
            result.add(addr.address);
          }
        }
      }
    } catch (_) {
      // ignore
    }
    return result;
  }
}
