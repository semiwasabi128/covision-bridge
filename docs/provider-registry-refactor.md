# ProviderRegistry 重構規格文件

> **目標**：消除 Bridge App 中所有硬編碼的 brand→URL / brand→model 映射表，改為動態探測使用者已設定的金鑰、動態拉取可用模型列表、按能力排序選最強大腦。

> **作者**：Hermes Agent（分析產出）
> **日期**：2026-07-30
> **狀態**：Spec — 待審查

---

## 目錄

1. [現狀分析](#1-現狀分析)
2. [ProviderRegistry 設計](#2-providerregistry-設計)
3. [遷移計畫](#3-遷移計畫)
4. [風險評估](#4-風險評估)

---

## 1. 現狀分析

### 1.1 系統架構概覽

Bridge App 目前的 provider 路由分散在 4 個檔案、5 個位置，每處各自維護一份硬編碼映射表。資料流如下：

```
使用者設定金鑰 (StorageService)
        │
        ├──► ProviderRouter._detectCloudProvider()   ← 硬編碼 fallback 順序 A
        │         │
        │         └──► ProviderRouter._cloudBaseUrl() ← 硬編碼 brand→URL 表 #1
        │
        ├──► StorageService.detectAvailableProvider() ← 硬編碼 fallback 順序 B（與 A 不同！）
        │
        ├──► ApiService._defaultModel()               ← 硬編碼 brand→model 表 #2
        │
        └──► AgentModelSelector._defaultGatewayUrl()  ← 硬編碼 brand→URL 表 #3
```

### 1.2 五處硬編碼的位置與問題

---

#### 硬編碼 #1：`provider_router.dart` L246-263 — `_cloudBaseUrl()` brand→URL 映射表

```dart
static String _cloudBaseUrl(String provider) {
  switch (provider) {
    case 'glm':      return 'https://open.bigmodel.cn/api/paas/v4';
    case 'openai':   return 'https://api.openai.com/v1';
    case 'minimax':  return 'https://api.minimax.chat/v1';
    case 'kimi':     return 'https://api.moonshot.cn/v1';
    case 'claude':   return 'https://api.anthropic.com/v1';
    case 'gemini':   return 'https://generativelanguage.googleapis.com/v1beta';
    default:         return 'https://open.bigmodel.cn/api/paas/v4'; // ← 硬編碼 fallback
  }
}
```

**問題**：
- 新增 provider（如 DeepSeek、Qwen）必須修改此 switch
- `default` 分支硬編碼回 GLM URL，若 provider 名拼錯會靜默導向錯誤 endpoint
- 此 URL 不會經過驗證——如果 provider 改了 API 版本路徑（如 GLM 從 v4 改 v5），要改程式碼

---

#### 硬編碼 #2：`api_service.dart` L1016-1036 — `_defaultModel()` brand→model 映射表

```dart
static String _defaultModel(String provider) {
  switch (provider) {
    case 'openai':   return 'gpt-5.4';
    case 'claude':   return 'claude-3-sonnet-20240229';
    case 'gemini':   return 'gemini-1.5-pro';
    case 'minimax':  return 'MiniMax-M2.5';
    case 'local':    return 'llama3.1:8b';
    case 'glm':      return 'glm-5.2';
    case 'kimi':
    default:         return 'kimi-k3';
  }
}
```

**問題**：
- 模型名硬編碼在程式碼裡，provider 發新模型（如 GPT-6、GLM-6）要改程式碼再發版
- 完全不考慮使用者的 API Key 實際能存取哪些模型——可能選了一個 key 沒權限的模型
- 與 `ProviderProfileStore` 的種子數據重複維護模型名（如 `glm-5.2` 出現在兩個地方）
- `claude-3-sonnet-20240229` 已過時，但程式碼不會自動更新

---

#### 硬編碼 #3：`agent_model_selector.dart` L45-64 — `_defaultGatewayUrl()` 又一份 brand→URL 映射表

```dart
String _defaultGatewayUrl(String provider) {
  switch (provider) {
    case 'openai':   return 'https://api.openai.com/v1';
    case 'kimi':     return 'https://api.moonshot.cn/v1';
    case 'minimax':  return 'https://api.minimax.io/v1';   // ← 注意：.io 不是 .chat
    case 'claude':   return 'https://api.anthropic.com/v1';
    case 'gemini':   return 'https://generativelanguage.googleapis.com/v1beta';
    case 'glm':      return 'https://open.bigmodel.cn/api/paas/v4';
    case 'local':    return 'http://127.0.0.1:18789';
    default:         return 'https://api.moonshot.cn/v1';   // ← 又一個不同的 fallback
  }
}
```

**問題**：
- **與 #1 的 URL 不一致**：MiniMax 在 #1 是 `api.minimax.chat`，這裡是 `api.minimax.io`
- **與 #1 的 default 不同**：#1 default 回 GLM，這裡 default 回 Kimi
- 使用者切換 provider 時，`_selectProvider()` 會呼叫 `saveGatewayUrl(_defaultGatewayUrl(provider))`，把這份可能有錯的 URL 寫進 StorageService，覆蓋使用者可能手動設定的 URL
- 這份映射表存在 widget 檔案裡，完全繞過了 service 層

---

#### 硬編碼 #4：`storage_service.dart` L173-186 — `detectAvailableProvider()` fallback 順序

```dart
static Future<String?> detectAvailableProvider() async {
  const providers = ['openai', 'glm', 'kimi', 'minimax', 'gemini', 'claude'];
  for (final p in providers) { ... }
  ...
}
```

**問題**：
- Fallback 順序：`openai > glm > kimi > minimax > gemini > claude`
- 這是品牌偏見，不是能力排序——OpenAI 不一定是最強的（基準測試顯示 GLM-5.2 和 GPT-5.4 同為 Tier 1）
- 使用者可能只有 GLM 的 key，但因為 OpenAI 排第一，`detectAvailableProvider()` 會先檢查 OpenAI（空轉一圈），浪費時間

---

#### 硬編碼 #5：`provider_router.dart` L274 — `_detectCloudProvider()` fallback 順序

```dart
for (final p in ['glm', 'minimax', 'openai', 'kimi', 'anthropic']) { ... }
```

**問題**：
- Fallback 順序：`glm > minimax > openai > kimi > anthropic`
- **與 #4 的順序不同！** #4 是 `openai > glm > kimi > minimax > gemini > claude`
- #5 用 `'anthropic'`，#4 用 `'claude'`——**同一個 provider 用了不同的 ID 字串**，所以 #5 永遠找不到 Claude 的 token（因為 token 存在 `'claude'` 底下）
- ProviderRouter 和 StorageService 各自決定 fallback，結果可能不一致——同一個使用者在不同 code path 被路由到不同 provider

---

### 1.3 核心問題摘要

| 問題 | 影響 |
|------|------|
| **5 份映射表各自維護** | 新增 provider 要改 5 個地方，漏改就出 bug |
| **兩處 URL 表不一致** | MiniMax: `.chat` vs `.io`；default: GLM vs Kimi |
| **兩處 fallback 順序不一致** | StorageService: openai 優先；ProviderRouter: glm 優先 |
| **Claude ID 不一致** | StorageService 用 `'claude'`，ProviderRouter 用 `'anthropic'` |
| **brand→model 硬編碼** | 不探測實際可用模型，可能選到 key 無權限的模型 |
| **secure storage -34018 bug** | ProviderRouter 拿不到 token → fallback 到錯誤 provider |
| **無能力排序** | Fallback 是品牌偏見而非能力排序，違反「選最強大腦」理念 |

---

## 2. ProviderRegistry 設計

### 2.1 設計理念

> **動態路由應該調用當前使用者金鑰設定裡面的最強大腦，而非硬編碼品牌優先順序。**
> **三層分級架構保留（本地／雲端快速／雲端高級），每層的模型動態選擇。**

三個核心原則：
1. **單一真相來源** — 所有 brand→URL、brand→model、provider 順序的知識集中在 `ProviderRegistry` 一處
2. **動態探測** — 掃描使用者已設定的金鑰 → 拉取每個 provider 的 `/v1/models` → 取得實際可用模型
3. **三層能力分級** — 用 `ProviderProfileStore` 的 Tier 資料將模型分到三層，路由層按意圖選層、Registry 在層內選最強

### 2.1.1 三層模型調用架構

| 層級 | 名稱 | ProviderTier | 用途 | 對應 IntentSpineMode |
|------|------|-------------|------|---------------------|
| **Layer 1** | 本地模型 | — (本地) | 閒聊、輕量釐清、快速回應 | `casual`, `clarify`(簡單), `analyze`(簡單) |
| **Layer 2** | 雲端快速 | Tier 2 | 簡單執行、翻譯、摘要、結構化輸出 | `clarify`(複雜), `analyze`(複雜), `execute`(簡單) |
| **Layer 3** | 雲端高級 | Tier 1 | 複雜推理、多步驟 Agent Loop、專案管理 | `execute`(複雜), `project`, `assetReuse`, `capabilitySetup` |

**主大腦 = Layer 3 的最強模型**（使用者鑰匙裡能力最高的那個）。

**設計規則**：
- 使用者只設了一把鑰匙 → 那把就是主大腦，Layer 2 和 Layer 3 都用它（分級仍在，但模型同一個）
- 使用者設了多把鑰匙 → Tier 1 模型走 Layer 3，Tier 2 模型走 Layer 2，各自選最強
- 本地模型在跑 → 自動作為 Layer 1，不受鑰匙影響
- 沒有 Tier 2 模型 → Layer 2 退化到 Layer 3 的模型（降級兼容）
- 沒有 Tier 1 模型 → Layer 3 退化到 Tier 2 最佳模型（升級補位）

### 2.2 ProviderRegistry 類別設計

新檔案：`lib/services/provider_registry.dart`

```dart
/// ProviderRegistry — 單一真相來源，取代所有硬編碼映射表
///
/// 職責：
///   1. 掃描使用者已設定的金鑰（透過 StorageService.getToken）
///   2. 拉取每個有金鑰的 provider 的可用模型列表（透過 ApiService.testConnectionWith）
///   3. 按 ProviderProfileStore 的 Tier 排序，回傳最強大腦
///   4. 提供 provider→baseUrl 查詢（唯一一份 URL 表）
///
/// 不負責：
///   - 路由判斷（本地 vs 雲端）→ 仍由 ProviderRouter 負責
///   - IntentSpine 分析 → 仍由 IntentSpine 負責
///   - API 呼叫 → 仍由 ApiService 負責
class ProviderRegistry {
  static ProviderRegistry instance = ProviderRegistry._();
  ProviderRegistry._();

  // ═══════════════════════════════════════════════════
  // 唯一的 provider 元數據表（取代 5 份散落的硬編碼表）
  // ═══════════════════════════════════════════════════

  /// Provider 基礎元數據——唯一的一份 brand→URL 映射
  /// 新增 provider 只需在此加一條
  static const _providerMetadata = <String, ProviderMeta>{
    'openai': ProviderMeta(
      id: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      displayName: 'GPT',
      emoji: '🤖',
    ),
    'glm': ProviderMeta(
      id: 'glm',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      displayName: '智譜',
      emoji: '🧠',
    ),
    'kimi': ProviderMeta(
      id: 'kimi',
      baseUrl: 'https://api.moonshot.cn/v1',
      displayName: 'Kimi',
      emoji: '🌙',
    ),
    'minimax': ProviderMeta(
      id: 'minimax',
      baseUrl: 'https://api.minimax.io/v1',
      displayName: 'MiniMax',
      emoji: '📊',
    ),
    'gemini': ProviderMeta(
      id: 'gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      displayName: 'Gemini',
      emoji: '✨',
    ),
    'claude': ProviderMeta(
      id: 'claude',
      baseUrl: 'https://api.anthropic.com/v1',
      displayName: 'Claude',
      emoji: '🎭',
    ),
    'local': ProviderMeta(
      id: 'local',
      baseUrl: 'http://127.0.0.1:18789',
      displayName: '本地模型',
      emoji: '💻',
    ),
  };

  /// 所有已註冊的 provider ID（不含 local）
  static List<String> get cloudProviderIds =>
      _providerMetadata.keys.where((id) => id != 'local').toList();

  /// 取得 provider 的 base URL（唯一入口，取代 _cloudBaseUrl + _defaultGatewayUrl）
  static String? baseUrlOf(String providerId) =>
      _providerMetadata[providerId]?.baseUrl;

  /// 取得 provider 的顯示資訊（取代 agent_model_selector 的 _allProviderInfos）
  static ProviderMeta? metaOf(String providerId) =>
      _providerMetadata[providerId];

  // ═══════════════════════════════════════════════════
  // 動態探測
  // ═══════════════════════════════════════════════════

  /// 探測結果快取（啟動時探測一次，設定頁變更時 invalidate）
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

  /// 完整探測：金鑰 + 可用模型 + 能力排序
  /// 較重（會發 N 個 HTTP 請求），建議啟動時或設定變更後呼叫
  Future<List<DiscoveredProvider>> discoverAll() async {
    // 快取檢查
    if (_discoveredCache != null && _discoveredAt != null &&
        DateTime.now().difference(_discoveredAt!) < _cacheTTL) {
      return _discoveredCache!;
    }

    final configured = await discoverConfiguredProviders();
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
          tier: _bestTierForModels(providerId, models),
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
  ProviderTier _bestTierForModels(String providerId, List<String> models) {
    ProviderTier best = ProviderTier.tier3;
    for (final model in models) {
      final profile = await ProviderProfileStore.instance.getProfile(providerId, model);
      if (profile.tier.index < best.index) {
        best = profile.tier;
      }
    }
    return best;
  }

  /// 從可用模型列表中選能力最強的模型
  String _pickBestModel(String providerId, List<String> models) {
    String? bestModel;
    ProviderTier bestTier = ProviderTier.tier3;
    for (final model in models) {
      final profile = await ProviderProfileStore.instance.getProfile(providerId, model);
      if (profile.tier.index < bestTier.index ||
          (profile.tier == bestTier && bestModel == null)) {
        bestTier = profile.tier;
        bestModel = model;
      }
    }
    return bestModel ?? models.first;
  }

  /// Fallback：ProviderProfileStore 種子數據中取 provider 的預設模型
  String? _fallbackModelFor(String providerId) {
    // ProviderProfileStore 種子數據的 key 格式: 'provider_model'
    // 找 Tier 最低的
    // 實作時用 ProviderProfileStore.listProfiles() 過濾
    return null; // 待實作
  }
}

// ═══════════════════════════════════════════════════
// 資料模型
// ═══════════════════════════════════════════════════

/// Provider 靜態元數據（唯一的一份 brand→URL 表）
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
  final ProviderTier tier;      // 最佳模型的 Tier
  final bool reachable;         // API 是否可連

  const DiscoveredProvider({
    required this.providerId,
    required this.baseUrl,
    required this.availableModels,
    required this.tier,
    this.reachable = true,
  });
}
```

### 2.3 資料流（重構後）

```
使用者設定金鑰 (StorageService)
        │
        ▼
ProviderRegistry.discoverAll()
   ├── 掃描 getToken(provider: X) for each X
   ├── testConnectionWith(baseUrl, token) → 取得可用模型
   └── ProviderProfileStore.getProfile() → 計算 Tier → 排序
        │
        ├──► ProviderRouter.route()
        │       └── selectBestCloud() → 取代 _detectCloudProvider() + _cloudBaseUrl()
        │
        ├──► ApiService
        │       └── selectBestModel(provider) → 取代 _defaultModel()
        │
        ├──► AgentModelSelector
        │       └── ProviderRegistry.metaOf() → 取代 _allProviderInfos + _defaultGatewayUrl()
        │
        └──► StorageService.detectAvailableProvider()
                └── 委派 selectBestCloud() → 取代硬編碼順序
```

### 2.4 能力排序邏輯

排序優先級（從高到低）：

1. **Tier 1** — 完整多步驟工具使用（如 GPT-5.4、GLM-5.2）
2. **Tier 2** — 能用工具但需拆分小任務（如 Kimi-K3、MiniMax-M2.5）
3. **Tier 3** — API 不穩或能力不足

同一 Tier 內的 tiebreaker：
- `tested == true` 優先於 `tested == false`
- 可用模型數量多者优先（API 更穩定）
- 最後依 provider ID 字母序（穩定排序，避免非確定性）

### 2.5 與既有系統的整合點

| 既有系統 | 整合方式 |
|----------|----------|
| `ProviderProfileStore` | **不改**——ProviderRegistry 讀取其 Tier 資料做排序 |
| `ProviderProfile` / `ProviderTier` | **不改**——直接複用 enum 和 class |
| `StorageService.getToken()` | **不改**——ProviderRegistry 呼叫它掃描金鑰 |
| `ApiService.testConnectionWith()` | **不改**——ProviderRegistry 呼叫它拉取模型列表 |
| `ProviderRouter` | **改**——刪除 `_cloudBaseUrl()` 和 `_detectCloudProvider()`，改呼叫 ProviderRegistry |
| `ApiService._defaultModel()` | **改**——刪除或改為委派 ProviderRegistry.selectBestModel() |
| `AgentModelSelector` | **改**——刪除 `_defaultGatewayUrl()` 和 `_allProviderInfos`，改讀 ProviderRegistry |
| `StorageService.detectAvailableProvider()` | **改**——委派 ProviderRegistry |

---

## 3. 遷移計畫

### 3.1 檔案變更清單

| 順序 | 檔案 | 動作 | 說明 |
|------|------|------|------|
| 1 | `lib/services/provider_registry.dart` | **新增** | ProviderRegistry + ProviderMeta + DiscoveredProvider |
| 2 | `lib/screens/bridge_desktop_screen.dart` | **修改** | L243: `ProviderRouter.instance.init()` 之後加 `ProviderRegistry.instance.discoverAll()` |
| 3 | `lib/services/storage_service.dart` | **修改** | L173-186: `detectAvailableProvider()` 改為委派 ProviderRegistry |
| 4 | `lib/services/provider_router.dart` | **修改** | 刪 `_cloudBaseUrl()` L246-263；改 `_detectCloudProvider()` L266-279 呼叫 ProviderRegistry |
| 5 | `lib/services/api_service.dart` | **修改** | L1016-1036: `_defaultModel()` 改為 async 委派 ProviderRegistry.selectBestModel() |
| 6 | `lib/widgets/chat/agent_model_selector.dart` | **修改** | 刪 `_defaultGatewayUrl()` L45-64 和 `_allProviderInfos` L26-34，改讀 ProviderRegistry |
| 7 | `lib/services/native_agent_loop.dart` | **修改** | L633-650: `_detectProviderProfile()` 改用 ProviderRegistry 取得 provider + model |

### 3.2 詳細變更

---

#### Step 1：新增 `lib/services/provider_registry.dart`

建立 2.2 節設計的 `ProviderRegistry` 類別。此步驟不影響既有程式碼——新檔案只是加入，沒有被任何地方 import。

**驗收**：`flutter analyze` 通過，無錯誤。

---

#### Step 2：啟動時初始化 ProviderRegistry

`bridge_desktop_screen.dart` L243 之後加入：

```dart
ProviderRouter.instance.init();
// [新增] 動態探測可用 provider + 模型
ProviderRegistry.instance.discoverAll();
```

**驗收**：啟動 app 後 console 可見 `[ProviderRegistry] 探測 N 個 provider` 日誌。

---

#### Step 3：改造 `StorageService.detectAvailableProvider()`

**Before** (L173-186)：
```dart
static Future<String?> detectAvailableProvider() async {
  const providers = ['openai', 'glm', 'kimi', 'minimax', 'gemini', 'claude'];
  for (final p in providers) { ... }
  ...
}
```

**After**：
```dart
static Future<String?> detectAvailableProvider() async {
  // [重構] 委派 ProviderRegistry——動態探測 + 能力排序
  final best = await ProviderRegistry.instance.selectBestCloud();
  return best?.providerId;
}
```

**注意**：此方法被 `ApiService.sendMessage()` L157-158 和 `NativeAgentLoop._detectProviderProfile()` L638 呼叫。改為委派後行為一致——都是選最強大腦。

---

#### Step 4：改造 `ProviderRouter`

**4a. 刪除 `_cloudBaseUrl()`** (L246-263)

完全刪除此方法。所有呼叫處改用 `ProviderRegistry.baseUrlOf(providerId)`。

**4b. 改造 `_detectCloudProvider()`** (L266-279)

**Before**：
```dart
Future<String?> _detectCloudProvider() async {
  final stored = await StorageService.getProvider() ?? '';
  if (stored != 'local' && stored.isNotEmpty) {
    final token = await StorageService.getToken(provider: stored);
    if (token != null && token.isNotEmpty) return stored;
  }
  for (final p in ['glm', 'minimax', 'openai', 'kimi', 'anthropic']) { ... }
  return null;
}
```

**After**：
```dart
Future<String?> _detectCloudProvider() async {
  // [重構] 使用者明確設定了 provider → 尊重選擇
  final stored = await StorageService.getProvider() ?? '';
  if (stored != 'local' && stored.isNotEmpty) {
    final token = await StorageService.getToken(provider: stored);
    if (token != null && token.isNotEmpty) return stored;
  }
  // [重構] 沒有明確選擇 → 動態選最強大腦
  final best = await ProviderRegistry.instance.selectBestCloud();
  return best?.providerId;
}
```

**4c. 改造 `_setAsync()`** (L226-227)

**Before**：
```dart
if (target == RoutedTarget.cloud) {
  _routedBaseUrl = _cloudBaseUrl(providerId);
}
```

**After**：
```dart
if (target == RoutedTarget.cloud) {
  _routedBaseUrl = ProviderRegistry.baseUrlOf(providerId);
}
```

**4d. 修正 fallback 硬編碼** (L127-128, L145)

**Before**：
```dart
return _setAsync(RoutedTarget.cloud, cloudProvider ?? 'glm', ...);
return _setAsync(RoutedTarget.cloud, 'glm', ...);
```

**After**：
```dart
// 不再硬編碼 'glm'——如果 selectBestCloud 回傳 null 就真的沒有
final fallback = cloudProvider ??
    (await ProviderRegistry.instance.selectBestCloud())?.providerId;
return _setAsync(RoutedTarget.cloud, fallback ?? 'unknown', ...);
```

---

#### Step 5：改造 `ApiService._defaultModel()`

**Before** (L1016-1036)：
```dart
static String _defaultModel(String provider) {
  switch (provider) { ... }
}
```

**After**：
```dart
/// [重構] 動態選最佳模型——委派 ProviderRegistry
static Future<String> _defaultModelFor(String provider) async {
  if (provider == 'local') {
    final localModel = await StorageService.getLocalModelName();
    if (localModel != null && localModel.trim().isNotEmpty) {
      return localModel.trim();
    }
    return 'llama3.1:8b'; // local fallback——本地模型不拉 /v1/models
  }
  // 動態選最佳模型
  final model = await ProviderRegistry.instance.selectBestModel(provider);
  if (model != null) return model;
  // 最終 fallback——用 ProviderProfileStore 種子數據
  return _legacyFallbackModel(provider);
}

/// 舊版硬編碼保留為 private fallback（只在動態探測失敗時使用）
static String _legacyFallbackModel(String provider) {
  switch (provider) {
    case 'openai':  return 'gpt-5.4';
    case 'glm':     return 'glm-5.2';
    case 'minimax': return 'MiniMax-M2.5';
    case 'kimi':    return 'kimi-k3';
    default:        return 'gpt-5.4';
  }
}

/// [保留] 公開 API——給 NativeAgentLoop 同步呼叫
/// 注意：此方法為同步，只能回 fallback。動態版本請用 selectBestModel()。
static String defaultModelFor(String provider) => _legacyFallbackModel(provider);
```

**注意**：`_defaultModelFor` 本來就是 async（L1038），所以呼叫端不需改 signature。但 `defaultModelFor` (L1014) 是同步的——NativeAgentLoop L644 呼叫它。需要將 NativeAgentLoop 改為用 async 版本（見 Step 7）。

---

#### Step 6：改造 `AgentModelSelector`

**6a. 刪除 `_allProviderInfos` 和 `_defaultGatewayUrl()`**

完全刪除 L12-64 的 `_ProviderDisplayInfo`、`_allProviderInfos`、`_findProviderInfo`、`_defaultGatewayUrl`。

**6b. 改用 ProviderRegistry**

```dart
// 偵測可用 provider 列表
Future<void> _detectProviders() async {
  final List<ProviderMeta> available = [];
  final discovered = await ProviderRegistry.instance.discoverAll();

  for (final dp in discovered) {
    if (dp.reachable) {
      available.add(ProviderRegistry.metaOf(dp.providerId)!);
    }
  }

  // 檢查 local 模型是否在跑
  final localRunning = await _isLocalModelRunning();
  if (localRunning) {
    available.add(ProviderRegistry.metaOf('local')!);
  }

  // 取得當前 provider
  final currentProvider = await StorageService.getProvider();

  if (mounted) {
    setState(() {
      _availableProviders = available;
      _currentProvider = currentProvider;
      _localRunning = localRunning;
      _isLoading = false;
    });
  }
}

// 切換 provider
Future<void> _selectProvider(String provider) async {
  if (provider == _currentProvider) return;
  // ...
  await StorageService.saveProvider(provider);
  // [重構] 用 ProviderRegistry 取得 URL，不再用 _defaultGatewayUrl
  final url = ProviderRegistry.baseUrlOf(provider);
  if (url != null) {
    await StorageService.saveGatewayUrl(url);
  }
  // [重構] invalidate 快取——provider 切換後重新探測
  ProviderRegistry.instance.invalidate();
  // ...
}
```

---

#### Step 7：改造 `NativeAgentLoop._detectProviderProfile()`

**Before** (L633-650)：
```dart
final provider = routedProvider?.providerId ??
    await StorageService.getProvider() ??
    await StorageService.detectAvailableProvider() ??
    'openai';
String model;
if (provider == 'local') {
  model = await StorageService.getLocalModelName() ?? 'llama3.1:8b';
} else {
  model = ApiService.defaultModelFor(provider); // ← 同步，只有 fallback
}
```

**After**：
```dart
final provider = routedProvider?.providerId ??
    await StorageService.getProvider() ??
    await StorageService.detectAvailableProvider() ??
    'openai';
String model;
if (provider == 'local') {
  model = await StorageService.getLocalModelName() ?? 'llama3.1:8b';
} else {
  // [重構] 動態選最佳模型
  model = await ProviderRegistry.instance.selectBestModel(provider) ??
      ApiService.defaultModelFor(provider); // fallback
}
```

---

#### Step 8：設定頁面 invalidate

在設定頁面儲存 token 後呼叫 `ProviderRegistry.instance.invalidate()`，確保下次探測使用最新金鑰。

需要找到設定頁面的 save token 呼叫處（`StorageService.saveToken()` 的呼叫端），加入 invalidate。

---

### 3.3 遷移順序圖

```
Step 1 (新增 ProviderRegistry)
  │  ✅ 不影響既有程式碼
  ▼
Step 2 (啟動初始化)
  │  ✅ 在既有 init 之後加一行
  ▼
Step 3 (StorageService.detectAvailableProvider)
  │  ⚠️ 行為變更：fallback 順序從品牌偏見改為能力排序
  ▼
Step 4 (ProviderRouter)
  │  ⚠️ 行為變更：刪 _cloudBaseUrl，fallback 不再硬編碼 'glm'
  ▼
Step 5 (ApiService._defaultModel)
  │  ⚠️ 行為變更：模型選擇從硬編碼改為動態探測
  ▼
Step 6 (AgentModelSelector)
  │  ⚠️ 行為變更：URL 來源統一
  ▼
Step 7 (NativeAgentLoop)
  │  ⚠️ 行為變更：模型選擇動態化
  ▼
Step 8 (設定頁 invalidate)
     ✅ 確保快取一致性
```

---

## 4. 風險評估

### 4.1 高風險

| 風險 | 嚴重度 | 說明 | 緩解措施 |
|------|--------|------|----------|
| **`/v1/models` API 不一致** | 🔴 高 | 各 provider 的 `/v1/models` 回傳格式可能不同。Anthropic 的 API 不支援標準 `/v1/models` endpoint；Gemini 用不同的 schema。 | 1. `testConnectionWith()` 已有 `data['data']` 解析——相容 OpenAI 格式。2. 對不支援的 provider，catch exception 後標記 `reachable: false`，fallback 到 `_legacyFallbackModel()`。3. Phase 2 再為 Anthropic/Gemini 偫適配器。 |
| **啟動延遲增加** | 🔴 高 | `discoverAll()` 會對每個有金鑰的 provider 發 HTTP 請求。若使用者設了 5 個 key，啟動時多 5 個網路請求。 | 1. 快取機制（10 分鐘 TTL）。2. `discoverAll()` 用 `Future.wait` 並行請求。3. 啟動時只跑輕量版 `discoverConfiguredProviders()`，完整 `discoverAll()` 延後到第一次路由時。4. 每個請求 3 秒 timeout。 |
| **`_defaultModelFor` 變 async** | 🟡 中 | 原本 `defaultModelFor()` 是同步的，改為動態後需要 async。NativeAgentLoop L644 呼叫處需要改。 | Step 7 已處理：改為 `await ProviderRegistry.instance.selectBestModel()`。保留 `defaultModelFor()` 同步版作 fallback。 |

### 4.2 中風險

| 風險 | 嚴重度 | 說明 | 緩解措施 |
|------|--------|------|----------|
| **secure storage -34018 bug 未根治** | 🟡 中 | ProviderRegistry 仍透過 `StorageService.getToken()` 讀 token。如果 macOS secure storage 持續 -34018，探測結果會是空的。 | StorageService 已有 macOS SharedPreferences fallback（L46-47, L53-56）。ProviderRegistry 不直接碰 secure storage，受影響程度低於現有 ProviderRouter。 |
| **MiniMax URL 不一致修哪個** | 🟡 中 | #1 用 `api.minimax.chat`，#3 用 `api.minimax.io`。ProviderRegistry 需選一個。 | 需驗證哪個是正確的。若兩個都能用，選 `api.minimax.io`（#3 版本較新）。在 `_providerMetadata` 中統一為一個。 |
| **Claude/Anthropic ID 統一** | 🟡 中 | #4 用 `'claude'`，#5 用 `'anthropic'`。需統一。 | 統一為 `'claude'`（與 StorageService 的 token key 一致）。ProviderRegistry 的 `_providerMetadata` 只包含 `'claude'`。 |
| **ProviderProfileStore 查詢效能** | 🟡 中 | `_pickBestModel()` 對每個可用模型呼叫 `getProfile()`，可能有 10-50 個模型。 | ProviderProfileStore 有記憶體 cache（L22）。首次查詢後後續都是記憶體讀取。可接受。 |

### 4.3 低風險

| 風險 | 嚴重度 | 說明 | 緩解措施 |
|------|--------|------|----------|
| **舊版 `_defaultModel` 被其他地方呼叫** | 🟢 低 | `defaultModelFor()` 可能被其他未發現的地方呼叫。 | 保留同步版 `_legacyFallbackModel()` 作為 fallback，不刪除公開 API。 |
| **快取過期導致用舊資料** | 🟢 低 | 10 分鐘 TTL 期間，使用者若在 provider 平台改了模型權限，app 不知道。 | Step 8 的 invalidate 機制 + 使用者切換 provider 時 invalidate。10 分鐘 TTL 可接受——模型列表不常變。 |
| **動態探測無結果時的行為** | 🟢 低 | 如果所有 provider 的 `/v1/models` 都失敗，`selectBestCloud()` 回傳 null。 | Fallback 鏈：`selectBestCloud()` → `discoverConfiguredProviders()` → `_legacyFallbackModel()` → 硬編碼。確保永遠有值。 |

### 4.4 不改變的範圍（明確排除）

以下系統**不在本次重構範圍**，維持原樣：

- `ProviderProfileStore` 的種子數據和自進化機制
- `ProviderProfile` / `ProviderTier` 的定義
- `IntentSpine` 的意圖分類邏輯
- `ProviderRouter.route()` 的路由判斷邏輯（本地 vs 雲端）
- `MemoryGuardService` 的安全閥
- `ApiService.testConnectionWith()` 的實作
- `StorageService.getToken()` / `saveToken()` 的儲存機制

### 4.5 回滾計畫

如果重構後出現問題：

1. **Step 3-4 可獨立回滾**：`detectAvailableProvider()` 和 `_detectCloudProvider()` 恢復硬編碼版本，ProviderRegistry 閒置不影響系統。
2. **Step 5 保留 `_legacyFallbackModel()`**：動態選模型失敗時自動 fallback，不需手動回滾。
3. **Step 6 的 `_defaultGatewayUrl()`** 可從 git 歷史恢復。
4. **ProviderRegistry 是新增檔案**：刪除即完全回滾，不影響既有程式碼。

---

## 附錄 A：既有硬編碼 URL 對照表

| Provider | `provider_router.dart` #1 | `agent_model_selector.dart` #3 | 差異 |
|----------|--------------------------|-------------------------------|------|
| openai | `api.openai.com/v1` | `api.openai.com/v1` | ✅ 一致 |
| glm | `open.bigmodel.cn/api/paas/v4` | `open.bigmodel.cn/api/paas/v4` | ✅ 一致 |
| kimi | `api.moonshot.cn/v1` | `api.moonshot.cn/v1` | ✅ 一致 |
| minimax | `api.minimax.chat/v1` | `api.minimax.io/v1` | ❌ **域名不同** |
| claude | `api.anthropic.com/v1` | `api.anthropic.com/v1` | ✅ 一致 |
| gemini | `generativelanguage.googleapis.com/v1beta` | `generativelanguage.googleapis.com/v1beta` | ✅ 一致 |
| default | GLM | Kimi | ❌ **完全不同** |

## 附錄 B：既有 Fallback 順序對照表

| 位置 | 順序 | Claude ID |
|------|------|-----------|
| `storage_service.dart` #4 | `openai > glm > kimi > minimax > gemini > claude` | `'claude'` |
| `provider_router.dart` #5 | `glm > minimax > openai > kimi > anthropic` | `'anthropic'` ❌ |

**重構後**：統一為 `ProviderRegistry.selectBestCloud()` → 按 Tier 排序，Claude ID 統一為 `'claude'`。

---

*End of document*
