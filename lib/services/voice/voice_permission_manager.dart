// voice_permission_manager.dart — Phase 4 信任治理：權限分級
//
// 對 Agent 的操作進行權限分級管控，確保危險操作需要使用者確認。
//
// 操作分級：
//   safe — 讀檔、截圖、分析（不需要確認）
//   moderate — 修改檔案、畫布操作（語音確認「要我做嗎？」）
//   dangerous — 終端命令、刪除、系統設定（必須明確說「好」或「確認」）
//
// 設計要點：
//   - checkPermission(action) → PermissionLevel
//   - requestConfirmation(action) → 等待使用者語音確認
//   - 全局權限等級設定（全部 safe / 全部 moderate / 自訂）
//   - 權限設定持久化（SharedPreferences）

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── 權限等級列舉 ───

/// 操作權限等級
///
/// 數值越大，需要的確認越嚴格。
enum PermissionLevel {
  /// 安全 — 不需要確認
  ///
  /// 適用：讀檔、截圖、分析等唯讀操作
  safe,

  /// 中等 — 需要語音確認「要我做嗎？」
  ///
  /// 適用：修改檔案、畫布操作等可逆變更
  moderate,

  /// 危險 — 必須明確說「好」「確認」「yes」
  ///
  /// 適用：終端命令、刪除、系統設定等不可逆或高風險操作
  dangerous,
}

// ─── 全局權限模式 ───

/// 全局權限模式
///
/// 使用者可以設定全局權限等級，簡化權限管理。
enum GlobalPermissionMode {
  /// 自訂 — 每個操作依預設規則分級
  custom,

  /// 全部安全 — 所有操作都不需要確認（最寬鬆）
  allSafe,

  /// 全部中等 — 所有操作都需要語音確認
  allModerate,

  /// 全部危險 — 所有操作都需要明確確認（最嚴格）
  allDangerous,
}

// ─── 操作描述 ───

/// 描述一個待檢查的操作
///
/// 用於 [VoicePermissionManager.checkPermission] 的輸入。
class PermissionAction {
  /// 操作名稱（例：read_file, patch_file, run_terminal, canvas_place）
  final String name;

  /// 操作目標（例：檔案路徑、終端命令）
  final String? target;

  /// 操作摘要（人類可讀）
  final String summary;

  /// 建立操作描述
  const PermissionAction({
    required this.name,
    this.target,
    required this.summary,
  });

  @override
  String toString() =>
      'PermissionAction(name: $name, summary: $summary)';
}

// ─── 確認結果 ───

/// 使用者確認的結果
enum ConfirmationResult {
  /// 使用者確認同意
  confirmed,

  /// 使用者拒絕
  denied,

  /// 等待超時（使用者沒有回應）
  timeout,
}

// ─── VoicePermissionManager ───

/// Phase 4 權限分級管理器
///
/// 管理 Agent 操作的權限分級，確保危險操作需要使用者確認。
///
/// 使用方式：
///   final permissionManager = VoicePermissionManager();
///   await permissionManager.initialize();
///
///   // 檢查操作權限
///   final action = PermissionAction(
///     name: 'patch_file',
///     target: 'lib/main.dart',
///     summary: '修改 main.dart',
///   );
///   final level = permissionManager.checkPermission(action);
///
///   if (level == PermissionLevel.safe) {
///     // 直接執行
///   } else {
///     // 請求確認
///     final result = await permissionManager.requestConfirmation(
///       action,
///       speakCallback: (text) => ttsHandler.speak(text),
///       listenCallback: () => sttService.listen(),
///     );
///     if (result == ConfirmationResult.confirmed) {
///       // 執行
///     }
///   }
///
///   // 設定全局權限模式
///   await permissionManager.setGlobalMode(GlobalPermissionMode.allModerate);
class VoicePermissionManager {
  VoicePermissionManager();

  /// SharedPreferences 的 key 前綴
  static const _prefKeyGlobalMode = 'voice_permission_global_mode';

  /// SharedPreferences 的 key 前綴（自訂規則）
  static const _prefKeyCustomRules = 'voice_permission_custom_rules';

  /// SharedPreferences 實例
  SharedPreferences? _prefs;

  /// 全局權限模式
  GlobalPermissionMode _globalMode = GlobalPermissionMode.custom;

  /// 自訂操作權限規則（操作名稱 → 權限等級）
  ///
  /// 覆蓋預設的分類規則。
  final Map<String, PermissionLevel> _customRules = {};

  /// 預設的操作分類規則
  ///
  /// 依操作名稱關鍵字匹配，決定預設權限等級。
  static const Map<String, PermissionLevel> _defaultRules = {
    // ── safe：唯讀操作 ──
    'read_file': PermissionLevel.safe,
    'read_source_file': PermissionLevel.safe,
    'screen_capture': PermissionLevel.safe,
    'screenshot': PermissionLevel.safe,
    'vision_analyze': PermissionLevel.safe,
    'local_vision_analyze': PermissionLevel.safe,
    'code_analyze': PermissionLevel.safe,
    'dart_analyze': PermissionLevel.safe,
    'search': PermissionLevel.safe,
    'list': PermissionLevel.safe,
    'get': PermissionLevel.safe,
    'view': PermissionLevel.safe,
    'inspect': PermissionLevel.safe,

    // ── moderate：可逆變更 ──
    'patch_file': PermissionLevel.moderate,
    'patch_source_file': PermissionLevel.moderate,
    'write_file': PermissionLevel.moderate,
    'edit': PermissionLevel.moderate,
    'modify': PermissionLevel.moderate,
    'canvas_place': PermissionLevel.moderate,
    'canvas_connect': PermissionLevel.moderate,
    'canvas_move': PermissionLevel.moderate,
    'canvas_update': PermissionLevel.moderate,
    'create': PermissionLevel.moderate,
    'add': PermissionLevel.moderate,
    'update': PermissionLevel.moderate,

    // ── dangerous：不可逆或高風險 ──
    'run_terminal': PermissionLevel.dangerous,
    'execute_command': PermissionLevel.dangerous,
    'shell': PermissionLevel.dangerous,
    'delete': PermissionLevel.dangerous,
    'remove': PermissionLevel.dangerous,
    'rm': PermissionLevel.dangerous,
    'system_setting': PermissionLevel.dangerous,
    'system_config': PermissionLevel.dangerous,
    'install': PermissionLevel.dangerous,
    'uninstall': PermissionLevel.dangerous,
    'deploy': PermissionLevel.dangerous,
    'format': PermissionLevel.dangerous,
    'reset': PermissionLevel.dangerous,
    'purge': PermissionLevel.dangerous,
  };

  /// 確認等待超時時間（秒）
  static const int confirmationTimeoutSeconds = 15;

  /// 確認完成的 completer（等待使用者語音確認時使用）
  Completer<ConfirmationResult>? _confirmationCompleter;

  // ─── 初始化 ───

  /// 初始化 — 載入持久化的權限設定
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    // 載入全局模式
    final modeIndex = _prefs?.getInt(_prefKeyGlobalMode);
    if (modeIndex != null && modeIndex >= 0 && modeIndex < 4) {
      _globalMode = GlobalPermissionMode.values[modeIndex];
    }

    // 載入自訂規則
    final rulesJson = _prefs?.getString(_prefKeyCustomRules);
    if (rulesJson != null && rulesJson.isNotEmpty) {
      try {
        final parts = rulesJson.split(';');
        for (final part in parts) {
          if (part.isEmpty) continue;
          final kv = part.split('=');
          if (kv.length == 2) {
            final levelIndex = int.tryParse(kv[1]);
            if (levelIndex != null &&
                levelIndex >= 0 &&
                levelIndex < 3) {
              _customRules[kv[0]] = PermissionLevel.values[levelIndex];
            }
          }
        }
      } catch (e) {
        debugPrint('[VoicePermissionManager] 載入自訂規則失敗: $e');
      }
    }

    debugPrint('[VoicePermissionManager] 初始化完成 — '
        '全局模式: ${_globalMode.name}, '
        '自訂規則: ${_customRules.length} 條');
  }

  // ─── 權限檢查 ───

  /// 檢查操作的權限等級
  ///
  /// 依序檢查：全局模式 → 自訂規則 → 預設規則 → 關鍵字匹配 → 預設 dangerous
  PermissionLevel checkPermission(PermissionAction action) {
    // 1. 全局模式優先
    switch (_globalMode) {
      case GlobalPermissionMode.allSafe:
        return PermissionLevel.safe;
      case GlobalPermissionMode.allModerate:
        return PermissionLevel.moderate;
      case GlobalPermissionMode.allDangerous:
        return PermissionLevel.dangerous;
      case GlobalPermissionMode.custom:
        // 繼續往下檢查
        break;
    }

    // 2. 自訂規則
    final customLevel = _customRules[action.name];
    if (customLevel != null) {
      return customLevel;
    }

    // 3. 預設規則（精確匹配）
    final defaultLevel = _defaultRules[action.name];
    if (defaultLevel != null) {
      return defaultLevel;
    }

    // 4. 關鍵字匹配（操作名稱包含預設規則的關鍵字）
    final nameLower = action.name.toLowerCase();
    for (final entry in _defaultRules.entries) {
      if (nameLower.contains(entry.key)) {
        return entry.value;
      }
    }

    // 5. 未知操作 — 預設為 dangerous（安全優先）
    debugPrint('[VoicePermissionManager] 未知操作 "${action.name}"，'
        '預設為 dangerous');
    return PermissionLevel.dangerous;
  }

  /// 快速檢查操作是否需要確認
  ///
  /// 回傳 true 表示需要確認（moderate 或 dangerous）；
  /// false 表示不需要確認（safe）。
  bool needsConfirmation(PermissionAction action) {
    return checkPermission(action) != PermissionLevel.safe;
  }

  // ─── 確認請求 ───

  /// 請求使用者確認
  ///
  /// 透過語音向使用者確認操作。
  ///
  /// [action] — 要確認的操作
  /// [speakCallback] — 語音朗讀回調（用於向使用者說出確認問題）
  /// [confirmationStream] — 使用者語音確認的文字流
  ///
  /// 回傳確認結果。如果使用者在 [confirmationTimeoutSeconds] 秒內
  /// 沒有回應，回傳 [ConfirmationResult.timeout]。
  Future<ConfirmationResult> requestConfirmation({
    required PermissionAction action,
    required void Function(String text) speakCallback,
    required Stream<String> confirmationStream,
  }) async {
    final level = checkPermission(action);

    if (level == PermissionLevel.safe) {
      // safe 不需要確認
      return ConfirmationResult.confirmed;
    }

    // 產生確認問題
    final question = _buildConfirmationQuestion(action, level);
    debugPrint('[VoicePermissionManager] 請求確認: $question');
    speakCallback(question);

    // 等待使用者語音確認
    _confirmationCompleter = Completer<ConfirmationResult>();

    // 設定超時
    final timer = Timer(
      Duration(seconds: confirmationTimeoutSeconds),
      () {
        if (_confirmationCompleter != null &&
            !_confirmationCompleter!.isCompleted) {
          _confirmationCompleter!.complete(ConfirmationResult.timeout);
          debugPrint('[VoicePermissionManager] 確認超時');
        }
      },
    );

    // 監聽確認文字流
    final subscription = confirmationStream.listen(
      (text) {
        final result = _parseConfirmation(text, level);
        if (result != null) {
          if (_confirmationCompleter != null &&
              !_confirmationCompleter!.isCompleted) {
            _confirmationCompleter!.complete(result);
          }
        }
        // 如果不是確認/拒絕的關鍵字，繼續等待
      },
      onError: (e) {
        debugPrint('[VoicePermissionManager] 確認串流錯誤: $e');
      },
    );

    try {
      final result = await _confirmationCompleter!.future;
      return result;
    } finally {
      timer.cancel();
      subscription.cancel();
      _confirmationCompleter = null;
    }
  }

  /// 手動提交確認結果
  ///
  /// 如果呼叫方自行處理了語音辨識，可以透過此方法提交結果。
  void submitConfirmation(String spokenText) {
    if (_confirmationCompleter == null ||
        _confirmationCompleter!.isCompleted) {
      return;
    }

    final level = PermissionLevel.moderate; // 預設用 moderate 解析
    final result = _parseConfirmation(spokenText, level);
    if (result != null) {
      _confirmationCompleter!.complete(result);
    }
  }

  /// 手動提交確認（帶權限等級）
  void submitConfirmationWithLevel(
    String spokenText,
    PermissionLevel level,
  ) {
    if (_confirmationCompleter == null ||
        _confirmationCompleter!.isCompleted) {
      return;
    }

    final result = _parseConfirmation(spokenText, level);
    if (result != null) {
      _confirmationCompleter!.complete(result);
    }
  }

  /// 解析使用者的語音確認
  ///
  /// 回傳確認結果；如果無法辨認，回傳 null（繼續等待）。
  ConfirmationResult? _parseConfirmation(
    String text,
    PermissionLevel level,
  ) {
    final lower = text.toLowerCase().trim();

    // 確認關鍵字
    final confirmKeywords = [
      '好', '確認', '可以', '沒問題', '對', '沒錯', '行', 'ok', 'yes',
      'sure', 'yeah', 'yep', 'confirm', 'go ahead', 'do it',
    ];

    // 拒絕關鍵字
    final denyKeywords = [
      '不要', '不行', '不好', '否', '不對', '取消', 'cancel', 'no',
      'nope', 'stop', 'don\'t', '別',
    ];

    // 檢查確認
    for (final keyword in confirmKeywords) {
      if (lower.contains(keyword)) {
        // dangerous 等級需要更明確的確認
        if (level == PermissionLevel.dangerous) {
          // dangerous 需要說「好」「確認」「yes」等明確關鍵字
          // 「對」「沒錯」等模糊確認不算
          final strictKeywords = [
            '好', '確認', '可以', '沒問題', 'ok', 'yes', 'sure',
            'confirm', 'do it',
          ];
          for (final strict in strictKeywords) {
            if (lower.contains(strict)) {
              debugPrint('[VoicePermissionManager] 確認通過: "$text"');
              return ConfirmationResult.confirmed;
            }
          }
          // 模糊確認不算，繼續等待
          return null;
        }
        debugPrint('[VoicePermissionManager] 確認通過: "$text"');
        return ConfirmationResult.confirmed;
      }
    }

    // 檢查拒絕
    for (final keyword in denyKeywords) {
      if (lower.contains(keyword)) {
        debugPrint('[VoicePermissionManager] 使用者拒絕: "$text"');
        return ConfirmationResult.denied;
      }
    }

    // 無法辨認
    return null;
  }

  /// 產生確認問題
  String _buildConfirmationQuestion(
    PermissionAction action,
    PermissionLevel level,
  ) {
    switch (level) {
      case PermissionLevel.moderate:
        return '我接下來要${action.summary}，要我做嗎？';
      case PermissionLevel.dangerous:
        return '注意，我接下來要${action.summary}，'
            '這是比較危險的操作。'
            '請說「確認」或「好」來執行，或者說「不要」來取消。';
      case PermissionLevel.safe:
        return ''; // safe 不需要確認
    }
  }

  // ─── 全局權限模式 ───

  /// 目前的全局權限模式
  GlobalPermissionMode get globalMode => _globalMode;

  /// 設定全局權限模式
  ///
  /// 會持久化到 SharedPreferences。
  Future<void> setGlobalMode(GlobalPermissionMode mode) async {
    _globalMode = mode;
    await _prefs?.setInt(_prefKeyGlobalMode, mode.index);
    debugPrint('[VoicePermissionManager] 全局模式設為: ${mode.name}');
  }

  // ─── 自訂規則 ───

  /// 取得自訂規則（唯讀副本）
  Map<String, PermissionLevel> get customRules =>
      Map.unmodifiable(_customRules);

  /// 設定單一操作的自訂權限等級
  ///
  /// 會持久化到 SharedPreferences。
  Future<void> setCustomRule(
    String actionName,
    PermissionLevel level,
  ) async {
    _customRules[actionName] = level;
    await _persistCustomRules();
    debugPrint('[VoicePermissionManager] 自訂規則: '
        '$actionName → ${level.name}');
  }

  /// 移除單一操作的自訂權限等級
  ///
  /// 移除後，該操作回到預設規則。
  Future<void> removeCustomRule(String actionName) async {
    _customRules.remove(actionName);
    await _persistCustomRules();
    debugPrint('[VoicePermissionManager] 移除自訂規則: $actionName');
  }

  /// 清除所有自訂規則
  Future<void> clearCustomRules() async {
    _customRules.clear();
    await _prefs?.remove(_prefKeyCustomRules);
    debugPrint('[VoicePermissionManager] 已清除所有自訂規則');
  }

  /// 持久化自訂規則
  Future<void> _persistCustomRules() async {
    // 用 "actionName=levelIndex;actionName=levelIndex" 格式存儲
    final parts = _customRules.entries
        .map((e) => '${e.key}=${e.value.index}')
        .toList();
    final jsonString = parts.join(';');
    await _prefs?.setString(_prefKeyCustomRules, jsonString);
  }

  // ─── 預設規則查詢 ───

  /// 取得預設規則（唯讀副本）
  Map<String, PermissionLevel> get defaultRules =>
      Map.unmodifiable(_defaultRules);

  /// 取得所有已知的操作名稱（預設規則 + 自訂規則）
  Set<String> get knownActions =>
      {..._defaultRules.keys, ..._customRules.keys};

  // ─── 便利方法 ───

  /// 檢查操作是否為安全等級
  bool isSafe(PermissionAction action) =>
      checkPermission(action) == PermissionLevel.safe;

  /// 檢查操作是否為危險等級
  bool isDangerous(PermissionAction action) =>
      checkPermission(action) == PermissionLevel.dangerous;

  /// 產生目前權限設定的摘要文字
  String generateSettingsSummary() {
    final buffer = StringBuffer();
    buffer.writeln('權限設定摘要：');
    buffer.writeln('  全局模式：${_globalMode.name}');
    buffer.writeln('  自訂規則：${_customRules.length} 條');

    if (_customRules.isNotEmpty) {
      buffer.writeln('  自訂規則清單：');
      for (final entry in _customRules.entries) {
        buffer.writeln('    ${entry.key} → ${entry.value.name}');
      }
    }

    return buffer.toString();
  }
}
