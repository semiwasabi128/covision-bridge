// lib/services/chat_intent_router.dart
// [以利沙 Sprint 2 2026-06-24]
// Top-level intent routing functions extracted from chat_screen.dart.
// [Phase 2] 新增語意版覆寫方法——feature flag 開啟時使用 SemanticIntentService。

import '../models/bridge_action.dart';
import '../services/intent_spine_service.dart';
import '../services/semantic_intent/semantic_intent_service.dart';
import '../services/semantic_intent/semantic_result.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

bool containsAnyText(String text, List<String> needles) {
  return needles.any(text.contains);
}

// ── Helpers (exported for use in chat_screen) ─────────────────────────────────

bool isAnalysisOrFeasibilityQuestion(String text) {
  return containsAnyText(text, const [
    '可行嗎',
    '可不可行',
    '是否可行',
    '行得通',
    '你覺得',
    '評估',
    '分析',
    '判斷',
    '建議',
    '怎麼做',
    '如何做',
    '怎麼開始',
    '流程',
    '工作流',
    '架構',
    '規劃',
    '需要哪些',
    '需要什麼',
    '有哪些',
    '哪些選擇',
    '什麼選擇',
    '怎麼用',
    '如何用',
    '可以怎麼',
    '是什麼',
    '原則',
    '會不會',
  ]);
}

bool isRealtimeLookupQuestion(String text) {
  // [Phase 2 #12 快速修復] 排除社交語句中的「最近」誤判
  // 「最近過得好嗎」「最近好嗎」「最近怎樣」等社交語句不應觸發即時查詢
  final socialPatterns = [
    '最近過得',
    '最近好',
    '最近怎樣',
    '最近怎麼樣',
    '最近過的好',
    '最近過的好嗎',
    '最近好嗎',
    '最近還好嗎',
    '最近忙什麼',
    '最近在忙',
    '最近做什麼',
    '最近在幹嘛',
    '最近在做什麼',
  ];
  for (final pattern in socialPatterns) {
    if (text.contains(pattern)) return false;
  }

  return containsAnyText(text, const [
    '今天',
    '今日',
    '現在',
    '目前',
    '最新',
    '即時',
    '最近',
    '時刻表',
    '班次',
    '天氣',
    '股價',
    '匯率',
    'today',
    'latest',
    'current',
    'now',
  ]);
}

// ── Public API ────────────────────────────────────────────────────────────────

BridgeAction? inferChatBridgeActionForRequest(
  String text, {
  String? imagePath,
}) {
  final normalized = text.trim().toLowerCase();
  final hasImage = imagePath != null && imagePath.trim().isNotEmpty;
  if (normalized.isEmpty) return null;
  final intentSpine = const IntentSpineService().analyze(
    text,
    hasImage: hasImage,
  );
  final wantsAnalysisFirst = intentSpine.shouldAnalyzeBeforeBridge;
  if (intentSpine.shouldSelectManagedFolderRuleFirst) return null;

  final asksImageRecognition =
      hasImage &&
      containsAnyText(normalized, const [
        '識別',
        '辨識',
        '看得懂',
        '看一下',
        '看圖',
        '分析',
        '內容',
        '這是什麼',
        '是什麼',
        '圖中',
        '畫面',
        'recognize',
        'describe',
        'vision',
      ]);
  if (asksImageRecognition) {
    return BridgeAction(
      type: BridgeActionType.vision,
      prompt: text,
      referenceImagePaths: [imagePath.trim()],
    );
  }
  if (hasImage) return null;
  if (containsAnyText(normalized, const [
    '音樂',
    '作曲',
    '配樂',
    '歌曲',
    '生成音',
    'music',
    'song',
    'soundtrack',
  ])) {
    if (wantsAnalysisFirst) return null;
    return BridgeAction(type: BridgeActionType.generateMusic, prompt: text);
  }
  if (containsAnyText(normalized, const [
    '影片',
    '短片',
    '分鏡',
    '動畫影片',
    'video',
    'movie',
  ])) {
    if (wantsAnalysisFirst) return null;
    return BridgeAction(type: BridgeActionType.generateVideo, prompt: text);
  }
  if (containsAnyText(normalized, const [
    '文件',
    '報告',
    'pdf',
    '清單',
    '企劃',
    '整理成',
    '輸出檔案',
    '存成',
    'markdown',
    'document',
    'report',
  ])) {
    if (wantsAnalysisFirst) return null;
    return BridgeAction(type: BridgeActionType.document, prompt: text);
  }
  if (containsAnyText(normalized, const [
    '新聞',
    '最新',
    '搜尋',
    '查',
    '查詢',
    '上網',
    '網頁',
    '瀏覽',
    '時刻表',
    '班次',
    '火車',
    '高鐵',
    '公車',
    '捷運',
    '車站',
    '航班',
    '天氣',
    '匯率',
    '股價',
    'browser',
    'search',
    'news',
    'schedule',
    'timetable',
  ])) {
    if (wantsAnalysisFirst && !isRealtimeLookupQuestion(normalized)) {
      return null;
    }
    return BridgeAction(type: BridgeActionType.browse, prompt: text);
  }
  if (containsAnyText(normalized, const [
    '桌面',
    '檔案',
    '資料夾',
    '本機',
    '整理資料',
    '掃描桌面',
    '掃描檔案',
    '列出桌面',
    '找檔案',
    'desktop',
    'folder',
    'local file',
  ])) {
    if (wantsAnalysisFirst) return null;
    return BridgeAction(type: BridgeActionType.desktopFiles, prompt: text);
  }
  return null;
}

bool shouldSkipCapabilityGapForRequest(String text, {String? imagePath}) {
  final normalized = text.trim().toLowerCase();
  final intentSpine = const IntentSpineService().analyze(
    text,
    hasImage: imagePath != null && imagePath.trim().isNotEmpty,
  );
  if (intentSpine.shouldAskClarifyingQuestion) return true;
  if (intentSpine.shouldAnalyzeBeforeBridge &&
      !isRealtimeLookupQuestion(normalized)) {
    return true;
  }
  return false;
}

bool shouldShowCapabilityGapForRequest(String text, {String? imagePath}) {
  return !shouldSkipCapabilityGapForRequest(text, imagePath: imagePath);
}

String routeWithReturnTo(String route, {String returnTo = '/chat'}) {
  final uri = Uri.parse(route);
  if (uri.queryParameters.containsKey('returnTo')) return route;
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'returnTo': returnTo})
      .toString();
}

String desktopBridgeSetupRoute({String returnTo = '/chat'}) {
  return routeWithReturnTo('/bridge-desktop', returnTo: returnTo);
}

// ── Phase 2: Semantic overrides ──────────────────────────────────────────────

/// [Phase 2 #11] 語意版 isAnalysisOrFeasibilityQuestion()。
/// 使用 SemanticIntentService.classifyRoutingIntent() 的 isAnalysis 欄位。
/// feature flag 關閉時 fallback 到正則版。
Future<bool> isAnalysisOrFeasibilityQuestionSemantic(
  String text,
  SemanticIntentService? semanticService, {
  List<({String role, String content})> history = const [],
}) async {
  if (semanticService != null) {
    try {
      final result = await semanticService.classifyRoutingIntent(
        message: text,
        history: history,
      );
      if (result != null && result.confidence >= 0.7) {
        return result.isAnalysis;
      }
    } catch (_) {}
  }
  return isAnalysisOrFeasibilityQuestion(text);
}

/// [Phase 2 #13] 語意版 inferChatBridgeActionForRequest()。
/// 使用 SemanticIntentService.inferBridgeAction()。
/// L1 正則快車道先跑（inferChatBridgeActionForRequest），
/// L1 未命中時走 L3 LLM。feature flag 關閉時直接走正則版。
Future<BridgeAction?> inferChatBridgeActionForRequestSemantic(
  String text, {
  String? imagePath,
  SemanticIntentService? semanticService,
  List<({String role, String content})> history = const [],
}) async {
  // 先跑正則版（L1 快車道）
  final regexResult = inferChatBridgeActionForRequest(text, imagePath: imagePath);
  if (regexResult != null) return regexResult;

  // L1 未命中 → 嘗試 L3 LLM
  if (semanticService != null) {
    try {
      final hasImage = imagePath != null && imagePath.trim().isNotEmpty;
      final result = await semanticService.inferBridgeAction(
        message: text,
        history: history,
        hasImage: hasImage,
      );
      if (result != null && result.confidence >= 0.7) {
        // 將 bridgeType 字串轉為 BridgeActionType
        final type = _parseBridgeActionType(result.bridgeType);
        if (type != null) {
          return BridgeAction(
            type: type,
            prompt: text,
            referenceImagePaths: hasImage ? [imagePath!.trim()] : const [],
          );
        }
      }
    } catch (_) {}
  }

  return null;
}

BridgeActionType? _parseBridgeActionType(String type) {
  switch (type.toLowerCase()) {
    case 'vision':
      return BridgeActionType.vision;
    case 'generatemusic':
      return BridgeActionType.generateMusic;
    case 'generatevideo':
      return BridgeActionType.generateVideo;
    case 'generateimage':
      return BridgeActionType.generateImage;
    case 'document':
      return BridgeActionType.document;
    case 'browse':
      return BridgeActionType.browse;
    case 'desktopfiles':
      return BridgeActionType.desktopFiles;
    default:
      return null;
  }
}
