// api_usage_tracker.dart
// [教練 Agent 2026-07-29] API 額度追蹤 — 按 provider 分開統計 + 溫馨提醒
//
// 每次 API 呼叫後呼叫 recordUsage()，累計今日/本週 token 數。
// 支援多 provider（openai, glm, kimi, minimax, gemini, claude, local）。
// UI 透過 usageStream 監聽更新。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 單次 API 使用記錄
class ApiUsageRecord {
  final DateTime timestamp;
  final int inputTokens;
  final int outputTokens;
  final String model;
  final String provider; // 'openai', 'glm', 'kimi', 'minimax', 'gemini', 'claude', 'local'
  /// [小葵 2026-09-21 收尾驗收] false=串流 usage 真值；true=chars÷4 估算
  final bool estimated;

  const ApiUsageRecord({
    required this.timestamp,
    required this.inputTokens,
    required this.outputTokens,
    required this.model,
    required this.provider,
    this.estimated = true,
  });

  int get totalTokens => inputTokens + outputTokens;
}

/// 單一 provider 的日統計
class ProviderUsage {
  final String provider;
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int requestCount;
  final bool isLocal;

  const ProviderUsage({
    required this.provider,
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.requestCount,
    required this.isLocal,
  });
}

/// API 額度追蹤 singleton
class ApiUsageTracker {
  static final ApiUsageTracker instance = ApiUsageTracker._();
  ApiUsageTracker._();

  final List<ApiUsageRecord> _records = [];

  int _dailyWarningThreshold = 100000;
  int _dailyLimitThreshold = 200000;

  // [教練 Agent 2026-07-29] SharedPreferences key — 持久化使用者自訂警告閾值
  static const _keyWarningThreshold = 'api_usage_warning_threshold';

  final StreamController<List<ProviderUsage>> _summaryController =
      StreamController<List<ProviderUsage>>.broadcast();
  Stream<List<ProviderUsage>> get usageStream => _summaryController.stream;

  List<ProviderUsage>? _lastSummary;
  List<ProviderUsage>? get lastSummary => _lastSummary;

  bool _warningShown = false;

  /// 已知 provider 顯示名稱
  static const _providerDisplayNames = {
    'openai': 'OpenAI',
    'glm': 'GLM (智譜)',
    'kimi': 'Kimi (月之暗面)',
    'minimax': 'MiniMax',
    'gemini': 'Gemini',
    'claude': 'Claude',
    'local': '本地模型',
  };

  static String providerDisplayName(String provider) {
    return _providerDisplayNames[provider] ?? provider;
  }

  /// 是否為本地 provider
  static bool isLocalProvider(String provider) {
    return provider == 'local';
  }

  void setThresholds({int? warning, int? limit}) {
    if (warning != null) _dailyWarningThreshold = warning;
    if (limit != null) _dailyLimitThreshold = limit;
  }

  // [教練 Agent 2026-07-29] 從 SharedPreferences 載入使用者自訂警告閾值
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_keyWarningThreshold);
      if (saved != null && saved > 0) {
        _dailyWarningThreshold = saved;
        debugPrint('[ApiUsageTracker] 載入自訂警告閾值: $saved');
      }
    } catch (e) {
      debugPrint('[ApiUsageTracker] 載入警告閾值失敗: $e');
    }
  }

  // [教練 Agent 2026-07-29] 讓使用者自訂警告閾值，並持久化到 SharedPreferences
  // isLimitLevel / isWarningLevel 僅用於 UI 提醒，不觸發 provider 切換或限流
  Future<void> setWarningThreshold(int tokens) async {
    _dailyWarningThreshold = tokens;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyWarningThreshold, tokens);
      debugPrint('[ApiUsageTracker] 已儲存警告閾值: $tokens');
    } catch (e) {
      debugPrint('[ApiUsageTracker] 儲存警告閾值失敗: $e');
    }
    _recomputeSummary();
  }

  /// 記錄一次 API 使用
  void recordUsage({
    required int inputTokens,
    required int outputTokens,
    required String model,
    required String provider,
    bool estimated = true,
  }) {
    final record = ApiUsageRecord(
      timestamp: DateTime.now(),
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      model: model,
      provider: provider,
      estimated: estimated,
    );
    _records.add(record);

    // 清理超過 7 天的記錄
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    _records.removeWhere((r) => r.timestamp.isBefore(cutoff));

    // [小葵 2026-09-21 收尾驗收] 持久化——jsonl 落地，重啟不洗牌
    // （fire-and-forget，失敗不擋主流程）
    _persistRecord(record, cutoff);

    _recomputeSummary();
  }

  // ── [小葵 2026-09-21 收尾驗收] 持久化 ──────────────────────
  // 檔案：~/Library/Application Support/bridge_app/api_usage_log.jsonl
  // 載入策略：App 啟動時呼叫 loadPersisted() 一次（見 main 初始化）。
  File? _logFile;
  bool _loaded = false;

  File _ensureLogFile() {
    if (_logFile != null) return _logFile!;
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/Library/Application Support/bridge_app');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _logFile = File('${dir.path}/api_usage_log.jsonl');
    return _logFile!;
  }

  void _persistRecord(ApiUsageRecord r, DateTime cutoff) {
    try {
      final f = _ensureLogFile();
      final line = jsonEncode({
        'ts': r.timestamp.toIso8601String(),
        'provider': r.provider,
        'model': r.model,
        'in': r.inputTokens,
        'out': r.outputTokens,
        'estimated': r.estimated,
      });
      f.writeAsString('$line\n', mode: FileMode.append);
      // 順手清老檔案（>7 天）——只在載入時做一次，這裡只 append
      // （避免每次寫入都重寫整檔）
      if (!_loaded) {
        _loaded = true; // 標記：本 session 已至少寫過一次
      }
    } catch (e) {
      debugPrint('[ApiUsageTracker] 持久化失敗（不擋主流程）: $e');
    }
  }

  /// App 啟動時載入歷史（7 天內）——冪等，重複呼叫安全
  Future<void> loadPersisted() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _ensureLogFile();
      if (!f.existsSync()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final lines = await f.readAsLines();
      var restored = 0;
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final d = jsonDecode(line) as Map<String, dynamic>;
          final ts = DateTime.tryParse(d['ts'] as String? ?? '');
          if (ts == null || ts.isBefore(cutoff)) continue;
          _records.add(ApiUsageRecord(
            timestamp: ts,
            inputTokens: (d['in'] as num?)?.toInt() ?? 0,
            outputTokens: (d['out'] as num?)?.toInt() ?? 0,
            model: d['model'] as String? ?? 'unknown',
            provider: d['provider'] as String? ?? 'unknown',
            estimated: d['estimated'] as bool? ?? true,
          ));
          restored++;
        } catch (_) {}
      }
      // 清掉檔案裡超過 7 天的舊行（重寫精簡檔）
      if (restored > 0 || lines.isNotEmpty) {
        final keep = _records.map((r) => jsonEncode({
              'ts': r.timestamp.toIso8601String(),
              'provider': r.provider,
              'model': r.model,
              'in': r.inputTokens,
              'out': r.outputTokens,
              'estimated': r.estimated,
            })).join('\n');
        await f.writeAsString(keep + (keep.isEmpty ? '' : '\n'));
      }
      if (restored > 0) {
        _recomputeSummary();
        debugPrint('[ApiUsageTracker] 載入 $restored 筆歷史記錄');
      }
    } catch (e) {
      debugPrint('[ApiUsageTracker] 載入歷史失敗: $e');
    }
  }

  /// [收尾驗收] 真值/估算比例——儀表板數據可信度指標
  double get todayRealValueShare {
    final now = DateTime.now();
    final today = _records
        .where((r) => r.timestamp.year == now.year &&
            r.timestamp.month == now.month &&
            r.timestamp.day == now.day)
        .toList();
    if (today.isEmpty) return 0;
    final real = today.where((r) => !r.estimated).length;
    return real / today.length;
  }

  /// 取得今日所有 provider 的統計
  List<ProviderUsage> getTodaySummary() {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final todayRecords = _records.where((r) =>
        r.timestamp.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
        r.timestamp.isBefore(dayEnd)).toList();

    // 按 provider 分組統計
    final providerMap = <String, List<ApiUsageRecord>>{};
    for (final r in todayRecords) {
      providerMap.putIfAbsent(r.provider, () => []).add(r);
    }

    final result = <ProviderUsage>[];
    for (final entry in providerMap.entries) {
      final records = entry.value;
      result.add(ProviderUsage(
        provider: entry.key,
        totalTokens: records.fold(0, (s, r) => s + r.totalTokens),
        inputTokens: records.fold(0, (s, r) => s + r.inputTokens),
        outputTokens: records.fold(0, (s, r) => s + r.outputTokens),
        requestCount: records.length,
        isLocal: isLocalProvider(entry.key),
      ));
    }

    // 按 totalTokens 降序排列
    result.sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    return result;
  }

  /// 今日總 token 數
  int get todayTotalTokens {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _records
        .where((r) =>
            r.timestamp.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
            r.timestamp.isBefore(dayEnd))
        .fold(0, (s, r) => s + r.totalTokens);
  }

  /// 取得本週統計
  List<ProviderUsage> getWeekSummary() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDay = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final weekRecords = _records.where((r) => r.timestamp.isAfter(weekStartDay)).toList();

    final providerMap = <String, List<ApiUsageRecord>>{};
    for (final r in weekRecords) {
      providerMap.putIfAbsent(r.provider, () => []).add(r);
    }

    final result = <ProviderUsage>[];
    for (final entry in providerMap.entries) {
      final records = entry.value;
      result.add(ProviderUsage(
        provider: entry.key,
        totalTokens: records.fold(0, (s, r) => s + r.totalTokens),
        inputTokens: records.fold(0, (s, r) => s + r.inputTokens),
        outputTokens: records.fold(0, (s, r) => s + r.outputTokens),
        requestCount: records.length,
        isLocal: isLocalProvider(entry.key),
      ));
    }
    result.sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    return result;
  }

  void _recomputeSummary() {
    final summary = getTodaySummary();
    _lastSummary = summary;
    _summaryController.add(summary);

    final total = summary.fold(0, (s, p) => s + p.totalTokens);
    if (!_warningShown && total >= _dailyWarningThreshold) {
      _warningShown = true;
      debugPrint('[ApiUsageTracker] 今日 token 用量達到警告閾值: $total');
    }
  }

  bool get isWarningLevel => todayTotalTokens >= _dailyWarningThreshold;
  bool get isLimitLevel => todayTotalTokens >= _dailyLimitThreshold;
  int get dailyWarningThreshold => _dailyWarningThreshold;

  void resetDailyWarning() {
    _warningShown = false;
  }

  void dispose() {
    _summaryController.close();
  }
}
