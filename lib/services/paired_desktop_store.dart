// paired_desktop_store.dart
// 持久化已配對的桌面端資訊。
// Sprint 15a by 教練 Agent (CEO)

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 一台已配對的 Bridge Desktop。
class PairedDesktop {
  final String id; // 用 host+port hash
  final String host;
  final int port;
  final String pairingCode;
  final String desktopName;
  final DateTime pairedAt;

  const PairedDesktop({
    required this.id,
    required this.host,
    required this.port,
    required this.pairingCode,
    required this.desktopName,
    required this.pairedAt,
  });

  String get endpoint => 'ws://$host:$port/bridge';

  factory PairedDesktop.fromJson(Map<String, dynamic> json) {
    return PairedDesktop(
      id: json['id'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 8790,
      pairingCode: json['pairingCode'] as String? ?? '',
      desktopName: json['desktopName'] as String? ?? 'Bridge Desktop',
      pairedAt: json['pairedAt'] != null
          ? DateTime.parse(json['pairedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host,
        'port': port,
        'pairingCode': pairingCode,
        'desktopName': desktopName,
        'pairedAt': pairedAt.toIso8601String(),
      };

  static String makeId(String host, int port) =>
      '${host}_$port';
}

/// 管理 SharedPreferences 裡的已配對桌面清單。
class PairedDesktopStore {
  static const _key = 'bridge_paired_desktops';

  static Future<List<PairedDesktop>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PairedDesktop.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(PairedDesktop desktop) async {
    final all = await getAll();
    all.removeWhere((d) => d.id == desktop.id);
    all.add(desktop);
    await _writeAll(all);
  }

  static Future<void> remove(String id) async {
    final all = await getAll();
    all.removeWhere((d) => d.id == id);
    await _writeAll(all);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _writeAll(List<PairedDesktop> desktops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(desktops.map((d) => d.toJson()).toList()),
    );
  }
}
