// onboarding_detector.dart
// 桌面版 Agent 對話式 onboarding 偵測
//
// 啟動時偵測是否為「空白狀態」（無 API Key 或無 Companion），
// 如果是 → 產生歡迎引導訊息，讓使用者完成初始設定。
//
// [Phase 0 2026-07-17] 擴充：偵測 Companion 存在性，不只是 token
//
// 設計原則：
// - Agent 不碰 key 內容，只引導到設定頁
// - 偵測結果用 SharedPreferences 記住，不重複打擾
// - 歡迎訊息以 assistant role 注入對話，使用者看到時像 Agent 主動開口

import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import 'companion_store.dart';

class OnboardingStatus {
  /// 是否為首次安裝 / 空白狀態（無任何 provider token）
  final bool isEmptyState;

  /// [Phase 0 2026-07-17] 是否有 Companion（夥伴）
  final bool hasCompanion;

  /// 是否已經展示過 onboarding 歡迎訊息
  final bool onboardingShown;

  /// 已設定的 provider（如果有）
  final String? configuredProvider;

  /// 建議的 provider（用於引導訊息）
  final String recommendedProvider;

  const OnboardingStatus({
    required this.isEmptyState,
    required this.hasCompanion,
    required this.onboardingShown,
    this.configuredProvider,
    this.recommendedProvider = 'minimax',
  });

  /// 是否應該顯示 onboarding 歡迎訊息
  bool get shouldShowWelcome => (isEmptyState || !hasCompanion) && !onboardingShown;

  /// [Phase 0 2026-07-17] 完整的桌面 onboarding 階段
  /// null = 已完成 onboarding
  /// 'welcome' = 需要設定 API Key
  /// 'summon' = 需要召喚夥伴
  String? get desktopOnboardingStage {
    if (isEmptyState) return 'welcome';
    if (!hasCompanion) return 'summon';
    return null;
  }
}

class OnboardingDetector {
  static const String _keyOnboardingShown = 'desktop_onboarding_shown_v1';

  /// 偵測目前的 onboarding 狀態
  static Future<OnboardingStatus> detect() async {
    final detectedProvider = await StorageService.detectAvailableProvider();
    final hasToken = detectedProvider != null;

    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_keyOnboardingShown) ?? false;

    return OnboardingStatus(
      isEmptyState: !hasToken,
      hasCompanion: CompanionStore().all.isNotEmpty, // [Phase 0 2026-07-17]
      onboardingShown: shown,
      configuredProvider: detectedProvider,
    );
  }

  /// 標記 onboarding 歡迎訊息已展示
  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingShown, true);
  }

  /// 產生歡迎引導訊息（Agent 主動開口的內容）
  static String buildWelcomeMessage(OnboardingStatus status) {
    return '''你好！我是你的橋樑助理，歡迎來到橋樑計畫。

在我們開始之前，需要先設定一個 AI 服務讓我能夠運作。簡單來說，我需要一把「服務金鑰」才能跟你對話。

📌 推薦方案：MiniMax
• 註冊網址：https://platform.minimaxi.com/
• 有免費額度，台灣可直接使用
• 註冊後在「API Keys」頁面建立一把金鑰

其他選項：
• OpenAI（https://platform.openai.com/）— 功能最完整，需付費
• Kimi（https://platform.moonshot.cn/）— 中文能力強，有免費額度
• GLM（https://open.bigmodel.cn/）— 智譜 AI，中文優秀

拿到金鑰後：
1. 點左側「系統」→「設定」
2. 選擇你註冊的服務（如 MiniMax）
3. 貼上 API Key → 按「測試連線」→ 存檔

設定好之後回來跟我說一聲，我就可以開始幫你做事了！有任何問題隨時問我。''';
  }

  /// 產生設定完成後的確認訊息
  static String buildSetupCompleteMessage(String provider) {
    final providerName = _providerDisplayName(provider);
    return '太好了！$providerName 已經設定成功，我現在可以正常運作了。有什麼想做的事情，儘管告訴我！';
  }

  /// 產生「還沒設定」的提醒訊息（使用者試圖對話但沒設定時）
  static String buildNotYetSetupMessage() {
    return '''我還沒有連上任何 AI 服務，所以暫時無法回覆你的問題。

請先完成初始設定：
1. 到 https://platform.minimaxi.com/ 註冊 MiniMax（推薦，有免費額度）
2. 建立 API Key
3. 點左側「系統」→「設定」→ 選 MiniMax → 貼上金鑰 → 測試連線

設定完成後回來跟我說，我就能開始幫你了！''';
  }

  static String _providerDisplayName(String provider) {
    switch (provider.toLowerCase()) {
      case 'minimax':
        return 'MiniMax';
      case 'openai':
        return 'OpenAI';
      case 'kimi':
        return 'Kimi';
      case 'glm':
        return 'GLM';
      case 'gemini':
        return 'Gemini';
      case 'claude':
        return 'Claude';
      case 'local':
        return '本地模型';
      default:
        return provider;
    }
  }
}
