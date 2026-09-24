// swarm_muster.dart
// [TRIO M5b 2026-09-23] 羅盤出陣登記——一戰役一筆（Blue 令：統一性質，不逐兵）
//
// 儀式（輕量版）：群任務 → 羅盤 → 領工具包+藥包 → 出陣。
// 登記 = compass_meta 一筆 JSON：
//   key: 'swarm_muster_<campaignId>'
//   value: {objective, endpoint, toolkit, medkit, registeredAt, byHuman}
// swarm_open 的 G0 檢查：無登記 → 擋（「先去羅盤領裝備」）。
library;

import 'dart:convert';
import 'package:bridge_app/services/compass/compass_store.dart';

/// 一筆出陣登記
class SwarmMuster {
  final String campaignId;
  final String objective;
  final String endpoint;
  final String toolkit; // 工具包描述（領了什麼工具）
  final String medkit; // 藥包（預備方案/停損線）
  final DateTime registeredAt;
  final String byHuman; // 誰批准出陣（Blue）

  const SwarmMuster({
    required this.campaignId,
    required this.objective,
    required this.endpoint,
    required this.toolkit,
    required this.medkit,
    required this.registeredAt,
    required this.byHuman,
  });

  Map<String, dynamic> toJson() => {
        'campaignId': campaignId,
        'objective': objective,
        'endpoint': endpoint,
        'toolkit': toolkit,
        'medkit': medkit,
        'registeredAt': registeredAt.toIso8601String(),
        'byHuman': byHuman,
      };

  factory SwarmMuster.fromJson(Map<String, dynamic> j) => SwarmMuster(
        campaignId: j['campaignId'] as String,
        objective: j['objective'] as String? ?? '',
        endpoint: j['endpoint'] as String? ?? '',
        toolkit: j['toolkit'] as String? ?? '',
        medkit: j['medkit'] as String? ?? '',
        registeredAt:
            DateTime.tryParse(j['registeredAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        byHuman: j['byHuman'] as String? ?? 'unknown',
      );
}

/// 出陣登記簿（羅盤的一頁）
class SwarmMusterRoll {
  SwarmMusterRoll._();
  static SwarmMusterRoll? _instance;
  static SwarmMusterRoll get instance => _instance ??= SwarmMusterRoll._();

  static const _keyPrefix = 'swarm_muster_';

  String _key(String campaignId) => '$_keyPrefix$campaignId';

  /// 登記出陣（一戰役一筆——重複登記=更新）
  Future<SwarmMuster> register({
    required String campaignId,
    required String objective,
    required String endpoint,
    required String toolkit,
    required String medkit,
    required String byHuman,
  }) async {
    final m = SwarmMuster(
      campaignId: campaignId,
      objective: objective,
      endpoint: endpoint,
      toolkit: toolkit,
      medkit: medkit,
      registeredAt: DateTime.now(),
      byHuman: byHuman,
    );
    await CompassStore.instance.initialize();
    CompassStore.instance
        .setMeta(_key(campaignId), jsonEncode(m.toJson()));
    return m;
  }

  /// 查登記（G0 檢查用）——null = 未領裝備
  SwarmMuster? lookup(String campaignId) {
    try {
      final raw = CompassStore.instance.getMeta(_key(campaignId));
      if (raw == null || raw.isEmpty) return null;
      return SwarmMuster.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // 查不到=未登記（fail-closed——出陣要明確登記過）
    }
  }

  /// 註銷（戰役結案後清——保持羅盤不積灰）
  Future<void> unregister(String campaignId) async {
    await CompassStore.instance.initialize();
    CompassStore.instance.setMeta(_key(campaignId), '');
  }
}
