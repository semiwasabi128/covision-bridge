// browser_task.dart
// 瀏覽器自動化任務腳本模型。
// 定義一個瀏覽器任務包含哪些步驟，每步有 action + selector + value + waitAfter。
// Sprint 19b by 教練 Agent (CEO)

/// 單一瀏覽器操作步驟的類型。
enum BrowserStepAction {
  /// 導航到 URL（value = URL）
  navigate,
  /// 點擊元素（selector = CSS selector）
  click,
  /// 填寫輸入框（selector = CSS selector, value = 文字）
  type,
  /// 等待元素出現（selector = CSS selector）
  waitForSelector,
  /// 等待固定時間（value = 毫秒數字字串）
  wait,
  /// 執行 JavaScript（value = JS code）
  evaluate,
  /// 截圖（result 會帶 base64 圖片）
  screenshot,
  /// 下載檔案（value = URL）
  download,
  /// 取得頁面文字內容（selector = CSS selector, result 帶文字）
  getText,
  /// 捲動到元素（selector = CSS selector）
  scrollTo,
}

/// 瀏覽器操作步驟。
class BrowserStep {
  final BrowserStepAction action;
  final String? selector;
  final String? value;
  final Duration? waitAfter;
  final Duration? timeout;

  const BrowserStep({
    required this.action,
    this.selector,
    this.value,
    this.waitAfter,
    this.timeout,
  });

  factory BrowserStep.fromJson(Map<String, dynamic> json) {
    final actionName = json['action'] as String? ?? 'navigate';
    final action = BrowserStepAction.values.firstWhere(
      (a) => a.name == actionName,
      orElse: () => BrowserStepAction.navigate,
    );
    return BrowserStep(
      action: action,
      selector: json['selector'] as String?,
      value: json['value'] as String?,
      waitAfter: json['waitAfterMs'] != null
          ? Duration(milliseconds: (json['waitAfterMs'] as num).toInt())
          : null,
      timeout: json['timeoutMs'] != null
          ? Duration(milliseconds: (json['timeoutMs'] as num).toInt())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'action': action.name,
      if (selector != null) 'selector': selector,
      if (value != null) 'value': value,
      if (waitAfter != null) 'waitAfterMs': waitAfter!.inMilliseconds,
      if (timeout != null) 'timeoutMs': timeout!.inMilliseconds,
    };
  }
}

/// 瀏覽器自動化任務腳本。
///
/// 一個任務由多個 [BrowserStep] 組成，按順序執行。
/// 任務執行時，每步完成後推播進度；偵測到登入/付款頁時暫停等待確認。
class BrowserTask {
  final String id;
  final String name;
  final List<BrowserStep> steps;
  final bool headless;

  const BrowserTask({
    required this.id,
    required this.name,
    required this.steps,
    this.headless = false, // 設計文件要求使用者看得到瀏覽器
  });

  factory BrowserTask.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json['steps'];
    final steps = stepsRaw is List
        ? stepsRaw
            .map((s) => s is Map<String, dynamic>
                ? BrowserStep.fromJson(s)
                : const BrowserStep(action: BrowserStepAction.navigate))
            .toList()
        : <BrowserStep>[];
    return BrowserTask(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'unnamed',
      steps: steps,
      headless: json['headless'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'steps': [for (final s in steps) s.toJson()],
      'headless': headless,
    };
  }
}

/// 瀏覽器任務執行結果。
class BrowserTaskResult {
  final bool success;
  final List<Map<String, dynamic>> stepResults;
  final String? error;

  const BrowserTaskResult({
    required this.success,
    this.stepResults = const [],
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'stepResults': stepResults,
      if (error != null) 'error': error,
    };
  }
}
