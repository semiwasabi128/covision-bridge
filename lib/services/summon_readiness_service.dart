import '../models/bridge_action.dart';
import 'bridge_adapters/bridge_adapter_registry.dart';
import 'capability_router.dart';
import 'storage_service.dart';

class SummonReadiness {
  final bool brainReady;
  final bool imageReady;
  final String brainProvider;
  final String? imageProvider;
  final String imageProviderLabel;
  final String summary;
  final String actionLabel;

  const SummonReadiness({
    required this.brainReady,
    required this.imageReady,
    required this.brainProvider,
    required this.imageProvider,
    required this.imageProviderLabel,
    required this.summary,
    required this.actionLabel,
  });

  bool get ready => brainReady && imageReady;
}

class SummonReadinessService {
  SummonReadinessService({BridgeAdapterRegistry? registry})
    : _registry = registry ?? BridgeAdapterRegistry() {
    _router = CapabilityRouter(registry: _registry);
  }

  final BridgeAdapterRegistry _registry;
  late final CapabilityRouter _router;

  Future<SummonReadiness> inspect() async {
    final brainProvider = (await StorageService.getProvider() ?? 'kimi')
        .trim()
        .toLowerCase();
    final brainToken = await StorageService.getToken(provider: brainProvider);
    final brainReady = brainToken != null && brainToken.trim().isNotEmpty;
    final imageRoute = await _router.route(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: 'first companion appearance preview',
      ),
    );
    final imageProvider = imageRoute.provider ?? imageRoute.adapter?.id;
    final imageReady =
        imageRoute.adapter != null &&
        imageRoute.reason != 'provider_not_configured';
    final imageLabel =
        imageRoute.adapter?.displayName ?? _providerName(imageProvider);

    if (brainReady && imageReady) {
      return SummonReadiness(
        brainReady: true,
        imageReady: true,
        brainProvider: brainProvider,
        imageProvider: imageProvider,
        imageProviderLabel: imageLabel,
        summary: '主腦與形象生成都已準備好，可以即時創造夥伴形象。',
        actionLabel: '創造第一位夥伴',
      );
    }

    final missing = <String>[
      if (!brainReady) 'AI 服務授權碼', // [以利沙 P1 修復 2026-06-27] 去術語：雲端主腦 API Key → AI 服務授權碼
      if (!imageReady) '圖片生成金鑰',
    ];
    return SummonReadiness(
      brainReady: brainReady,
      imageReady: imageReady,
      brainProvider: brainProvider,
      imageProvider: imageProvider,
      imageProviderLabel: imageLabel,
      summary: '還需要設定 ${missing.join('、')}，才能讓 AI 助理即時生成夥伴形象。', // [以利沙 P1 修復 2026-06-27] 召喚鏡 → AI 助理
      actionLabel: '設定連線能力', // [以利沙 P1 修復 2026-06-27] 橋接 → 連線
    );
  }

  String _providerName(String? provider) {
    switch (provider) {
      case 'openai':
        return 'OpenAI';
      case 'replicate':
        return 'Replicate';
      case 'kimi':
        return 'Kimi';
      case 'minimax':
        return 'MiniMax';
      case 'claude':
        return 'Claude';
      case 'gemini':
        return 'Gemini';
      case null:
        return '圖片服務';
      default:
        return provider;
    }
  }
}
