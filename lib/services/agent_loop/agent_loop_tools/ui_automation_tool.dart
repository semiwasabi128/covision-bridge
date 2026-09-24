// UI Automation Tool — 讓 Agent 能操作 App UI
// [Phase 2 2026-07-18] 讓原生 Agent能看見按鈕、使用按鈕、切換頁面
// [教練 Agent 2026-08-02] 擴大感知範圍 + ui_inspect 深度檢視 + 金鑰保密
//
// 四個工具：
// 1. ui_get_state — 查詢當前頁面 + 可點擊元素列表 + 頁面摘要
// 2. ui_inspect — 深度檢視頁面內容（對話訊息、設定狀態等，排除金鑰）
// 3. ui_navigate — 導航到指定頁面
// 4. ui_tap — 點擊指定元素（用 label 查找）

import '../agent_tool.dart';

/// UI 操作執行器 — 由 BridgeDesktopScreen / DesktopWelcomeScreen 實作
abstract class UiActionExecutor {
  /// 取得當前 UI 狀態
  /// 回傳：{page, activeTab, hasCompanion, companionName, tappable: [...], pageSummary: "..."}
  Map<String, dynamic> getState();

  /// 深度檢視頁面內容
  /// 回傳頁面的詳細資訊（對話摘要、設定狀態、vault 狀態等）
  /// [注意] 金鑰匙頁面的 token/key 永遠回傳 [已隱藏]
  Map<String, dynamic> inspect();

  /// 導航到指定頁面
  bool navigate(String target);

  /// 點擊指定元素（用 label 查找）
  bool tap(String label);
}

/// Stub — 未傳入 executor 時用
class StubUiActionExecutor implements UiActionExecutor {
  @override
  Map<String, dynamic> getState() => {
    'page': 'unknown',
    'tappable': <String>[],
    'pageSummary': 'UI 感知未啟用',
  };

  @override
  Map<String, dynamic> inspect() => {
    'page': 'unknown',
    'details': 'UI 感知未啟用',
  };

  @override
  bool navigate(String target) => false;

  @override
  bool tap(String label) => false;
}

// ═══════════════════════════════════════════════════
// ui_get_state — 查詢當前 UI 狀態（含頁面摘要）
// ═══════════════════════════════════════════════════

class UiGetStateTool extends AgentTool {
  final UiActionExecutor _executor;

  UiGetStateTool(this._executor);

  @override
  String get name => 'ui_get_state';

  @override
  String get description =>
      '查詢 App 當前 UI 狀態。回傳：當前頁面、活躍分頁、是否有夥伴、夥伴名稱、'
      '可點擊元素列表、頁面內容摘要。'
      '這是了解 App 畫面狀態的第一步，先用此工具再決定下一步操作。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final state = _executor.getState();
    final page = state['page'] ?? 'unknown';
    final tappable = state['tappable'] as List<dynamic>? ?? [];
    final hasCompanion = state['hasCompanion'] ?? false;
    final companionName = state['companionName'] ?? '無';
    final pageSummary = state['pageSummary'] ?? '';

    final summary = '當前頁面: $page\n'
        '有夥伴: $hasCompanion\n'
        '夥伴名稱: $companionName\n'
        '可點擊元素 (${tappable.length} 個): ${tappable.join(", ")}';
    final fullSummary = pageSummary.isNotEmpty
        ? '$summary\n頁面摘要: $pageSummary'
        : summary;

    return AgentToolResult.success(fullSummary, metadata: state);
  }
}

// ═══════════════════════════════════════════════════
// ui_inspect — 深度檢視頁面內容（排除金鑰）
// ═══════════════════════════════════════════════════

class UiInspectTool extends AgentTool {
  final UiActionExecutor _executor;

  UiInspectTool(this._executor);

  @override
  String get name => 'ui_inspect';

  @override
  String get description =>
      '深度檢視當前頁面的內容。回傳頁面的詳細資訊：\n'
      '- 對話頁面：最近幾則訊息、對話標題、訊息數量\n'
      '- 設定頁面：provider 配置狀態（token 是否已設定，但**不顯示 token 內容**）\n'
      '- 金鑰匙頁面：各能力的就緒狀態（**金鑰內容永遠顯示 [已隱藏]**）\n'
      '- 資料庫頁面：資產數量、嵌入狀態、檢視模式\n'
      '- 大腦頁面：記憶數量、查看模式\n'
      '注意：API Key / Token 等敏感資訊永遠被過濾，Agent 看不到。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final details = _executor.inspect();
    final page = details['page'] ?? 'unknown';
    final content = details['details'] ?? '無法取得頁面詳細資訊';

    // 安全過濾：確保沒有洩露 token/key
    final filtered = _filterSensitive(content);

    return AgentToolResult.success(
      '頁面檢視: $page\n\n$filtered',
      metadata: details,
    );
  }

  /// 過濾敏感資訊 — 多層保護
  String _filterSensitive(String text) {
    var result = text;
    // 過濾 API Key 格式（sk-..., Bearer ..., 等）
    result = result.replaceAll(RegExp(r'sk-[A-Za-z0-9]{10,}'), '[已隱藏]');
    result = result.replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._\-]{10,}'), '[已隱藏]');
    // 過濾常見 token 格式（超過 20 字的英數字串，像是 JWT 或 API token）
    result = result.replaceAll(RegExp(r'\b[A-Za-z0-9]{32,}\b'), '[已隱藏]');
    // 過濾明確標記的 token/key 值
    result = result.replaceAll(RegExp(r'token[:\s]+[^\s\[]{8,}', caseSensitive: false), 'token: [已隱藏]');
    result = result.replaceAll(RegExp(r'key[:\s]+[^\s\[]]{8,}', caseSensitive: false), 'key: [已隱藏]');
    return result;
  }
}

// ═══════════════════════════════════════════════════
// ui_navigate — 導航到指定頁面
// ═══════════════════════════════════════════════════

class UiNavigateTool extends AgentTool {
  final UiActionExecutor _executor;

  UiNavigateTool(this._executor);

  @override
  String get name => 'ui_navigate';

  @override
  String get description =>
      '導航到指定頁面。可用目標：'
      'home（首頁）, companion_hall（夥伴館）, '
      'chat（對話）, canvas（畫布）, project（專案）, '
      'brain（大腦）, vault（向量資料庫）, system（系統設定）, '
      'summon（召喚頁）, settings（設定頁）, '
      'golden_keys（金鑰匙頁）, capabilities（能力中心）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'target',
      description: '導航目標：home/companion_hall/chat/canvas/project/brain/vault/system/summon/settings/golden_keys/capabilities',
      required: true,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final target = args['target'] as String?;
    if (target == null || target.isEmpty) {
      return AgentToolResult.failure('缺少 target 參數');
    }

    final validTargets = [
      'home', 'companion_hall', 'chat', 'canvas', 'project',
      'brain', 'vault', 'system', 'summon', 'settings',
      'golden_keys', 'capabilities',
    ];
    if (!validTargets.contains(target)) {
      return AgentToolResult.failure('無效的 target: $target。可用：${validTargets.join(", ")}');
    }

    final success = _executor.navigate(target);
    if (success) {
      return AgentToolResult.success('已導航到 $target');
    } else {
      return AgentToolResult.failure('無法導航到 $target（可能目前頁面不支援此目標）');
    }
  }
}

// ═══════════════════════════════════════════════════
// ui_tap — 點擊指定元素
// ═══════════════════════════════════════════════════

class UiTapTool extends AgentTool {
  final UiActionExecutor _executor;

  UiTapTool(this._executor);

  @override
  String get name => 'ui_tap';

  @override
  String get description =>
      '點擊 App 畫面上的指定元素。先用 ui_get_state 查看可點擊元素列表（tappable），'
      '再用 label 點擊。例如：ui_tap(label="新增對話")。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'label',
      description: '要點擊的元素 label（從 ui_get_state 的 tappable 列表中選擇）',
      required: true,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final label = args['label'] as String?;
    if (label == null || label.isEmpty) {
      return AgentToolResult.failure('缺少 label 參數');
    }

    // 金鑰保護：禁止點擊涉及金鑰操作的元素
    final protectedLabels = ['顯示密碼', '顯示金鑰', '複製金鑰', '查看 token'];
    if (protectedLabels.contains(label)) {
      return AgentToolResult.failure('「$label」是保密操作，Agent 無法執行。');
    }

    final success = _executor.tap(label);
    if (success) {
      return AgentToolResult.success('已點擊「$label」');
    } else {
      final state = _executor.getState();
      final tappable = state['tappable'] as List<dynamic>? ?? [];
      return AgentToolResult.failure('找不到「$label」。目前可點擊的元素：${tappable.join(", ")}');
    }
  }
}
