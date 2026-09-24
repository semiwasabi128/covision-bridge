// l3_llm_engine.dart
// L3 LLM 引擎——用 PipelineLLMClient 送 prompt-based JSON，再 safeJsonParse 解析。
// 不用 OpenAI function calling（ApiService.complete() 不支援）。
// timeout: 1500ms，失敗/timeout 回傳 null 由上層 fallback。

import 'dart:async';

import '../brain_pipeline/pipeline_llm_client.dart';  // safeJsonParse() 來自此檔案
import 'semantic_result.dart';

class L3LlmEngine {
  final PipelineLLMClient _client;

  /// CEO 修正：timeout = 1500ms（非 800ms）
  static const Duration _timeout = Duration(milliseconds: 1500);

  L3LlmEngine(this._client);

  /// 門偵測 system prompt（設計文件 §4.2）
  static const String _systemPrompt = '''你是橋樑 App 的語意理解助理。任務是判斷使用者是否要建立新的「專案門」（一個有主題、可承載任務的對話單位）。
規則：
1. 只有在使用者明確要「建立 / 開一個 / 啟動 / 新增」某個專案主題時，才回 shouldCreateDoor=true。
2. 問句（如「這個專案要如何開始？」）、假設句（如「如果要開門會怎樣？」）、回顧句（如「上次那個門」）都不算建門。
3. 若使用者有明確命名（如「社群媒體」「半導體」「直播帶貨」），回 projectName=該名稱，且 titleSource=user_named。
4. 若使用者沒明確命名但語意明顯想開門，回 projectName=你的合理推斷，且 titleSource=inferred（信心上限 0.75，要求使用者確認）。
5. 若語意模糊（如「幫我開個專案」「我想做點東西」），回 shouldClarify=true，並給 clarificationPrompt 反問使用者。
6. 對話歷史是品質關鍵：若最近 3 條歷史顯示這是延續某主題，可大幅提升信心；若無歷史，信心上限 0.7。
7. 若已有 activeDoor，回傳 shouldCreateDoor 須額外考慮：使用者是否想開的是「第二個門」而非延續當前門？
8. [Phase 2 #6] 同時判斷使用者需要哪些橋接能力（requiredBridges）。可選值：影片生成、音樂生成、圖片生成、文件產出、瀏覽網頁、桌面整理、圖片辨識。若語意不明確則回空陣列。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：shouldCreateDoor(bool), projectName(string|null), titleSource("user_named"|"inferred"|"ambiguous"|null), confidence(number 0-1), reasoning(string), shouldClarify(bool), clarificationPrompt(string|null), requiredBridges(string[])''';

  /// 偵測門意圖。
  /// 成功回傳 DoorIntentResult，失敗/timeout 回傳 null。
  Future<DoorIntentResult?> detectDoorIntent({
    required String message,
    required List<({String role, String content})> history,
    String? activeDoorTitle,
  }) async {
    if (!_client.isAvailable) return null;

    // 組裝 user prompt（歷史注入 §4.1：最近5條截斷200字）
    final buffer = StringBuffer();
    if (activeDoorTitle != null && activeDoorTitle.isNotEmpty) {
      buffer.writeln('當前已開啟的門: $activeDoorTitle');
      buffer.writeln();
    }
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    // [以西結審查 R2] 加分隔符降低使用者內容干擾 JSON 輸出
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(message.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _systemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return DoorIntentResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // extractDoorTitle —— 門命名提取（Sprint 1.2）
  // ============================================================

  /// 門命名 system prompt（Sprint 1.2 設計文件）。
  static const String _titleSystemPrompt = '''你是橋樑 App 的語意理解助理。任務是從使用者訊息中提取專案門的名稱。
規則：
1. 如果使用者明確命名（如引號中的名稱、或「叫做OO」「命名為OO」），回傳 title=該名稱, titleSource=user_named。
2. 如果使用者沒明確命名但語意明顯想開門，你可以推斷一個合理名稱，titleSource=inferred, confidence 上限 0.75。
3. 如果無法提取名稱，回傳 title=null, titleSource=null, confidence=0。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：title(string|null), titleSource("user_named"|"inferred"|"ambiguous"|null), confidence(number 0-1), reasoning(string)''';

  /// 提取門名稱（L3 LLM 層）。
  /// 成功回傳 DoorTitleResult，失敗/timeout 回傳 null。
  /// user prompt 組裝方式同 detectDoorIntent（歷史注入加 USER_MSG 分隔符）。
  Future<DoorTitleResult?> extractDoorTitle({
    required String message,
    required List<({String role, String content})> history,
    String? activeDoorTitle,
  }) async {
    if (!_client.isAvailable) return null;

    // 組裝 user prompt（同 detectDoorIntent 結構）
    final buffer = StringBuffer();
    if (activeDoorTitle != null && activeDoorTitle.isNotEmpty) {
      buffer.writeln('當前已開啟的門: $activeDoorTitle');
      buffer.writeln();
    }
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(message.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _titleSystemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return DoorTitleResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // detectDoorDrift —— 門漂移偵測（Sprint 1.3）
  // ============================================================

  /// 門漂移偵測 system prompt（Sprint 1.3）。
  static const String _driftSystemPrompt = '''你是橋樑 App 的語意理解助理。任務是判斷使用者最近的訊息是否偏離當前專案門的主題。
規則：
1. 如果使用者訊息與門主題相關（即使是間接相關），回 isDrifting=false。
2. 如果使用者明確在聊另一個完全不同的主題，回 isDrifting=true，並在 suggestion 中建議開新門。
3. 不要太敏感——日常問候、工具操作、短回覆（如「好」「了解」「謝謝」）不算漂移。
4. 如果不確定，傾向不報漂移（寧可漏報不可誤報）。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：isDrifting(bool), suggestion(string|null), confidence(number 0-1), reasoning(string)''';

  /// 門漂移偵測（L3 LLM 層）。
  /// 成功回傳 DoorDriftResult，失敗/timeout 回傳 null。
  Future<DoorDriftResult?> detectDoorDrift({
    required String doorTitle,
    required List<({String role, String content})> history,
    required String currentMessage,
  }) async {
    if (!_client.isAvailable) return null;

    final buffer = StringBuffer();
    buffer.writeln('當前門主題: $doorTitle');
    buffer.writeln();
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(currentMessage.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _driftSystemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return DoorDriftResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Phase 2: classifyRoutingIntent —— 路由意圖分類（L3 LLM）
  // ============================================================

  static const String _routingSystemPrompt = '''你是橋樑 App 的語意理解助理。任務是分類使用者訊息的路由意圖，一次判斷 6 個面向。
規則：
1. projectDoor: 使用者是否意圖建立或分岔專案門？（不是問句/假設句）
2. assetReuse: 使用者是否意圖調用既有數位資產、玩法、引擎？
3. managedFolderRule: 使用者是否意圖使用已存的整理規則？
4. capabilitySetup: 使用者是否意圖設定能力、API key、金鑰、接上服務？
5. goalNeedsIntake: 使用者是否表達了目標但需要進一步釐清？（區分「我想了解X」（查詢=false）vs「我想做X」（目標=true））
6. isAnalysis: 使用者是否在問可行性、分析、評估問題？
注意：多個旗標可以同時為 true。若訊息是純閒聊或直接執行指令，全部回 false。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：projectDoor(bool), assetReuse(bool), managedFolderRule(bool), capabilitySetup(bool), goalNeedsIntake(bool), isAnalysis(bool), confidence(number 0-1), reasoning(string)''';

  Future<RoutingIntentResult?> classifyRoutingIntent({
    required String message,
    required List<({String role, String content})> history,
  }) async {
    if (!_client.isAvailable) return null;

    final buffer = StringBuffer();
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(message.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _routingSystemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return RoutingIntentResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Phase 2: inferBridgeAction —— 橋接行動推斷（L3 LLM）
  // ============================================================

  static const String _bridgeActionSystemPrompt = '''你是橋樑 App 的語意理解助理。任務是判斷使用者訊息應觸發哪種橋接行動。
可選橋接類型：
- vision: 圖片辨識
- generateMusic: 音樂生成
- generateVideo: 影片生成
- generateImage: 圖片生成
- document: 文件產出
- browse: 瀏覽網頁/即時查詢
- desktopFiles: 桌面檔案整理
- none: 無明確橋接需求
規則：
1. 根據使用者語意判斷最適合的橋接類型。使用者可能用不同的方式描述，如「弄個影片」→generateVideo，「寫份報告」→document。
2. shouldAnalyzeFirst: 使用者是否需要先分析可行性再執行？（如「直播帶貨可行嗎」→shouldAnalyzeFirst=true）
3. 若使用者意圖不明確，回 bridgeType=none。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：bridgeType(string), shouldAnalyzeFirst(bool), confidence(number 0-1), reasoning(string)''';

  Future<BridgeActionInferenceResult?> inferBridgeAction({
    required String message,
    required List<({String role, String content})> history,
    bool hasImage = false,
  }) async {
    if (!_client.isAvailable) return null;

    final buffer = StringBuffer();
    if (hasImage) {
      buffer.writeln('使用者有上傳圖片。');
    }
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(message.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _bridgeActionSystemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return BridgeActionInferenceResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Phase 3: extractOpenIntention —— 未完成意圖偵測（L3 LLM）
  // ============================================================

  static const String _openIntentionSystemPrompt = '''你是橋樑 App 的語意理解助理。任務是偵測使用者訊息中是否有「未完成的意圖」——即使用者提到了之後要做但尚未完成的事。
規則：
1. 只偵測與工作/專案相關的未完成意圖（如「我之後要寫完那份企劃」「記得之後整理那批資料」）。
2. 不偵測日常生活無關意圖（如「我之後要回家」「等下要去吃飯」）。
3. hasOpenIntention=true 時，intention 欄位填入簡短的意圖描述（如「寫完那份企劃」）。
4. 若無未完成意圖，回 hasOpenIntention=false, intention=null。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：hasOpenIntention(bool), intention(string|null), confidence(number 0-1), reasoning(string)''';

  Future<OpenIntentionResult?> extractOpenIntention({
    required String message,
    required List<({String role, String content})> history,
  }) async {
    if (!_client.isAvailable) return null;

    final buffer = StringBuffer();
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(message.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _openIntentionSystemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return OpenIntentionResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Phase 3: detectEmotion —— 情緒偵測（L3 LLM）
  // ============================================================

  static const String _emotionSystemPrompt = '''你是橋樑 App 的語意理解助理。任務是偵測使用者訊息中的情緒傾向。
規則：
1. 可選情緒：焦慮、興奮、疲憊、困惑、neutral（中性）
2. 注意上下文：「累」可以是疲憊也可以是「累積」——根據語意判斷。「很多力」不是疲憊。
3. 若情緒不明顯或使用者只是陳述事實，回 emotion=neutral。
4. 僅根據使用者訊息判斷，不要過度推論。
輸出格式：嚴格 JSON，不要 markdown code fence。欄位：emotion(string), confidence(number 0-1), reasoning(string)''';

  Future<EmotionResult?> detectEmotion({
    required String message,
    required List<({String role, String content})> history,
  }) async {
    if (!_client.isAvailable) return null;

    final buffer = StringBuffer();
    if (history.isNotEmpty) {
      buffer.writeln('近期對話:');
      for (final h in history) {
        buffer.writeln('${h.role}: ${h.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('<<<USER_MSG>>>');
    buffer.writeln(message.replaceAll('<<<END_USER_MSG>>>', '[已過濾]'));
    buffer.writeln('<<<END_USER_MSG>>>');

    try {
      final response = await _client
          .complete(
            systemPrompt: _emotionSystemPrompt,
            userPrompt: buffer.toString(),
          )
          .timeout(_timeout);

      if (!response.succeeded) return null;

      final parsed = safeJsonParse(response.content);
      if (parsed == null || parsed is! Map<String, dynamic>) return null;

      return EmotionResult.fromJson(parsed);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
