import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'memory_store.dart';
import 'semantic_intent/semantic_intent_service.dart';
import 'semantic_intent/semantic_result.dart';

// 橋樑意識層（最小可行版）
// 本地輕量觀察引擎，不需要 AI API
// 負責：偵測模式、產生洞察、主動提醒

/// 觀察記錄
class Observation {
  final String id;
  final String type;    // 'pattern', 'emotion', 'incomplete', 'reminder'
  final String content;
  final DateTime timestamp;
  final bool isRead;

  Observation({
    required this.id,
    required this.type,
    required this.content,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
  };

  factory Observation.fromJson(Map<String, dynamic> json) => Observation(
    id: json['id'] ?? '',
    type: json['type'] ?? 'pattern',
    content: json['content'] ?? '',
    timestamp: DateTime.parse(json['timestamp']),
    isRead: json['isRead'] ?? false,
  );
}

class BridgeConsciousness {
  static const String _keyObservations = 'bridge_observations';
  static const String _keyEmotionLog = 'bridge_emotion_log';

  // ===== 1. 對話觀察 =====

  /// 每次對話後呼叫：掃描是否有值得記錄的模式
  /// [Phase 3] 新增 semanticService 參數——feature flag 開啟時用 LLM 做語意偵測。
  static Future<List<Observation>> observeConversation(
    String userMessage,
    String assistantReply, {
    SemanticIntentService? semanticService,
    List<({String role, String content})> history = const [],
  }) async {
    final observations = <Observation>[];
    final now = DateTime.now();

    // A. [Phase 3 #15] 偵測「未完成的意圖」——語意版
    if (semanticService != null) {
      try {
        final intentionResult = await semanticService.extractOpenIntention(
          message: userMessage,
          history: history,
        );
        if (intentionResult != null &&
            intentionResult.hasOpenIntention &&
            intentionResult.intention != null &&
            intentionResult.intention!.length > 2) {
          observations.add(Observation(
            id: 'inc_${now.millisecondsSinceEpoch}',
            type: 'incomplete',
            content: '用戶提到「之後要${intentionResult.intention}」，但尚未確認進度',
            timestamp: now,
          ));
        }
      } catch (_) {
        // LLM 失敗，fallback 到正則
        _detectOpenIntentionRegex(userMessage, observations, now);
      }
    } else {
      // 無語意服務 → 正則版
      _detectOpenIntentionRegex(userMessage, observations, now);
    }

    // B. [Phase 3 #16] 偵測情緒傾向——語意版
    if (semanticService != null) {
      try {
        final emotionResult = await semanticService.detectEmotion(
          message: userMessage,
          history: history,
        );
        if (emotionResult != null && emotionResult.emotion != 'neutral') {
          await _logEmotion(emotionResult.emotion, userMessage);
          final streak = await _getEmotionStreak(emotionResult.emotion);
          if (streak >= 3) {
            observations.add(Observation(
              id: 'emo_${now.millisecondsSinceEpoch}',
              type: 'emotion',
              content: '用戶連續 $streak 次對話顯示「${emotionResult.emotion}」情緒，可能需要關注',
              timestamp: now,
            ));
          }
        }
      } catch (_) {
        // LLM 失敗，fallback 到正則
        await _detectEmotionRegex(userMessage, observations, now);
      }
    } else {
      // 無語意服務 → 正則版
      await _detectEmotionRegex(userMessage, observations, now);
    }

    // C. 偵測重複提問（同樣的問題問第三次？）
    final recentQuestions = await _getRecentUserMessages(10);
    final similarCount = _countSimilarMessages(userMessage, recentQuestions);
    if (similarCount >= 2) {
      observations.add(Observation(
        id: 'rep_${now.millisecondsSinceEpoch}',
        type: 'pattern',
        content: '用戶似乎在重複探索類似主題（$similarCount 次），可能需要更深入的回答',
        timestamp: now,
      ));
    }

    // 保存觀察
    for (final obs in observations) {
      await _saveObservation(obs);
    }

    return observations;
  }

  // ===== 2. 主動提醒 =====

  /// 取得未讀的觀察（用於 UI 顯示「教練 Agent想跟你說...」）
  static Future<List<Observation>> getUnreadObservations() async {
    final all = await _getAllObservations();
    return all.where((o) => !o.isRead).toList();
  }

  /// 標記觀察為已讀
  static Future<void> markAsRead(String observationId) async {
    final all = await _getAllObservations();
    final updated = all.map((o) {
      if (o.id == observationId) {
        return Observation(
          id: o.id,
          type: o.type,
          content: o.content,
          timestamp: o.timestamp,
          isRead: true,
        );
      }
      return o;
    }).toList();
    await _saveAllObservations(updated);
  }

  /// 產生一條「教練 Agent的洞察」
  static Future<String?> generateInsight() async {
    final memories = await MemoryStore.getAll();
    if (memories.isEmpty) return null;

    // 簡易洞察：最近有沒有「目標」類記憶但沒有「進度」
    final goals = memories.where((m) =>
      m.contains('我要') || m.contains('我想') || m.contains('我計畫')
    ).toList();

    if (goals.isNotEmpty) {
      final randomGoal = goals[DateTime.now().millisecond % goals.length];
      return '你之前提到「$randomGoal」，最近有進展嗎？需要我幫你盤點一下嗎？';
    }

    return null;
  }

  // ===== 3. 情緒追蹤（內部） =====

  /// [Phase 3] 正則版未完成意圖偵測——LLM 不可用時的 fallback。
  static void _detectOpenIntentionRegex(
    String userMessage,
    List<Observation> observations,
    DateTime now,
  ) {
    final incompletePatterns = [
      RegExp(r'我(之後|改天|有空|下次)(要|想|會|打算)(.+)'),
      RegExp(r'(記得|別忘了)(之後|改天|下次)(.+)'),
      RegExp(r'等(我|有空|之後)(再|就)(.+)'),
    ];
    for (final pattern in incompletePatterns) {
      final match = pattern.firstMatch(userMessage);
      if (match != null) {
        final intent = match.group(3)?.trim() ?? '';
        if (intent.length > 2) {
          observations.add(Observation(
            id: 'inc_${now.millisecondsSinceEpoch}',
            type: 'incomplete',
            content: '用戶提到「之後要$intent」，但尚未確認進度',
            timestamp: now,
          ));
        }
      }
    }
  }

  /// [Phase 3] 正則版情緒偵測——LLM 不可用時的 fallback。
  static Future<void> _detectEmotionRegex(
    String userMessage,
    List<Observation> observations,
    DateTime now,
  ) async {
    final emotionMarkers = {
      '焦慮': ['煩', '壓力', '焦慮', '擔心', '害怕', '怎麼辦'],
      '興奮': ['開心', '興奮', '期待', '終於', '太好了'],
      '疲憊': ['累', '倦', '沒力', '撐不住', '想睡'],
      '困惑': ['不懂', '困惑', '迷茫', '不知道', '卡住'],
    };
    for (final entry in emotionMarkers.entries) {
      for (final marker in entry.value) {
        if (userMessage.contains(marker)) {
          await _logEmotion(entry.key, userMessage);
          final streak = await _getEmotionStreak(entry.key);
          if (streak >= 3) {
            observations.add(Observation(
              id: 'emo_${now.millisecondsSinceEpoch}',
              type: 'emotion',
              content: '用戶連續 $streak 次對話顯示「${entry.key}」情緒，可能需要關注',
              timestamp: now,
            ));
          }
          break;
        }
      }
    }
  }

  static Future<void> _logEmotion(String emotion, String context) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(_keyEmotionLog) ?? [];
    log.add(jsonEncode({
      'emotion': emotion,
      'context': context.substring(0, context.length > 50 ? 50 : context.length),
      'timestamp': DateTime.now().toIso8601String(),
    }));
    // 只保留最近 50 條
    if (log.length > 50) log.removeAt(0);
    await prefs.setStringList(_keyEmotionLog, log);
  }

  static Future<int> _getEmotionStreak(String emotion) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(_keyEmotionLog) ?? [];
    int streak = 0;
    for (final entry in log.reversed) {
      final data = jsonDecode(entry);
      if (data['emotion'] == emotion) {
        streak++;
      } else {
        break; // 連續中斷
      }
    }
    return streak;
  }

  static Future<List<String>> _getRecentUserMessages(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(_keyEmotionLog) ?? [];
    return log.reversed.take(count).map((e) {
      final data = jsonDecode(e);
      return data['context']?.toString() ?? '';
    }).toList();
  }

  // ===== 4. 觀察儲存（內部） =====

  static Future<void> _saveObservation(Observation obs) async {
    final all = await _getAllObservations();
    all.add(obs);
    // 只保留最近 100 條
    if (all.length > 100) all.removeAt(0);
    await _saveAllObservations(all);
  }

  static Future<List<Observation>> _getAllObservations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyObservations) ?? [];
    return raw.map((r) => Observation.fromJson(jsonDecode(r))).toList();
  }

  static Future<void> _saveAllObservations(List<Observation> observations) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = observations.map((o) => jsonEncode(o.toJson())).toList();
    await prefs.setStringList(_keyObservations, raw);
  }

  // ===== 5. 相似度計算（簡易） =====

  static int _countSimilarMessages(String target, List<String> candidates) {
    int count = 0;
    final targetWords = target.split('');
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      // 簡易：如果有一半以上字元相同，算相似
      int matches = 0;
      for (final char in targetWords) {
        if (candidate.contains(char)) matches++;
      }
      if (matches / targetWords.length > 0.5) count++;
    }
    return count;
  }
}
