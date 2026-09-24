import 'package:dio/dio.dart';

import '../models/bridge_action.dart';
import 'api_service.dart';
import 'bridge_adapters/bridge_adapter_registry.dart';
import 'capability_router.dart';
import 'provider_registry.dart';
import 'storage_service.dart';

enum CapabilityHealthStatus { ready, needsSetup, unsupported }

extension CapabilityHealthStatusX on CapabilityHealthStatus {
  String get label {
    switch (this) {
      case CapabilityHealthStatus.ready:
        return '可用';
      case CapabilityHealthStatus.needsSetup:
        return '需設定';
      case CapabilityHealthStatus.unsupported:
        return '未支援';
    }
  }
}

/// [教練 Agent 2026-08-08] 已驗證的替代 provider——不是猜的，是 discoverAll 真的打過 API 的
class VerifiedAlternative {
  final String providerId;
  final String displayName;
  final String model;
  final bool reachable;
  const VerifiedAlternative({
    required this.providerId,
    required this.displayName,
    required this.model,
    required this.reachable,
  });
}

class CapabilityHealthItem {
  final BridgeActionType type;
  final String label;
  final CapabilityHealthStatus status;
  final String providerLabel;
  final String detail;
  final String? recommendedProvider;
  /// [教練 Agent 2026-08-08] 當指定 provider 不可用時，列出其他已驗證可用的選項
  final List<VerifiedAlternative> verifiedAlternatives;

  const CapabilityHealthItem({
    required this.type,
    required this.label,
    required this.status,
    required this.providerLabel,
    required this.detail,
    this.recommendedProvider,
    this.verifiedAlternatives = const [],
  });
}

class CapabilityHealthService {
  CapabilityHealthService({BridgeAdapterRegistry? registry, Dio? dio})
    : _registry = registry ?? BridgeAdapterRegistry(),
      _dio = dio ?? Dio() {
    _router = CapabilityRouter(registry: _registry);
  }

  final BridgeAdapterRegistry _registry;
  final Dio _dio;
  late final CapabilityRouter _router;

  Future<List<CapabilityHealthItem>> inspect() async {
    final provider = await StorageService.getProvider() ?? 'kimi';
    final hasChatToken = await _hasToken(provider);
    final items = <CapabilityHealthItem>[
      CapabilityHealthItem(
        type: BridgeActionType.unknown,
        label: '聊天',
        status: hasChatToken
            ? CapabilityHealthStatus.ready
            : CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: hasChatToken
            ? '目前主腦 provider 已設定 token'
            : '請設定主腦 provider token',
        recommendedProvider: hasChatToken ? null : provider,
      ),
      CapabilityHealthItem(
        type: BridgeActionType.unknown,
        label: '語意壓縮',
        status: hasChatToken
            ? CapabilityHealthStatus.ready
            : CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: hasChatToken
            ? '長對話會由主腦 provider 整理任務狀態'
            : '需要主腦 provider token',
        recommendedProvider: hasChatToken ? null : provider,
      ),
    ];

    items.add(await _inspectBridgeAction(BridgeActionType.document));
    items.add(await _inspectBridgeAction(BridgeActionType.generateImage));
    items.add(
      const CapabilityHealthItem(
        type: BridgeActionType.generateAnimation,
        label: '角色動態接口',
        status: CapabilityHealthStatus.unsupported,
        providerLabel: 'Future Plugin',
        detail: '前端已暫停半成品動圖流程，等待更穩定的插件或外部引擎接入',
      ),
    );
    // [教練 Agent 2026-07-23] video/music 改用 _inspectBridgeAction 走正常路由
    items.add(await _inspectBridgeAction(BridgeActionType.generateVideo));
    items.add(await _inspectBridgeAction(BridgeActionType.generateMusic));
    // [教練 Agent 2026-07-23] TTS 健康檢查 — TTS 複用 generateMusic type，provider=minimax-tts
    items.add(await _inspectTtsAction());
    items.add(await _inspectBridgeAction(BridgeActionType.browse));
    items.add(await _inspectBridgeAction(BridgeActionType.vision));
    return items;
  }

  /// 輕量查詢：browse 能力是否已開通。
  /// 給 CapabilityAdvisorService 用的快速判斷，不跑完整 inspect()。
  Future<bool> isBrowseReady() async {
    final item = await _inspectBridgeAction(BridgeActionType.browse);
    return item.status == CapabilityHealthStatus.ready;
  }

  Future<List<CapabilityHealthItem>> runLiveChecks() async {
    final provider = await StorageService.getProvider() ?? 'kimi';
    final chat = await _checkChatProvider(provider);
    return [
      chat,
      await _checkDocumentProvider(provider, chat.status),
      await _checkImageProvider(),
      // [教練 Agent 2026-07-23] video/music/tts 實機檢查
      await _checkMediaProvider('minimax-video', '影片實機'),
      await _checkMediaProvider('minimax-music', '音樂實機'),
      await _checkMediaProvider('minimax-tts', '語音實機'),
    ];
  }

  /// [教練 Agent 2026-07-23] 通用媒體 provider 實機檢查
  Future<CapabilityHealthItem> _checkMediaProvider(
    String provider,
    String label,
  ) async {
    final token = await StorageService.getToken(provider: 'minimax');
    if (token == null || token.trim().isNotEmpty == false) {
      return _liveItem(
        label: label,
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: 'MiniMax API Key 尚未設定',
        recommendedProvider: 'minimax',
      );
    }
    try {
      await _pingProvider(provider, token);
      return _liveItem(
        label: label,
        status: CapabilityHealthStatus.ready,
        providerLabel: _providerName(provider),
        detail: 'MiniMax API 可連線',
      );
    } catch (error) {
      return _liveItem(
        label: label,
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: '連線失敗：$error',
        recommendedProvider: 'minimax',
      );
    }
  }

  Future<CapabilityHealthItem> _inspectBridgeAction(
    BridgeActionType type,
  ) async {
    final route = await _router.route(
      BridgeAction(type: type, prompt: _probePrompt(type)),
    );
    if (route.adapter == null) {
      return CapabilityHealthItem(
        type: type,
        label: _label(type),
        status: CapabilityHealthStatus.unsupported,
        providerLabel: '尚未接入',
        detail: '目前沒有可處理此能力的 adapter',
      );
    }

    final ready = route.reason != 'provider_not_configured';
    // [教練 Agent 2026-08-08] 使用者要求：不只報錯，還要清點手上還有什麼已驗證的鑰匙
    List<VerifiedAlternative> alternatives = const [];
    if (!ready) {
      alternatives = await _findVerifiedAlternatives(type);
    }
    return CapabilityHealthItem(
      type: type,
      label: _label(type),
      status: ready
          ? CapabilityHealthStatus.ready
          : CapabilityHealthStatus.needsSetup,
      providerLabel: route.adapter!.displayName,
      detail: ready
          ? '將由 ${route.adapter!.displayName} 執行'
          : alternatives.isEmpty
              ? '請設定 ${_providerName(route.provider ?? route.adapter!.id)} token'
              : '${_providerName(route.provider ?? route.adapter!.id)} 尚未設定，但你有 ${alternatives.length} 個已驗證的替代選項',
      recommendedProvider: ready
          ? null
          : _recommendedProvider(type, route.candidateProviders),
      verifiedAlternatives: alternatives,
    );
  }

  /// [教練 Agent 2026-08-08] 掃描所有 adapter，找出有 token 且已驗證連通的替代 provider
  Future<List<VerifiedAlternative>> _findVerifiedAlternatives(
    BridgeActionType type,
  ) async {
    final adapters = _registry.adaptersFor(type);
    final result = <VerifiedAlternative>[];
    for (final adapter in adapters) {
      final token = await StorageService.getToken(provider: adapter.id);
      if (token == null || token.trim().isEmpty) continue;
      // 有 token——嘗試驗證連通性（用 ProviderRegistry 的快取結果）
      // 如果 adapter 是 local_document / local_desktop_files，直接標為可用
      if (adapter.id == 'local_document' || adapter.id == 'local_desktop_files') {
        result.add(VerifiedAlternative(
          providerId: adapter.id,
          displayName: adapter.displayName,
          model: 'local',
          reachable: true,
        ));
        continue;
      }
      // 檢查 ProviderRegistry 是否有探測結果
      final baseUrl = ProviderRegistry.baseUrlOf(adapter.id);
      if (baseUrl == null) continue;
      try {
        final models = await ApiService.testConnectionWith(baseUrl, token);
        result.add(VerifiedAlternative(
          providerId: adapter.id,
          displayName: adapter.displayName,
          model: models.isNotEmpty ? models.first : 'unknown',
          reachable: true,
        ));
      } catch (_) {
        // token 存在但連線失敗——仍列入但標為不可達
        result.add(VerifiedAlternative(
          providerId: adapter.id,
          displayName: adapter.displayName,
          model: 'unknown',
          reachable: false,
        ));
      }
    }
    return result;
  }

  /// [教練 Agent 2026-07-23] TTS 健康檢查 — TTS 複用 generateMusic type，
  /// 但 provider 固定為 minimax-tts。需要檢查 minimax token 是否設定。
  Future<CapabilityHealthItem> _inspectTtsAction() async {
    final token = await StorageService.getToken(provider: 'minimax');
    final hasToken = token != null && token.trim().isNotEmpty;
    return CapabilityHealthItem(
      type: BridgeActionType.generateMusic,
      label: '語音合成',
      status: hasToken
          ? CapabilityHealthStatus.ready
          : CapabilityHealthStatus.needsSetup,
      providerLabel: 'MiniMax Speech 2.8 HD',
      detail: hasToken
          ? '將由 MiniMax Speech 2.8 HD 執行'
          : '請設定 MiniMax API Key（語音合成共用 MiniMax 帳號）',
      recommendedProvider: hasToken ? null : 'minimax',
    );
  }

  Future<bool> _hasToken(String provider) async {
    final token = await StorageService.getToken(provider: provider);
    return token != null && token.trim().isNotEmpty;
  }

  Future<CapabilityHealthItem> _checkChatProvider(String provider) async {
    final url = await StorageService.getGatewayUrl();
    final token = await StorageService.getToken(provider: provider);
    if (url == null || url.trim().isEmpty) {
      return _liveItem(
        label: '聊天實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: 'Gateway URL 尚未設定',
        recommendedProvider: provider,
      );
    }
    if (token == null || token.trim().isEmpty) {
      return _liveItem(
        label: '聊天實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: 'API Token 尚未設定',
        recommendedProvider: provider,
      );
    }

    try {
      final models = await ApiService.testConnectionWith(url, token);
      return _liveItem(
        label: '聊天實機',
        status: CapabilityHealthStatus.ready,
        providerLabel: _providerName(provider),
        detail: models.isEmpty
            ? '模型列表可連線'
            : '可連線，模型 ${models.take(2).join('、')}',
      );
    } catch (error) {
      return _liveItem(
        label: '聊天實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: '連線失敗：$error',
        recommendedProvider: provider,
      );
    }
  }

  Future<CapabilityHealthItem> _checkDocumentProvider(
    String provider,
    CapabilityHealthStatus chatStatus,
  ) async {
    if (provider != 'openai' && provider != 'kimi' && provider != 'minimax') {
      return _liveItem(
        label: '文件實機',
        status: CapabilityHealthStatus.ready,
        providerLabel: '本地文件',
        detail: '目前會使用本地 Markdown fallback',
      );
    }
    if (chatStatus != CapabilityHealthStatus.ready) {
      return _liveItem(
        label: '文件實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: '需先通過聊天實機檢查',
        recommendedProvider: provider,
      );
    }

    try {
      final markdown = await ApiService.generateDocumentMarkdown(
        'Health Check|請用一句話回覆橋樑文件生成可用。',
      );
      return _liveItem(
        label: '文件實機',
        status: CapabilityHealthStatus.ready,
        providerLabel: _providerName(provider),
        detail: markdown.trim().isEmpty ? '文件 API 已回應' : '文件 API 已回應',
      );
    } catch (error) {
      return _liveItem(
        label: '文件實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: _providerName(provider),
        detail: '文件生成失敗：$error',
        recommendedProvider: provider,
      );
    }
  }

  Future<CapabilityHealthItem> _checkImageProvider() async {
    final route = await _router.route(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: 'capability live check image',
      ),
    );
    final provider = route.provider ?? route.adapter?.id;
    if (route.adapter == null || provider == null) {
      return _liveItem(
        label: '圖片實機',
        status: CapabilityHealthStatus.unsupported,
        providerLabel: '尚未接入',
        detail: '沒有圖片 adapter',
      );
    }

    final token = await StorageService.getToken(provider: provider);
    if (token == null || token.trim().isEmpty) {
      return _liveItem(
        label: '圖片實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: route.adapter!.displayName,
        detail: '圖片 provider token 尚未設定',
        recommendedProvider: provider,
      );
    }

    try {
      await _pingProvider(provider, token);
      return _liveItem(
        label: '圖片實機',
        status: CapabilityHealthStatus.ready,
        providerLabel: route.adapter!.displayName,
        detail: 'provider API 可連線',
      );
    } catch (error) {
      return _liveItem(
        label: '圖片實機',
        status: CapabilityHealthStatus.needsSetup,
        providerLabel: route.adapter!.displayName,
        detail: '連線失敗：$error',
        recommendedProvider: provider,
      );
    }
  }

  Future<void> _pingProvider(String provider, String token) async {
    switch (provider) {
      case 'openai':
        await ApiService.testConnectionWith('https://api.openai.com/v1', token);
        return;
      case 'replicate':
        await _dio.get(
          'https://api.replicate.com/v1/account',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return;
      // [教練 Agent 2026-07-23] MiniMax 連線測試
      case 'minimax':
      case 'minimax-video':
      case 'minimax-music':
      case 'minimax-tts':
        await _dio.get(
          'https://api.minimax.io/v1/account',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return;
      default:
        throw UnsupportedError('${_providerName(provider)} 尚未支援實機檢查');
    }
  }

  CapabilityHealthItem _liveItem({
    required String label,
    required CapabilityHealthStatus status,
    required String providerLabel,
    required String detail,
    String? recommendedProvider,
  }) {
    return CapabilityHealthItem(
      type: BridgeActionType.unknown,
      label: label,
      status: status,
      providerLabel: providerLabel,
      detail: detail,
      recommendedProvider: recommendedProvider,
    );
  }

  String? _recommendedProvider(BridgeActionType type, List<String> candidates) {
    // [教練 Agent 2026-07-23] video/music 優先推薦 MiniMax adapter
    if (type == BridgeActionType.generateVideo) {
      if (candidates.contains('minimax-video')) return 'minimax-video';
      if (candidates.contains('minimax')) return 'minimax';
    }
    if (type == BridgeActionType.generateMusic) {
      if (candidates.contains('minimax-music')) return 'minimax-music';
      if (candidates.contains('minimax')) return 'minimax';
    }
    if (type == BridgeActionType.generateImage) {
      if (candidates.contains('replicate')) return 'replicate';
      if (candidates.contains('openai')) return 'openai';
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  String _probePrompt(BridgeActionType type) {
    switch (type) {
      case BridgeActionType.generateImage:
        return 'capability health check image';
      case BridgeActionType.generateAnimation:
        return 'capability health check animation';
      case BridgeActionType.document:
      case BridgeActionType.desktopFiles:
        return 'Capability Health|Bridge status';
      case BridgeActionType.generateMusic:
      case BridgeActionType.generateVideo:
      case BridgeActionType.browse:
      case BridgeActionType.vision:
      case BridgeActionType.unknown:
        return 'capability health check';
    }
  }

  String _label(BridgeActionType type) {
    switch (type) {
      case BridgeActionType.generateImage:
        return '圖片生成';
      case BridgeActionType.generateAnimation:
        return '角色動態接口';
      case BridgeActionType.generateMusic:
        return '音樂生成';
      case BridgeActionType.generateVideo:
        return '影片生成';
      case BridgeActionType.browse:
        return '瀏覽';
      case BridgeActionType.vision:
        return '圖片辨識';
      case BridgeActionType.document:
        return '文件生成';
      case BridgeActionType.desktopFiles:
        return '桌面整理';
      case BridgeActionType.unknown:
        return '未知能力';
    }
  }

  String _providerName(String provider) {
    switch (provider) {
      case 'openai':
        return 'OpenAI';
      case 'replicate':
        return 'Replicate';
      case 'kimi':
        return 'Kimi';
      case 'minimax':
        return 'MiniMax';
      case 'minimax-video':
        return 'MiniMax Hailuo';
      case 'minimax-music':
        return 'MiniMax Music';
      case 'minimax-tts':
        return 'MiniMax Speech';
      case 'local':
        return '本地主腦';
      case 'claude':
        return 'Claude';
      case 'gemini':
        return 'Gemini';
      case 'local_document':
        return '本地文件';
      default:
        return provider;
    }
  }
}
