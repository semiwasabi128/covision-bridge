// voice_emotion_memory.dart — 情緒記憶累積
//
// Phase 4: 信任治理 — 情緒記憶
//
// 記住使用者的情緒模式，長期優化互動風格。
// 例如：使用者經常在早上急迫，Agent 可以主動加快節奏。
//       使用者討論程式碼時常困惑，Agent 可以主動提供更多上下文。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_emotion_analyzer.dart';

/// 情緒記憶記錄
class EmotionMemoryEntry {
  final DateTime timestamp;
  final VoiceEmotion emotion;
  final String? topic; // 當時在討論什麼（可選）
  final double? speechRate; // 語速

  const EmotionMemoryEntry({
    required this.timestamp,
    required this.emotion,
    this.topic,
    this.speechRate,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'emotion': emotion.name,
        'topic': topic,
        'speechRate': speechRate,
      };

  factory EmotionMemoryEntry.fromJson(Map<String, dynamic> json) =>
      EmotionMemoryEntry(
        timestamp: DateTime.parse(json['timestamp']),
        emotion: VoiceEmotion.values.firstWhere(
          (e) => e.name == json['emotion'],
          orElse: () => VoiceEmotion.calm,
        ),
        topic: json['topic'] as String?,
        speechRate: (json['speechRate'] as num?)?.toDouble(),
      );
}

/// 情緒模式分析結果
class EmotionPattern {
  /// 最常見的情緒
  final VoiceEmotion dominantEmotion;

  /// 各情緒的出現頻率（0.0 ~ 1.0）
  final Map<VoiceEmotion, double> frequency;

  /// 特定 topic 的情緒傾向
  final Map<String, VoiceEmotion> topicEmotions;

  /// 平均語速
  final double averageSpeechRate;

  /// 建議的回應策略
  final String suggestedStrategy;

  const EmotionPattern({
    required this.dominantEmotion,
    required this.frequency,
    required this.topicEmotions,
    required this.averageSpeechRate,
    required this.suggestedStrategy,
  });
}

/// 情緒記憶管理器
///
/// 累積使用者的情緒模式，長期優化 Agent 的互動風格。
///
/// 使用方式：
///   final memory = VoiceEmotionMemory();
///   await memory.init();
///   memory.record(emotion: Emotion.urgent, topic: '程式碼審查');
///   final pattern = memory.analyzePattern();
///   // pattern.suggestedStrategy → '使用者在此場景常急迫，先給短回答'
class VoiceEmotionMemory {
  static const String _storageKey = 'voice_emotion_memory';
  static const int _maxEntries = 500;

  final List<EmotionMemoryEntry> _entries = [];
  bool _initialized = false;

  /// 初始化 — 從 SharedPreferences 載入歷史
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _entries.addAll(
          list.map((e) => EmotionMemoryEntry.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('[EmotionMemory] 載入失敗: $e');
    }

    _initialized = true;
    debugPrint('[EmotionMemory] 載入 ${_entries.length} 筆情緒記錄');
  }

  /// 記錄一次情緒
  Future<void> record({
    required VoiceEmotion emotion,
    String? topic,
    double? speechRate,
  }) async {
    final entry = EmotionMemoryEntry(
      timestamp: DateTime.now(),
      emotion: emotion,
      topic: topic,
      speechRate: speechRate,
    );

    _entries.add(entry);

    // 超過上限就移除最舊的
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }

    // 持久化
    await _persist();
  }

  /// 分析情緒模式
  EmotionPattern analyzePattern() {
    if (_entries.isEmpty) {
      return const EmotionPattern(
        dominantEmotion: VoiceEmotion.calm,
        frequency: {},
        topicEmotions: {},
        averageSpeechRate: 1.0,
        suggestedStrategy: '尚無足夠資料，使用預設回應策略',
      );
    }

    // 統計各情緒頻率
    final counts = <VoiceEmotion, int>{};
    for (final entry in _entries) {
      counts[entry.emotion] = (counts[entry.emotion] ?? 0) + 1;
    }

    final total = _entries.length;
    final frequency = counts.map((k, v) => MapEntry(k, v / total));

    // 找出最常見的情緒
    final dominantEmotion = counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    ).key;

    // 按 topic 分析情緒傾向
    final topicGroups = <String, List<VoiceEmotion>>{};
    for (final entry in _entries) {
      if (entry.topic != null) {
        topicGroups.putIfAbsent(entry.topic!, () => []).add(entry.emotion);
      }
    }
    final topicEmotions = <String, VoiceEmotion>{};
    for (final entry in topicGroups.entries) {
      final topicCounts = <VoiceEmotion, int>{};
      for (final e in entry.value) {
        topicCounts[e] = (topicCounts[e] ?? 0) + 1;
      }
      topicEmotions[entry.key] = topicCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    // 平均語速
    final speechRates = _entries
        .where((e) => e.speechRate != null)
        .map((e) => e.speechRate!)
        .toList();
    final avgRate = speechRates.isEmpty
        ? 1.0
        : speechRates.reduce((a, b) => a + b) / speechRates.length;

    // 生成建議策略
    final strategy = _generateStrategy(dominantEmotion, topicEmotions, avgRate);

    return EmotionPattern(
      dominantEmotion: dominantEmotion,
      frequency: frequency,
      topicEmotions: topicEmotions,
      averageSpeechRate: avgRate,
      suggestedStrategy: strategy,
    );
  }

  /// 生成回應策略建議
  String _generateStrategy(
    VoiceEmotion dominant,
    Map<String, VoiceEmotion> topicEmotions,
    double avgRate,
  ) {
    final buffer = StringBuffer();

    switch (dominant) {
      case VoiceEmotion.urgent:
        buffer.write('使用者整體偏急迫，優先給短回答、快速行動');
        break;
      case VoiceEmotion.confused:
        buffer.write('使用者常困惑，主動提供更多上下文和引導');
        break;
      case VoiceEmotion.happy:
        buffer.write('使用者情緒正向，可以更自然輕鬆的互動');
        break;
      case VoiceEmotion.angry:
        buffer.write('使用者常不滿，優先道歉和快速修正，不辯解');
        break;
      case VoiceEmotion.calm:
        buffer.write('使用者情緒穩定，可以正常節奏詳細回應');
        break;
    }

    if (avgRate > 1.3) {
      buffer.write('。語速偏快，可能喜歡高效率互動');
    } else if (avgRate < 0.8) {
      buffer.write('。語速偏慢，可能需要更多思考時間');
    }

    // 特定 topic 的建議
    for (final entry in topicEmotions.entries) {
      if (entry.value == VoiceEmotion.urgent) {
        buffer.write('。討論「${entry.key}」時常急迫，要加快處理');
      } else if (entry.value == VoiceEmotion.confused) {
        buffer.write('。討論「${entry.key}」時常困惑，要多解釋');
      }
    }

    return buffer.toString();
  }

  /// 持久化到 SharedPreferences
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, json);
    } catch (e) {
      debugPrint('[EmotionMemory] 儲存失敗: $e');
    }
  }

  /// 清除所有記憶
  Future<void> clear() async {
    _entries.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// 取得最近的 N 筆記錄
  List<EmotionMemoryEntry> getRecent(int count) {
    if (_entries.length <= count) return List.unmodifiable(_entries);
    return List.unmodifiable(_entries.sublist(_entries.length - count));
  }

  /// 總記錄數
  int get count => _entries.length;
}
