// voice_action_history.dart — Phase 4 信任治理：操作歷史 + 回滾
//
// 記錄 Agent 的每次操作（檔案修改、終端命令、畫布操作），
// 並提供回滾能力，讓使用者可以「撤銷」Agent 做的事。
//
// 設計要點：
//   - 每筆記錄包含操作類型、目標、舊值/新值、時間戳
//   - undoLast() 回滾最後一筆操作
//   - undoTo(index) 回滾到指定位置（撤銷 index 之後的所有操作）
//   - 最多保留 100 筆，超過自動淘汰最舊的
//   - 回滾透過回調函數執行，不直接耦合具體工具

import 'dart:async';

import 'package:flutter/foundation.dart';

// ─── 操作類型列舉 ───

/// Agent 操作的類型
///
/// 用於分類歷史記錄，也影響回滾策略。
enum VoiceActionType {
  /// 檔案修改（新增、編輯、刪除檔案內容）
  fileModification,

  /// 終端命令執行
  terminalCommand,

  /// 畫布操作（放置節點、連接節點、刪除節點）
  canvasOperation,

  /// 系統設定變更
  systemSetting,

  /// 其他操作
  other,
}

// ─── 操作歷史記錄 ───

/// 單筆操作歷史記錄
///
/// 記錄 Agent 做了什麼操作、影響了什麼、以及如何回滾。
class VoiceActionRecord {
  /// 操作類型
  final VoiceActionType type;

  /// 操作目標的描述（例：檔案路徑、終端命令、畫布節點 ID）
  final String target;

  /// 操作前的舊值（用於回滾）
  ///
  /// 檔案修改時為修改前的檔案內容；畫布操作時為 null（刪除節點即可回滾）。
  final String? oldValue;

  /// 操作後的新值
  ///
  /// 檔案修改時為修改後的檔案內容；終端命令時為指令輸出。
  final String? newValue;

  /// 操作時間戳
  final DateTime timestamp;

  /// 人類可讀的操作摘要（例：「修改了 voice_engine.dart」「執行了 dart analyze」）
  final String summary;

  /// 回滾回調 — 執行此函數以撤銷操作
  ///
  /// 由操作發起者提供，透過 [VoiceActionHistory.registerUndoCallback] 設定。
  /// 回傳 true 表示回滾成功。
  final Future<bool> Function()? undoCallback;

  const VoiceActionRecord({
    required this.type,
    required this.target,
    this.oldValue,
    this.newValue,
    required this.timestamp,
    required this.summary,
    this.undoCallback,
  });

  @override
  String toString() {
    return 'VoiceActionRecord('
        'type: $type, '
        'target: $target, '
        'summary: $summary, '
        'timestamp: $timestamp)';
  }

  /// 轉換為 Map（用於序列化）
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'target': target,
      'oldValue': oldValue,
      'newValue': newValue,
      'timestamp': timestamp.toIso8601String(),
      'summary': summary,
    };
  }
}

// ─── VoiceActionHistory ───

/// Phase 4 操作歷史管理器
///
/// 記錄 Agent 的每次操作，並提供回滾能力。
///
/// 使用方式：
///   final history = VoiceActionHistory();
///
///   // Agent 執行操作前，先記錄
///   final record = history.record(
///     type: VoiceActionType.fileModification,
///     target: 'lib/services/voice/voice_engine.dart',
///     oldValue: originalContent,
///     newValue: modifiedContent,
///     summary: '修改了 voice_engine.dart',
///     undoCallback: () async {
///       // 回滾邏輯：把舊內容寫回去
///       return true;
///     },
///   );
///
///   // 回滾最後一筆
///   final success = await history.undoLast();
///
///   // 回滾到第 3 筆（撤銷第 3 筆之後的所有操作）
///   await history.undoTo(3);
class VoiceActionHistory {
  VoiceActionHistory({this.maxRecords = 100});

  /// 最多保留的記錄筆數
  final int maxRecords;

  /// 操作歷史列表（按時間順序，最舊在前）
  final List<VoiceActionRecord> _records = [];

  /// 取得操作歷史列表（唯讀副本）
  List<VoiceActionRecord> getHistory() => List.unmodifiable(_records);

  /// 目前歷史記錄筆數
  int get length => _records.length;

  /// 是否有可回滾的操作
  bool get canUndo => _records.isNotEmpty;

  /// 最後一筆記錄（null 表示沒有記錄）
  VoiceActionRecord? get last =>
      _records.isNotEmpty ? _records.last : null;

  // ─── 記錄操作 ───

  /// 記錄一筆操作
  ///
  /// [type] — 操作類型
  /// [target] — 操作目標（檔案路徑、終端命令、畫布節點 ID 等）
  /// [oldValue] — 操作前的舊值（用於回滾）
  /// [newValue] — 操作後的新值
  /// [summary] — 人類可讀的操作摘要
  /// [undoCallback] — 回滾回調，執行此函數以撤銷操作
  ///
  /// 回傳建立的 [VoiceActionRecord]。
  VoiceActionRecord record({
    required VoiceActionType type,
    required String target,
    String? oldValue,
    String? newValue,
    required String summary,
    Future<bool> Function()? undoCallback,
  }) {
    final record = VoiceActionRecord(
      type: type,
      target: target,
      oldValue: oldValue,
      newValue: newValue,
      timestamp: DateTime.now(),
      summary: summary,
      undoCallback: undoCallback,
    );

    _records.add(record);

    // 超過上限時淘汰最舊的記錄
    while (_records.length > maxRecords) {
      final removed = _records.removeAt(0);
      debugPrint('[VoiceActionHistory] 淘汰舊記錄: ${removed.summary}');
    }

    debugPrint('[VoiceActionHistory] 記錄操作: ${record.summary} '
        '（共 ${_records.length} 筆）');

    return record;
  }

  // ─── 回滾操作 ───

  /// 回滾最後一筆操作
  ///
  /// 執行最後一筆記錄的 undoCallback。
  /// 回傳 true 表示回滾成功；false 表示沒有可回滾的操作或回滾失敗。
  Future<bool> undoLast() async {
    if (_records.isEmpty) {
      debugPrint('[VoiceActionHistory] undoLast: 沒有可回滾的操作');
      return false;
    }

    final record = _records.last;
    final success = await _undoRecord(record);

    if (success) {
      _records.removeLast();
      debugPrint('[VoiceActionHistory] undoLast 成功: ${record.summary}'
          '（剩餘 ${_records.length} 筆）');
    } else {
      debugPrint('[VoiceActionHistory] undoLast 失敗: ${record.summary}');
    }

    return success;
  }

  /// 回滾到指定位置
  ///
  /// 撤銷從 [index] 之後的所有操作（不含 index 本身）。
  /// 回滾順序為從最後一筆往前逐一回滾。
  ///
  /// [index] — 目標位置（0-based），回滾後歷史保留 0 ~ index 的記錄
  ///
  /// 回傳 true 表示全部回滾成功；false 表示至少有一筆回滾失敗。
  /// 即使部分失敗，也會嘗試回滾所有後續操作。
  Future<bool> undoTo(int index) async {
    if (index < 0 || index >= _records.length) {
      debugPrint('[VoiceActionHistory] undoTo($index): 索引超出範圍 '
          '（目前 ${_records.length} 筆）');
      return false;
    }

    var allSuccess = true;

    // 從最後一筆往前回滾，直到 index
    while (_records.length > index + 1) {
      final record = _records.last;
      final success = await _undoRecord(record);

      if (success) {
        _records.removeLast();
        debugPrint('[VoiceActionHistory] undoTo 回滾成功: ${record.summary}');
      } else {
        // 回滾失敗 — 移除記錄但標記失敗
        // （記錄已經被「嘗試回滾」，即使失敗也從歷史中移除，避免重複嘗試）
        _records.removeLast();
        debugPrint('[VoiceActionHistory] undoTo 回滾失敗: ${record.summary}');
        allSuccess = false;
      }
    }

    debugPrint('[VoiceActionHistory] undoTo($index) 完成，'
        '剩餘 ${_records.length} 筆，成功: $allSuccess');
    return allSuccess;
  }

  /// 執行單筆記錄的回滾
  Future<bool> _undoRecord(VoiceActionRecord record) async {
    final callback = record.undoCallback;
    if (callback == null) {
      debugPrint('[VoiceActionHistory] 回滾失敗（無 undoCallback）: '
          '${record.summary}');
      return false;
    }

    try {
      return await callback();
    } catch (e) {
      debugPrint('[VoiceActionHistory] 回滾例外: ${record.summary} — $e');
      return false;
    }
  }

  // ─── 清除歷史 ───

  /// 清除所有歷史記錄
  ///
  /// 注意：此操作不會執行回滾，只是清除記錄。
  /// 如果需要撤銷所有操作，請先呼叫 [undoTo](0) 再呼叫 [clear]。
  void clear() {
    final count = _records.length;
    _records.clear();
    debugPrint('[VoiceActionHistory] 已清除 $count 筆歷史記錄');
  }

  // ─── 查詢 ───

  /// 依操作類型篩選歷史記錄
  List<VoiceActionRecord> getByType(VoiceActionType type) {
    return _records.where((r) => r.type == type).toList();
  }

  /// 取得最後 N 筆記錄
  List<VoiceActionRecord> getLastN(int n) {
    if (n <= 0) return [];
    if (n >= _records.length) return List.from(_records);
    return _records.sublist(_records.length - n);
  }

  /// 依關鍵字搜尋歷史記錄（搜尋 target 和 summary）
  List<VoiceActionRecord> search(String keyword) {
    final lowerKeyword = keyword.toLowerCase();
    return _records.where((r) {
      return r.target.toLowerCase().contains(lowerKeyword) ||
          r.summary.toLowerCase().contains(lowerKeyword);
    }).toList();
  }

  /// 產生歷史摘要文字（給使用者看）
  ///
  /// 列出最近的操作，每筆一行。
  String generateSummary({int? maxLines}) {
    if (_records.isEmpty) {
      return '目前沒有操作記錄。';
    }

    final lines = <String>[];
    final recordsToShow =
        maxLines != null && maxLines < _records.length
            ? _records.sublist(_records.length - maxLines)
            : _records;

    for (var i = 0; i < recordsToShow.length; i++) {
      final r = recordsToShow[i];
      final timeStr =
          '${r.timestamp.hour.toString().padLeft(2, '0')}:'
          '${r.timestamp.minute.toString().padLeft(2, '0')}:'
          '${r.timestamp.second.toString().padLeft(2, '0')}';
      lines.add('${i + 1}. [$timeStr] ${r.summary}');
    }

    return lines.join('\n');
  }
}
