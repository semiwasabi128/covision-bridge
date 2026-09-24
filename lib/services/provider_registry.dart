/// ProviderRegistry — 動態 Provider 探測 + 能力排序 + URL 統一管理
///
/// [教練 Agent 2026-07-30] ProviderRegistry 重構 Step 1
///
/// 取代散落在 5 個檔案中的硬編碼 brand→URL / brand→model 映射表。
/// 核心職責：
///   1. 維護唯一一份 provider 元數據表（brand→baseUrl, displayName, emoji）
///   2. 掃描 StorageService 已設定的金鑰，動態探測可用 provider
///   3. 拉取每個有金鑰的 provider 的可用模型列表（透過 ApiService.testConnectionWith）
///   4. 按 ProviderProfileStore 的 Tier 排序，回傳最強大腦
///   5. 提供 provider→baseUrl 查詢（唯一一份 URL 表）
///
/// 不負責：
///   - 路由判斷（本地 vs 雲端）→ 仍由 ProviderRouter 負責
///   - IntentSpine 分析 → 仍由 IntentSpine 負責
///   - API 呼叫 → 仍由 ApiService 負責
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'agent_loop/agent_profile_store.dart';
import 'agent_loop/agent_provider_profile.dart';

// ═══════════════════════════════════════════════════
// 資料模型
// ═══════════════════════════════════════════════════

/// Provider 靜態元數據（唯一的一份 brand→URL 表）
/// [教練 Agent 2026-07-30] 取代散落在 provider_router / agent_model_selector / api_service 的多份硬編碼表
class ProviderMeta {
  final String id;
  final String baseUrl;
  final String displayName;
  final String emoji;
  const ProviderMeta({
    required this.id,
    required this.baseUrl,
    required this.displayName,
    required this.emoji,
  });
}

/// 動態探測結果
class DiscoveredProvider {
  final String providerId;
  final String baseUrl;
  final List<String> availableModels;
  final ProviderTier tier; // 最佳模型的 Tier
  final bool reachable; // API 是否可連

  const DiscoveredProvider({
    required this.providerId,
    required this.baseUrl,
    required this.availableModels,
    required this.tier,
    this.reachable = true,
  });
}

// ═══════════════════════════════════════════════════
// ProviderRegistry
// ═══════════════════════════════════════════════════

class ProviderRegistry {
  static final ProviderRegistry instance = ProviderRegistry._();
  ProviderRegistry._();

  // ═══════════════════════════════════════════════════
  // 唯一的 provider 元數據表（取代 5 份散落的硬編碼表）
  // ═══════════════════════════════════════════════════

  /// Provider 基礎元數據——唯一的一份 brand→URL 映射
  /// 新增 provider 只需在此加一條
  /// [教練 Agent 2026-07-30] 唯一硬編碼來源——其餘地方一律透過 ProviderRegistry 查詢
  static const _providerMeta = <ProviderMeta>[
    ProviderMeta(
      id: 'glm',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      displayName: 'GLM',
      emoji: '🟢',
    ),
    ProviderMeta(
      id: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      displayName: 'OpenAI',
      emoji: '🟦',
    ),
    ProviderMeta(
      id: 'minimax',
      baseUrl: 'https://api.minimaxi.chat/v1',
      displayName: 'MiniMax',
      emoji: '🟡',
    ),
    ProviderMeta(
      id: 'kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      displayName: 'Kimi',
      emoji: '🌙',
    ),
    ProviderMeta(
      id: 'claude',
      baseUrl: 'https://api.anthropic.com/v1',
      displayName: 'Claude',
      emoji: '🟠',
    ),
    ProviderMeta(
      id: 'gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      displayName: 'Gemini',
      emoji: '💎',
    ),
  ];

  /// 所有已註冊的 provider ID（不含 local）
  static List<String> get cloudProviderIds =>
      _providerMeta.map((m) => m.id).toList();

  /// [教練 Agent 2026-07-30] 所有 provider 元數據（含 local）
  /// 取代 agent_model_selector 的 _allProviderInfos
  List<ProviderMeta> allMetas() {
    return [..._providerMeta, _localMeta];
  }

  /// local 模型元數據（不在 _providerMeta 中，因為 local 不是雲端 provider）
  /// [教練 Agent 2026-08-21] local 從單一 id 升級為「本地 runtime 家族」——
  /// LM Studio / Ollama / LMNX 等都走 OpenAI 相容 API，模型列表同格式。
  /// 使用者的 DGX Spark 計畫：橋樑 app 全本地主權方案。
  static const _localRuntimeMetas = <ProviderMeta>[
    ProviderMeta(
      id: 'local', // LM Studio 相容 runtime（預設）
      baseUrl: 'http://127.0.0.1:18789',
      displayName: '本地模型',
      emoji: '💻',
    ),
    ProviderMeta(
      id: 'ollama',
      baseUrl: 'http://127.0.0.1:11434',
      displayName: 'Ollama',
      emoji: '🦙',
    ),
  ];

  /// 舊介面相容：local = LM Studio 相容 runtime（getter——非 const，
  /// 因為 const list 元素引用在舊 SDK 需 runtime init）
  static ProviderMeta get _localMeta => _localRuntimeMetas[0];

  /// 取得 provider 的 base URL（唯一入口，取代 _cloudBaseUrl + _defaultGatewayUrl）
  /// [教練 Agent 2026-07-30] 含 local 模型
  static String? baseUrlOf(String providerId) {
    for (final m in _localRuntimeMetas) {
      if (m.id == providerId) return m.baseUrl;
    }
    for (final m in _providerMeta) {
      if (m.id == providerId) return m.baseUrl;
    }
    return null;
  }

  /// 取得 provider 的顯示資訊（取代 agent_model_selector 的 _allProviderInfos）
  /// [教練 Agent 2026-07-30] 含 local 模型
  static ProviderMeta? metaOf(String providerId) {
    for (final m in _localRuntimeMetas) {
      if (m.id == providerId) return m;
    }
    for (final m in _providerMeta) {
      if (m.id == providerId) return m;
    }
    return null;
  }

  // ═══════════════════════════════════════════════════
  // 動態探測
  // ═══════════════════════════════════════════════════

  /// 探測結果快取（啟動時探測一次，設定頁變更時 invalidate）
  /// [教練 Agent 2026-07-30] TTL 10 分鐘，避免每次 route() 都發 HTTP 請求
  List<DiscoveredProvider>? _discoveredCache;
  DateTime? _discoveredAt;
  static const _cacheTTL = Duration(minutes: 10);

  /// 探測使用者已設定的金鑰，回傳有 token 的 provider 列表
  /// 不拉取模型列表——輕量級，適合快速 fallback 判斷
  Future<List<String>> discoverConfiguredProviders() async {
    final result = <String>[];
    for (final id in cloudProviderIds) {
      final token = await StorageService.getToken(provider: id);
      if (token != null && token.trim().isNotEmpty) {
        result.add(id);
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════
  // [教練 Agent 2026-08-21] 本地 runtime 家族探測——DGX Spark 全本地主權
  // ═══════════════════════════════════════════════════

  /// 本地 runtime 的實際 URL——支援自訂（DGX Spark 在網路另一台主機）
  /// SharedPreferences key: local_runtime_url_<id>
  static Future<String> _resolveLocalBaseUrl(ProviderMeta meta) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString('local_runtime_url_${meta.id}');
    return custom ?? meta.baseUrl;
  }

  /// 本地 runtime 設定自訂 URL（如 DGX Spark 主機 http://192.168.x.x:11434）
  static Future<void> setLocalRuntimeUrl(String id, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_runtime_url_$id', url);
  }

  /// 探測本地 runtime（不靠金鑰——靠 HTTP ping /models）
  /// LM Studio 相容（local）+ Ollama（ollama）
  Future<List<DiscoveredProvider>> discoverLocalRuntimes() async {
    final results = <DiscoveredProvider>[];
    for (final meta in _localRuntimeMetas) {
      final baseUrl = await _resolveLocalBaseUrl(meta);
      try {
        final models = await ApiService.testConnectionWith(baseUrl, '');
        // 命中已知端點但 0 模型——runtime 沿著但沒載模型，仍列出（誠實）
        results.add(DiscoveredProvider(
          providerId: meta.id,
          baseUrl: baseUrl,
          availableModels: models,
          tier: await _bestTierForModels(meta.id, models),
        ));
      } catch (_) {
        // runtime 不在線——正常情況（多數使用者沒裝），靜默
      }
    }
    return results;
  }

  /// 完整探測：金鑰 + 可用模型 + 能力排序
  /// 較重（會發 N 個 HTTP 請求），建議啟動時或設定變更後呼叫
  /// [教練 Agent 2026-07-30] 快取 10 分鐘，避免重複探測
  Future<List<DiscoveredProvider>> discoverAll() async {
    // 快取檢查
    if (_discoveredCache != null && _discoveredAt != null &&
        DateTime.now().difference(_discoveredAt!) < _cacheTTL) {
      return _discoveredCache!;
    }

    final configured = await discoverConfiguredProviders();
    debugPrint('[ProviderRegistry] 探測 ${configured.length} 個 provider');

    final results = <DiscoveredProvider>[];

    for (final providerId in configured) {
      final baseUrl = baseUrlOf(providerId);
      final token = await StorageService.getToken(provider: providerId);
      if (baseUrl == null || token == null) continue;

      try {
        final models = await ApiService.testConnectionWith(baseUrl, token);
        results.add(DiscoveredProvider(
          providerId: providerId,
          baseUrl: baseUrl,
          availableModels: models,
          tier: await _bestTierForModels(providerId, models),
        ));
      } catch (e) {
        // 探測失敗——仍加入列表但標記不可用
        debugPrint('[ProviderRegistry] 探測 $providerId 失敗: $e');
        results.add(DiscoveredProvider(
          providerId: providerId,
          baseUrl: baseUrl,
          availableModels: const [],
          tier: ProviderTier.tier3,
          reachable: false,
        ));
      }
    }

    // 按 Tier 排序：Tier 1 > Tier 2 > Tier 3
    results.sort((a, b) => a.tier.index.compareTo(b.tier.index));

    _discoveredCache = results;
    _discoveredAt = DateTime.now();
    return results;
  }

  /// 選擇最強大腦——回傳能力排序最高的可用 provider
  /// 取代 detectAvailableProvider() 和 _detectCloudProvider()
  /// 對應 Layer 3（雲端高級）
  Future<DiscoveredProvider?> selectBestCloud() async {
    final all = await discoverAll();
    final reachable = all.where((p) => p.reachable).toList();
    return reachable.isNotEmpty ? reachable.first : null;
  }

  /// 依三層架構選擇 provider+model
  /// layer 1=本地, layer 2=雲端快速(Tier 2), layer 3=雲端高級(Tier 1)
  Future<DiscoveredProvider?> selectForLayer(int layer) async {
    switch (layer) {
      case 1:
        // Layer 1: 本地模型——不走雲端探測
        return null; // 由 ProviderRouter 判斷 isLocal
      case 2:
        // Layer 2: 雲端快速——優先 Tier 2，沒有則退化到 Tier 1（降級兼容）
        final all = await discoverAll();
        final reachable = all.where((p) => p.reachable).toList();
        final tier2 = reachable.where((p) => p.tier == ProviderTier.tier2).toList();
        if (tier2.isNotEmpty) return tier2.first;
        // 沒有 Tier 2 → 用 Tier 1 補位
        return reachable.isNotEmpty ? reachable.first : null;
      case 3:
        // Layer 3: 雲端高級——優先 Tier 1，沒有則退化到 Tier 2（升級補位）
        return await selectBestCloud();
      default:
        return await selectBestCloud();
    }
  }

  /// 選擇最強大腦的模型 ID
  /// 取代 ApiService._defaultModel()
  /// [教練 Agent 2026-07-30] 先查動態探測結果，fallback 用 ProviderProfileStore 種子數據
  Future<String?> selectBestModel(String providerId) async {
    final all = await discoverAll();
    final provider = all.where((p) => p.providerId == providerId).firstOrNull;
    if (provider == null || provider.availableModels.isEmpty) {
      // fallback：用 ProviderProfileStore 的種子數據
      return _fallbackModelFor(providerId);
    }
    return _pickBestModel(providerId, provider.availableModels);
  }

  /// Invalidate 快取（設定頁變更後呼叫）
  void invalidate() {
    _discoveredCache = null;
    _discoveredAt = null;
  }

  // ═══════════════════════════════════════════════════
  // 內部方法
  // ═══════════════════════════════════════════════════

  /// 從可用模型列表中，用 ProviderProfileStore 找出最佳 Tier
  /// [教練 Agent 2026-07-30] getProfile 是 async，所以這裡也是 async
  Future<ProviderTier> _bestTierForModels(
      String providerId, List<String> models) async {
    ProviderTier best = ProviderTier.tier3;
    for (final model in models) {
      final profile =
          await ProviderProfileStore.instance.getProfile(providerId, model);
      if (profile.tier.index < best.index) {
        best = profile.tier;
      }
    }
    return best;
  }

  /// 從可用模型列表中選能力最強的模型
  /// [教練 Agent 2026-07-30] getProfile 是 async，所以這裡也是 async
  Future<String> _pickBestModel(
      String providerId, List<String> models) async {
    String? bestModel;
    ProviderTier bestTier = ProviderTier.tier3;
    for (final model in models) {
      final profile =
          await ProviderProfileStore.instance.getProfile(providerId, model);
      if (profile.tier.index < bestTier.index ||
          (profile.tier == bestTier && bestModel == null)) {
        bestTier = profile.tier;
        bestModel = model;
      }
    }
    return bestModel ?? models.first;
  }

  /// Fallback：ProviderProfileStore 種子數據中取 provider 的預設模型
  /// [教練 Agent 2026-07-30] 查 listProfiles，過濾 provider，取 Tier 最低的模型
  Future<String?> _fallbackModelFor(String providerId) async {
    try {
      final all = await ProviderProfileStore.instance.listProfiles();
      final providerProfiles = all.where((p) => p['provider'] == providerId).toList();
      if (providerProfiles.isEmpty) return null;

      // 按 Tier 排序（tier1 < tier2 < tier3）
      providerProfiles.sort((a, b) {
        final tierA = a['tier'] as String? ?? 'tier3';
        final tierB = b['tier'] as String? ?? 'tier3';
        return tierA.compareTo(tierB);
      });

      final model = providerProfiles.first['model'] as String?;
      return model;
    } catch (e) {
      debugPrint('[ProviderRegistry] fallback model 查詢失敗: $e');
      return null;
    }
  }
}
