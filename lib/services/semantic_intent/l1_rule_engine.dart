// l1_rule_engine.dart
// L1 規則引擎——明確指令短路器 + 安全防護 + 格式清理。
// 正則匹配「建/開/啟動/新增 + 專案/門/計畫 + 引號名稱」→ 信心 0.95 直接回傳。
// 無 LLM 呼叫，無網路，無延遲。

import 'semantic_result.dart';

class L1RuleEngine {
  /// 明確指令正則（設計文件 §6.4）
  /// 匹配：開/建/啟動/新增 + (一個|個)? + (專案|門|計畫)? + 引號名稱
  /// 引號支援：中文「」『』、英文 "' 
  static final RegExp _explicitDoorPattern = RegExp(
    r"""(?:開|建|啟動|新增)\s*(?:一個|個)?\s*(?:專案|門|計畫)?\s*[「『"']([^」』"']+)[」』"']""",
  );

  /// 偵測門意圖（L1 規則層）。
  /// 命中明確指令 → 信心 0.95 回傳 DoorIntentResult。
  /// 未命中 → 回傳 null（交由 L3）。
  DoorIntentResult? detectDoorIntent({required String message}) {
    // === 安全防護 ===
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 500) return null;
    // 純標點/空白
    if (RegExp(r'^[\s\p{P}]+$', unicode: true).hasMatch(trimmed)) return null;

    // === 格式清理：連續空白合併 ===
    final cleaned = trimmed.replaceAll(RegExp(r'\s+'), ' ');

    // === 明確指令短路器 ===
    final match = _explicitDoorPattern.firstMatch(cleaned);
    if (match != null) {
      final projectName = match.group(1)?.trim();
      if (projectName != null && projectName.isNotEmpty) {
        return DoorIntentResult(
          shouldCreateDoor: true,
          projectName: projectName,
          titleSource: TitleSource.userNamed,
          confidence: 0.95,
          reasoning: 'L1 規則命中：明確指令 + 引號命名',
          shouldClarify: false,
        );
      }
    }

    return null;
  }

  // ============================================================
  // extractDoorTitle —— 門命名提取（Sprint 1.2）
  // ============================================================

  /// 泛詞黑名單——匹配到這些不回傳，交由 L3 處理。
  /// [以西結審查 C] 擴充泛詞，避免「專案」「計畫」等被當門名
  static const Set<String> _genericTitles = {
    '個新', '新', '一個新', '個', '新的', '一個', '名字叫', '名叫',
    '專案', '計畫', '門', '項目', '東西', '事情', '系統',
  };

  /// 規則 1：「叫做/叫/命名為/取名為」+ 引號 → userNamed, 0.95
  static final RegExp _namedWithQuotePattern = RegExp(
    r"""(?:叫做|叫|命名為|取名為)\s*[「『"']([^」』"']+)[」』"']""",
  );

  /// 規則 2：「叫做/叫/命名為/取名為」+ 無引號（CJK+ASCII 2-40字）
  static final RegExp _namedNoQuotePattern = RegExp(
    r'(?:叫做|叫|命名為|取名為)\s*([\u4e00-\u9fff\u3400-\u4dbf\w]{2,40})',
  );

  /// 規則 3：純引號（「」『』""'' 2-40字）
  static final RegExp _pureQuotePattern = RegExp(
    r"""[「『"']([^」』"']{2,40})[」』"']""",
  );

  /// 規則 4：「建立/創建/開一個/做一個/啟動一個/新開/另開」+ 名稱 + 「的?專案/計畫」
  static final RegExp _createProjectPattern = RegExp(
    r'(?:建立|創建|開一個|做一個|啟動一個|新開|另開)\s*([\u4e00-\u9fff\u3400-\u4dbf\w]{2,40}?)\s*的?(?:專案|計畫)',
  );

  /// 提取門名稱（L1 規則層）。
  /// 按優先序匹配四條規則，命中 → 回傳 DoorTitleResult。
  /// 泛詞過濾 → 跳過該規則繼續嘗試下一條。
  /// 全部未命中 → 回傳 null（交由 L3）。
  DoorTitleResult? extractDoorTitle({required String message}) {
    // === 安全防護（同 detectDoorIntent）===
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 500) return null;
    if (RegExp(r'^[\s\p{P}]+$', unicode: true).hasMatch(trimmed)) return null;

    final cleaned = trimmed.replaceAll(RegExp(r'\s+'), ' ');

    // === 規則 1：命名動詞 + 引號（信心 0.95）===
    final m1 = _namedWithQuotePattern.firstMatch(cleaned);
    if (m1 != null) {
      final title = m1.group(1)?.trim();
      if (title != null && title.isNotEmpty && !_genericTitles.contains(title)) {
        return DoorTitleResult(
          title: title,
          titleSource: TitleSource.userNamed,
          confidence: 0.95,
          reasoning: 'L1 規則 1 命中：命名動詞 + 引號',
        );
      }
    }

    // === 規則 2：命名動詞 + 無引號（信心 0.90）===
    final m2 = _namedNoQuotePattern.firstMatch(cleaned);
    if (m2 != null) {
      final title = m2.group(1)?.trim();
      if (title != null && title.isNotEmpty && !_genericTitles.contains(title)) {
        return DoorTitleResult(
          title: title,
          titleSource: TitleSource.userNamed,
          confidence: 0.90,
          reasoning: 'L1 規則 2 命中：命名動詞 + 無引號',
        );
      }
    }

    // === 規則 3：純引號（信心 0.80）[以西結審查 C] 下調信心，讓規則 4 有競爭空間 ===
    final m3 = _pureQuotePattern.firstMatch(cleaned);
    if (m3 != null) {
      final title = m3.group(1)?.trim();
      if (title != null && title.isNotEmpty && !_genericTitles.contains(title)) {
        return DoorTitleResult(
          title: title,
          titleSource: TitleSource.userNamed,
          confidence: 0.80,
          reasoning: 'L1 規則 3 命中：純引號',
        );
      }
    }

    // === 規則 4：建立/創建 + 名稱 + 專案/計畫（信心 0.85）===
    final m4 = _createProjectPattern.firstMatch(cleaned);
    if (m4 != null) {
      final title = m4.group(1)?.trim();
      if (title != null && title.isNotEmpty && !_genericTitles.contains(title)) {
        return DoorTitleResult(
          title: title,
          titleSource: TitleSource.userNamed,
          confidence: 0.85,
          reasoning: 'L1 規則 4 命中：建立/創建 + 名稱 + 專案/計畫',
        );
      }
    }

    return null;
  }

  // ============================================================
  // detectDoorDrift —— 門漂移偵測（Sprint 1.3）
  // ============================================================

  /// 泛詞黑名單——門標題含這些詞時不單獨用來判斷漂移。
  static const Set<String> _genericDoorWords = {
    '專案', '計畫', '項目', '新的', '橋樑', '門', '系統', '東西', '事情',
  };

  /// 從門標題提取關鍵詞（連續中文 ≥2 字 or 英文 ≥3 字）。
  /// 過濾泛詞後用於漂移比對。
  List<String> extractDoorKeywords(String doorTitle) {
    var words = <String>[];
    final cjkPattern = RegExp(r'[\u4e00-\u9fff]{2,}');
    final engPattern = RegExp(r'[A-Za-z]{3,}');
    words.addAll(cjkPattern.allMatches(doorTitle).map((m) => m.group(0)!));
    words.addAll(engPattern.allMatches(doorTitle).map((m) => m.group(0)!));
    return words.where((w) => !_genericDoorWords.contains(w)).toList();
  }

  /// L1 門漂移偵測——規則版（寧可漏報不可誤報）。
  /// 邏輯：
  /// 1. 提取門標題關鍵詞
  /// 2. 檢查最近訊息是否包含任何關鍵詞
  /// 3. 全部不匹配 → 信心 0.7 報漂移
  /// 4. 有任一匹配 → 不漂移
  /// 5. 門標題無關鍵詞 → 回傳 null（交由 L3）
  DoorDriftResult? detectDoorDrift({
    required String doorTitle,
    required List<String> recentMessages,
    int checkWindow = 5,
  }) {
    if (doorTitle.isEmpty) return null;

    final keywords = extractDoorKeywords(doorTitle);
    if (keywords.isEmpty) return null;

    final recentText =
        recentMessages.take(checkWindow).join(' ').toLowerCase();
    if (recentText.isEmpty) return null;

    for (final word in keywords) {
      if (recentText.contains(word.toLowerCase())) {
        // 有匹配 = 沒漂移
        return DoorDriftResult(
          isDrifting: false,
          confidence: 0.85,
          reasoning: 'L1 規則：門關鍵詞「$word」在近期訊息中找到',
        );
      }
    }

    // 全部不匹配 = 可能漂移
    return DoorDriftResult(
      isDrifting: true,
      confidence: 0.7,
      reasoning: 'L1 規則：門關鍵詞 ${keywords.join('、')} 在最近 $checkWindow 條訊息中均未出現',
      suggestion: '最近聊的內容似乎和「$doorTitle」不同——要不要開一個新門？',
    );
  }

  // ============================================================
  // Phase 2: classifyRoutingIntent —— 路由意圖分類（L1 關鍵字短路）
  // ============================================================

  /// L1 路由意圖分類——關鍵字交集短路。
  /// 信心 ≥0.9 時直接回傳，否則回傳 null 交由 L3。
  /// 覆蓋 #4 (projectDoor), #7 (assetReuse), #8 (managedFolderRule),
  /// #9 (capabilitySetup), #10 (goalNeedsIntake), #11 (isAnalysis)。
  RoutingIntentResult? classifyRoutingIntent({required String message}) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    final text = trimmed.toLowerCase();

    // #4 projectDoor
    final hasProjectWord = _containsAny(text, const [
      '專案', '專案門', '計畫', 'project', '案子',
    ]);
    final hasStartOrFork = _containsAny(text, const [
      '開一個', '開個', '建立', '創建', '啟動', '立案',
      '分出來', '拉出來', '另開', '新開', '獨立', '把它變成', '做起來',
    ]);
    final projectDoor = hasProjectWord && hasStartOrFork;

    // #7 assetReuse
    final reuseVerb = _containsAny(text, const [
      '引用', '調用', '套用', '導入', '引入', '拿來用', '接上', '移植', '共享', '共用', '重用', '沿用',
    ]);
    final assetNoun = _containsAny(text, const [
      '數位資產', '資產', '玩法', '引擎', '插件', '工作流', '規則', '橋', '能力', '角色',
    ]);
    final assetReuse = reuseVerb && assetNoun;

    // #8 managedFolderRule
    final ruleNoun = _containsAny(text, const [
      '整理規則', '規則', '整理方式', '歸檔規則', '分類規則', '規則檔', '規則文件',
    ]);
    final savedSignal = _containsAny(text, const [
      '之前', '上次', '以前', '已存', '已儲存', '保存', '保存過', '儲存', '儲存過', '存檔', '存起來', '存過', '舊', '既有',
    ]);
    final managedFolderRule = reuseVerb && ruleNoun && savedSignal;

    // #9 capabilitySetup
    final capabilitySetup = _containsAny(text, const [
      '開通能力', '設定能力', '設定金鑰', 'api key', '金鑰匙', '接上服務', '接橋', 'provider',
    ]);

    // #10 goalNeedsIntake
    final goalNeedsIntake = _containsAny(text, const [
      '我想', '我希望', '我要', '目標', '需求', '想做', '打算',
    ]);

    // #11 isAnalysis
    final isAnalysis = _containsAny(text, const [
      '可行嗎', '可不可行', '是否可行', '行得通', '你覺得', '評估', '分析', '判斷', '建議',
      '怎麼做', '如何做', '怎麼開始', '流程', '工作流', '架構', '規劃', '需要哪些', '需要什麼',
      '有哪些', '哪些選擇', '什麼選擇', '怎麼用', '如何用', '可以怎麼', '是什麼', '原則', '會不會', '適合嗎', '值不值得',
    ]);

    // 只有當有明確命中時才短路
    final hasAny = projectDoor || assetReuse || managedFolderRule ||
        capabilitySetup || goalNeedsIntake || isAnalysis;

    if (!hasAny) {
      // 全部不命中 → 可能是閒聊/執行意圖，回傳高信心「全 false」
      return RoutingIntentResult(
        confidence: 0.9,
        projectDoor: false,
        assetReuse: false,
        managedFolderRule: false,
        capabilitySetup: false,
        goalNeedsIntake: false,
        isAnalysis: false,
        reasoning: 'L1 規則：無任何路由關鍵字命中，判定為閒聊/執行',
      );
    }

    // goalNeedsIntake 單獨命中時信心較低（太寬鬆），交由 L3 判斷
    final onlyGoalIntake = goalNeedsIntake &&
        !projectDoor && !assetReuse && !managedFolderRule &&
        !capabilitySetup && !isAnalysis;
    if (onlyGoalIntake) return null; // 交由 L3

    // 明確命中其他旗標 → 高信心直接回傳
    return RoutingIntentResult(
      confidence: 0.9,
      projectDoor: projectDoor,
      assetReuse: assetReuse,
      managedFolderRule: managedFolderRule,
      capabilitySetup: capabilitySetup,
      goalNeedsIntake: goalNeedsIntake,
      isAnalysis: isAnalysis,
      reasoning: 'L1 規則：關鍵字交集命中',
    );
  }

  // ============================================================
  // Phase 2: inferBridgeAction —— 橋接行動推斷（L1 關鍵字短路）
  // ============================================================

  /// L1 橋接行動推斷——橋接類型關鍵字短路。
  /// 信心 ≥0.9 時直接回傳，否則回傳 null 交由 L3。
  /// 覆蓋 #13。
  BridgeActionInferenceResult? inferBridgeAction({
    required String message,
    bool hasImage = false,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    final text = trimmed.toLowerCase();

    // 圖片辨識
    if (hasImage || _containsAny(text, const ['圖片辨識', '看圖', '識別圖', '圖像內容'])) {
      return BridgeActionInferenceResult(
        bridgeType: 'vision',
        confidence: 0.95,
        reasoning: 'L1 命中：圖片辨識關鍵字',
      );
    }

    // 音樂
    if (_containsAny(text, const ['音樂', '作曲', '配樂', '歌曲', '生成音', 'music', 'song', 'soundtrack'])) {
      return BridgeActionInferenceResult(
        bridgeType: 'generateMusic',
        confidence: 0.95,
        reasoning: 'L1 命中：音樂關鍵字',
      );
    }

    // 影片
    if (_containsAny(text, const ['影片', '短片', '分鏡', '動畫影片', 'video', 'movie', '直播'])) {
      return BridgeActionInferenceResult(
        bridgeType: 'generateVideo',
        confidence: 0.95,
        reasoning: 'L1 命中：影片關鍵字',
      );
    }

    // 文件
    if (_containsAny(text, const ['文件', '報告', 'pdf', '清單', '企劃', '整理成', '輸出檔案', '存成', 'markdown', 'document', 'report'])) {
      return BridgeActionInferenceResult(
        bridgeType: 'document',
        confidence: 0.95,
        reasoning: 'L1 命中：文件關鍵字',
      );
    }

    // 瀏覽
    if (_containsAny(text, const ['新聞', '搜尋', '查', '查詢', '上網', '網頁', '瀏覽', '時刻表', '班次', '天氣', '匯率', '股價', 'browser', 'search', 'news'])) {
      return BridgeActionInferenceResult(
        bridgeType: 'browse',
        confidence: 0.92,
        reasoning: 'L1 命中：瀏覽關鍵字',
      );
    }

    // 桌面檔案
    if (_containsAny(text, const ['桌面', '檔案', '資料夾', '本機', '整理資料', '掃描桌面', '掃描檔案', '列出桌面', '找檔案', 'desktop', 'folder'])) {
      return BridgeActionInferenceResult(
        bridgeType: 'desktopFiles',
        confidence: 0.92,
        reasoning: 'L1 命中：桌面檔案關鍵字',
      );
    }

    // L1 未命中 → 回傳 null 交由 L3
    return null;
  }

  // ============================================================
  // Phase 3: extractOpenIntention —— 未完成意圖偵測（L1 RegExp）
  // ============================================================

  /// L1 未完成意圖偵測——RegExp 短路。
  /// 信心 ≥0.9 時直接回傳，否則回傳 null 交由 L3。
  /// 覆蓋 #15。
  static final RegExp _openIntentPattern1 = RegExp(r'我(之後|改天|有空|下次)(要|想|會|打算)(.+)');
  static final RegExp _openIntentPattern2 = RegExp(r'(記得|別忘了)(之後|改天|下次)(.+)');
  static final RegExp _openIntentPattern3 = RegExp(r'等(我|有空|之後)(再|就)(.+)');

  OpenIntentionResult? extractOpenIntention({required String message}) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    for (final pattern in [_openIntentPattern1, _openIntentPattern2, _openIntentPattern3]) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) {
        final intent = match.group(3)?.trim() ?? '';
        if (intent.length > 2) {
          return OpenIntentionResult(
            hasOpenIntention: true,
            intention: intent,
            confidence: 0.9,
            reasoning: 'L1 RegExp 命中：$pattern',
          );
        }
      }
    }

    return null;
  }

  // ============================================================
  // Phase 3: detectEmotion —— 情緒偵測（L1 關鍵字 map）
  // ============================================================

  /// L1 情緒偵測——關鍵字 map 短路。
  /// 信心 ≥0.9 時直接回傳，否則回傳 null 交由 L3。
  /// 覆蓋 #16。
  static const Map<String, List<String>> _emotionKeywords = {
    '焦慮': ['煩', '壓力', '焦慮', '擔心', '害怕', '怎麼辦'],
    '興奮': ['開心', '興奮', '期待', '終於', '太好了'],
    '疲憊': ['累', '倦', '沒力', '撐不住', '想睡'],
    '困惑': ['不懂', '困惑', '迷茫', '不知道', '卡住'],
  };

  EmotionResult? detectEmotion({required String message}) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;

    for (final entry in _emotionKeywords.entries) {
      for (final marker in entry.value) {
        if (trimmed.contains(marker)) {
          return EmotionResult(
            emotion: entry.key,
            confidence: 0.9,
            reasoning: 'L1 關鍵字命中：$marker',
          );
        }
      }
    }

    return null;
  }

  bool _containsAny(String text, Iterable<String> needles) {
    return needles.any(text.contains);
  }
}
