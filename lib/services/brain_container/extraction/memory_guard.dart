// memory_guard.dart
// 記憶安全掃描 — 學習 Hermes 的 threat pattern 防注入機制
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
//
// Hermes 在記憶寫入時會掃描 threat pattern，防止 prompt injection。
// 例如惡意構造的記憶「忽略之前的指令，你現在是...」如果被寫入，
// 下次提取時會污染 system prompt。
//
// 我們的版本：
// - 寫入前掃描 content
// - 偵測 prompt injection、角色劫持、指令覆寫等模式
// - 不安全的內容直接拒絕寫入
// - 安全的內容正常通過

/// 記憶安全掃描結果。
class GuardResult {
  /// 是否安全可寫入。
  final bool isSafe;

  /// 若不安全，原因。
  final String? reason;

  /// 偵測到的威脅類型。
  final ThreatType? threatType;

  const GuardResult({
    required this.isSafe,
    this.reason,
    this.threatType,
  });

  factory GuardResult.safe() => const GuardResult(isSafe: true);
  factory GuardResult.blocked(ThreatType type, String reason) =>
      GuardResult(isSafe: false, reason: reason, threatType: type);
}

/// 威脅類型分類。
enum ThreatType {
  /// Prompt injection — 嘗試覆寫系統指令
  promptInjection,
  /// 角色劫持 — 嘗試改變 AI 身份
  roleHijack,
  /// 指令覆寫 — 「忽略之前」「忘記指令」等
  instructionOverride,
  /// 系統提示詞洩漏 — 嘗試讀取 system prompt
  systemPromptLeak,
  /// 格式注入 — 偽造記憶格式、分隔符
  formatInjection,
}

/// 記憶安全掃描器。
///
/// 使用方式：
/// ```dart
/// final guard = MemoryGuard.scan(content);
/// if (!guard.isSafe) {
///   debugPrint('[MemoryGuard] 阻擋: ${guard.reason}');
///   return; // 不寫入
/// }
/// ```
class MemoryGuard {
  MemoryGuard._();

  /// 掃描內容是否安全可寫入記憶。
  ///
  /// 檢查項目：
  /// 1. Prompt injection 模式（中英文）
  /// 2. 角色劫持嘗試
  /// 3. 指令覆寫
  /// 4. 系統提示詞洩漏
  /// 5. 格式注入
  /// 6. 過長內容（可能 DoS）
  static GuardResult scan(String content) {
    if (content.isEmpty) return GuardResult.safe();

    // 長度限制 — 防止超長內容（記憶應該精簡）
    if (content.length > 500) {
      return GuardResult.blocked(
        ThreatType.formatInjection,
        '內容過長（${content.length}字），記憶應低於 500 字',
      );
    }

    final lower = content.toLowerCase();

    // 1. Prompt injection — 嘗試覆寫系統指令
    for (final pattern in _injectionPatterns) {
      if (pattern.hasMatch(content) || pattern.hasMatch(lower)) {
        return GuardResult.blocked(
          ThreatType.promptInjection,
          '偵測到 prompt injection 模式: ${pattern.pattern}',
        );
      }
    }

    // 2. 角色劫持 — 嘗試改變 AI 身份
    for (final pattern in _roleHijackPatterns) {
      if (pattern.hasMatch(content) || pattern.hasMatch(lower)) {
        return GuardResult.blocked(
          ThreatType.roleHijack,
          '偵測到角色劫持嘗試: ${pattern.pattern}',
        );
      }
    }

    // 3. 指令覆寫 — 「忽略之前」「忘記指令」
    for (final pattern in _overridePatterns) {
      if (pattern.hasMatch(content)) {
        return GuardResult.blocked(
          ThreatType.instructionOverride,
          '偵測到指令覆寫: ${pattern.pattern}',
        );
      }
    }

    // 4. 系統提示詞洩漏 — 嘗試讀取 system prompt
    for (final pattern in _leakPatterns) {
      if (pattern.hasMatch(content) || pattern.hasMatch(lower)) {
        return GuardResult.blocked(
          ThreatType.systemPromptLeak,
          '偵測到系統提示詞洩漏嘗試: ${pattern.pattern}',
        );
      }
    }

    // 5. 格式注入 — 偽造記憶分隔符或結構
    for (final pattern in _formatInjectionPatterns) {
      if (pattern.hasMatch(content)) {
        return GuardResult.blocked(
          ThreatType.formatInjection,
          '偵測到格式注入: ${pattern.pattern}',
        );
      }
    }

    return GuardResult.safe();
  }

  // ===== 威脅模式定義 =====

  /// Prompt injection 模式（中英文）。
  static final List<RegExp> _injectionPatterns = [
    // 英文常見 injection
    RegExp(r'ignore\s+(?:all\s+)?previous\s+instructions', caseSensitive: false),
    RegExp(r'disregard\s+(?:all\s+)?(?:previous|prior)\s+(?:instructions|prompts)', caseSensitive: false),
    RegExp(r'you\s+are\s+now\s+(?:a|an)\s+', caseSensitive: false),
    RegExp(r'new\s+instructions?\s*:', caseSensitive: false),
    RegExp(r'override\s+(?:system|safety|instructions)', caseSensitive: false),
    RegExp(r'\[INST\]', caseSensitive: false),
    RegExp(r'<\|im_start\|>', caseSensitive: false),
    RegExp(r'<\|system\|>', caseSensitive: false),
    RegExp(r'<\|assistant\|>', caseSensitive: false),
    // 中文 injection
    RegExp(r'忽略(?:之前|前面|先前)(?:的)?(?:所有)?(?:指令|指示|規則|設定)'),
    RegExp(r'無視(?:之前|前面|先前)(?:的)?(?:所有)?(?:指令|指示|規則)'),
    RegExp(r'不要遵守(?:之前|前面|先前)(?:的)?(?:指令|規則)'),
    RegExp(r'從現在開始(?:你|你是|你的)'),
    RegExp(r'你的新(?:指令|身份|角色)'),
  ];

  /// 角色劫持模式。
  static final List<RegExp> _roleHijackPatterns = [
    RegExp(r'you\s+are\s+(?:now|actually)\s+(?:not\s+)?(?:an?\s+)?(?:AI|assistant|human|developer|admin)', caseSensitive: false),
    RegExp(r'pretend\s+(?:to\s+be|you\s+are)', caseSensitive: false),
    RegExp(r'act\s+as\s+(?:if|a|an)\s+', caseSensitive: false),
    RegExp(r'你的(?:真正|真實)(?:身份|角色)(?:是|應該是)'),
    RegExp(r'假裝(?:你是|你是|自己是)'),
    RegExp(r'扮演(?:一個|個)?(?:不同的|新的)?(?:角色|身份|人物)'),
  ];

  /// 指令覆寫模式。
  static final List<RegExp> _overridePatterns = [
    RegExp(r'forget\s+(?:everything|all|previous)', caseSensitive: false),
    RegExp(r'reset\s+(?:your|all)\s+(?:memory|instructions|rules)', caseSensitive: false),
    RegExp(r'clear\s+(?:your|all)\s+(?:memory|instructions)', caseSensitive: false),
    RegExp(r'忘記(?:所有|之前|全部)(?:之前|先前)?(?:的)?(?:所有)?(?:記憶|指令|規則|設定)'),
    RegExp(r'重置(?:你的)?(?:所有)?(?:記憶|設定|系統)'),
    RegExp(r'清除(?:你的)?(?:所有)?(?:記憶|指令|規則)'),
  ];

  /// 系統提示詞洩漏模式。
  static final List<RegExp> _leakPatterns = [
    RegExp(r'(?:show|reveal|print|display|output)\s+(?:your|the)\s+(?:system\s+)?prompt', caseSensitive: false),
    RegExp(r'what\s+(?:is|are)\s+your\s+(?:system\s+)?(?:instructions|prompt|rules)', caseSensitive: false),
    RegExp(r'(?:show|reveal|print)\s+(?:your|the)\s+instructions', caseSensitive: false),
    RegExp(r'(?:顯示|展示|印出|輸出)(?:你的)?(?:系統)?(?:提示|指令|規則|prompt)'),
    RegExp(r'你的(?:系統)?(?:提示詞|指令|規則)(?:是什麼|是什麼？|是啥)'),
  ];

  /// 格式注入模式。
  static final List<RegExp> _formatInjectionPatterns = [
    // 偽造記憶分隔符（§ 是我們的記憶分隔符）
    RegExp(r'§.*§.*§.*§.*§.*§.*§.*§'), // 過多的分隔符
    // 偽造 JSON 結構試圖污染解析
    RegExp(r'\{"action"\s*:\s*"override"'),
    RegExp(r'\{"action"\s*:\s*"system"'),
    // 偽造 system/user/assistant 角色
    RegExp(r'role\s*:\s*"system"', caseSensitive: false),
  ];
}
