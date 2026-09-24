// voice_audit_log.dart — Phase 4 信任治理：審計日誌
//
// 記錄所有語音操作的全生命週期，讓使用者可以回溯查看
// 「Agent 做了什麼」，建立信任基礎。
//
// 記錄內容：
//   - 使用者說了什麼（語音轉文字）
//   - Agent 偵測到的情緒
//   - Agent 做了什麼（五層回應的每一層）
//   - 工具調用記錄
//   - 結果
//
// 設計要點：
//   - 每筆記錄有時間戳
//   - 可以匯出為文字報告（給使用者看「Agent 做了什麼」）
//   - persistToDisk() / loadFromDisk() — 存取到檔案
//   - 不直接耦合 VoiceEngine，透過方法呼叫記錄

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// ─── 審計事件類型 ───

/// 審計事件的類型
///
/// 對應五層回應架構和操作生命週期的各個階段。
enum AuditEventType {
  /// 使用者語音輸入（語音轉文字結果）
  userSpeech,

  /// 情緒偵測結果
  emotionDetected,

  /// 第一層：即時虛字答腔
  layer1Backchannel,

  /// 第二層：情緒短回應
  layer2EmotionResponse,

  /// 第三層：現況回報
  layer3ProgressReport,

  /// 第四層：聰明反問
  layer4Clarification,

  /// 第五層：短結論
  layer5Conclusion,

  /// 工具調用
  toolCall,

  /// 工具調用結果
  toolResult,

  /// 操作完成
  actionCompleted,

  /// 操作失敗
  actionFailed,

  /// 使用者中斷
  userInterrupt,

  /// 權限確認請求
  permissionRequest,

  /// 權限確認結果
  permissionResult,

  /// 操作回滾
  undo,
}

// ─── 審計事件記錄 ───

/// 單筆審計事件
///
/// 記錄語音操作生命週期中的一個事件。
class AuditEvent {
  /// 事件類型
  final AuditEventType type;

  /// 事件時間戳
  final DateTime timestamp;

  /// 事件內容（主要訊息）
  final String message;

  /// 附加資料（鍵值對，用於存儲結構化資訊）
  ///
  /// 例如：工具名稱、參數、情緒分數等。
  final Map<String, dynamic> metadata;

  /// 建立一筆審計事件
  const AuditEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.metadata = const {},
  });

  @override
  String toString() {
    return 'AuditEvent($type, $timestamp, $message)';
  }

  /// 轉換為 Map（用於 JSON 序列化）
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'metadata': metadata,
    };
  }

  /// 從 Map 建立（用於 JSON 反序列化）
  factory AuditEvent.fromMap(Map<String, dynamic> map) {
    return AuditEvent(
      type: AuditEventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AuditEventType.actionCompleted,
      ),
      timestamp: DateTime.parse(map['timestamp'] as String),
      message: map['message'] as String? ?? '',
      metadata: Map<String, dynamic>.from(
        map['metadata'] as Map? ?? const {},
      ),
    );
  }
}

// ─── 對談記錄 ───

/// 一輪對談的完整審計記錄
///
/// 從使用者說話開始，到 Agent 回應完成為止，
/// 所有相關的審計事件集合。
class ConversationAuditRecord {
  /// 對談開始時間
  final DateTime startTime;

  /// 對談結束時間（null 表示進行中）
  final DateTime? endTime;

  /// 使用者說的話（語音轉文字）
  final String userInput;

  /// 偵測到的情緒（文字描述）
  final String? emotion;

  /// 此對談中的所有事件
  final List<AuditEvent> events;

  /// 建立一筆對談記錄
  const ConversationAuditRecord({
    required this.startTime,
    this.endTime,
    required this.userInput,
    this.emotion,
    required this.events,
  });

  /// 轉換為 Map
  Map<String, dynamic> toMap() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'userInput': userInput,
      'emotion': emotion,
      'events': events.map((e) => e.toMap()).toList(),
    };
  }

  /// 從 Map 建立
  factory ConversationAuditRecord.fromMap(Map<String, dynamic> map) {
    return ConversationAuditRecord(
      startTime: DateTime.parse(map['startTime'] as String),
      endTime: map['endTime'] != null
          ? DateTime.parse(map['endTime'] as String)
          : null,
      userInput: map['userInput'] as String? ?? '',
      emotion: map['emotion'] as String?,
      events: (map['events'] as List? ?? [])
          .map((e) => AuditEvent.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── VoiceAuditLog ───

/// Phase 4 審計日誌管理器
///
/// 記錄所有語音操作的全生命週期，可匯出為文字報告。
///
/// 使用方式：
///   final auditLog = VoiceAuditLog();
///
///   // 開始記錄一輪對談
///   auditLog.startConversation('幫我修這個檔案');
///
///   // 記錄情緒
///   auditLog.logEmotion('urgent');
///
///   // 記錄各層回應
///   auditLog.logLayer(1, '嗯');
///   auditLog.logLayer(2, '我看你很急，我馬上幫你看。');
///
///   // 記錄工具調用
///   auditLog.logToolCall('read_source_file', {'path': 'lib/main.dart'});
///   auditLog.logToolResult('read_source_file', '檔案內容...');
///
///   // 結束對談
///   auditLog.endConversation('修好了，dart analyze 沒問題。');
///
///   // 匯出報告
///   final report = auditLog.exportReport();
///
///   // 存取到磁碟
///   await auditLog.persistToDisk('/path/to/audit.json');
class VoiceAuditLog {
  VoiceAuditLog({this.maxRecords = 500});

  /// 最多保留的對談記錄數
  final int maxRecords;

  /// 所有對談記錄
  final List<ConversationAuditRecord> _records = [];

  /// 當前正在記錄的對談（null 表示沒有進行中的對談）
  ConversationAuditRecord? _currentConversation;

  /// 當前對談的事件列表（累積中）
  final List<AuditEvent> _currentEvents = [];

  /// 取得所有對談記錄（唯讀副本）
  List<ConversationAuditRecord> get records =>
      List.unmodifiable(_records);

  /// 目前是否有進行中的對談
  bool get hasActiveConversation => _currentConversation != null;

  /// 目前對談記錄數
  int get recordCount => _records.length;

  // ─── 對談生命週期 ───

  /// 開始記錄一輪對談
  ///
  /// [userInput] — 使用者說的話（語音轉文字結果）
  void startConversation(String userInput) {
    // 如果上一輪還沒結束，先結束它
    if (_currentConversation != null) {
      endConversation('（對談未正常結束）');
    }

    _currentConversation = ConversationAuditRecord(
      startTime: DateTime.now(),
      userInput: userInput,
      events: const [],
    );
    _currentEvents.clear();

    _logEvent(
      AuditEventType.userSpeech,
      '使用者說：「$userInput」',
      metadata: {'text': userInput},
    );

    debugPrint('[VoiceAuditLog] 開始記錄對談: "$userInput"');
  }

  /// 記錄情緒偵測結果
  void logEmotion(String emotion, {Map<String, dynamic>? details}) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.emotionDetected,
      '偵測到情緒：$emotion',
      metadata: {'emotion': emotion, ...?details},
    );
  }

  /// 記錄五層回應的某一層
  ///
  /// [layer] — 層數（1~5）
  /// [content] — 該層回應的內容
  void logLayer(int layer, String content) {
    if (_currentConversation == null) return;

    final type = switch (layer) {
      1 => AuditEventType.layer1Backchannel,
      2 => AuditEventType.layer2EmotionResponse,
      3 => AuditEventType.layer3ProgressReport,
      4 => AuditEventType.layer4Clarification,
      5 => AuditEventType.layer5Conclusion,
      _ => AuditEventType.actionCompleted,
    };

    final layerName = switch (layer) {
      1 => '第一層：虛字答腔',
      2 => '第二層：情緒短回應',
      3 => '第三層：現況回報',
      4 => '第四層：聰明反問',
      5 => '第五層：短結論',
      _ => '第$layer層',
    };

    _logEvent(
      type,
      '$layerName — $content',
      metadata: {'layer': layer, 'content': content},
    );
  }

  /// 記錄工具調用
  ///
  /// [toolName] — 工具名稱
  /// [params] — 調用參數
  void logToolCall(String toolName, Map<String, dynamic> params) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.toolCall,
      '調用工具：$toolName',
      metadata: {'tool': toolName, 'params': params},
    );
  }

  /// 記錄工具調用結果
  ///
  /// [toolName] — 工具名稱
  /// [result] — 結果文字
  /// [success] — 是否成功
  void logToolResult(
    String toolName,
    String result, {
    bool success = true,
  }) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.toolResult,
      success
          ? '工具 $toolName 完成：$result'
          : '工具 $toolName 失敗：$result',
      metadata: {
        'tool': toolName,
        'result': result,
        'success': success,
      },
    );
  }

  /// 記錄操作完成
  void logActionCompleted(String summary) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.actionCompleted,
      '操作完成：$summary',
      metadata: {'summary': summary},
    );
  }

  /// 記錄操作失敗
  void logActionFailed(String error) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.actionFailed,
      '操作失敗：$error',
      metadata: {'error': error},
    );
  }

  /// 記錄使用者中斷
  void logUserInterrupt(String context) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.userInterrupt,
      '使用者中斷（$context）',
      metadata: {'context': context},
    );
  }

  /// 記錄權限確認請求
  void logPermissionRequest(String action, String level) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.permissionRequest,
      '請求權限確認：$action（等級：$level）',
      metadata: {'action': action, 'level': level},
    );
  }

  /// 記錄權限確認結果
  void logPermissionResult(String action, bool granted) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.permissionResult,
      granted ? '權限已確認：$action' : '權限被拒絕：$action',
      metadata: {'action': action, 'granted': granted},
    );
  }

  /// 記錄操作回滾
  void logUndo(String action, bool success) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.undo,
      success ? '回滾成功：$action' : '回滾失敗：$action',
      metadata: {'action': action, 'success': success},
    );
  }

  /// 結束當前對談記錄
  ///
  /// [finalReply] — Agent 的最終回覆
  void endConversation(String finalReply) {
    if (_currentConversation == null) return;

    _logEvent(
      AuditEventType.layer5Conclusion,
      '對談結束 — 最終回覆：$finalReply',
      metadata: {'finalReply': finalReply},
    );

    // 建立完整的對談記錄
    final record = ConversationAuditRecord(
      startTime: _currentConversation!.startTime,
      endTime: DateTime.now(),
      userInput: _currentConversation!.userInput,
      emotion: _currentConversation!.emotion,
      events: List.from(_currentEvents),
    );

    _records.add(record);

    // 超過上限時淘汰最舊的
    while (_records.length > maxRecords) {
      _records.removeAt(0);
    }

    _currentConversation = null;
    _currentEvents.clear();

    debugPrint('[VoiceAuditLog] 結束對談記錄（共 ${_records.length} 筆）');
  }

  // ─── 內部方法 ───

  void _logEvent(
    AuditEventType type,
    String message, {
    Map<String, dynamic>? metadata,
  }) {
    final event = AuditEvent(
      type: type,
      timestamp: DateTime.now(),
      message: message,
      metadata: metadata ?? {},
    );
    _currentEvents.add(event);
    debugPrint('[VoiceAuditLog] $message');
  }

  // ─── 報告匯出 ───

  /// 匯出為文字報告
  ///
  /// 產生人類可讀的報告，讓使用者查看「Agent 做了什麼」。
  ///
  /// [conversationIndex] — 指定對談記錄的索引（null = 全部）
  String exportReport({int? conversationIndex}) {
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('  語音操作審計報告');
    buffer.writeln('  產生時間：${DateTime.now()}');
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln();

    final recordsToExport = conversationIndex != null
        ? [_records[conversationIndex]]
        : _records;

    if (recordsToExport.isEmpty) {
      buffer.writeln('（沒有審計記錄）');
      return buffer.toString();
    }

    for (var i = 0; i < recordsToExport.length; i++) {
      final record = recordsToExport[i];
      buffer.writeln('─── 對談 #${i + 1} ───────────────────────');
      buffer.writeln('時間：${record.startTime}');
      if (record.endTime != null) {
        final duration = record.endTime!.difference(record.startTime);
        buffer.writeln('歷時：${duration.inSeconds} 秒');
      }
      buffer.writeln('使用者說：「${record.userInput}」');
      if (record.emotion != null) {
        buffer.writeln('情緒：${record.emotion}');
      }
      buffer.writeln();

      buffer.writeln('事件記錄：');
      for (final event in record.events) {
        final timeStr =
            '${event.timestamp.hour.toString().padLeft(2, '0')}:'
            '${event.timestamp.minute.toString().padLeft(2, '0')}:'
            '${event.timestamp.second.toString().padLeft(2, '0')}';
        buffer.writeln('  [$timeStr] ${event.message}');
      }
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('  報告結束（共 ${recordsToExport.length} 筆對談）');
    buffer.writeln('═══════════════════════════════════════════');

    return buffer.toString();
  }

  /// 匯出最近 N 筆對談的報告
  String exportRecentReport({int count = 10}) {
    if (count >= _records.length) {
      return exportReport();
    }
    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('  語音操作審計報告（最近 $count 筆）');
    buffer.writeln('  產生時間：${DateTime.now()}');
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln();

    final startIndex = _records.length - count;
    for (var i = startIndex; i < _records.length; i++) {
      final record = _records[i];
      buffer.writeln('─── 對談 #${i + 1} ───────────────────────');
      buffer.writeln('時間：${record.startTime}');
      if (record.endTime != null) {
        final duration = record.endTime!.difference(record.startTime);
        buffer.writeln('歷時：${duration.inSeconds} 秒');
      }
      buffer.writeln('使用者說：「${record.userInput}」');
      if (record.emotion != null) {
        buffer.writeln('情緒：${record.emotion}');
      }
      buffer.writeln();

      buffer.writeln('事件記錄：');
      for (final event in record.events) {
        final timeStr =
            '${event.timestamp.hour.toString().padLeft(2, '0')}:'
            '${event.timestamp.minute.toString().padLeft(2, '0')}:'
            '${event.timestamp.second.toString().padLeft(2, '0')}';
        buffer.writeln('  [$timeStr] ${event.message}');
      }
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('  報告結束');
    buffer.writeln('═══════════════════════════════════════════');

    return buffer.toString();
  }

  // ─── 持久化 ───

  /// 存取到磁碟
  ///
  /// 將所有審計記錄以 JSON 格式寫入指定檔案。
  ///
  /// [filePath] — 目標檔案路徑
  Future<void> persistToDisk(String filePath) async {
    try {
      final file = File(filePath);
      final jsonData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'recordCount': _records.length,
        'records': _records.map((r) => r.toMap()).toList(),
      };
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(jsonData));
      debugPrint('[VoiceAuditLog] 已儲存 ${_records.length} 筆記錄到 $filePath');
    } catch (e) {
      debugPrint('[VoiceAuditLog] 儲存失敗: $e');
    }
  }

  /// 從磁碟載入
  ///
  /// 從指定檔案讀取審計記錄，合併到現有記錄中。
  ///
  /// [filePath] — 來源檔案路徑
  /// [replace] — true 表示取代現有記錄；false 表示合併
  Future<void> loadFromDisk(String filePath, {bool replace = true}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[VoiceAuditLog] 檔案不存在: $filePath');
        return;
      }

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      final recordsJson = jsonData['records'] as List? ?? [];

      final loadedRecords = recordsJson
          .map((r) => ConversationAuditRecord.fromMap(
                r as Map<String, dynamic>,
              ))
          .toList();

      if (replace) {
        _records.clear();
      }
      _records.addAll(loadedRecords);

      // 超過上限時淘汰最舊的
      while (_records.length > maxRecords) {
        _records.removeAt(0);
      }

      debugPrint('[VoiceAuditLog] 從 $filePath 載入 ${loadedRecords.length} '
          '筆記錄（目前共 ${_records.length} 筆）');
    } catch (e) {
      debugPrint('[VoiceAuditLog] 載入失敗: $e');
    }
  }

  // ─── 清除 ───

  /// 清除所有審計記錄
  void clear() {
    _records.clear();
    _currentEvents.clear();
    _currentConversation = null;
    debugPrint('[VoiceAuditLog] 已清除所有審計記錄');
  }
}
