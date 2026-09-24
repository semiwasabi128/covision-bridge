/// ServiceRegistry — JSON 驅動的服務註冊表
///
/// 設計文件: 02-架構設計/keychain-settings-design.md §3-4
/// [教練 Agent 2026-08-01] Phase 0 — 能力中心地基
///
/// 核心職責:
///   1. 維護所有已註冊的服務定義（資料驅動，非硬編碼）
///   2. 按能力分組
///   3. 查詢使用者已開通的服務（結合 StorageService 的 Key 存取狀態）
///   4. 新增/下架服務只需改 JSON，不需要發版
///
/// 相容性:
///   - StorageService.saveToken/getToken 保持不變
///   - ProviderRegistry 的 brand→URL 映射保持不變
///   - ProviderProfileStore 的 Tier 分級保持不變
///   - 本類在上面加一層能力導向的分類
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'capability_models.dart';
import '../storage_service.dart';
import '../provider_registry.dart';

class ServiceRegistry {
  static final ServiceRegistry instance = ServiceRegistry._();
  ServiceRegistry._();

  final List<ServiceDefinition> _services = [];

  /// 是否已初始化
  bool _initialized = false;

  // ═══════════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════════

  /// 載入內建服務定義
  /// 在 App 啟動時呼叫一次
  Future<void> initialize() async {
    if (_initialized) return;

    _services.clear();
    _services.addAll(_builtInServices());

    // TODO Phase 3: 載入社群 Adapter Pack
    // await _loadCommunityServices();

    // TODO Phase 2: 載入遠端服務列表更新
    // await _loadRemoteUpdates();

    _initialized = true;
    debugPrint('[ServiceRegistry] 已載入 ${_services.length} 個服務定義');
  }

  /// [小葵 2026-09-24 修 bug·找不到服務] 查詢前確保已初始化。
  /// 舊行為：initialize() 只在「能力中心」頁面 initState 呼叫——
  /// 使用者沒開過那頁，註冊表就是空的 → 畫布生成節點全炸
  /// 「找不到服務: openai_image」（budget_ledger 實錄），
  /// 工作流空轉零圖。註冊表是純內建靜態定義（無 async 依賴），
  /// 同步載入安全；initialize() 冪等，重複呼叫無副作用。
  void _ensureInitialized() {
    if (_initialized) return;
    _services.clear();
    _services.addAll(_builtInServices());
    _initialized = true;
    debugPrint('[ServiceRegistry] 惰性載入 ${_services.length} 個服務定義');
  }

  // ═══════════════════════════════════════════════════
  // 查詢
  // ═══════════════════════════════════════════════════

  /// 所有已註冊的服務
  List<ServiceDefinition> get allServices {
    _ensureInitialized();
    return List.unmodifiable(_services);
  }

  /// 按能力分組
  List<CapabilityGroup> get capabilityGroups {
    final groups = <CapabilityId, List<ServiceDefinition>>{};

    // 確保所有能力都出現（即使沒有服務）
    for (final cap in CapabilityId.values) {
      groups[cap] = [];
    }

    for (final s in _services) {
      groups[s.capability]?.add(s);
    }

    return CapabilityId.values
        .map((cap) => CapabilityGroup(
              capability: cap,
              services: groups[cap] ?? [],
            ))
        .toList();
  }

  /// 取得指定能力的所有服務
  List<ServiceDefinition> servicesFor(CapabilityId capability) {
    return _services.where((s) => s.capability == capability).toList();
  }

  /// 取得指定能力的已開通服務（結合 StorageService 的 Key 狀態）
  Future<List<ServiceDefinition>> activatedServicesFor(CapabilityId capability) async {
    final services = servicesFor(capability);
    final result = <ServiceDefinition>[];

    for (final s in services) {
      if (!s.status.isUsable) continue;

      if (s.keyRequirement.type == KeyType.none) {
        // 不需要 Key（如本地模型）
        result.add(s);
      } else if (s.keyRequirement.storageKey != null) {
        // 檢查 StorageService 是否有對應的 Key
        final token = await StorageService.getToken(provider: s.keyRequirement.storageKey);
        if (token != null && token.isNotEmpty) {
          result.add(s);
        }
      }
    }

    return result;
  }

  /// 指定能力是否已開通
  Future<bool> isCapabilityActivated(CapabilityId capability) async {
    final activated = await activatedServicesFor(capability);
    return activated.isNotEmpty;
  }

  /// 取得特定服務定義 by ID
  ServiceDefinition? serviceById(String id) {
    _ensureInitialized(); // [小葵 2026-09-24] 惰性載入——見 _ensureInitialized 註解
    for (final s in _services) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 找出共用同一把 Key 的所有服務
  /// 例如 OpenAI Key 可以用在 LLM + Image + Vision + TTS + Whisper + Search
  List<ServiceDefinition> servicesSharingKey(String storageKey) {
    return _services.where((s) =>
        s.keyRequirement.storageKey == storageKey &&
        s.keyRequirement.type != KeyType.none
    ).toList();
  }

  // ═══════════════════════════════════════════════════
  // 動態操作（未來擴充用）
  // ═══════════════════════════════════════════════════

  /// 新增服務（社群插件或遠端更新）
  void addService(ServiceDefinition service) {
    // 如果已存在（同 ID），替換
    _services.removeWhere((s) => s.id == service.id);
    _services.add(service);
    debugPrint('[ServiceRegistry] 新增服務: ${service.id}');
  }

  /// 標記服務下架
  void deprecateService(String serviceId, {String? reason, String? alternative}) {
    final idx = _services.indexWhere((s) => s.id == serviceId);
    if (idx >= 0) {
      final old = _services[idx];
      _services[idx] = ServiceDefinition(
        id: old.id,
        capability: old.capability,
        providerName: old.providerName,
        serviceName: old.serviceName,
        description: old.description,
        keyRequirement: old.keyRequirement,
        defaultBaseUrl: old.defaultBaseUrl,
        models: old.models,
        pricing: old.pricing,
        isBuiltIn: old.isBuiltIn,
        status: ServiceStatus.deprecated,
        deprecationNotice: reason,
        alternativeServiceId: alternative,
        note: old.note,
      );
      debugPrint('[ServiceRegistry] 服務下架: $serviceId');
    }
  }

  /// 匯出為 JSON（供匯出設定或遠端同步用）
  String toJson() {
    return jsonEncode({
      'version': _builtInVersion,
      'services': _services.map((s) {
        // 序列化 ServiceDefinition
        return {
          'id': s.id,
          'capability': s.capability.id,
          'providerName': s.providerName,
          'serviceName': s.serviceName,
          'description': s.description,
          'keyRequirement': s.keyRequirement.toJson(),
          'defaultBaseUrl': s.defaultBaseUrl,
          'models': s.models.map((m) => {
            'id': m.id,
            'displayName': m.displayName,
            'isDefault': m.isDefault,
          }).toList(),
          'isBuiltIn': s.isBuiltIn,
          'status': s.status.name,
          'note': s.note,
        };
      }).toList(),
    });
  }

  static const _builtInVersion = '1.0.0';

  // ═══════════════════════════════════════════════════
  // 內建服務定義（隨 App 發版）
  // ═══════════════════════════════════════════════════

  /// 內建服務列表
  ///
  /// 新增 provider 或服務 = 在這裡加一條
  /// 下架服務 = 改 status 為 deprecated
  ///
  /// Key 共用映射:
  ///   openai_token → LLM + Image + Vision + TTS + Whisper + Search (6 项)
  ///   glm_token    → LLM + Vision
  ///   minimax_token → LLM + Image + Video + Music
  ///   kimi_token   → LLM
  ///   tavily_token → Search
  List<ServiceDefinition> _builtInServices() {
    return [
      // ─── 文字推理 (LLM) ───
      ServiceDefinition(
        id: 'openai_llm',
        capability: CapabilityId.textReasoning,
        providerName: 'OpenAI',
        serviceName: 'GPT 系列',
        description: 'OpenAI GPT 系列大型語言模型',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          getUrl: 'https://platform.openai.com/api-keys',
          storageKey: 'openai',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('openai') ?? 'https://api.openai.com/v1',
        models: const [
          ServiceModel(id: 'gpt-5.4', displayName: 'GPT-5.4', isDefault: true),
          ServiceModel(id: 'gpt-4o', displayName: 'GPT-4o'),
          ServiceModel(id: 'gpt-4o-mini', displayName: 'GPT-4o Mini'),
        ],
        pricing: const PricingInfo(type: 'per_token', example: '~\$1-10/1M tokens'),
        note: '一把 Key 開通 6 項能力',
      ),
      ServiceDefinition(
        id: 'glm_llm',
        capability: CapabilityId.textReasoning,
        providerName: 'ZAI (智譜)',
        serviceName: 'GLM 系列',
        description: '智譜 AI GLM 系列模型',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'ZAI API Key',
          getUrl: 'https://open.bigmodel.cn',
          storageKey: 'glm',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('glm') ?? 'https://open.bigmodel.cn/api/paas/v4',
        models: const [
          ServiceModel(id: 'glm-5.2', displayName: 'GLM-5.2', isDefault: true),
          ServiceModel(id: 'glm-4.7', displayName: 'GLM-4.7'),
          ServiceModel(id: 'glm-4.5', displayName: 'GLM-4.5'),
        ],
        pricing: const PricingInfo(type: 'per_token', example: '~\$0.5-3/1M tokens'),
      ),
      ServiceDefinition(
        id: 'kimi_llm',
        capability: CapabilityId.textReasoning,
        providerName: 'Kimi (Moonshot)',
        serviceName: 'Kimi',
        description: '月之暗面 Kimi 大型語言模型',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Kimi API Key',
          getUrl: 'https://platform.moonshot.cn',
          storageKey: 'kimi',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('kimi') ?? 'https://api.moonshot.cn/v1',
        models: const [
          ServiceModel(id: 'kimi-k3', displayName: 'Kimi K3', isDefault: true),
          ServiceModel(id: 'kimi-k2.5', displayName: 'Kimi K2.5'),
        ],
      ),
      ServiceDefinition(
        id: 'minimax_llm',
        capability: CapabilityId.textReasoning,
        providerName: 'MiniMax',
        serviceName: 'MiniMax M2',
        description: 'MiniMax 大型語言模型',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'MiniMax API Key',
          getUrl: 'https://www.minimaxi.com',
          storageKey: 'minimax',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('minimax') ?? 'https://api.minimaxi.chat/v1',
        models: const [
          ServiceModel(id: 'MiniMax-M3', displayName: 'MiniMax M3', isDefault: true),
          ServiceModel(id: 'MiniMax-M2.7', displayName: 'MiniMax M2.7'),
          ServiceModel(id: 'MiniMax-M2.5', displayName: 'MiniMax M2.5'),
        ],
      ),
      ServiceDefinition(
        id: 'local_llm',
        capability: CapabilityId.textReasoning,
        providerName: '本地模型',
        serviceName: 'llama.cpp (隨 App 附帶)',
        description: 'App 內建 llama.cpp 本地推理引擎',
        keyRequirement: KeyRequirement.none,
        defaultBaseUrl: ProviderRegistry.baseUrlOf('local') ?? 'http://127.0.0.1:18789',
        models: const [
          ServiceModel(id: 'gemma-3-4b', displayName: 'Gemma 3 4B', isDefault: true),
        ],
      ),

      // ─── 圖片生成 ───
      ServiceDefinition(
        id: 'openai_image',
        capability: CapabilityId.imageGeneration,
        providerName: 'OpenAI',
        serviceName: 'gpt-image / DALL-E',
        description: 'OpenAI 圖片生成 API',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          storageKey: 'openai',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('openai') ?? 'https://api.openai.com/v1',
        models: const [
          ServiceModel(id: 'gpt-image-1', displayName: 'GPT Image 1', isDefault: true),
          ServiceModel(id: 'dall-e-3', displayName: 'DALL-E 3'),
        ],
        pricing: const PricingInfo(type: 'per_image', example: '~\$0.04-0.19/張'),
        note: '跟 OpenAI LLM 共用同一把 Key',
      ),
      ServiceDefinition(
        id: 'minimax_image',
        capability: CapabilityId.imageGeneration,
        providerName: 'MiniMax',
        serviceName: 'image-01',
        description: 'MiniMax 圖片生成 API',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'MiniMax API Key',
          storageKey: 'minimax',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('minimax') ?? 'https://api.minimaxi.chat/v1',
        models: const [
          ServiceModel(id: 'image-01', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_image', example: '~\$0.03/張'),
        note: '跟 MiniMax LLM 共用同一把 Key',
      ),
      // [教練 Agent 2026-08-10] 補上 Gemini 圖片生成——之前 ServiceRegistry 漏了
      ServiceDefinition(
        id: 'gemini_image',
        capability: CapabilityId.imageGeneration,
        providerName: 'Google Gemini',
        serviceName: 'Nano Banana 2',
        description: 'Gemini 圖片生成 (generateContent API)',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Gemini API Key',
          getUrl: 'https://aistudio.google.com/apikey',
          storageKey: 'gemini',
        ),
        defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        models: const [
          ServiceModel(id: 'gemini-3.1-flash-image-preview', displayName: 'Nano Banana 2', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_image', example: '免費額度內 \$0'),
        note: '跟 Gemini LLM 共用同一把 Key',
      ),
      ServiceDefinition(
        id: 'flux_replicate',
        capability: CapabilityId.imageGeneration,
        providerName: 'Flux (via Replicate)',
        serviceName: 'FLUX.1',
        description: '最強大的開源圖片生成模型',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Replicate API Key',
          getUrl: 'https://replicate.com/account/api-tokens',
          storageKey: 'replicate',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('replicate') ?? 'https://api.replicate.com/v1',
        models: const [
          ServiceModel(id: 'black-forest-labs/flux-1.1-pro', displayName: 'FLUX 1.1 Pro', isDefault: true),
          ServiceModel(id: 'black-forest-labs/flux-schnell', displayName: 'FLUX Schnell'),
        ],
        pricing: const PricingInfo(type: 'per_image', example: '~\$0.01-0.03/張'),
        note: '角色一致性首選：支援 IP-Adapter',
      ),
      ServiceDefinition(
        id: 'comfyui_image',
        capability: CapabilityId.imageGeneration,
        providerName: '本地 ComfyUI',
        serviceName: 'ComfyUI 工作流引擎',
        description: '連接到本地或雲端的 ComfyUI 伺服器',
        keyRequirement: const KeyRequirement(
          type: KeyType.url,
          label: 'ComfyUI 伺服器位址',
          hint: 'http://127.0.0.1:8188',
          storageKey: 'comfyui_url',
        ),
        defaultBaseUrl: 'http://127.0.0.1:8188',
        models: const [
          ServiceModel(id: 'sdxl-turbo', displayName: 'SDXL Turbo', isDefault: true),
          ServiceModel(id: 'flux-dev', displayName: 'FLUX Dev'),
        ],
        note: '最強大的角色一致性方案：ControlNet + IP-Adapter + LoRA',
      ),

      // ─── 圖片理解 (Vision) ───
      ServiceDefinition(
        id: 'openai_vision',
        capability: CapabilityId.imageUnderstanding,
        providerName: 'OpenAI',
        serviceName: 'GPT-4o Vision',
        description: 'OpenAI GPT-4o 多模態視覺理解',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          storageKey: 'openai',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('openai') ?? 'https://api.openai.com/v1',
        models: const [
          ServiceModel(id: 'gpt-4o', isDefault: true),
          ServiceModel(id: 'gpt-4o-mini'),
        ],
        note: '跟 OpenAI LLM 共用同一把 Key',
      ),

      // ─── 影片生成 ───
      ServiceDefinition(
        id: 'runway_video',
        capability: CapabilityId.videoGeneration,
        providerName: 'Runway',
        serviceName: 'Gen-3 Alpha',
        description: 'Runway Gen-3 Alpha 影片生成',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Runway API Key',
          getUrl: 'https://runwayml.com/api',
          storageKey: 'runway',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('runway') ?? 'https://api.runwayml.com/v1',
        models: const [
          ServiceModel(id: 'gen-3-alpha', displayName: 'Gen-3 Alpha', isDefault: true),
          ServiceModel(id: 'gen-3-alpha-turbo', displayName: 'Gen-3 Alpha Turbo'),
        ],
        pricing: const PricingInfo(type: 'per_second', example: '~\$0.05-0.10/秒'),
      ),
      ServiceDefinition(
        id: 'minimax_video',
        capability: CapabilityId.videoGeneration,
        providerName: 'MiniMax',
        serviceName: 'video-01',
        description: 'MiniMax 影片生成 API',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'MiniMax API Key',
          storageKey: 'minimax',
        ),
        defaultBaseUrl: ProviderRegistry.baseUrlOf('minimax') ?? 'https://api.minimaxi.chat/v1',
        models: const [
          ServiceModel(id: 'video-01', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_second', example: '~\$0.05/秒'),
        note: '跟 MiniMax LLM 共用同一把 Key',
      ),
      ServiceDefinition(
        id: 'kling_video',
        capability: CapabilityId.videoGeneration,
        providerName: 'Kuaishou (快手)',
        serviceName: 'Kling AI',
        description: '快手 Kling AI 影片生成',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Kling API Key',
          getUrl: 'https://kling.kuaishou.com',
          storageKey: 'kling',
        ),
        models: const [
          ServiceModel(id: 'kling-v2', displayName: 'Kling V2', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_second', example: '~\$0.05/秒'),
      ),

      // ─── 音樂生成 ───
      ServiceDefinition(
        id: 'suno_music',
        capability: CapabilityId.musicGeneration,
        providerName: 'Suno',
        serviceName: 'Suno AI Music',
        description: 'Suno AI 音樂生成',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Suno API Key',
          getUrl: 'https://suno.com/api',
          storageKey: 'suno',
        ),
        models: const [
          ServiceModel(id: 'suno-v4', displayName: 'Suno V4', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_song', example: '~\$0.10/首'),
      ),
      ServiceDefinition(
        id: 'minimax_music',
        capability: CapabilityId.musicGeneration,
        providerName: 'MiniMax',
        serviceName: 'music-01',
        description: 'MiniMax 音樂生成 API',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'MiniMax API Key',
          storageKey: 'minimax',
        ),
        models: const [
          ServiceModel(id: 'music-01', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_song', example: '~\$0.08/首'),
        note: '跟 MiniMax LLM 共用同一把 Key',
      ),

      // ─── 語音合成 (TTS) ───
      ServiceDefinition(
        id: 'openai_tts',
        capability: CapabilityId.voiceSynthesis,
        providerName: 'OpenAI',
        serviceName: 'OpenAI TTS',
        description: 'OpenAI 文字轉語音',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          storageKey: 'openai',
        ),
        models: const [
          ServiceModel(id: 'tts-1', displayName: 'TTS-1', isDefault: true),
          ServiceModel(id: 'tts-1-hd', displayName: 'TTS-1 HD'),
        ],
        pricing: const PricingInfo(type: 'per_token', example: '~\$15/1M chars'),
        note: '跟 OpenAI LLM 共用同一把 Key',
      ),
      ServiceDefinition(
        id: 'elevenlabs_tts',
        capability: CapabilityId.voiceSynthesis,
        providerName: 'ElevenLabs',
        serviceName: 'ElevenLabs Voice',
        description: 'ElevenLabs 高品質語音合成',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'ElevenLabs API Key',
          getUrl: 'https://elevenlabs.io',
          storageKey: 'elevenlabs',
        ),
        models: const [
          ServiceModel(id: 'eleven-multilingual-v2', displayName: 'Multilingual V2', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_token', example: '~\$0.30/1K chars'),
      ),

      // ─── 語音辨識 (STT) ───
      ServiceDefinition(
        id: 'local_whisper',
        capability: CapabilityId.voiceRecognition,
        providerName: '本地',
        serviceName: 'Open Whisper (本地)',
        description: 'App 內建的 Whisper 語音辨識引擎',
        keyRequirement: KeyRequirement.none,
        models: const [],
      ),
      ServiceDefinition(
        id: 'openai_whisper',
        capability: CapabilityId.voiceRecognition,
        providerName: 'OpenAI',
        serviceName: 'Whisper API',
        description: 'OpenAI Whisper 雲端語音辨識',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          storageKey: 'openai',
        ),
        models: const [
          ServiceModel(id: 'whisper-1', isDefault: true),
        ],
        note: '跟 OpenAI LLM 共用同一把 Key',
      ),

      // ─── 網頁搜尋 ───
      ServiceDefinition(
        id: 'openai_search',
        capability: CapabilityId.webSearch,
        providerName: 'OpenAI',
        serviceName: 'Web Search',
        description: 'OpenAI 網頁搜尋 API',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          storageKey: 'openai',
        ),
        models: const [],
        note: '跟 OpenAI LLM 共用同一把 Key',
      ),
      ServiceDefinition(
        id: 'tavily_search',
        capability: CapabilityId.webSearch,
        providerName: 'Tavily',
        serviceName: 'Tavily Search API',
        description: 'Tavily 專業網頁搜尋 API',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Tavily API Key',
          getUrl: 'https://tavily.com',
          storageKey: 'tavily_token',
        ),
        models: const [],
      ),

      // ─── 向量嵌入 ───
      ServiceDefinition(
        id: 'local_embedding',
        capability: CapabilityId.vectorEmbedding,
        providerName: '本地',
        serviceName: 'EmbeddingGemma 300M',
        description: 'App 內建的向量嵌入模型',
        keyRequirement: KeyRequirement.none,
        models: const [],
      ),

      // ─── 角色一致性 ───
      ServiceDefinition(
        id: 'openai_character',
        // [小葵 2026-09-24 修 bug·服務未設定 API 位址] 補 defaultBaseUrl——
        // 定義漏了這欄，executor 檢查 baseUrl == null 直接失敗
        // （budget_ledger 01:25 三連敗＝三視角 characterLock 全滅）。
        defaultBaseUrl: ProviderRegistry.baseUrlOf('openai') ?? 'https://api.openai.com/v1',
        capability: CapabilityId.characterLock,
        providerName: 'OpenAI',
        serviceName: 'gpt-image + 參考圖',
        description: '使用 OpenAI gpt-image 配合參考圖維持角色一致性',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'OpenAI API Key',
          storageKey: 'openai',
        ),
        models: const [
          ServiceModel(id: 'gpt-image-1.5', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_image', example: '~\$0.04-0.08/張'),
        note: '基本一致性 (~80%)，跟 OpenAI LLM 共用同一把 Key',
      ),
      ServiceDefinition(
        id: 'flux_character',
        capability: CapabilityId.characterLock,
        providerName: 'Flux (via Replicate)',
        serviceName: 'FLUX + IP-Adapter',
        description: '使用 Flux 配合 IP-Adapter 實現高角色一致性',
        keyRequirement: const KeyRequirement(
          type: KeyType.apiKey,
          label: 'Replicate API Key',
          storageKey: 'replicate',
        ),
        models: const [
          ServiceModel(id: 'flux-1.1-pro', displayName: 'FLUX 1.1 Pro', isDefault: true),
        ],
        pricing: const PricingInfo(type: 'per_image', example: '~\$0.01-0.03/張'),
        note: '高一致性 (~90%)',
      ),
    ];
  }
}
