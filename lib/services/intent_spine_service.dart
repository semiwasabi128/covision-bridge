import '../models/bridge_action.dart';
import '../models/intent_spine.dart';
import '../services/semantic_intent/semantic_result.dart';

class IntentSpineService {
  const IntentSpineService();

  /// [Phase 2 #4] 帶語意路由結果的 analyze 變體。
  /// 不改 analyze() 同步簽名——在 chat_controller 層先跑 async 語意偵測，
  /// 將結果傳入此方法。semanticResult 非 null 時覆寫 _looksLike* 的判斷。
  /// semanticResult 為 null 時等同原始 analyze()。
  IntentSpine analyzeWithSemantic(
    String text, {
    bool hasImage = false,
    RoutingIntentResult? semanticResult,
  }) {
    if (semanticResult == null) {
      return analyze(text, hasImage: hasImage);
    }

    // 語意結果覆寫路由旗標
    final raw = text.trim();
    final normalized = _normalize(raw);
    if (normalized.isEmpty) {
      return analyze(text, hasImage: hasImage);
    }

    // 使用語意結果取代正則判斷
    final project = semanticResult.projectDoor;
    final assetReuse = semanticResult.assetReuse;
    final managedFolderRuleReuse = semanticResult.managedFolderRule;
    final capabilitySetup = semanticResult.capabilitySetup;
    final clarify = semanticResult.goalNeedsIntake;

    // 仍需正則輔助的判斷
    final conversationalFileTopic = _looksLikeConversationalFileTopic(normalized);
    final incompleteObservation = _looksLikeIncompleteObservation(normalized);
    final realtimeLookup =
        !conversationalFileTopic && _looksLikeRealtimeLookup(normalized);
    final analysisFirst =
        (semanticResult.isAnalysis || conversationalFileTopic) &&
        !realtimeLookup &&
        !_looksLikeExplicitExecutionCommit(normalized);
    final bridges = _suggestedBridgeTypes(
      normalized,
      hasImage: hasImage,
      conversationalFileTopic: conversationalFileTopic,
      analysisFirst: analysisFirst,
    );
    final execute =
        !managedFolderRuleReuse &&
        !conversationalFileTopic &&
        (_looksLikeDirectExecution(normalized) ||
            realtimeLookup ||
            (bridges.isNotEmpty && !analysisFirst));
    final vagueAesthetic = _looksLikeVagueAestheticRequest(normalized);
    final shouldAskClarifyingQuestion =
        incompleteObservation || (clarify && !project && !assetReuse) ||
        vagueAesthetic;

    final mode = project
        ? IntentSpineMode.project
        : assetReuse || managedFolderRuleReuse
        ? IntentSpineMode.assetReuse
        : capabilitySetup
        ? IntentSpineMode.capabilitySetup
        : analysisFirst
        ? IntentSpineMode.analyze
        : vagueAesthetic
        ? IntentSpineMode.clarify
        : execute
        ? IntentSpineMode.execute
        : clarify
        ? IntentSpineMode.clarify
        : IntentSpineMode.casual;

    final signals = <String>[
      if (analysisFirst) '使用者先要分析/判斷，不應直接開通能力',
      if (conversationalFileTopic) '使用者正在談檔案整理觀察或原則，不應直接開資料夾',
      if (shouldAskClarifyingQuestion) '意圖尚未完整，先反問釐清下一步',
      if (vagueAesthetic) '使用者用感覺/風格描述需求，需要反問釐清具體方向',
      if (execute) '使用者表達執行或查詢意圖',
      if (project) '語意像是在建立或分岔專案門',
      if (assetReuse) '語意像是在調用既有資產或玩法',
      if (managedFolderRuleReuse) '語意像是要先選擇已存整理規則',
      if (capabilitySetup) '語意像是在補能力或金鑰匙',
      if (bridges.isNotEmpty)
        '可能需要橋：${bridges.map((type) => type.displayLabel).join('、')}',
      if (hasImage) '包含圖片脈絡',
    ];

    return IntentSpine(
      rawText: raw,
      normalizedGoal: _summarizeGoal(raw, normalized, mode),
      mode: mode,
      confidence: _confidenceFor(
        mode,
        signals.length,
        hasBridge: bridges.isNotEmpty,
      ),
      signals: signals,
      suggestedBridgeTypes: bridges,
      shouldCheckReusableAssets:
          assetReuse ||
          managedFolderRuleReuse ||
          _looksLikeReusableAssetNeed(normalized),
      shouldCreateOrRouteProject: project,
      shouldExecuteImmediately: execute && !analysisFirst,
      shouldAnalyzeBeforeBridge:
          analysisFirst || mode == IntentSpineMode.clarify,
      shouldSelectManagedFolderRuleFirst: managedFolderRuleReuse,
      shouldAskClarifyingQuestion: shouldAskClarifyingQuestion,
      clarificationOptions: _clarificationOptionsFor(
        normalized,
        bridges,
        incompleteObservation: incompleteObservation,
      ),
    );
  }

  IntentSpine analyze(String text, {bool hasImage = false}) {
    final raw = text.trim();
    final normalized = _normalize(raw);
    if (normalized.isEmpty) {
      return IntentSpine(
        rawText: raw,
        normalizedGoal: hasImage ? '先理解使用者上傳圖片的用途。' : '等待使用者說明目的。',
        mode: hasImage ? IntentSpineMode.clarify : IntentSpineMode.casual,
        confidence: hasImage ? 0.74 : 0.52,
        signals: [if (hasImage) '只有圖片，還沒有文字意圖'],
        suggestedBridgeTypes: hasImage
            ? const [BridgeActionType.vision]
            : const [],
        shouldExecuteImmediately: false,
        shouldAnalyzeBeforeBridge: true,
      );
    }

    // [以利沙修正 2026-06-24] 先計算語境旗標，再傳給 _suggestedBridgeTypes() 做過濾
    final conversationalFileTopic = _looksLikeConversationalFileTopic(
      normalized,
    );
    final incompleteObservation = _looksLikeIncompleteObservation(normalized);
    final realtimeLookup =
        !conversationalFileTopic && _looksLikeRealtimeLookup(normalized);
    final analysisFirst =
        (_looksLikeAnalysisOrDecision(normalized) || conversationalFileTopic) &&
        !realtimeLookup &&
        !_looksLikeExplicitExecutionCommit(normalized);
    final bridges = _suggestedBridgeTypes(
      normalized,
      hasImage: hasImage,
      conversationalFileTopic: conversationalFileTopic,
      analysisFirst: analysisFirst,
    );
    final project = _looksLikeProjectDoor(normalized);
    final assetReuse = _looksLikeAssetReuse(normalized);
    final managedFolderRuleReuse = _looksLikeManagedFolderRuleReuse(normalized);
    final capabilitySetup = _looksLikeCapabilitySetup(normalized);
    final execute =
        !managedFolderRuleReuse &&
        !conversationalFileTopic &&
        (_looksLikeDirectExecution(normalized) ||
            realtimeLookup ||
            (bridges.isNotEmpty && !analysisFirst));
    final clarify = _looksLikeGoalButNeedsIntake(normalized) && !execute;
    final vagueAesthetic = _looksLikeVagueAestheticRequest(normalized);
    final shouldAskClarifyingQuestion =
        incompleteObservation || (clarify && !project && !assetReuse) ||
        vagueAesthetic;

    final mode = project
        ? IntentSpineMode.project
        : assetReuse || managedFolderRuleReuse
        ? IntentSpineMode.assetReuse
        : capabilitySetup
        ? IntentSpineMode.capabilitySetup
        : analysisFirst
        ? IntentSpineMode.analyze
        : vagueAesthetic
        ? IntentSpineMode.clarify
        : execute
        ? IntentSpineMode.execute
        : clarify
        ? IntentSpineMode.clarify
        : IntentSpineMode.casual;

    final signals = <String>[
      if (analysisFirst) '使用者先要分析/判斷，不應直接開通能力',
      if (conversationalFileTopic) '使用者正在談檔案整理觀察或原則，不應直接開資料夾',
      if (shouldAskClarifyingQuestion) '意圖尚未完整，先反問釐清下一步',
      if (vagueAesthetic) '使用者用感覺/風格描述需求，需要反問釐清具體方向',
      if (execute) '使用者表達執行或查詢意圖',
      if (project) '語意像是在建立或分岔專案門',
      if (assetReuse) '語意像是在調用既有資產或玩法',
      if (managedFolderRuleReuse) '語意像是要先選擇已存整理規則',
      if (capabilitySetup) '語意像是在補能力或金鑰匙',
      if (bridges.isNotEmpty)
        '可能需要橋：${bridges.map((type) => type.displayLabel).join('、')}',
      if (hasImage) '包含圖片脈絡',
    ];

    return IntentSpine(
      rawText: raw,
      normalizedGoal: _summarizeGoal(raw, normalized, mode),
      mode: mode,
      confidence: _confidenceFor(
        mode,
        signals.length,
        hasBridge: bridges.isNotEmpty,
      ),
      signals: signals,
      suggestedBridgeTypes: bridges,
      shouldCheckReusableAssets:
          assetReuse ||
          managedFolderRuleReuse ||
          _looksLikeReusableAssetNeed(normalized),
      shouldCreateOrRouteProject: project,
      shouldExecuteImmediately: execute && !analysisFirst,
      shouldAnalyzeBeforeBridge:
          analysisFirst || mode == IntentSpineMode.clarify,
      shouldSelectManagedFolderRuleFirst: managedFolderRuleReuse,
      shouldAskClarifyingQuestion: shouldAskClarifyingQuestion,
      clarificationOptions: _clarificationOptionsFor(
        normalized,
        bridges,
        incompleteObservation: incompleteObservation,
      ),
    );
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _containsAny(String text, Iterable<String> needles) {
    return needles.any(text.contains);
  }

  bool _looksLikeAnalysisOrDecision(String text) {
    return _containsAny(text, const [
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
      '適合嗎',
      '值不值得',
    ]);
  }

  bool _looksLikeConversationalFileTopic(String text) {
    final fileTopic = _containsAny(text, const [
      '整理資料',
      '整理檔案',
      '整理資料夾',
      '檔案資料',
      '資料夾',
      '檔案',
    ]);
    if (!fileTopic) return false;

    final asksPrinciple = _containsAny(text, const [
      '原則',
      '平常',
      '通常',
      '你會怎麼',
      '你怎麼',
      '怎麼看',
      '為什麼',
      '什麼意思',
      '是什麼',
      '差別',
    ]);
    final describesObservation = _containsAny(text, const [
      '發現',
      '現象',
      '有趣',
      '想到',
      '我注意到',
      '我看到',
      '剛才',
      '剛剛',
    ]);
    return asksPrinciple || describesObservation;
  }

  bool _looksLikeIncompleteObservation(String text) {
    final fileTopic = _containsAny(text, const [
      '整理資料',
      '整理檔案',
      '整理資料夾',
      '檔案資料',
      '資料夾',
      '檔案',
    ]);
    if (!fileTopic) return false;
    final describesObservation = _containsAny(text, const [
      '發現',
      '現象',
      '有趣',
      '想到',
      '我注意到',
      '我看到',
    ]);
    if (!describesObservation) return false;
    final asksQuestion = _containsAny(text, const [
      '什麼',
      '為什麼',
      '怎麼',
      '如何',
      '可以嗎',
      '嗎',
      '？',
      '?',
    ]);
    final explicitExecution = _looksLikeExplicitExecutionCommit(text);
    return !asksQuestion && !explicitExecution;
  }

  bool _looksLikeRealtimeLookup(String text) {
    // [教練 Agent 2026-07-22] 排除閒聊用語——「最近過得怎樣」「今天天氣不錯」不是即時查詢
    final casualPatterns = const [
      '過得', '好嗎', '怎樣', '怎麼樣', '還好',
      '最近過', '最近好', '最近怎',
      '不錯', '很好', '真好', '不錯呢', '不錯啊',
      '真好呢', '很好啊',
    ];
    final isCasualGreeting = casualPatterns.any((p) => text.contains(p));
    if (isCasualGreeting) return false;

    // 查詢型詞彙需要搭配疑問詞或查詢動詞才算即時查詢
    // 「今天天氣」 alone 不是查詢；「今天天氣如何」「查今天天氣」才是
    final queryWords = const ['今天', '今日', '現在', '目前', '最新', '即時', '最近', '時刻表', '班次', '天氣', '股價', '新聞'];
    final hasQueryWord = queryWords.any((w) => text.contains(w));
    if (!hasQueryWord) return false;

    // 必須同時有疑問詞或查詢動詞
    final questionMarkers = const [
      '如何', '怎樣', '嗎', '呢？', '多少', '幾點', '什麼',
      '查', '找', '看', '搜尋', '搜索', '告訴我', '給我',
    ];
    final hasQuestion = questionMarkers.any((w) => text.contains(w));
    if (!hasQuestion) return false;

    return true;
  }

  bool _looksLikeDirectExecution(String text) {
    return _containsAny(text, const [
      '幫我',
      '請幫我',
      '開始做',
      '開始動手',
      '開始執行',
      '執行',
      '產出',
      '生成',
      '建立',
      '整理',
      '掃描',
      '查',
      '查詢',
      '寫一份',
      '做一份',
      '輸出',
      '保存',
      '轉成',
    ]);
  }

  bool _looksLikeExplicitExecutionCommit(String text) {
    return _containsAny(text, const [
      '開始做',
      '開始動手',
      '開始執行',
      '立刻執行',
      '直接做',
      '幫我產出',
      '幫我生成',
      '幫我整理',
      '幫我掃描',
      '幫我查',
      '請幫我產出',
      '請幫我生成',
      '請幫我整理',
      '請幫我掃描',
      '照這個做',
      '就這麼做',
      '我們開始',
    ]);
  }

  bool _looksLikeProjectDoor(String text) {
    final hasProjectWord = _containsAny(text, const [
      '專案',
      '專案門',
      '計畫',
      'project',
      '案子',
    ]);
    final hasStartOrFork = _containsAny(text, const [
      '開一個',
      '開個',
      '建立',
      '創建',
      '啟動',
      '立案',
      '分出來',
      '拉出來',
      '另開',
      '新開',
      '獨立',
      '把它變成',
      '做起來',
      '一步一步帶我',
    ]);
    return hasProjectWord && hasStartOrFork;
  }

  bool _looksLikeAssetReuse(String text) {
    final reuseVerb = _containsAny(text, const [
      '引用',
      '調用',
      '套用',
      '導入',
      '引入',
      '拿來用',
      '接上',
      '移植',
      '共享',
      '共用',
      '重用',
      '沿用',
    ]);
    final assetNoun = _containsAny(text, const [
      '數位資產',
      '資產',
      '玩法',
      '引擎',
      '插件',
      '工作流',
      '規則',
      '橋',
      '能力',
      '角色',
    ]);
    return reuseVerb && assetNoun;
  }

  bool _looksLikeManagedFolderRuleReuse(String text) {
    final reuseVerb = _containsAny(text, const [
      '沿用',
      '套用',
      '匯入',
      '導入',
      '使用',
      '用之前',
      '用上次',
      '照之前',
      '照上次',
      '照這條',
      '照這個',
      '用這條',
      '用這個',
      '拿來用',
      '重用',
    ]);
    final savedSignal = _containsAny(text, const [
      '之前',
      '上次',
      '以前',
      '已存',
      '已儲存',
      '保存',
      '保存過',
      '儲存',
      '儲存過',
      '存檔',
      '存起來',
      '存過',
      '舊',
      '既有',
    ]);
    final ruleNoun = _containsAny(text, const [
      '整理規則',
      '規則',
      '整理方式',
      '歸檔規則',
      '分類規則',
      '規則檔',
      '規則文件',
    ]);
    return reuseVerb && ruleNoun && savedSignal;
  }

  bool _looksLikeReusableAssetNeed(String text) {
    return _containsAny(text, const [
      '不要重新做',
      '不用重新造輪子',
      '之前做過',
      '既有',
      '已有',
      '以前那個',
      '上次那個',
      '同一套',
    ]);
  }

  bool _looksLikeCapabilitySetup(String text) {
    return _containsAny(text, const [
      '開通能力',
      '設定能力',
      '設定金鑰',
      'api key',
      '金鑰匙',
      '接上服務',
      '接橋',
      'provider',
    ]);
  }

  bool _looksLikeGoalButNeedsIntake(String text) {
    return _containsAny(text, const [
      '我想',
      '我希望',
      '我要',
      '目標',
      '需求',
      '想做',
      '打算',
    ]);
  }

  /// [教練 Agent 2026-07-20] 感覺/風格描述——使用者的需求沒有具體到可以直接執行
  /// 例：「更有質感」「有呼吸感」「太擠」「廉價感」「不舒服」「更精緻」
  /// 這類輸入不應該直接讀碼動手改，應該先反問釐清
  /// 但如果使用者已經給了具體方向（參考 App、具體屬性、具體區域），就不反問
  bool _looksLikeVagueAestheticRequest(String text) {
    final hasVagueWord = _containsAny(text, const [
      '質感', '呼吸感', '太擠', '廉價', '不舒服', '精緻',
      '高級感', '廉價感', '感覺不對', '看起來怪', '不順眼',
      '不太對勁', '有感覺', '沒感覺', '你懂那種感覺', '什麼感覺',
      '風格', '味道', '氛圍', '氣質', '品味',
    ]);
    if (!hasVagueWord) return false;

    // 使用者已經給了具體方向——不反問，讓 AgentLoop 處理
    final hasSpecificDirection = _containsAny(text, const [
      'Notion', 'Figma', 'Linear', 'Apple', 'iOS',
      '間距', '距離', 'padding', 'margin',
      '色調', '顏色', '背景色', '文字色',
      '圓角', '字級', '字體',
      '留白', '乾淨',
      '太近', '太遠', '太深', '太淺', '太大', '太小',
      '參考', '像.*那樣',
    ]);
    return !hasSpecificDirection;
  }

  // [以利沙修正 2026-06-24] 加入語境旗標過濾：
  // conversationalFileTopic=true 時不填 desktopFiles；
  // analysisFirst=true 時不填 generateVideo/generateMusic/generateImage 等執行型橋
  List<BridgeActionType> _suggestedBridgeTypes(
    String text, {
    required bool hasImage,
    bool conversationalFileTopic = false,
    bool analysisFirst = false,
  }) {
    final types = <BridgeActionType>{
      if (hasImage || _containsAny(text, const ['圖片辨識', '看圖', '識別圖', '圖像內容']))
        BridgeActionType.vision,
      if (_containsAny(text, const ['新聞', '搜尋', '查詢', '上網', '時刻表', '班次']))
        BridgeActionType.browse,
      if (_containsAny(text, const ['文件', '報告', 'pdf', '企劃', 'markdown']))
        BridgeActionType.document,
      if (!conversationalFileTopic &&
          _containsAny(text, const ['桌面', '資料夾', '檔案', '整理資料']))
        BridgeActionType.desktopFiles,
      if (!analysisFirst &&
          _containsAny(text, const ['音樂', '配樂', '歌曲', '作曲']))
        BridgeActionType.generateMusic,
      if (!analysisFirst &&
          _containsAny(text, const ['影片', '短片', '直播', '影像']))
        BridgeActionType.generateVideo,
      if (!analysisFirst &&
          _containsAny(text, const ['生成圖片', '畫一張', '圖像生成']))
        BridgeActionType.generateImage,
    };
    return types.toList(growable: false);
  }

  String _summarizeGoal(String raw, String normalized, IntentSpineMode mode) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return mode.label;
    if (cleaned.length <= 72) return cleaned;
    if (_containsAny(normalized, const ['直播帶貨', '銷售商品'])) {
      return '把 AI 角色直播帶貨從想法推進成可落地專案。';
    }
    if (_containsAny(normalized, const ['整理', '桌面', '資料夾', '檔案'])) {
      return '整理使用者指定資料並產出可確認的整理方案。';
    }
    if (_containsAny(normalized, const ['專案', '專案門'])) {
      return '把目前討論整理成可追蹤的專案門與水流。';
    }
    return '${cleaned.substring(0, 72)}...';
  }

  double _confidenceFor(
    IntentSpineMode mode,
    int signalCount, {
    required bool hasBridge,
  }) {
    var score = switch (mode) {
      IntentSpineMode.casual => 0.56,
      IntentSpineMode.clarify => 0.68,
      IntentSpineMode.analyze => 0.78,
      IntentSpineMode.execute => 0.76,
      IntentSpineMode.project => 0.84,
      IntentSpineMode.assetReuse => 0.82,
      IntentSpineMode.capabilitySetup => 0.78,
    };
    score += (signalCount * 0.025).clamp(0.0, 0.12);
    if (hasBridge) score += 0.04;
    return score.clamp(0.0, 0.96).toDouble();
  }

  List<String> _clarificationOptionsFor(
    String text,
    List<BridgeActionType> bridges, {
    required bool incompleteObservation,
  }) {
    if (incompleteObservation &&
        bridges.contains(BridgeActionType.desktopFiles)) {
      return const ['先聽你描述這個現象', '分析整理原則', '掃描資料夾並列整理計畫'];
    }
    if (bridges.isNotEmpty) {
      return ['先分析可行性', '問你幾個問題釐清目標', '直接開始執行 ${bridges.first.displayLabel}'];
    }
    return const ['先聊天釐清', '整理成目標', '建立專案門'];
  }
}
