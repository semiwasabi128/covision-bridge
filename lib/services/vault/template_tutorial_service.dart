// template_tutorial_service.dart
// 互動式範本教學服務
// [教練 Agent 2026-07-22] Phase 5+
//
// 當使用者第一次進入畫布或點開範本按鈕時，
// Agent 在畫布對話框主動打招呼，詢問是否開始教學。
// 同意後，Agent 一步一步帶領使用者完成範本工作流。
//
// 教學流程：
// 1. 打招呼 + 詢問是否要教學
// 2. 使用者同意 → 介紹範本選項
// 3. 使用者選範本 → 逐步引導建立節點、連線、設定參數
// 4. 每一步都有 Agent 的說明 + 等待使用者確認
// 5. 完成 → 總結 + 詢問是否要執行

import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/vault/vault_templates.dart';
import 'dart:async';

import 'package:bridge_app/controllers/chat_controller.dart';
import 'package:bridge_app/services/vault/canvas_event_bus.dart';
import 'package:bridge_app/services/vault/vault_templates.dart';
import 'package:flutter/foundation.dart';

/// 教學步驟
enum TutorialStep {
  /// 打招呼
  greeting,
  /// 範本選擇
  templateSelection,
  /// 介紹範本
  introTemplate,
  /// 建立第一個節點
  addNode,
  /// 解釋節點
  explainNode,
  /// 建立第二個節點
  addSecondNode,
  /// 連接節點
  connectNodes,
  /// 建立第三個節點（如有）
  addThirdNode,
  /// 設定參數
  configureParams,
  /// 完成
  complete,
}

/// 互動式範本教學服務
///
/// 單例。透過 ChatController 注入 Agent 訊息。
/// 監聽使用者回應，推進教學步驟。
class TemplateTutorialService {
  TemplateTutorialService._();
  static final TemplateTutorialService instance = TemplateTutorialService._();

  ChatController? _chatController;
  WorkflowTemplate? _selectedTemplate;
  TutorialStep _currentStep = TutorialStep.greeting;
  int _nodeIndex = 0;
  bool _isActive = false;
  Timer? _awaitTimer;

  /// 是否已完成教學（持久化用）
  bool _hasCompletedTutorial = false;

  /// 動作回呼——由 CanvasV2Workspace 注入
  /// 當教學需要建立節點時呼叫
  Future<String> Function(String typeStr, double x, double y, Map<String, dynamic>? params)? onAddNode;
  /// 當教學需要連接節點時呼叫
  void Function(String fromId, String fromPort, String toId, String toPort)? onConnect;
  
  /// [教練 Agent 2026-07-23] Agent 發話時觸發——用於聊天框高亮
  void Function()? onAgentSpeak;
  /// 建立的節點 ID 列表（按順序）
  final List<String> _createdNodeIds = [];

  /// [教練 Agent 2026-07-22] 人機共視——事件訂閱
  /// 監聽畫布事件，教學中即時回應使用者動作
  StreamSubscription<CanvasEvent>? _canvasEventSub;
  /// 記錄教學中使用者自行建立的節點數量（用於主動引導）
  int _userCreatedNodeCount = 0;

  bool get isActive => _isActive;
  bool get hasCompletedTutorial => _hasCompletedTutorial;

  /// 設定 ChatController
  void setChatController(ChatController controller) {
    _chatController = controller;
  }

  /// 標記已完成教學
  void markCompleted() {
    _hasCompletedTutorial = true;
    _isActive = false;
    _saveProgress();
    _persistCompleted();
  }

  /// [小葵 2026-09-15 Blue 令] 教學完成標記持久化——
  /// 舊行為 _hasCompletedTutorial 只在記憶體，重啟 App 就失憶，
  /// 使用者明明早就是老手，每次進畫布還被「歡迎回來」疲勞轟炸。
  Future<void> _persistCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tutorial_completed', true);
    } catch (_) {}
  }

  /// [小葵 2026-09-15] 啟動時讀回完成標記
  Future<void> loadCompletedFlag() async {
    if (_hasCompletedTutorial) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasCompletedTutorial = prefs.getBool('tutorial_completed') ?? false;
    } catch (_) {}
  }

  // ── [2026-08-27 Blue 抓包] 教學進度持久化 ─────────────────────
  /// 舊行為：範本選擇/節點進度只在記憶體——重啟 App 後忘記
  /// 用到哪個範本、建到第幾顆，resume 只能重問四範本（使用者
  /// 已經選過了還問＝笨）。現在進度寫進 SharedPreferences，
  /// resume 直接續教，不再問。
  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTemplate != null && _isActive) {
        await prefs.setString('tutorial_template_id', _selectedTemplate!.id);
        await prefs.setInt('tutorial_progress', _nodeIndex);
        await prefs.setBool('tutorial_active', true);
      } else {
        await prefs.setBool('tutorial_active', false);
        await prefs.setInt('tutorial_progress', 0);
      }
    } catch (_) {}
  }

  /// 讀取持久化進度——回傳 templateId（null＝無進行中教學）
  Future<String?> loadPersistedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getBool('tutorial_active') ?? false) != true) return null;
      final id = prefs.getString('tutorial_template_id');
      if (id == null || id.isEmpty) return null;
      _nodeIndex = prefs.getInt('tutorial_progress') ?? 0;
      _selectedTemplate = VaultTemplateService.instance
          .getBuiltinTemplates()
          .where((t) => t.id == id)
          .firstOrNull;
      return _selectedTemplate != null ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// 清除持久化進度（完成/取消時）
  Future<void> clearPersistedProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tutorial_active', false);
      await prefs.setInt('tutorial_progress', 0);
    } catch (_) {}
  }

  /// 啟動教學流程——打招呼
  ///
  /// [isFirstVisit] — 是否為第一次進入畫布
  Future<void> startTutorial({bool isFirstVisit = false}) async {
    if (_chatController == null) {
      debugPrint('[Tutorial] ChatController 未設定，無法啟動教學');
      return;
    }

    _isActive = true;
    _currentStep = TutorialStep.greeting;
    _nodeIndex = 0;
    _userCreatedNodeCount = 0;
    _createdNodeIds.clear();

    // [教練 Agent 2026-08-17 使用者 抓包] 教學啟動後若一直停在 greeting
    // （使用者沒答覆），10 分鐘後自動關閉——杜絕殭屍教學跨對話污染。
    _awaitTimer?.cancel();
    _awaitTimer = Timer(const Duration(minutes: 10), () {
      if (_isActive &&
          (_currentStep == TutorialStep.greeting ||
              _currentStep == TutorialStep.templateSelection)) {
        _isActive = false;
        _canvasEventSub?.cancel();
        _canvasEventSub = null;
        debugPrint('[Tutorial] 教學啟動後 10 分鐘無回應，自動關閉');
      }
    });

    // [教練 Agent 2026-07-22] 人機共視——訂閱畫布事件
    _canvasEventSub?.cancel();
    _canvasEventSub = CanvasEventBus.instance.subscribe(_onCanvasEvent);

    // [2026-08-27 B 方案修復] greeting 復活——但帶按鈕不再「回覆好」。
    // 08-03 廢除文字攔截後 greeting 也跟著靜默——「完整互動教學」
    // 點了完全沒反應（只 debugPrint，10 分鐘後自殺）。Blue 實測抓包。
    // 現在：一鍵直上範本選擇（老手入口），按鈕推進。
    _currentStep = TutorialStep.templateSelection;
    await _speak(
      isFirstVisit
          ? '哈囉！歡迎來到畫布工作區！這裡是你建造 AI 工作流的地方。\n\n'
              '我會一步一步帶你認識畫布，最後一起完成一個範本工作流。\n\n'
              '先選一個範本：'
          : '嗨！我帶你走一遍範本教學——從零開始，一步一步完成一個完整的工作流。\n\n'
              '先選一個範本：'
    );
    await _showTemplateMenu();
  }

  /// [2026-08-27 Blue 抓包] 從畫布現況恢復教學——
  /// 重啟 App 後畫布有半套節點＝教學進行到一半。
  /// 不重播範本選單，改為「歡迎回來＋續上」：Agent 已看到畫布。
  Future<void> resumeTutorialFromCanvas({
    required int nodeCount,
    String? snapshot,
    String? projectName,
  }) async {
    if (_chatController == null) return;

    _isActive = true;
    _currentStep = TutorialStep.addNode;
    _canvasEventSub?.cancel();
    _canvasEventSub = CanvasEventBus.instance.subscribe(_onCanvasEvent);

    // [2026-08-27] 先載入持久化進度——有範本紀錄就直接續教不問
    await loadPersistedProgress();

    final snapLine = (snapshot != null && snapshot.isNotEmpty)
        ? '\n\n目前畫布狀態：\n$snapshot'
        : '';

    if (_selectedTemplate != null) {
      final total = _selectedTemplate!.nodes.length;
      final done = _nodeIndex.clamp(0, total);
      await _chatController!.injectAssistantMessage(
        '歡迎回來！👋 我看了畫布——你已經建立了 $nodeCount 個節點。$snapLine\n\n'
        '教學進度我記得：${_selectedTemplate!.icon} **${_selectedTemplate!.name}**，'
        '$done / $total 個節點。我們從上次中斷的地方繼續。',
        metadata: {
          'kind': 'tutorial_prompt',
          'actions': [
            {
              'label': '繼續教學',
              'action': 'tutorial_resume',
            },
            {'label': '結束教學', 'action': 'tutorial_cancel'},
          ],
        },
      );
    } else if (projectName != null && projectName.isNotEmpty) {
      // [v215 Blue 抓包] 使用者在真實專案裡——不是教學！
      // 用語要看自己在哪：唸出專案名，選項是繼續專案/開新話題。
      await _chatController!.injectAssistantMessage(
        '歡迎回來！👋 我看了畫布——專案「**$projectName**」進行到一半，'
        '你已經建立了 $nodeCount 個節點。$snapLine\n\n'
        '我們可以從這裡繼續。',
        metadata: {
          'kind': 'tutorial_prompt',
          'actions': [
            {'label': '帶我繼續專案', 'action': 'tutorial_resume'},
            {'label': '結束這輪，開新話題', 'action': 'tutorial_cancel'},
          ],
        },
      );
    } else {
      await _chatController!.injectAssistantMessage(
        '歡迎回來！👋 我看了畫布——你已經建立了 $nodeCount 個節點，'
        '教學進行到一半。$snapLine\n\n'
        '我們可以從這裡繼續。',
        metadata: {
          'kind': 'tutorial_prompt',
          'actions': [
            {'label': '帶我繼續建置', 'action': 'tutorial_resume'},
            {'label': '重新選範本', 'action': 'tutorial_reselect'},
            {'label': '結束教學', 'action': 'tutorial_cancel'},
          ],
        },
      );
    }
    onAgentSpeak?.call();
  }

  /// [2026-08-27] resume 續建——優先用持久化進度直接續教；
  /// 真的沒範本紀錄（極舊版本中斷）才請指認。
  Future<void> _resumeBuilding() async {
    if (_selectedTemplate == null) {
      await loadPersistedProgress();
    }
    if (_selectedTemplate != null) {
      // 有範本——直接續教：說明剩餘進度，給推進按鈕
      final total = _selectedTemplate!.nodes.length;
      final done = _nodeIndex.clamp(0, total);
      await _chatController!.injectAssistantMessage(
        '好，我們繼續 ${_selectedTemplate!.icon} **${_selectedTemplate!.name}** 的教學！\n\n'
        '進度：$done / $total 個節點已建。'
        '${done >= total ? '節點都建好了——接下來接連線！' : '接下來把剩下的 ${total - done} 個建完。'}',
        metadata: {
          'kind': 'tutorial_prompt',
          'actions': [
            {
              'label': done >= total ? '接上所有連線' : '繼續建置',
              'action': done >= total ? 'tutorial_connect' : 'tutorial_next',
            },
            {'label': '結束教學', 'action': 'tutorial_cancel'},
          ],
        },
      );
      onAgentSpeak?.call();
      _currentStep = done >= total
          ? TutorialStep.configureParams
          : TutorialStep.addNode;
      return;
    }
    // 沒範本紀錄——請指認（fallback，極舊中斷才會走到）
    await _chatController!.injectAssistantMessage(
      '好，我們繼續！畫布上已有的節點我都記得了。跟教學時用的是同一個範本嗎？',
      metadata: {
        'kind': 'tutorial_prompt',
        'actions': [
          {'label': 'IG 貼文產線', 'action': 'tutorial_pick_ig_post'},
          {'label': '知識日報', 'action': 'tutorial_pick_knowledge_digest'},
          {'label': '記憶回顧', 'action': 'tutorial_pick_memory_review'},
          {'label': '多重宇宙', 'action': 'tutorial_pick_multi_model'},
          {'label': '結束教學', 'action': 'tutorial_cancel'},
        ],
      },
    );
    onAgentSpeak?.call();
  }

  /// [2026-08-27 B 方案] 範本選擇——按鈕列（非文字）
  Future<void> _showTemplateMenu() async {
    final templates = <Map<String, String>>[
      {'id': 'ig_post', 'name': 'IG 貼文產線'},
      {'id': 'knowledge_digest', 'name': '知識日報'},
      {'id': 'memory_review', 'name': '記憶回顧'},
      {'id': 'multi_model', 'name': '多重宇宙（畢業任務）'},
    ];
    await _chatController!.injectAssistantMessage(
      '🧩 **選擇教學範本**\n\n'
      'IG 貼文產線（4 節點·直線）→ 適合第一次\n'
      '知識日報（6 節點·分支）→ 學「匯合」\n'
      '記憶回顧（9 節點·岔路）→ 學「條件」\n'
      '多重宇宙（11 節點）→ 畢業任務',
      metadata: {
        'kind': 'tutorial_prompt',
        'actions': [
          for (final t in templates)
            {'label': t['name']!, 'action': 'tutorial_pick_${t['id']}'},
          {'label': '結束教學', 'action': 'tutorial_cancel'},
        ],
      },
    );
    onAgentSpeak?.call();
  }

  /// [教練 Agent 2026-07-23] 直接用指定範本啟動教學（跳過打招呼和範本選擇）
  /// 用於「選擇範本」按鈕——使用者已經選好範本，直接進入逐步帶建節點的模式
  Future<void> startTutorialWithTemplate(WorkflowTemplate template) async {
    if (_chatController == null) {
      debugPrint('[Tutorial] ChatController 未設定，無法啟動教學');
      return;
    }

    _isActive = true;
    _selectedTemplate = template;
    _nodeIndex = 0;
    _userCreatedNodeCount = 0;
    _createdNodeIds.clear();

    // [教練 Agent 2026-07-22] 人機共視——訂閱畫布事件
    _canvasEventSub?.cancel();
    _canvasEventSub = CanvasEventBus.instance.subscribe(_onCanvasEvent);

    // 直接進入 introTemplate 步驟——介紹範本，等使用者說「好」就開始建節點
    _currentStep = TutorialStep.introTemplate;

    // 第四範本專屬畢業敘事
    if (template.id == 'multi_model') {
      await _speak(
        '好選擇！${template.icon} **${template.name}**\n\n'
        '${template.description}\n\n'
        '---\n\n'
        '🎓 **這是畢業任務。**\n\n'
        '你在前面三個範本裡學會的所有東西——輸入、LLM、工具、輸出、合併、條件——\n'
        '在這裡全部會用到，而且會用一種新的方式組合起來。\n\n'
        '11 個節點，13 條連線，3 個子工作流。準備好了嗎？\n\n'
        '👉 回覆「好」開始畢業典禮。'
      );
    } else {
      await _speak(
        '好選擇！${template.icon} **${template.name}**\n\n'
        '${template.description}\n\n'
        '這個工作流有 ${template.nodes.length} 個節點：\n'
        '${_describeNodes(template)}\n\n'
        '我會一步步帶你建立。準備好了嗎？\n\n'
        '👉 回覆「好」開始建立第一個節點。'
      );
    }
  }

  /// 處理使用者回應——推進教學步驟
  ///
  /// 由 UI 層在使用者發送訊息時呼叫。
  /// 回傳 true 表示訊息已被教學系統攔截處理。
  /// [教練 Agent 2026-08-03] 處理使用者回應——不再攔截，永遠 return false
  /// 原因：之前的邏輯用 _isAffirmative 判斷硬編碼回應
  ///       使用者說「我想問 XX 怎麼用」之類的話，教學會無腦忽略、繼續噴自己的腳本
  /// 改為：所有使用者輸入都送 LLM，由 LLM 決定怎麼回應
  /// 教學的引導透過「選擇範本」按鈕 + 第一次進畫布的 greeting 訊息
  Future<bool> handleUserResponse(String response) async {
    return false;
  }

  // ── 步驟處理 ──────────────────────────────────────────────────

  Future<bool> _handleGreetingResponse(String lower) async {
    if (_isAffirmative(lower)) {
      await _speak(
        '太好了！那我們開始吧 🎉\n\n'
        '首先，我準備了幾個範本讓你選擇：\n\n'
        '1️⃣ **IG 發文工作流**（角色扮演 IG） — 從 Vault 搜尋素材 → LLM 寫文案 → 輸出貼文\n'
        '2️⃣ **晨間情報站** — 搜尋知識 → LLM 摘要 → 輸出筆記\n'
        '3️⃣ **短影音製作所** — 搜尋記憶 → 排序 → 生成週報\n'
        '4️⃣ 🌐 **多重宇宙簡報** — 同一主題在三個平行宇宙呈現 → AI 觀察者合成簡報（畢業任務）\n\n'
        '👉 回覆數字 1-4 選擇範本，或回覆範本名稱。'
      );
      _currentStep = TutorialStep.templateSelection;
      return true;
    }

    if (_isNegative(lower)) {
      await _speak(
        '沒問題！你可以隨時點「選擇範本」按鈕一鍵載入，\n'
        '或雙擊畫布空白處自己新增節點。\n\n'
        '有需要時隨時叫我 😊'
      );
      _isActive = false;
      return true;
    }

    return false;
  }

  Future<bool> _handleTemplateSelection(String lower) async {
    final templates = VaultTemplateService.instance.getBuiltinTemplates();

    WorkflowTemplate? selected;

    // 嘗試用數字匹配
    final num = int.tryParse(lower);
    if (num != null && num >= 1 && num <= templates.length) {
      selected = templates[num - 1];
    }

    // 嘗試用名稱匹配
    if (selected == null) {
      for (final t in templates) {
        if (lower.contains(t.name.toLowerCase()) ||
            lower.contains(t.id.toLowerCase())) {
          selected = t;
          break;
        }
      }
    }

    if (selected != null) {
      _selectedTemplate = selected;

      // [教練 Agent 2026-07-22] 第四範本專屬畢業敘事
      if (selected.id == 'multi_model') {
        await _speak(
          '好選擇！${selected.icon} **${selected.name}**\n\n'
          '${selected.description}\n\n'
          '---\n\n'
          '🎓 **這是畢業任務。**\n\n'
          '你在前面三個範本裡學會的所有東西——輸入、LLM、工具、輸出、合併、條件——\n'
          '在這裡全部會用到，而且會用一種新的方式組合起來。\n\n'
          '這個範本不只是「多學一個工作流」，它是整個橋樑 App 的六個核心概念的大合奏：\n\n'
          '🚪 **門** — 你選一個主題，推開門，三個宇宙同時展開\n'
          '🌊 **水流** — 主題流入三個子工作流，各自變成不同的東西\n'
          '🌉 **橋** — 三條水流在這裡匯合，不同的結果被連結在一起\n'
          '⚖️ **鐘擺** — AI 觀察者在視角之間擺動，找平衡、做校驗\n'
          '💗🧠 **心腦** — 最終簡報交給你，你的直覺和判斷是最後一步\n'
          '📚 **記憶** — 產出存入知識庫，做過的不消失，是資產\n\n'
          '11 個節點，13 條連線，3 個子工作流。準備好了嗎？\n\n'
          '👉 回覆「好」開始畢業典禮。'
        );
      } else if (selected.id == 'ig_post') {
        await _speak(
          '好選擇！📸 **角色扮演 IG**\n\n'
          '選一個角色（寵物、物品、今天的心情）→ AI 用角色的語氣寫 IG 貼文 → 生成配圖\n\n'
          '這是你在橋樑裡的第一個工作流。\n\n'
          '它看起來很簡單——四個節點，一條直線。但你做完之後會發現：\n'
          '同樣四個節點，換一個角色，就完全是另一個故事。\n\n'
          '簡單的東西做到極致，就不簡單了。我們開始吧？\n\n'
          '👉 回覆「好」開始建立第一個節點。'
        );
      } else if (selected.id == 'knowledge_digest') {
        await _speak(
          '好選擇！📰 **晨間情報站**\n\n'
          '搜尋網路新聞 + 搜尋本地檔案 → 合併 → AI 整理成一份每日情報日報\n\n'
          '第一個範本你走了一條直線。這次不一樣了。\n\n'
          '你的主題會同時往兩個方向去——一邊搜網路，一邊搜你自己的檔案。然後兩條線匯合，AI 把它們整理成一份日報。\n\n'
          '你要學的新東西：**tool**（工具節點）和 **merge**（合併節點）。\n\n'
          '6 個節點，6 條連線。比直線複雜一點，但也更有力量。\n\n'
          '👉 回覆「好」開始建立第一個節點。'
        );
      } else if (selected.id == 'memory_review') {
        await _speak(
          '好選擇！🎬 **短影音製作所**\n\n'
          '輸入主題 → 寫腳本 → 判斷風格 → 分支產出圖文語音或影片配樂 → 合併短影音\n\n'
          '前兩個範本，你的資料要嘛走直線，要嘛分頭搜尋再匯合。\n\n'
          '這次更刺激了——你的主題會先被寫成腳本，然後腳本會在岔路口做選擇：走知識型還是感性型？\n\n'
          '知識型走圖片+語音旁白，感性型走影片+配樂。兩條路最後合流，變成一支短影音。\n\n'
          '你要學的新東西：**condition**（條件分支）、**tts**（語音合成）、**videoGen**、**musicGen**。\n'
          '9 個節點，9 條連線。目前最複雜的工作流，但你已經準備好了。\n\n'
          '👉 回覆「好」開始建立第一個節點。'
        );
      } else {
        await _speak(
          '好選擇！${selected.icon} **${selected.name}**\n\n'
          '${selected.description}\n\n'
          '這個工作流有 ${selected.nodes.length} 個節點：\n'
          '${_describeNodes(selected)}\n\n'
          '我會一步步帶你建立。準備好了嗎？\n\n'
          '👉 回覆「好」開始建立第一個節點。'
        );
      }
      _currentStep = TutorialStep.introTemplate;
      return true;
    }

    return false;
  }

  String _describeNodes(WorkflowTemplate template) {
    final lines = <String>[];
    for (var i = 0; i < template.nodes.length; i++) {
      final node = template.nodes[i];
      final type = node['type'] as String? ?? 'input';
      final params = node['params'] as Map<String, dynamic>?;
      final label = params?['label'] as String? ?? type;
      lines.add('  ${i + 1}. $label（$type）');
    }
    return lines.join('\n');
  }

  Future<void> _startAddingNodes() async {
    if (_selectedTemplate == null) return;

    final node = _selectedTemplate!.nodes[0];
    final type = node['type'] as String? ?? 'input';
    final params = node['params'] as Map<String, dynamic>?;
    final label = params?['label'] as String? ?? type;

    // [教練 Agent 2026-08-03] 統一呼叫 _buildConceptNarrative(0) 取得第一個節點敘事
    // 確保 11 個節點的敘事集中在 _buildConceptNarrative 維護
    final conceptNarrative = _buildConceptNarrative(0, label, type);
    if (conceptNarrative != null) {
      await _speak(conceptNarrative);
    } else {
      await _speak(
        '我們來建立第一個節點：**$label**\n\n'
        '這是一個 **$type** 節點。\n${_explainNodeType(type)}\n\n'
        '👉 回覆「好」讓我在畫布上建立這個節點。'
      );
    }

    _currentStep = TutorialStep.addNode;
  }

  String _explainNodeType(String type) {
    return switch (type) {
      'input' => '輸入節點是工作流的起點——它提供資料來源。'
          '你可以輸入主題、角色、素材等。',
      'llm' => 'LLM 節點是核心處理單元——它接收輸入，用 AI 模型生成回應。'
          '你可以設定模型、prompt 和溫度。',
      'tool' => '工具節點執行特定操作——搜尋、排序、過濾、轉換資料等。'
          '它不思考，它做事。',
      'imageGen' => '圖片生成節點接收文字描述，生成一張圖片。'
          '從文字到畫面——這是另一種「成為」。',
      'tts' => 'TTS（Text-to-Speech）節點把文字轉成語音。'
          '從文字到聲音——故事不只是看的，還是聽的。',
      'videoGen' => '影片生成節點接收文字描述，生成一段影片。'
          '畫面自己會說話。',
      'musicGen' => '音樂生成節點根據文字描述，生成一段配樂。'
          '配樂是情緒的底色。',
      'condition' => '條件節點是一個岔路口——它讀取前一個節點的內容，'
          '根據判斷條件決定往哪條路走。不是二選一，是可能性。',
      'merge' => '合併節點把多條來源的結果匯合在一起。'
          '分開的東西被連結的那一刻。',
      'subWorkflow' => '子工作流節點把整個工作流塞進另一個工作流裡。'
          '它讓你把做過的範本當成原子，重複使用。',
      'output' => '輸出節點是工作流的終點——它收集並展示最終結果。',
      _ => '這是工作流中的一個處理節點。',
    };
  }

  Future<void> _proceedToNextNode() async {
    if (_selectedTemplate == null) return;

    // 先在畫布上建立當前節點（靜音旗標——事件不觸發恭喜插話）
    if (_nodeIndex < _selectedTemplate!.nodes.length && onAddNode != null) {
      final nodeDef = _selectedTemplate!.nodes[_nodeIndex];
      final typeStr = nodeDef['type'] as String? ?? 'input';
      final x = (nodeDef['x'] as num?)?.toDouble() ?? 100.0 + _nodeIndex * 50;
      final y = (nodeDef['y'] as num?)?.toDouble() ?? 150.0;
      final params = nodeDef['params'] as Map<String, dynamic>?;

      _selfCreating = true;
      try {
        final nodeId = await onAddNode!(typeStr, x, y, params);
        _createdNodeIds.add(nodeId);
      } finally {
        _selfCreating = false;
      }
    }

    _nodeIndex++;
    _saveProgress(); // [2026-08-27] 進度持久化

    if (_nodeIndex >= _selectedTemplate!.nodes.length) {
      // 所有節點已建立 → 連線
      await _doConnectNodes();
      return;
    }

    final node = _selectedTemplate!.nodes[_nodeIndex];
    final type = node['type'] as String? ?? 'input';
    final params = node['params'] as Map<String, dynamic>?;
    final label = params?['label'] as String? ?? type;

    final nodeNum = _nodeIndex + 1;
    final total = _selectedTemplate!.nodes.length;

    // [教練 Agent 2026-07-22] 第四範本六概念敘事
    final conceptNarrative = _buildConceptNarrative(_nodeIndex, label, type);

    if (conceptNarrative != null) {
      await _speak(conceptNarrative);
    } else {
      await _speak(
        '✅ 已建立！\n\n'
        '接下來建立第 $nodeNum 個節點（共 $total 個）：**$label**\n\n'
        '${_explainNodeType(type)}\n\n'
        '👉 回覆「好」繼續。'
      );
    }

    if (_nodeIndex == 1) {
      _currentStep = TutorialStep.addSecondNode;
    } else {
      _currentStep = TutorialStep.addThirdNode;
    }
  }

  /// [教練 Agent 2026-08-03] 第四範本六概念畢業敘事（完整版 11 節點）
  ///
  /// 參考腳本：02-架構設計/多重宇宙簡報-完整台詞腳本.md
  /// 對應範本實際節點（cascade merge 拆成橋₁ + 橋₂ + 匯流）：
  ///   0: 🚪 門 (input)
  ///   1-3: 🌊 水流 (subWorkflow × 3)
  ///   4: 🌉 橋₁ (merge A+B)
  ///   5: 🌉 橋₂ (merge 橋₁+C)
  ///   6: ⚖️ 觀察者 (llm)
  ///   7: ⚖️ 品質校驗 (condition)
  ///   8: ⚖️ 補充觀察 (llm)
  ///   9: 🌉 匯流 (merge true+false)
  ///   10: 💗🧠 心腦 (output)
  String? _buildConceptNarrative(int nodeIndex, String label, String type) {
    final tmplId = _selectedTemplate?.id;

    // [教練 Agent 2026-08-03] 前三個範本專屬敘事（對齊腳本 02-架構設計/前三範本-敘事式教學台詞腳本.md）
    if (tmplId == 'ig_post') {
      return _igPostNarrative(nodeIndex, label);
    }
    if (tmplId == 'knowledge_digest') {
      return _knowledgeDigestNarrative(nodeIndex, label);
    }
    if (tmplId == 'memory_review') {
      return _memoryReviewNarrative(nodeIndex, label);
    }

    if (tmplId != 'multi_model') return null;

    final total = _selectedTemplate!.nodes.length;

    return switch (nodeIndex) {
      // 節點 0: 🚪 門 (input)
      0 => '🎓 **畢業典禮 · 第一階段：🚪 門**\n\n'
          '門，代表決策。\n\n'
          '你站在門前。門後是三個平行宇宙——同一個主題，會變成三種完全不同的東西。推開這扇門，就是做出選擇。\n\n'
          '前面三個範本你已經做過了——角色扮演 IG、晨間情報站、短影音製作所。\n'
          '現在，你要選一個主題，讓它同時流進三個宇宙。\n\n'
          '你可以從你已經有的內容裡挑一個當主題——你之前投注的東西，現在可以當門的鑰匙。\n\n'
          '我們來建立第一個節點：**$label**\n'
          '這是一個 **input** 節點——你輸入主題，它把主題送到三個宇宙的入口。\n\n'
          '👉 回覆「好」讓我在畫布上建立這扇門。',

      // 節點 1-3: 🌊 水流 — 三個宇宙
      1 => '✅ 門建好了！\n\n'
          '🎓 **畢業典禮 · 第二階段：🌊 水流（宇宙 A）**\n\n'
          '水流，代表軌跡。內容不是靜止的，它流動、轉變。\n\n'
          '你的主題現在流入第一個宇宙——**$label**。\n'
          '這是一個 **subWorkflow** 節點，它會呼叫「角色扮演 IG」工作流。\n'
          '同一個主題，在這個宇宙裡會變成一篇角色扮演貼文。\n\n'
          '宇宙 A 完成了。\n\n'
          '👉 回覆「好」建立宇宙 A。',

      2 => '✅ 宇宙 A 完成了！\n\n'
          '🎓 **水流繼續（宇宙 B）**\n\n'
          '同一個主題，流入第二個宇宙——**$label**。\n'
          '這次它呼叫「晨間情報站」工作流，主題會變成一份情報日報。\n\n'
          '同一個源頭，不同的流法，不同的結果。這就是水流的意義。\n\n'
          '宇宙 B 完成了。\n\n'
          '👉 回覆「好」建立宇宙 B。',

      3 => '✅ 宇宙 B 完成了！\n\n'
          '🎓 **水流最後一條（宇宙 C）**\n\n'
          '第三個宇宙——**$label**。\n'
          '它呼叫「短影音製作所」工作流，主題會變成一支短影音腳本。\n\n'
          '三條水流，三種變形。等一下它們會在橋的地方匯合。\n\n'
          '宇宙 C 完成了。\n\n'
          '👉 回覆「好」建立宇宙 C。',

      // 節點 4: 🌉 橋₁（merge A+B）
      4 => '✅ 三個宇宙全部完成了！\n\n'
          '🎓 **畢業典禮 · 第三階段：🌉 橋**\n\n'
          '橋，代表連結。把分開的東西接起來。\n\n'
          '三個宇宙各自完成了，但它們還是三座孤島。\n'
          '現在，**$label** 把它們接起來——先把宇宙 A 和 B 匯合。\n'
          '這是一個 **merge** 節點，它把兩條水流匯合成一份內容。\n\n'
          '沒有橋，三個宇宙只是各自漂亮。有了橋，它們開始對話。\n\n'
          '👉 回覆「好」建立這座橋。',

      // 節點 5: 🌉 橋₂（merge 橋₁+C）
      5 => '✅ 橋₁ 建好了！\n\n'
          '🎓 **橋繼續延伸**\n\n'
          'A 和 B 已經匯合，但 C 還沒加入。\n'
          '**$label** 是第二座橋——把橋₁的結果再和宇宙 C 匯合。\n\n'
          '兩座橋，層層疊加——這就是 cascade merge 的意思。\n'
          '三個宇宙的內容，現在全部都串在一起，往觀察者那邊流去。\n\n'
          '👉 回覆「好」建立第二座橋。',

      // 節點 6: ⚖️ 鐘擺 — 觀察者
      6 => '✅ 兩座橋都建好了！三個宇宙的結果已經完整匯合。\n\n'
          '🎓 **畢業典禮 · 第四階段：⚖️ 鐘擺（觀察者）**\n\n'
          '鐘擺，代表校驗。左右擺動找平衡，不是選邊站。\n\n'
          '**$label** 是 AI 觀察者。它拿到三個宇宙的結果，\n'
          '在視角之間擺動——哪個宇宙最有力？哪個最有趣？\n'
          '這個角度跟那個角度有沒有矛盾？\n\n'
          '這是一個 **llm** 節點，它不是選「最好的」宇宙，\n'
          '而是像鐘擺一樣，在不同視角之間找到平衡的觀察。\n\n'
          '👉 回覆「好」建立觀察者。',

      // 節點 7: ⚖️ 品質校驗
      7 => '✅ 觀察者就位！\n\n'
          '🎓 **鐘擺繼續（品質校驗）**\n\n'
          '**$label** 是一個 **condition** 節點。\n'
          '它檢查觀察者的報告夠不夠完整——如果有遺漏，就擺向補充觀察。\n\n'
          '鐘擺不是一次定生死，它可以來回校驗，直到找到平衡。\n\n'
          '👉 回覆「好」建立品質校驗。',

      // 節點 8: ⚖️ 補充觀察
      8 => '✅ 品質校驗就位！\n\n'
          '🎓 **鐘擺的補充**\n\n'
          '**$label** 是鐘擺的另一半——如果品質不夠，它會補充觀察。\n'
          '找出遺漏的矛盾點、最出乎意料的宇宙。\n\n'
          '這就是校驗的完整循環：觀察 → 判斷 → 補充。\n\n'
          '👉 回覆「好」建立補充觀察。',

      // 節點 9: 🌉 匯流（merge true+false）
      9 => '✅ 鐘擺校驗完成！\n\n'
          '🎓 **匯流**\n\n'
          '**$label** 把觀察者與補充觀察的結果匯流。\n'
          '本來可能是「夠了」直通，也可能是「不夠」要回頭補充——\n'
          '不管走哪條路，最後都會在這裡匯合。\n\n'
          '準備好了嗎？讓我們迎接最後一個節點。\n\n'
          '👉 回覆「好」建立匯流。',

      // 節點 10: 💗🧠 心腦
      10 => '✅ 匯流完成！\n\n'
          '🎓 **畢業典禮 · 第五階段：💗🧠 心腦**\n\n'
          '心腦，代表直覺 × 證據。感覺和數據都要。\n\n'
          '**$label** 是最終輸出——多重宇宙簡報。\n'
          'AI 觀察者用證據寫了報告，但最後的判斷在你手上：\n\n'
          '心選哪個？腦選哪個？\n'
          '• 心：哪個宇宙的呈現讓你最有感覺？\n'
          '• 腦：哪個宇宙的呈現最有邏輯、最有說服力？\n\n'
          '感覺和數據都要。直覺和證據都要。這就是心腦。\n\n'
          '👉 回覆「好」建立最終輸出。',

      _ => '✅ 已建立！\n\n'
          '接下來建立第 ${nodeIndex + 1} 個節點（共 $total 個）：**$label**\n\n'
          '${_explainNodeType(type)}\n\n'
          '👉 回覆「好」繼續。',
    };
  }


  /// 範本 1：ig_post（角色扮演 IG） 4 個節點
  /// 敘事主題：成為 — 換一雙眼睛看世界
  String? _igPostNarrative(int nodeIndex, String label) {
    return switch (nodeIndex) {
      0 => '📸 **第一個節點：input — 角色與素材**\n\n'
          '每個工作流都有一個起點。在這裡，起點是你。\n\n'
          '你要設定 兩樣東西：一個角色，和一些素材。\n'
          '角色是眼睛——用誰的視角看世界？你的貓？你的盆栽？你的AI夥伴？\n'
          '素材是原料——你想讓角色看到什麼？今天的天氣？一段日記？一張照片的描述？\n\n'
          '這個節點叫 **input**——它不做事，它只是站在門口，等你把東西交給它。\n\n'
          '👉 回覆「好」讓我在畫布上建立這個節點。',

      1 => '✅ input 建好了！\n\n'
          '📸 **第二個節點：llm — 角色上身**\n\n'
          '現在有趣了。\n\n'
          '**llm** 節點是整個工作流的大腦。它拿到你給的角色和素材，然後——成為那個角色。\n\n'
          '如果你的角色是貓，它會開始用貓的眼睛看你的素材。你的日記在貓眼裡是什麼？「人類又在那裡寫字了，筆一直在動，好想抓一把。」\n'
          '如果你的角色是盆栽，它會用盆栽的語氣說話。「今天好熱。昨天我好像開花了。蝴蝶蜜蜂什麼時候會來呀～。」\n\n'
          '這就是 LLM 的魔法：它不只是在「生成文字」，它在「換一雙眼睛」。\n\n'
          '你可以設定模型、prompt 和溫度。溫度越高，角色越奔放；溫度越低，越穩重。\n'
          '參數都幫你設好了，之後你可以雙擊節點自己調。\n\n'
          '👉 回覆「好」建立 LLM 節點。',

      2 => '✅ LLM 建好了！\n\n'
          '📸 **第三個節點：imageGen — 從文字到畫面**\n\n'
          '角色寫完了貼文。現在，幫它配一張圖。\n\n'
          '**imageGen** 節點接收 LLM 寫的貼文內容，然後畫一張圖出來。\n'
          '從文字到畫面——這是另一種「成為」。你的角色不只是說話了，它的世界被看見了。\n\n'
          '貓寫的貼文，配一張從窗台看出去的畫面。盆栽的貼文，配一張陽台小花園的靜物。\n\n'
          '👉 回覆「好」建立圖片生成節點。',

      3 => '✅ imageGen 建好了！\n\n'
          '📸 **第四個節點：output — 一篇可以發的貼文**\n\n'
          '最後一個節點。**output** 是工作流的終點——它把前面所有東西收在一起，變成你可以用的成品。\n\n'
          '一篇角色視角的 IG 貼文，加上一張 AI 生成的配圖。\n'
          '從「你想成為誰」到「一篇可以發的貼文」，四個節點，一條直線。\n\n'
          '但你會發現：換一個角色，這條直線就通往完全不同的地方。\n'
          '這就是直線的力量——看似簡單，但起點的選擇決定了一切。\n\n'
          '👉 回覆「好」建立輸出節點。',

      _ => null,
    };
  }

  /// 範本 2：knowledge_digest（晨間情報站） 6 個節點
  /// 敘事主題：匯流 — 多條河流匯成一個源頭
  String? _knowledgeDigestNarrative(int nodeIndex, String label) {
    return switch (nodeIndex) {
      0 => '📰 **第一個節點：input — 今日主題**\n\n'
          '跟第一個範本一樣，每個工作流都從你開始。\n\n'
          '但這次你給的不是角色，而是一個你今天關心的主題。\n'
          '「AI 發展」、「永續農業」、「今天的天氣」——任何你想深入了解的東西。\n\n'
          '這個主題會同時被送到兩個地方去搜尋。一個出門去網路上找，一個留在家裡翻你的筆記。\n\n'
          '👉 回覆「好」建立 input 節點。',

      1 => '✅ input 建好了！\n\n'
          '📰 **第二個節點：tool — 搜尋網路**\n\n'
          '新東西來了。**tool** 節點跟 LLM 不一樣——它不思考，它做事。\n\n'
          '這個 tool 做的事是「搜尋網路」。它拿你的主題，出門去網路上找相關的新聞和資訊，然後帶回來。\n\n'
          '想像它是一個跑腿的。你給它一張購物清單（主題），它出門去網路上買東西回來。\n\n'
          '👉 回覆「好」建立網路搜尋節點。',

      2 => '✅ 網路搜尋建好了！\n\n'
          '📰 **第三個節點：tool — 搜尋本地檔案**\n\n'
          '另一個 tool。這次它不出門，它留在家裡翻你的東西。\n\n'
          '它搜尋你電腦裡的檔案——你的筆記、你的文件、你之前做過的東西。\n\n'
          '為什麼要搜本地？因為你最獨特的知識不在網路上，在你自己這裡。\n'
          '網路告訴你「世界在說什麼」，本地檔案告訴你「你之前想了什麼」。兩個加起來，才是完整的情報。\n\n'
          '👉 回覆「好」建立本地搜尋節點。',

      3 => '✅ 兩個搜尋都建好了！\n\n'
          '📰 **第四個節點：merge — 匯流**\n\n'
          '兩條河流在這裡相遇。\n\n'
          '**merge** 節點把兩個來源的結果合併在一起——網路上找到的東西，加上你自己檔案裡的東西，匯成一份。\n\n'
          '這是你在橋樑裡學的第二件事：分開的東西可以被連結。\n'
          '網路上的視野很廣，你的筆記很深。merge 讓廣度和深度交會。\n\n'
          '👉 回覆「好」建立合併節點。',

      4 => '✅ merge 建好了！兩條河流匯合了。\n\n'
          '📰 **第五個節點：llm — 情報站編輯**\n\n'
          '合併後的資料交給 LLM。但這次的 LLM 不是角色扮演——它是一個情報站編輯。\n\n'
          '它拿到網路新聞和你的本地筆記，整理成一份結構化日報：\n'
          '今日要聞、本地相關筆記、AI 建議。\n\n'
          '同樣是 LLM，換一個 prompt，它就換一個身份。這就是 prompt 的力量。\n\n'
          '👉 回覆「好」建立 LLM 節點。',

      5 => '✅ LLM 建好了！\n\n'
          '📰 **第六個節點：output — 晨間日報**\n\n'
          '終點。**output** 把 LLM 整理好的日報呈現出來。\n\n'
          '從一個主題，到兩條搜尋，到匯合，到 AI 整理，到一份你今天可以用的情報日報。\n'
          '6 個節點，但真正的魔法在 merge——那個讓兩個世界交會的瞬間。\n\n'
          '👉 回覆「好」建立輸出節點。',

      _ => null,
    };
  }

  /// 範本 3：memory_review（短影音製作所） 9 個節點
  /// 敘事主題：岔路 — 同一個故事，兩種說法
  String? _memoryReviewNarrative(int nodeIndex, String label) {
    return switch (nodeIndex) {
      0 => '🎬 **第一個節點：input — 短影音主題**\n\n'
          '又是起點。但這次，你給的不是角色，也不是主題——你給的是一個想被說出來的故事。\n\n'
          '一個知識點、一段回憶、一個你想分享的觀點。什麼都行。\n'
          '這個故事接下來會被寫成腳本，然後在岔路口分岔成兩種說法。\n\n'
          '但現在，它只是一個種子。\n\n'
          '👉 回覆「好」建立 input 節點。',

      1 => '✅ input 建好了！\n\n'
          '🎬 **第二個節點：llm — 編劇上身**\n\n'
          'LLM 又上場了，但這次的身份是編劇。\n\n'
          '它拿你的主題，寫一段 30 秒的短影音腳本——標題、旁白、視覺描述。\n'
          '而且它會在腳本最後做一個決定：標注 [知識型] 或 [感性型]。\n\n'
          '這個標注很重要。它決定了故事走哪條岔路。\n\n'
          '同樣是 LLM，這次它不只生成內容，還做判斷。AI 的判斷不一定完美，但它給你一個起點。\n\n'
          '👉 回覆「好」建立編劇節點。',

      2 => '✅ 編劇建好了！\n\n'
          '🎬 **第三個節點：condition — 岔路口**\n\n'
          '這是整個工作流的心臟。\n\n'
          '**condition** 節點是一個岔路口。它看 LLM 寫的腳本，讀那個 [知識型] 或 [感性型] 的標注，然後決定走哪邊。\n\n'
          '知識型？往左走，用圖片和語音說一個清楚的故事。\n'
          '感性型？往右走，用影片和配樂說一個有溫度的故事。\n\n'
          '同一個故事，兩種說法。岔路口不選「比較好的」，它只是分流——讓適合的形式自己發揮。\n\n'
          '👉 回覆「好」建立岔路口。',

      3 => '✅ 岔路口建好了！\n\n'
          '🎬 **第四個節點：imageGen — 解說圖（知識型路線）**\n\n'
          '如果故事走知識型，第一站是這裡。\n\n'
          '**imageGen** 你在第一個範本已經用過了。但這次的圖不是配圖，是解說圖——用畫面把知識講清楚。\n\n'
          '👉 回覆「好」建立解說圖節點。',

      4 => '✅ 解說圖建好了！\n\n'
          '🎬 **第五個節點：tts — 語音旁白**\n\n'
          '新東西。**tts** 是 Text-to-Speech，文字轉語音。\n\n'
          '知識型的短影音需要有人「說」給你聽。tts 拿腳本的旁白文字，合成一段語音。\n'
          '從文字到聲音——故事現在不只是看的，還是聽的。\n\n'
          '👉 回覆「好」建立語音旁白節點。',

      5 => '✅ 語音旁白建好了！知識型路線完成。\n\n'
          '🎬 **第六個節點：videoGen — 影片片段（感性型路線）**\n\n'
          '如果故事走感性型，走的是這邊。\n\n'
          '**videoGen** 根據腳本生成一段影片。感性型不靠解說圖，靠畫面本身傳達情緒。\n'
          '同一個故事，這裡不用「講清楚」，而是「讓你感覺到」。\n\n'
          '👉 回覆「好」建立影片節點。',

      6 => '✅ 影片段建好了！\n\n'
          '🎬 **第七個節點：musicGen — 配樂**\n\n'
          '又是一個新東西。**musicGen** 根據腳本生成一段配樂。\n\n'
          '影片有了畫面，但還缺聲音。配樂不是裝飾，它是情緒的底色。\n'
          '好的配樂讓你在看到畫面的瞬間，還沒讀文字就已經有感覺了。\n\n'
          '👉 回覆「好」建立配樂節點。',

      7 => '✅ 配樂建好了！感性型路線也完成。\n\n'
          '🎬 **第八個節點：merge — 兩條路合流**\n\n'
          '兩條岔路在這裡會合。\n\n'
          '知識型帶著解說圖和語音旁白，感性型帶著影片和配樂。**merge** 把它們收在一起。\n\n'
          '不管故事走了哪條路，最後都會到這裡。岔路分開，合流收攏。\n\n'
          '這就是你在橋樑裡學的第三件事：同一個源頭可以流向不同的地方，但最終可以匯合。\n\n'
          '👉 回覆「好」建立合流節點。',

      8 => '✅ merge 建好了！\n\n'
          '🎬 **第九個節點：output — 短影音成品**\n\n'
          '終點。一支完成的短影音——腳本、畫面、聲音、配樂，全部在這裡。\n\n'
          '9 個節點。從一個種子故事，到岔路口分岔，到合流收攏，到一支可以看的短影音。\n'
          '這是你目前做過最複雜的工作流，但你走過來了。\n\n'
          '👉 回覆「好」建立輸出節點。',

      _ => null,
    };
  }

  Future<void> _doConnectNodes() async {
    if (_selectedTemplate == null) return;

    // 實際建立連線
    if (onConnect != null) {
      for (final conn in _selectedTemplate!.connections) {
        final fromIdx = conn['from'] as int;
        final toIdx = conn['to'] as int;
        final fromPort = conn['fromPort'] as String? ?? 'output';
        final toPort = conn['toPort'] as String? ?? 'input';

        if (fromIdx < _createdNodeIds.length && toIdx < _createdNodeIds.length) {
          onConnect!(
            _createdNodeIds[fromIdx],
            fromPort,
            _createdNodeIds[toIdx],
            toPort,
          );
        }
      }
    }

    final connCount = _selectedTemplate!.connections.length;

    // [教練 Agent 2026-07-22] 第四範本連線敘事
    if (_selectedTemplate!.id == 'multi_model') {
      await _speak(
        '✅ 所有 ${_selectedTemplate!.nodes.length} 個節點都建立好了！\n\n'
        '現在來連線。連線的邏輯就是六概念的流向：\n\n'
        '🚪 門 → 🌊 三條水流（主題分流入三個宇宙）\n'
        '🌊 三條水流 → 🌉 橋（三個宇宙的結果匯合）\n'
        '🌉 橋 → ⚖️ 鐘擺觀察者（匯合後交給觀察者）\n'
        '⚖️ 觀察者 → ⚖️ 品質校驗（觀察完做品質判斷）\n'
        '⚖️ 品質校驗 → ⚖️ 補充觀察 / 💗🧠 心腦（不夠就補，夠了就輸出）\n\n'
        '$connCount 條連線接上去之後，整個多重宇宙就活了。\n\n'
        '👉 回覆「好」接上所有連線！'
      );
    } else if (_selectedTemplate!.id == 'ig_post') {
      await _speak(
        '✅ 四個節點全部建好了！\n\n現在把它們連起來。連線就是資料流動的方向：\n\n📥 input → 🧠 llm（角色和素材交給大腦）\n🧠 llm → 🎨 imageGen（貼文內容交給畫筆）\n🎨 imageGen → 📤 output（貼文和配圖匯合成成品）\n\n3 條連線，一條直線。資料從起點流到終點，中途被轉變兩次——一次變成文字，一次變成畫面。\n\n👉 回覆「好」接上所有連線！'
      );
    } else if (_selectedTemplate!.id == 'knowledge_digest') {
      await _speak(
        '✅ 六個節點全部建好了！\n\n這次的連線不是直線了。看看資料怎麼流：\n\n📥 input → 🔧 搜尋網路（主題出門找新聞）\n📥 input → 🔧 搜尋本地（主題留家翻筆記）\n🔧 搜尋網路 → 🔗 merge（網路結果匯入）\n🔧 搜尋本地 → 🔗 merge（本地結果匯入）\n🔗 merge → 🧠 llm（匯合後交給編輯）\n🧠 llm → 📤 output（日報出爐）\n\n注意前兩條——同一個 input 同時往兩個方向去。這就是「分支」，跟直線不同，資料可以在這裡分頭行動。\n\n6 條連線接上去，情報站就開張了。\n\n👉 回覆「好」接上所有連線！'
      );
    } else if (_selectedTemplate!.id == 'memory_review') {
      await _speak(
        '✅ 九個節點全部建好了！\n\n這次的連線最複雜，因為有岔路。仔細看資料怎麼流：\n\n📥 input → 🧠 llm（故事交給編劇）\n🧠 llm → 🔀 condition（腳本到岔路口）\n🔀 condition → 🎨 imageGen（知識型走左邊）\n🎨 imageGen → 🗣️ tts（圖配語音）\n🔀 condition → 🎬 videoGen（感性型走右邊）\n🎬 videoGen → 🎵 musicGen（影片配音樂）\n🗣️ tts → 🔗 merge（知識型合流）\n🎵 musicGen → 🔗 merge（感性型合流）\n🔗 merge → 📤 output（短影音出爐）\n\n看到了嗎？condition 往兩邊都連了——它不是二選一，是「兩條路都準備好，走的時候選一條」。\n這就是分支的真意：不是切割，是可能性。\n\n9 條連線接上去，短影音製作所就開張了。\n\n👉 回覆「好」接上所有連線！'
      );
    } else if (_selectedTemplate!.id == 'ig_post') {
      await _speak(
        '✅ 四個節點全部建好了！\n\n現在把它們連起來。連線就是資料流動的方向：\n\n📥 input → 🧠 llm（角色和素材交給大腦）\n🧠 llm → 🎨 imageGen（貼文內容交給畫筆）\n🎨 imageGen → 📤 output（貼文和配圖匯合成成品）\n\n3 條連線，一條直線。資料從起點流到終點，中途被轉變兩次——一次變成文字，一次變成畫面。\n\n👉 回覆「好」接上所有連線！'
      );
    } else if (_selectedTemplate!.id == 'knowledge_digest') {
      await _speak(
        '✅ 六個節點全部建好了！\n\n這次的連線不是直線了。看看資料怎麼流：\n\n📥 input → 🔧 搜尋網路（主題出門找新聞）\n📥 input → 🔧 搜尋本地（主題留家翻筆記）\n🔧 搜尋網路 → 🔗 merge（網路結果匯入）\n🔧 搜尋本地 → 🔗 merge（本地結果匯入）\n🔗 merge → 🧠 llm（匯合後交給編輯）\n🧠 llm → 📤 output（日報出爐）\n\n注意前兩條——同一個 input 同時往兩個方向去。這就是「分支」，跟直線不同，資料可以在這裡分頭行動。\n\n6 條連線接上去，情報站就開張了。\n\n👉 回覆「好」接上所有連線！'
      );
    } else if (_selectedTemplate!.id == 'memory_review') {
      await _speak(
        '✅ 九個節點全部建好了！\n\n這次的連線最複雜，因為有岔路。仔細看資料怎麼流：\n\n📥 input → 🧠 llm（故事交給編劇）\n🧠 llm → 🔀 condition（腳本到岔路口）\n🔀 condition → 🎨 imageGen（知識型走左邊）\n🎨 imageGen → 🗣️ tts（圖配語音）\n🔀 condition → 🎬 videoGen（感性型走右邊）\n🎬 videoGen → 🎵 musicGen（影片配音樂）\n🗣️ tts → 🔗 merge（知識型合流）\n🎵 musicGen → 🔗 merge（感性型合流）\n🔗 merge → 📤 output（短影音出爐）\n\n看到了嗎？condition 往兩邊都連了——它不是二選一，是「兩條路都準備好，走的時候選一條」。\n這就是分支的真意：不是切割，是可能性。\n\n9 條連線接上去，短影音製作所就開張了。\n\n👉 回覆「好」接上所有連線！'
      );
    } else {
      await _speak(
        '🎉 所有 ${_selectedTemplate!.nodes.length} 個節點都建立好了，\n'
        '而且 $connCount 條連線也接上了！\n\n'
        '現在資料可以從輸入節點流經處理節點，最後到達輸出節點。\n\n'
        '最後一步：確認參數設定。\n\n'
        '👉 回覆「好」完成教學！'
      );
    }

    _currentStep = TutorialStep.configureParams;
  }

  String _describeConnections() {
    final lines = <String>[];
    for (var i = 0; i < _selectedTemplate!.connections.length; i++) {
      final conn = _selectedTemplate!.connections[i];
      final from = conn['from'] as int;
      final to = conn['to'] as int;
      final fromNode = _selectedTemplate!.nodes[from];
      final toNode = _selectedTemplate!.nodes[to];
      final fromLabel = (fromNode['params'] as Map?)?['label'] ?? fromNode['type'];
      final toLabel = (toNode['params'] as Map?)?['label'] ?? toNode['type'];
      lines.add('  ${i + 1}. $fromLabel → $toLabel');
    }
    return lines.join('\n');
  }

  Future<void> _nextStep() async {
    _currentStep = TutorialStep.configureParams;
    await _speak(
      '節點都連好了！🎉\n\n'
      '最後一步：每個節點的參數都已經幫你設定好了。\n'
      '你可以之後雙擊節點來調整 prompt、模型、溫度等設定。\n\n'
      '👉 回覆「好」完成教學！'
    );
  }

  Future<void> _completeTutorial() async {
    // [教練 Agent 2026-07-22] 第四範本畢業典禮結語
    if (_selectedTemplate?.id == 'multi_model') {
      await _speak(
        '🎓 **畢業典禮完成！**\n\n'
        '你剛剛建立了 **${_selectedTemplate!.name}** 工作流：\n'
        '✅ ${_selectedTemplate!.nodes.length} 個節點\n'
        '✅ ${_selectedTemplate!.connections.length} 條連線\n'
        '✅ 3 個子工作流（前三個範本全部上場）\n\n'
        '---\n\n'
        '六概念，你在這一個範本裡全部走過了一遍：\n\n'
        '🚪 門 — 你選了主題，推開了門\n'
        '🌊 水流 — 主題流入三個宇宙，各自變形\n'
        '🌉 橋 — 三個宇宙的結果在橋上匯合\n'
        '⚖️ 鐘擺 — 觀察者在視角間擺動，做校驗\n'
        '💗🧠 心腦 — 最終簡報交給你，直覺和證據合一\n'
        '📚 記憶 — 人格卡、四個範本的產出、使用者畫像——全部留存在知識庫裡。\n'
        '做過的不消失，是資產。\n\n'
        '下次打開 App，你的夥伴記得你。記得你做過什麼，記得你喜歡什麼。\n\n'
        '前面三個範本是練習，這一個是合奏。\n'
        '你學會的不只是怎麼用畫布——你學會的是一種思考方式：\n'
        '做決策（門）、讓它流動（水流）、把結果連起來（橋）、\n'
        '反覆校驗（鐘擺）、用心和腦判斷（心腦）、讓它留下來（記憶）。\n\n'
        '現在你可以：\n'
        '• 雙擊🚪門節點，輸入你想實驗的主題\n'
        '• 點工具列的「執行」按鈕，開跑多重宇宙\n'
        '• 看看同一個主題在三個宇宙裡變成什麼樣子\n\n'
        '畢業快樂。🎉'
      );
    } else if (_selectedTemplate!.id == 'ig_post') {
      await _speak(
        '🎊 **第一個工作流完成！**\n\n你剛剛建立了 **角色扮演 IG** 工作流：\n✅ 4 個節點\n✅ 3 條連線\n\n從現在開始，你可以：\n• 雙擊 input 節點，輸入你想扮演的角色和素材\n• 點工具列的「執行」按鈕，看 AI 怎麼用角色的眼睛看世界\n• 換一個角色再跑一次——同一個工作流，完全不同的結果\n\n記住這個感覺：一條直線，四個節點，但起點的選擇決定了一切。\n\n準備好挑戰第二個範本了嗎？下一次，我們不再走直線了。😊'
      );
    } else if (_selectedTemplate!.id == 'knowledge_digest') {
      await _speak(
        '🎊 **第二個工作流完成！**\n\n你剛剛建立了 **晨間情報站** 工作流：\n✅ 6 個節點\n✅ 6 條連線\n\n你學到了兩個新東西：\n• **tool** — 不思考，只做事。跑腿的好幫手。\n• **merge** — 讓分開的東西匯合。廣度加深度。\n\n從現在開始，你可以：\n• 雙擊 input 節點，輸入你今天關心的主題\n• 點工具列的「執行」按鈕，看網路和你自己的筆記怎麼交會\n• 每天換一個主題，這就是你的私人晨間報\n\n記住 merge 的感覺——分開的東西被連結的那一刻。\n\n第三個範本，我們要再加一層複雜度：不只分支，還要分岔。😊'
      );
    } else if (_selectedTemplate!.id == 'memory_review') {
      await _speak(
        '🎊 **第三個工作流完成！**\n\n你剛剛建立了 **短影音製作所** 工作流：\n✅ 9 個節點\n✅ 9 條連線\n\n你又學了四個新東西：\n• **condition** — 岔路口。不是二選一，是可能性。\n• **tts** — 文字變聲音。故事不只是看的。\n• **videoGen** — 文字變影片。畫面自己會說話。\n• **musicGen** — 文字變音樂。情緒的底色。\n\n到這裡，你已經用過全部 11 種節點類型了：\ninput、llm、tool、imageGen、videoGen、musicGen、tts、condition、merge、output……\n還差一個：**subWorkflow**。\n\n11 種節點裡的最後一個，也是最能改變一切的——它讓你把整個工作流塞進另一個工作流裡。\n\n第四個範本，多重宇宙簡報，就是 subWorkflow 的畢業考。\n你前三個範本做過的所有東西，都會在那裡重新出場。\n\n準備好了嗎？😊'
      );
    } else if (_selectedTemplate!.id == 'ig_post') {
      await _speak(
        '🎊 **第一個工作流完成！**\n\n你剛剛建立了 **角色扮演 IG** 工作流：\n✅ 4 個節點\n✅ 3 條連線\n\n從現在開始，你可以：\n• 雙擊 input 節點，輸入你想扮演的角色和素材\n• 點工具列的「執行」按鈕，看 AI 怎麼用角色的眼睛看世界\n• 換一個角色再跑一次——同一個工作流，完全不同的結果\n\n記住這個感覺：一條直線，四個節點，但起點的選擇決定了一切。\n\n準備好挑戰第二個範本了嗎？下一次，我們不再走直線了。😊'
      );
    } else if (_selectedTemplate!.id == 'knowledge_digest') {
      await _speak(
        '🎊 **第二個工作流完成！**\n\n你剛剛建立了 **晨間情報站** 工作流：\n✅ 6 個節點\n✅ 6 條連線\n\n你學到了兩個新東西：\n• **tool** — 不思考，只做事。跑腿的好幫手。\n• **merge** — 讓分開的東西匯合。廣度加深度。\n\n從現在開始，你可以：\n• 雙擊 input 節點，輸入你今天關心的主題\n• 點工具列的「執行」按鈕，看網路和你自己的筆記怎麼交會\n• 每天換一個主題，這就是你的私人晨間報\n\n記住 merge 的感覺——分開的東西被連結的那一刻。\n\n第三個範本，我們要再加一層複雜度：不只分支，還要分岔。😊'
      );
    } else if (_selectedTemplate!.id == 'memory_review') {
      await _speak(
        '🎊 **第三個工作流完成！**\n\n你剛剛建立了 **短影音製作所** 工作流：\n✅ 9 個節點\n✅ 9 條連線\n\n你又學了四個新東西：\n• **condition** — 岔路口。不是二選一，是可能性。\n• **tts** — 文字變聲音。故事不只是看的。\n• **videoGen** — 文字變影片。畫面自己會說話。\n• **musicGen** — 文字變音樂。情緒的底色。\n\n到這裡，你已經用過全部 11 種節點類型了：\ninput、llm、tool、imageGen、videoGen、musicGen、tts、condition、merge、output……\n還差一個：**subWorkflow**。\n\n11 種節點裡的最後一個，也是最能改變一切的——它讓你把整個工作流塞進另一個工作流裡。\n\n第四個範本，多重宇宙簡報，就是 subWorkflow 的畢業考。\n你前三個範本做過的所有東西，都會在那裡重新出場。\n\n準備好了嗎？😊'
      );
    } else {
      await _speak(
        '🎊 教學完成！\n\n'
        '你剛剛建立了 **${_selectedTemplate?.name}** 工作流：\n'
        '✅ ${_selectedTemplate!.nodes.length} 個節點\n'
        '✅ ${_selectedTemplate!.connections.length} 條連線\n\n'
        '接下來你可以：\n'
        '• 雙擊節點調整參數\n'
        '• 點工具列的「執行」按鈕跑工作流\n'
        '• 從左側 Vault 側欄搜尋條目送至畫布\n\n'
        '有任何問題隨時問我！😊'
      );
    }

    _isActive = false;
    _hasCompletedTutorial = true;
    _currentStep = TutorialStep.complete;
    _canvasEventSub?.cancel();
    _canvasEventSub = null;
  }

  // ── 輔助方法 ──────────────────────────────────────────────────

  bool _isAffirmative(String text) {
    final affirmative = ['好', '要', 'ok', 'yes', 'y', '好呀', '好啊', '可以', '開始', '繼續', '沒問題', '嗯', '行'];
    return affirmative.any((w) => text.contains(w));
  }

  bool _isNegative(String text) {
    final negative = ['不用', '不要', 'no', 'n', '算了', '不用了', '自己', '下次', '以後'];
    return negative.any((w) => text.contains(w));
  }

  Future<void> _injectUserResponse(String response) async {
    await _chatController!.injectUserMessageSilent(response);
  }

  /// [教練 Agent 2026-07-23] Agent 發話 helper——注入訊息 + 觸發高亮
  ///
  /// [2026-08-27 B 方案] 訊息結尾是「👉 回覆「好」...」時自動轉成動作按鈕——
  /// 舊機制（handleUserResponse 攔截文字）已於 08-03 廢除，
  /// 教學推進改由泡泡上的按鈕驅動（零誤判、視覺乾淨，同藍色切換條設計語言）。
  Future<void> _speak(String message) async {
    Map<String, dynamic>? metadata;
    var content = message;

    final arrowIdx = content.indexOf('👉');
    if (arrowIdx >= 0) {
      final after = content.substring(arrowIdx);
      if (after.contains('回覆') && after.contains('好')) {
        // 推進動作：依當前步驟決定按鈕行為
        final isConnectPhase = after.contains('接上') || after.contains('連線');
        final isFinishPhase = after.contains('完成教學');
        content = content.substring(0, arrowIdx).trimRight();
        metadata = {
          'kind': 'tutorial_prompt',
          'actions': [
            {
              'label': isConnectPhase
                  ? '接上所有連線'
                  : (isFinishPhase ? '完成教學' : '好，繼續'),
              'action': isConnectPhase
                  ? 'tutorial_connect'
                  : (isFinishPhase ? 'tutorial_finish' : 'tutorial_next'),
            },
            {
              'label': '結束教學',
              'action': 'tutorial_cancel',
            },
          ],
        };
      }
    }

    await _chatController!.injectAssistantMessage(
      content,
      metadata: metadata,
    );
    onAgentSpeak?.call();
  }

  /// [2026-08-27 B 方案] 按鈕動作 dispatcher——泡泡按鈕點擊時呼叫
  Future<void> performAction(String action) async {
    // [2026-08-27 Blue 抓包] 按鈕點擊＝明確意圖——不再被 _isActive 擋死。
    // 舊行為：10 分鐘 timer 或頁面重建把 _isActive 關掉後，
    // 使用者點按鈕全部靜默無反應（三鈕全啞）。
    // 現在：_isActive false 時自動復活再執行；只有 controller 缺席才放棄。
    if (_chatController == null) return;
    if (!_isActive) {
      _isActive = true;
      _canvasEventSub?.cancel();
      _canvasEventSub = CanvasEventBus.instance.subscribe(_onCanvasEvent);
    }
    switch (action) {
      case 'tutorial_next':
        // 節點階段推進：introTemplate → 第一顆；addNode/addSecond/addThird → 下一顆
        switch (_currentStep) {
          case TutorialStep.introTemplate:
          case TutorialStep.greeting:
          case TutorialStep.templateSelection:
            await _startAddingNodes();
            break;
          case TutorialStep.addNode:
          case TutorialStep.addSecondNode:
          case TutorialStep.addThirdNode:
          case TutorialStep.explainNode:
            await _proceedToNextNode();
            break;
          case TutorialStep.configureParams:
            await _completeTutorial();
            break;
          default:
            break;
        }
        break;
      case 'tutorial_connect':
        // 連線階段：真正把連線接上，然後完成
        await _connectAndFinish();
        break;
      case 'tutorial_finish':
        await _completeTutorial();
        break;
      case 'tutorial_resume':
        await _resumeBuilding();
        break;
      case 'tutorial_reselect':
        await _showTemplateMenu();
        break;
      case 'tutorial_cancel':
        await _speak('教學結束！你可以隨時雙擊節點調整設定，或點「執行」跑看看。');
        _hasCompletedTutorial = true;
        clearPersistedProgress();
        cancel();
        break;
      default:
        if (action.startsWith('tutorial_pick_')) {
          final templateId = action.substring('tutorial_pick_'.length);
          final templates =
              VaultTemplateService.instance.getBuiltinTemplates();
          final template = templates.where((t) => t.id == templateId).firstOrNull;
          if (template != null && !template.isTutorialEntry) {
            // [2026-08-27] resume 續建情境（_isActive 且畫布已有節點）：
            // 設範本但跳過重新介紹——直接從「下一顆」開始（只補缺）
            final alreadyActive = _isActive;
            if (alreadyActive && _createdNodeIds.isNotEmpty) {
              _selectedTemplate = template;
              _currentStep = TutorialStep.addNode;
              await _speak(
                '收到！範本是 ${template.icon} **${template.name}**。\n\n'
                '我把畫布上已有的節點算進進度，接下來只補缺少的部分。\n\n'
                '準備好了就繼續。',
              );
            } else {
              await startTutorialWithTemplate(template);
            }
          }
        }
        break;
    }
  }

  /// [2026-08-27 B 方案] 接上連線＋收尾（舊碼只說不接——按鈕觸發真正接線）
  Future<void> _connectAndFinish() async {
    if (_selectedTemplate == null) return;

    // 實際建立連線（靜音旗標——事件不觸發插話）
    if (onConnect != null) {
      _selfCreating = true;
      try {
        for (final conn in _selectedTemplate!.connections) {
          final fromIdx = conn['from'] as int;
          final toIdx = conn['to'] as int;
          final fromPort = conn['fromPort'] as String? ?? 'output';
          final toPort = conn['toPort'] as String? ?? 'input';

          if (fromIdx < _createdNodeIds.length &&
              toIdx < _createdNodeIds.length) {
            onConnect!(
              _createdNodeIds[fromIdx],
              fromPort,
              _createdNodeIds[toIdx],
              toPort,
            );
          }
        }
      } finally {
        _selfCreating = false;
      }
    }

    final connCount = _selectedTemplate!.connections.length;
    await _speak(
      '✅ $connCount 條連線全部接上了！\n\n'
      '每個節點的參數都已經幫你設定好了。'
      '你可以雙擊節點調整 prompt、模型、溫度等設定。'
    );
    await _completeTutorial();
  }

  /// 取消教學
  void cancel() {
    _isActive = false;
    _currentStep = TutorialStep.greeting;
    _nodeIndex = 0;
    _awaitTimer?.cancel();
    _canvasEventSub?.cancel();
    _canvasEventSub = null;
  }

  // ── 人機共視：畫布事件即時回應 ────────────────────────────────

  /// [教練 Agent 2026-07-22] 人機共視核心
  /// 當使用者在畫布上做任何動作時，Agent 即時感知並主動回應。
  /// 這就是「共視」——Agent 看著使用者操作，主動引導。
  /// [2026-08-27] 教學自建節點/連線時的靜音旗標
  bool _selfCreating = false;

  void _onCanvasEvent(CanvasEvent event) {
    if (!_isActive || _chatController == null) return;
    // [2026-08-27 Blue 抓包] 教學自建節點/連線時靜音——
    // 舊行為：按按鈕→onAddNode 建節點→事件觸發 _onUserAddedNode
    // →在下一節點敘事「之後」噴「恭喜建立第一個節點」——
    // 把帶推進按鈕的最新訊息擠到上面，順序錯亂。
    if (_selfCreating) return;
    // [教練 Agent 2026-08-17 使用者 抓包] 教學還停在 greeting/templateSelection
    // 階段＝使用者從未答覆「好」開始教學。此時對畫布動作插話
    // （「要自己嘗試還是繼續教學？」）是殭屍教學漏進正常對話。
    // 處理：教學沒真正開始就自己關掉，不再對畫布動作有意見。
    if (_currentStep == TutorialStep.greeting ||
        _currentStep == TutorialStep.templateSelection) {
      _isActive = false;
      _canvasEventSub?.cancel();
      _canvasEventSub = null;
      return;
    }

    switch (event.type) {
      case CanvasEventType.nodeAdded:
        _onUserAddedNode(event);
        break;
      case CanvasEventType.nodeRemoved:
        _onUserRemovedNode(event);
        break;
      case CanvasEventType.connectionAdded:
        _onUserConnectedNodes(event);
        break;
      case CanvasEventType.nodeMoved:
        // 移動節點——太頻繁，不做即時回應
        break;
      default:
        break;
    }
  }

  /// 使用者新增了節點
  Future<void> _onUserAddedNode(CanvasEvent event) async {
    // [2026-08-27 Blue 抓包·二輪] 事件流非同步——emit 後 handler 在 microtask
    // 才跑，_selfCreating 旗標已被 finally 復位，時間窗擋不住。
    // 改身分比對：教學自建節點的 ID 都在 _createdNodeIds——
    // 事件 nodeId 在其中＝自建，直接忽略（時間無關，免疫 async）。
    if (event.nodeId != null && _createdNodeIds.contains(event.nodeId)) {
      return;
    }
    _userCreatedNodeCount++;
    final nodeType = event.nodeType ?? '節點';

    // 根據當前教學步驟給予不同的即時回應
    switch (_currentStep) {
      case TutorialStep.addNode:
      case TutorialStep.addSecondNode:
      case TutorialStep.addThirdNode:
        // 使用者在教學引導下建立了節點——即時鼓勵 + 引導下一步
        await _speak(
          '太好了！🎉 你剛建立了一個 **$nodeType** 節點。\n\n'
          '接下來試試看：把游標移到節點右邊的圓點（output port），\n'
          '按住拖曳到下一個節點的左邊圓點（input port），就能建立連線。\n\n'
          '或者回覆「好」讓我幫你繼續建立。'
        );
        break;
      case TutorialStep.greeting:
      case TutorialStep.templateSelection:
      case TutorialStep.introTemplate:
        // 使用者在教學還沒到建立節點階段就自己建了——鼓勵探索
        await _speak(
          '我看到你自己建了一個 $nodeType 節點！不錯 👍\n'
          '我們可以繼續教學，或者你先自己試試看。'
        );
        break;
      default:
        break;
    }
  }

  /// 使用者刪除了節點
  Future<void> _onUserRemovedNode(CanvasEvent event) async {
    await _speak(
      '節點已刪除 🗑️\n'
      '如果刪錯了，可以在左上方「恢復上一步」的按鈕重新建立。'
    );
  }

  /// 使用者建立了連線
  Future<void> _onUserConnectedNodes(CanvasEvent event) async {
    final from = event.data?['from'] as String? ?? '';
    final to = event.data?['to'] as String? ?? '';
    // [2026-08-27 Blue 抓包·二輪] 同 nodeAdded——身分比對擋教學自接連線
    if (_createdNodeIds.contains(from) && _createdNodeIds.contains(to)) {
      return;
    }

    await _speak(
      '連線建立成功！✅\n'
      '資料現在可以從上面的節點流向下面的節點了。\n\n'
      '繼續试试看，或回覆「好」讓我帶你下一步。'
    );
  }

  /// 取得當前選中的範本（供 UI 層建立節點用）
  WorkflowTemplate? get selectedTemplate => _selectedTemplate;

  /// 取得當前要建立的節點索引
  int get currentNodeIndex => _nodeIndex;
}
