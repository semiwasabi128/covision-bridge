// [教練 Agent Sprint 17 Step 7 2026-07-07]
// Capability gap 相關的純函數 helpers — 從 chat_screen.dart 提取。
// 需要 BuildContext / setState 的方法留在 chat_screen.dart 裡當薄委派。
import 'dart:convert';

import '../../../models/bridge_action.dart';
import '../../../models/chat_card_data.dart';
import '../../../services/bridge_action_executor.dart';
import '../../../services/chat_intent_router.dart';

/// 從 BridgeActionResult 組裝 CapabilityGapCardData。
/// 依據 result.metadata['type'] 分派到不同能力缺口類型。
CapabilityGapCardData capabilityGapFromBridgeResult(
  BridgeActionResult result, {
  BridgeAction? bridgeAction,
}) {
  final type = result.metadata?['type']?.toString() ?? '';
  final prompt = result.metadata?['prompt']?.toString() ??
      bridgeAction?.prompt ??
      result.message;
  final route = result.metadata?['setupRoute']?.toString().trim().isNotEmpty == true
      ? result.metadata!['setupRoute'].toString().trim()
      : '/golden-keys?returnTo=/chat';
  final desktopRoute = routeWithReturnTo(route);
  switch (type) {
    case 'generate_music':
      return CapabilityGapCardData(
        title: '開通音樂生成能力',
        request: prompt,
        missing: '音樂生成服務 / SemiDAO 音樂插件',
        status: '橋樑已理解你的音樂任務，但目前沒有可執行的音樂生成服務。',
        route: route,
        routeLabel: '設定生成能力',
        iconName: 'music_note',
        steps: const [
          '到金鑰匙中心新增支援音樂生成的服務或插件。',
          '貼上官方 API Key 並完成連線測試。',
          '回到這段對話，重新執行已保留的音樂任務。',
        ],
        providerHints: const ['音樂生成服務官方入口', 'SemiDAO 音樂生成插件'],
      );
    case 'vision':
      return CapabilityGapCardData(
        title: '開通圖片識別能力',
        request: prompt,
        missing: '圖片理解服務 / 圖像理解插件',
        status: '橋樑已理解你的圖片分析任務，但目前尚未接上可用 Vision 能力。',
        route: route,
        routeLabel: '設定圖片理解能力',
        iconName: 'image_search',
        steps: const [
          '到金鑰匙中心確認支援 Vision 的服務。',
          '完成 API Key 或插件開通測試。',
          '回到這段對話，我會接續分析原本那張圖片。',
        ],
        providerHints: const ['OpenAI Vision', '支援圖像理解的雲端模型'],
      );
    case 'browse':
      return CapabilityGapCardData(
        title: '開通新聞與網頁搜尋能力',
        request: prompt,
        missing: 'OpenAI 網頁搜尋 / 搜尋橋服務',
        status: '橋樑已理解你的搜尋任務，但目前尚未接上可用的網頁搜尋金鑰匙。',
        route: route,
        routeLabel: '設定搜尋能力',
        iconName: 'travel_explore',
        steps: const [
          '到金鑰匙中心確認 OpenAI 或其他搜尋服務已設定。',
          '貼上官方 API Key 並完成連線測試。',
          '完成後回到原任務，我會繼續查找、整理來源與摘要。',
        ],
        providerHints: const ['OpenAI Web Search', 'Bridge Desktop 搜尋插件'],
      );
    case 'desktop_files':
      return CapabilityGapCardData(
        title: '開啟桌面整理橋',
        request: prompt,
        missing: 'Bridge Desktop 檔案讀取器 / 本機資料夾授權',
        status:
            '橋樑已理解你要整理本機檔案；目前這個畫面是開發預覽，不能直接讀取你的桌面。請改用桌面 App 測試，讓 Bridge Desktop 在本機安全掃描。',
        route: desktopRoute,
        routeLabel: '檢查桌面橋',
        iconName: 'desktop_windows',
        steps: const [
          '開啟 Bridge 桌面 App，確認桌面橋狀態為可用。',
          '授權要整理的桌面、下載或文件資料夾。',
          '回到這段任務，我會先只讀掃描並列出整理計畫；你確認後才會搬移檔案。',
        ],
        providerHints: const ['Bridge Desktop', '本機資料夾授權', '只讀掃描優先'],
      );
    case 'generate_image':
    case 'generate_animation':
    case 'generate_video':
      return CapabilityGapCardData(
        title: '開通生成能力',
        request: prompt,
        missing: result.metadata?['provider']?.toString() ?? '生成服務',
        status: result.message,
        route: route,
        routeLabel: '設定生成能力',
        iconName: 'auto_awesome',
        steps: const [
          '到金鑰匙中心確認對應生成服務已設定。',
          '貼上官方 API Key 並完成連線測試。',
          '回到這段對話，重新執行已保留的生成任務。',
        ],
        providerHints: const ['圖像 / 影片 / 動態生成官方服務', 'SemiDAO 插件'],
      );
    case 'document':
    default:
      return CapabilityGapCardData(
        title: '開通橋樑能力',
        request: prompt,
        missing: result.metadata?['provider']?.toString() ?? '橋樑服務',
        status: result.message,
        route:
            result.metadata?['setupRoute']?.toString() ?? '/settings?returnTo=/chat',
        routeLabel: '檢查設定',
        iconName: 'hub',
        steps: const [
          '檢查主腦金鑰匙、Gateway 與能力服務狀態。',
          '完成連線測試。',
          '回到這段對話，重新執行已保留的任務。',
        ],
        providerHints: const ['主腦服務', 'Bridge Gateway', '本地文件引擎'],
      );
  }
}

/// 嘗試從訊息內容解析 CapabilityGapCardData。
CapabilityGapCardData? tryParseCapabilityCard(String content) {
  if (!content.startsWith(capabilityCardPrefix)) return null;
  try {
    final jsonText = content.substring(capabilityCardPrefix.length);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return CapabilityGapCardData.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

/// 從 CapabilityGapCardData 推導對應的 BridgeActionType。
BridgeActionType? capabilityCardActionType(CapabilityGapCardData card) {
  final value =
      '${card.title} ${card.missing} ${card.iconName} ${card.routeLabel}'
          .toLowerCase();
  if (value.contains('搜尋') ||
      value.contains('網頁') ||
      value.contains('browse') ||
      value.contains('travel_explore')) {
    return BridgeActionType.browse;
  }
  if (value.contains('圖片識別') ||
      value.contains('圖片理解') ||
      value.contains('vision') ||
      value.contains('image_search')) {
    return BridgeActionType.vision;
  }
  if (value.contains('音樂') || value.contains('music')) {
    return BridgeActionType.generateMusic;
  }
  if (value.contains('影片') || value.contains('video')) {
    return BridgeActionType.generateVideo;
  }
  if (value.contains('圖片生成') || value.contains('auto_awesome')) {
    return BridgeActionType.generateImage;
  }
  if (value.contains('桌面') ||
      value.contains('檔案') ||
      value.contains('資料夾') ||
      value.contains('desktop')) {
    return BridgeActionType.desktopFiles;
  }
  return null;
}
