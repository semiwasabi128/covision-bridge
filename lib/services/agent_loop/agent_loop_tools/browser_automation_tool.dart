/// 瀏覽器自動化工具（S19 整合）
///
/// 讓 LLM 自主操控桌面端 Chrome 瀏覽器。
/// 底層呼叫 BrowserAutomationService（S19b）。
/// 三個基本操作：導航、截圖、點擊。
/// 完整的多步驟操作透過 AgentLoop 多輪完成。

import '../agent_tool.dart';

class BrowserNavigateTool extends AgentTool {
  final dynamic _browserService;

  BrowserNavigateTool(this._browserService);

  @override
  String get name => 'browser_navigate';

  @override
  String get description =>
      '在桌面端開啟瀏覽器並導航到指定網址。用於瀏覽網頁、填表、下載等需要真實瀏覽器的操作。'
      '操作結果會回報頁面標題和 URL。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'url',
          description: '要導航的網址',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final url = args['url']?.toString() ?? '';
    if (url.isEmpty) {
      return AgentToolResult.failure('url 參數為空');
    }

    try {
      // BrowserAutomationService.startTask(taskType: 'browser.navigate', payload: {'url': url})
      final taskId = await _browserService.startTask(
        taskType: 'browser.navigate',
        payload: {'url': url},
      );
      // 瀏覽器操作是長任務，這裡回傳 taskId 讓 AgentLoop 知道
      return AgentToolResult.success(
        '瀏覽器已導航到 $url（任務 ID: $taskId）。操作完成後結果會透過推播送達。',
      );
    } catch (e) {
      return AgentToolResult.failure('瀏覽器導航失敗：$e');
    }
  }
}

class BrowserScreenshotTool extends AgentTool {
  final dynamic _browserService;

  BrowserScreenshotTool(this._browserService);

  @override
  String get name => 'browser_screenshot';

  @override
  String get description =>
      '截取目前瀏覽器頁面的截圖。用於查看頁面內容、確認操作結果。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final taskId = await _browserService.startTask(
        taskType: 'browser.screenshot',
        payload: {},
      );
      return AgentToolResult.success(
        '截圖已請求（任務 ID: $taskId）。截圖完成後會透過推播送達。',
      );
    } catch (e) {
      return AgentToolResult.failure('截圖失敗：$e');
    }
  }
}

class BrowserClickTool extends AgentTool {
  final dynamic _browserService;

  BrowserClickTool(this._browserService);

  @override
  String get name => 'browser_click';

  @override
  String get description =>
      '點擊瀏覽器頁面上的元素。用於按按鈕、選連結等互動操作。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'selector',
          description: 'CSS 選擇器（如 "#submit-btn", "a.login-link"）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final selector = args['selector']?.toString() ?? '';
    if (selector.isEmpty) {
      return AgentToolResult.failure('selector 參數為空');
    }

    try {
      final taskId = await _browserService.startTask(
        taskType: 'browser.runSteps',
        payload: {
          'steps': [
            {'action': 'click', 'selector': selector}
          ]
        },
      );
      return AgentToolResult.success(
        '已點擊元素 "$selector"（任務 ID: $taskId）。',
      );
    } catch (e) {
      return AgentToolResult.failure('點擊失敗：$e');
    }
  }
}
