// lib/services/image_provider_resolver.dart
//
// [教練 Agent 2026-08-12] 圖像生成模型自動選擇器
//
// 從 golden_keys（已解鎖的 API provider）自動挑選最高階的圖像生成 adapter。
// 用戶不需要在召喚流程選模型——我們直接用他已經付費/有額度的最佳選擇。
//
// 優先順序（由高到低）：
//   1. OpenAI（gpt-image-2）— 品質最強、最一致
//   2. MiniMax（image-01）— 第二強，支援透明背景
//   3. Replicate（Flux Pro 等）— 開源靈活
//   4. Gemini（Imagen）— 備用
//
// 如果最高階的 adapter 沒有 token，自動降級到下一個。
// BridgeActionExecutor 本身已有失敗 fallback 機制，所以這裡只要決定「起點」即可。

import 'package:flutter/foundation.dart';

import 'bridge_adapters/bridge_adapter_registry.dart';
import '../models/bridge_action.dart';
import 'storage_service.dart';

class ResolvedImageModel {
  final String providerId;
  final String adapterName;
  final String defaultModel;
  final String quality;
  final String description;
  final int priorityRank; // 1 = 最高階

  const ResolvedImageModel({
    required this.providerId,
    required this.adapterName,
    required this.defaultModel,
    required this.quality,
    required this.description,
    required this.priorityRank,
  });
}

class _ProviderImageConfig {
  final String model;
  final String quality;
  final String description;
  const _ProviderImageConfig({
    required this.model,
    required this.quality,
    required this.description,
  });
}

class ImageProviderResolver {
  static const _priority = [
    'openai',     // gpt-image-2
    'minimax',    // image-01
    'replicate',  // Flux Pro
    'gemini',     // Imagen
  ];

  /// Provider ID → 該 provider 的最高階圖像模型 + 描述
  /// [教練 Agent 2026-08-12] 集中管理模型名稱，避免散落在各處
  static const Map<String, _ProviderImageConfig> _providerConfig = {
    'openai': _ProviderImageConfig(
      model: 'gpt-image-2',
      // [小葵 2026-09-14] 預設畫質 high→low：9/13 事件 16 張探索期形象圖
      // 全以 high 計費（≈$3）。探索期 low，定稿由 UI 手動指定 high。
      quality: 'low',
      description: 'OpenAI 最新圖像引擎，品質最強、支援透明背景。探索期以低畫質篩選，定稿可切高畫質。',
    ),
    'minimax': _ProviderImageConfig(
      model: 'image-01',
      quality: 'high',
      description: 'MiniMax 圖像生成，支援角色一致性、1024×1024。',
    ),
    'replicate': _ProviderImageConfig(
      model: 'black-forest-labs/flux-1.1-pro',
      quality: 'high',
      description: 'Replicate Flux Pro，開源高品質、社群模型可選。',
    ),
    'gemini': _ProviderImageConfig(
      model: 'imagen-3.0-generate-002',
      quality: 'high',
      description: 'Google Imagen 3，整合搜尋與推理理解。',
    ),
  };

  /// 回傳所有有 token 的 image adapter（按優先級排序）。
  /// 用於 UI 讓用戶選擇。
  static Future<List<ResolvedImageModel>> resolveAll({
    BridgeAdapterRegistry? registry,
  }) async {
    final reg = registry ?? BridgeAdapterRegistry();
    final candidates = reg.adaptersFor(BridgeActionType.generateImage);

    final available = <ResolvedImageModel>[];
    for (final adapter in candidates) {
      final providerId = adapter.id;
      final config = _providerConfig[providerId];
      if (config == null) continue;
      final token = await StorageService.getToken(provider: providerId);
      if (token == null || token.trim().isEmpty) continue;
      final rank = _priority.indexOf(providerId) + 1;
      available.add(ResolvedImageModel(
        providerId: providerId,
        adapterName: adapter.displayName,
        defaultModel: config.model,
        quality: config.quality,
        description: config.description,
        priorityRank: rank,
      ));
    }

    available.sort((a, b) => a.priorityRank.compareTo(b.priorityRank));
    return available;
  }

  /// 回傳最高優先級的 image adapter（便捷方法）。
  static Future<ResolvedImageModel?> resolve({
    BridgeAdapterRegistry? registry,
  }) async {
    final reg = registry ?? BridgeAdapterRegistry();
    final candidates = reg.adaptersFor(BridgeActionType.generateImage);

    final available = <ResolvedImageModel>[];
    for (final adapter in candidates) {
      final providerId = adapter.id;
      final config = _providerConfig[providerId];
      if (config == null) continue; // 不在我們的圖像 provider 白名單
      final token = await StorageService.getToken(provider: providerId);
      if (token == null || token.trim().isEmpty) continue;
      final rank = _priority.indexOf(providerId) + 1;
      available.add(ResolvedImageModel(
        providerId: providerId,
        adapterName: adapter.displayName,
        defaultModel: config.model,
        quality: config.quality,
        description: config.description,
        priorityRank: rank,
      ));
    }

    if (available.isEmpty) {
      debugPrint('[ImageProviderResolver] 沒有任何 image adapter 有 token');
      return null;
    }

    // 依優先級排序
    available.sort((a, b) => a.priorityRank.compareTo(b.priorityRank));
    final chosen = available.first;
    debugPrint(
      '[ImageProviderResolver] 選擇 ${chosen.providerId} · ${chosen.defaultModel} '
      '(rank ${chosen.priorityRank}/${available.length})',
    );
    return chosen;
  }
}