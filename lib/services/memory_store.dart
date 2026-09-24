import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brain_container/brain_room.dart';
import '../models/brain_container/memory.dart';
import '../models/brain_container/memory_source.dart';
import '../models/second_brain_trace.dart';
import '../models/transurfing_brain.dart';
import 'brain_container/brain_database.dart';
import 'brain_container/extraction/memory_guard.dart';

enum TransurfingInsightFeedback { accurate, inaccurate, muted }

class TransurfingInsightRecord {
  final String insight;
  final TransurfingInsightFeedback? feedback;
  final bool inMemory;
  final int trustScore;
  /// [教練 Agent 2026-07-05] 大腦房間分類，供 UI 分組折疊使用。
  /// 從洞察文字中推斷；無法推斷時為 null（顯示在「未分類」組）。
  final BrainRoom? room;

  const TransurfingInsightRecord({
    required this.insight,
    required this.feedback,
    required this.inMemory,
    this.trustScore = 50,
    this.room,
  });
}

/// 長期記憶系統
/// 讓教練 Agent跨對話也能記得用戶的重要資訊
class MemoryStore {
  static const String _keyMemories = 'bridge_memories';
  static const String _keyInsightAccurate = 'bridge_insight_accurate';
  static const String _keyInsightInaccurate = 'bridge_insight_inaccurate';
  static const String _keyInsightMuted = 'bridge_insight_muted';
  static const String _keyInsightTrustScores = 'bridge_insight_trust_scores';
  static const String _keySecondBrainAssociationFeedbacks =
      'bridge_second_brain_association_feedbacks_v1';
  static const int _defaultTrustScore = 50;
  static const int _minimumRecallTrustScore = 20;

  /// 取得所有記憶
  static Future<List<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyMemories) ?? [];
  }

  /// 新增記憶
  static Future<void> add(String memory) async {
    if (memory.trim().isEmpty) return;
    final trimmed = memory.trim();

    // Hermes 風格安全掃描 — 防止 prompt injection 寫入記憶
    final guard = MemoryGuard.scan(trimmed);
    if (!guard.isSafe) {
      debugPrint('[MemoryGuard] 阻擋寫入: ${guard.reason}');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final memories = await getAll();
    // 避免重複
    if (!memories.contains(trimmed)) {
      memories.add(trimmed);
      await prefs.setStringList(_keyMemories, memories);
    }
    if (_isTransurfingInsight(trimmed)) {
      await _ensureInsightTrustScore(trimmed);
    }
  }

  /// 刪除記憶
  static Future<void> remove(String memory) async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await getAll();
    memories.remove(memory);
    await prefs.setStringList(_keyMemories, memories);
  }

  /// 批次操作 — 學習 Hermes 的 atomic operations 模式。
  ///
  /// 一次呼叫執行多個 add/replace/remove 操作，確保原子性。
  /// 適用於：更新記憶（先 remove 舊的再 add 新的）、批次清理等。
  ///
  /// 使用方式：
  /// ```dart
  /// await MemoryStore.batch([
  ///   MemoryOp.remove('我住在台北'),
  ///   MemoryOp.add('使用者已搬到新竹'),
  /// ]);
  /// ```
  static Future<BatchResult> batch(List<MemoryOp> operations) async {
    final prefs = await SharedPreferences.getInstance();
    var memories = await getAll();
    final result = BatchResult();

    for (final op in operations) {
      final trimmed = op.content.trim();

      switch (op.action) {
        case MemoryAction.add:
          // 安全掃描
          final guard = MemoryGuard.scan(trimmed);
          if (!guard.isSafe) {
            result.blocked.add(trimmed);
            debugPrint('[MemoryGuard] 批次阻擋: ${guard.reason}');
            break;
          }
          if (!memories.contains(trimmed)) {
            memories.add(trimmed);
            result.added.add(trimmed);
          }
          break;

        case MemoryAction.replace:
          if (op.oldText == null) {
            debugPrint('[MemoryStore.batch] replace 缺少 oldText');
            break;
          }
          final oldTrimmed = op.oldText!.trim();
          // 找到包含 oldText 的記憶並替換
          final idx = memories.indexWhere((m) => m.contains(oldTrimmed));
          if (idx >= 0) {
            // 安全掃描新內容
            final guard = MemoryGuard.scan(trimmed);
            if (!guard.isSafe) {
              result.blocked.add(trimmed);
              debugPrint('[MemoryGuard] 批次阻擋: ${guard.reason}');
              break;
            }
            memories[idx] = trimmed;
            result.replaced.add(trimmed);
          } else {
            debugPrint('[MemoryStore.batch] 找不到要替換的: $oldTrimmed');
          }
          break;

        case MemoryAction.remove:
          final removed = memories.where((m) => m.contains(trimmed)).toList();
          memories.removeWhere((m) => m.contains(trimmed));
          result.removed.addAll(removed);
          break;
      }
    }

    await prefs.setStringList(_keyMemories, memories);
    return result;
  }

  /// 清空所有記憶
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMemories);
    await prefs.remove(_keyInsightAccurate);
    await prefs.remove(_keyInsightInaccurate);
    await prefs.remove(_keyInsightMuted);
    await prefs.remove(_keyInsightTrustScores);
    await prefs.remove(_keySecondBrainAssociationFeedbacks);
  }

  /// 取得格式化的記憶文字（用於 system prompt）
  static Future<String> getFormattedMemories() async {
    final memories = await getAll();
    final suppressedInsights = await _getSuppressedTransurfingInsights();
    final trustScores = await _getInsightTrustScores();
    final visibleMemories = memories
        .where((memory) => !suppressedInsights.contains(memory))
        .where(
          (memory) =>
              !_isTransurfingInsight(memory) ||
              _trustScoreFor(memory, trustScores) >= _minimumRecallTrustScore,
        )
        .toList();
    if (visibleMemories.isEmpty) return '';
    return '\n\n【關於用戶的長期記憶】\n${visibleMemories.map((m) => '• $m').join('\n')}';
  }

  /// 自動從對話中提取記憶（保守版）
  /// 只提取明確的宣告句，避免從問句或曖昧語境抓錯
  ///
  /// [教練 Agent 2026-07-03] 此方法現在是「正則快車道」。
  /// 語意提取請見 SmartMemoryExtractor（LLM 二次提取）。
  /// 保留此方法作為快車道：即時、零延遲、不需 API 呼叫。
  static Future<List<String>> extractFromMessage(String content) async {
    return regexExtract(content);
  }

  /// 正則快車道 — 純模式比對，不呼叫 LLM。
  ///
  /// 處理明確指令（「記住：」「我叫」等）和身份/偏好宣告。
  /// 無前綴詞的隱含記憶由 [SmartMemoryExtractor] 處理。
  static Future<List<String>> regexExtract(String content) async {
    final extracted = <String>[];
    final lines = content.split(RegExp(r'[。！？\n，,；;]'));

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳過問句（半形/全形問號結尾）
      if (trimmed.endsWith('?') || trimmed.endsWith('？')) continue;

      // 跳過過短的句子（P1 修復：5→3，允許「我叫建新」等短身份宣告通過）
      if (trimmed.length < 3) continue;

      // ===== 模式 A：明確指令（必須在句首） =====
      // 支援多條記憶：「記住：第一個是 A，第二個是 B，第三個是 C」
      final explicitPatterns = [
        RegExp(r'^記住[：:]\s*(.+)$'),
        RegExp(r'^記得[：:]\s*(.+)$'),
        RegExp(r'^幫我記[：:]\s*(.+)$'),
        RegExp(r'^記一下[：:]\s*(.+)$'),
        RegExp(r'^幫我記住\s*(.+)$'),
        RegExp(r'^請記住\s*(.+)$'),
      ];
      bool matched = false;
      for (final pattern in explicitPatterns) {
        final match = pattern.firstMatch(trimmed);
        if (match != null) {
          final captured = match.group(1)?.trim() ?? '';
          if (captured.length >= 3) {
            // 檢查是否包含多條（用「第 X 個」分隔）
            if (RegExp(r'第[一二三四五六七八九十]').hasMatch(captured)) {
              // 分割多條記憶
              final parts = captured.split(RegExp(r'[，,、]\s*'));
              for (final part in parts) {
                final cleanPart = part.trim();
                if (cleanPart.isEmpty) continue;
                // 移除序號前綴
                final item = cleanPart.replaceAll(
                  RegExp(r'^第[一二三四五六七八九十]個[是：:\s]*'),
                  '',
                );
                if (item.length >= 3) {
                  extracted.add(item);
                  debugPrint('🧠 記憶提取[多條]: "$item"');
                }
              }
            } else {
              extracted.add(captured);
              debugPrint('🧠 記憶提取[指令]: "$captured" ← "$trimmed"');
            }
          }
          matched = true;
          break;
        }
      }
      if (matched) continue;

      // ===== 模式 B：身份與家人宣告（必須在句首，允許前面有語氣詞） =====
      // [教練 Agent 2026-07-03] 擴充身份提取範圍 — 不只認「嗨/你好」開頭
      // 也要認單獨的「我叫XXX」「我是XXX」
      final identityPatterns = [
        RegExp(r'^(?:嗨|你好|哈囉)[,，\s]*我是(.{2,}.+)$'),
        RegExp(r'^(?:嗨|你好|哈囉)[,，\s]*我叫(.{2,}.+)$'),
        RegExp(r'^我叫(.{2,15}?)$'),
        RegExp(r'^我是(.{2,15}?)$'),
        RegExp(r'^我的名字(?:叫|是)(.+)$'),
        RegExp(r'^我生日(?:是)?(.+)$'),
        RegExp(r'^我(?:今年)?(\d{1,3})歲$'),
        RegExp(r'^我女兒(?:叫|是)?(.+)$'),
        RegExp(r'^我兒子(?:叫|是)?(.+)$'),
        RegExp(r'^我(?:伴侶|家人|孩子)(?:叫|是)?(.+)$'),
      ];
      for (final pattern in identityPatterns) {
        final match = pattern.firstMatch(trimmed);
        if (match != null) {
          final captured = match.group(0) ?? trimmed; // 取整句
          // P1 修復：5→3，允許「我叫建新」(4字) 等短身份宣告通過
          // 正則本身已有 .{2,15} 限制，這裡只是防噪音
          if (captured.length >= 3) {
            extracted.add(captured);
            debugPrint('🧠 記憶提取[身份]: "$captured" ← "$trimmed"');
          }
          matched = true;
          break;
        }
      }
      if (matched) continue;

      // ===== 模式 C：偏好與計畫宣告（必須在句首） =====
      // 排除 Skill 引導語，避免誤提取
      final preferencePatterns = [
        RegExp(r'^我喜歡(.{3,}.+)$'),
        RegExp(r'^我討厭(.{3,}.+)$'),
        RegExp(r'^我要(.{3,}.+)$'),
        // 排除「我想釐清/我想問/我想知道」等探索性語句
        RegExp(r'^我想(?!釐清|問|知道|了解|確認|檢查|驗證|看看)(.{3,}.+)$'),
        RegExp(r'^我計畫(.{3,}.+)$'),
        RegExp(r'^我希望(.{3,}.+)$'),
        RegExp(r'^我夢想(.{3,}.+)$'),
        RegExp(r'^我的目標是(.+)$'),
        // [以利沙 P2 修復十輪 2026-06-27] 補充明確意向句前綴
        // 「我想用…」「我要用…」「我需要…」「我計劃…」「我打算…」「我決定…」
        RegExp(r'^我想用(.{2,}.+)$'),
        RegExp(r'^我要用(.{2,}.+)$'),
        RegExp(r'^我需要(.{2,}.+)$'),
        RegExp(r'^我計劃(.{2,}.+)$'),
        RegExp(r'^我打算(.{2,}.+)$'),
        RegExp(r'^我決定(.{2,}.+)$'),
      ];
      for (final pattern in preferencePatterns) {
        final match = pattern.firstMatch(trimmed);
        if (match != null) {
          final captured = match.group(0) ?? trimmed;
          if (captured.length >= 5) {
            extracted.add(captured);
            debugPrint('🧠 記憶提取[偏好]: "$captured" ← "$trimmed"');
          }
          break;
        }
      }

      // ===== 模式 D：職業/產業/生活情境宣告 =====
      // [以利沙 P0 修復十一輪 2026-06-27] 補充情境描述句提取
      // P3 修復（2026-07-03）：新增無主語模式，口語常省略「我」
      final contextPatterns = [
        // 原有模式（帶「我」）
        RegExp(r'我(?:是|在)(.{2,20}?(?:工作|上班|任職|服務))'),
        RegExp(r'我(?:在|做)(.{2,15}?(?:產業|行業|公司|業界))'),
        RegExp(r'工作(?:很忙|壓力|加班|很累)'),
        RegExp(r'我最近(?:壓力|工作|身體|家裡)(.{2,20})'),
        RegExp(r'我平常(?:喜歡|習慣|都會|會)(.{2,20})'),
        // P3 修復：省略主語的口語表達
        RegExp(r'最近搬(?:到|去)(.{2,20})'),
        RegExp(r'最近換了(.{2,20})'),
        RegExp(r'最近(?:開始|在|正在)(?:學|研究|讀|做)(.{2,20})'),
        RegExp(r'剛(?:搬|換|到)(?:到|去|進)?(.{2,20})'),
      ];
      for (final pattern in contextPatterns) {
        final match = pattern.firstMatch(trimmed);
        if (match != null) {
          final contextExtracted = match.groupCount > 0
              ? match.group(1)?.trim()
              : null;
          final content = (contextExtracted != null && contextExtracted.length > 2)
              ? trimmed
              : (trimmed.length > 4 ? trimmed : null);
          if (content != null) {
            extracted.add(content);
            debugPrint('🧠 記憶提取[情境]: $content');
          }
          break;
        }
      }
    }

    // 保存提取到的記憶
    for (final memory in extracted) {
      await add(memory);
    }

    if (extracted.isEmpty) {
      debugPrint('🧠 記憶提取: 無匹配 ← "$content"');
    }

    return extracted;
  }

  static List<String> extractTransurfingInsights(BrainReflection reflection) {
    final insights = <String>[];

    if (reflection.attentionState == AttentionState.captured) {
      insights.add('Transurfing洞察：使用者注意力容易被外部平台或新 AI 服務捕獲，需要先轉成自己的輸出。');
    } else if (reflection.attentionState == AttentionState.scattered) {
      insights.add('Transurfing洞察：使用者注意力出現分散訊號，需要收束到單一下一步。');
    }

    if (reflection.importanceLevel == ImportanceLevel.elevated ||
        reflection.importanceLevel == ImportanceLevel.excessive) {
      insights.add('Transurfing洞察：使用者在此類議題上重要性偏高，需要先建立安全網再推進。');
    }

    if (reflection.doorCandidates.any(
      (door) => door.kind == DoorKind.ownDoor,
    )) {
      insights.add('Transurfing洞察：此類議題出現自己的門訊號，與使用者需求、喜好或創作方向有共振。');
    }

    if (reflection.flowState == FlowState.againstFlow) {
      insights.add('Transurfing洞察：此類議題出現逆流訊號，需要檢查是否過度控制、焦慮或走進外部目標。');
    }

    if (reflection.recommendedMove == RecommendedMove.convertToOutput) {
      insights.add('Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。');
    }

    return insights;
  }

  static Future<List<String>> rememberTransurfingInsights(
    BrainReflection reflection,
  ) async {
    final insights = extractTransurfingInsights(reflection);
    for (final insight in insights) {
      await add(insight);
    }
    return insights;
  }

  static Future<List<String>> recallTransurfingInsights(
    BrainReflection reflection, {
    int limit = 5,
  }) async {
    final memories = await getAll();
    if (memories.isEmpty || limit <= 0) return [];

    final matchingInsights = extractTransurfingInsights(reflection);
    final suppressedInsights = await _getSuppressedTransurfingInsights();
    final trustScores = await _getInsightTrustScores();
    final recalled = matchingInsights
        .where(
          (insight) =>
              memories.contains(insight) &&
              !suppressedInsights.contains(insight) &&
              _trustScoreFor(insight, trustScores) >= _minimumRecallTrustScore,
        )
        .toSet()
        .toList();

    recalled.sort(
      (a, b) => _trustScoreFor(
        b,
        trustScores,
      ).compareTo(_trustScoreFor(a, trustScores)),
    );
    return recalled.take(limit).toList();
  }

  static Future<void> markTransurfingInsightFeedback(
    String insight,
    TransurfingInsightFeedback feedback,
  ) async {
    final trimmed = insight.trim();
    if (trimmed.isEmpty) return;

    switch (feedback) {
      case TransurfingInsightFeedback.accurate:
        await add(trimmed);
        await _adjustInsightTrustScore(trimmed, 15);
        await _addUnique(_keyInsightAccurate, trimmed);
        await _removeFromKey(_keyInsightInaccurate, trimmed);
        await _removeFromKey(_keyInsightMuted, trimmed);
        break;
      case TransurfingInsightFeedback.inaccurate:
        await _adjustInsightTrustScore(trimmed, -30);
        await _addUnique(_keyInsightInaccurate, trimmed);
        await _removeFromKey(_keyInsightAccurate, trimmed);
        await _removeFromKey(_keyInsightMuted, trimmed);
        await remove(trimmed);
        break;
      case TransurfingInsightFeedback.muted:
        await _addUnique(_keyInsightMuted, trimmed);
        await _removeFromKey(_keyInsightAccurate, trimmed);
        await _removeFromKey(_keyInsightInaccurate, trimmed);
        break;
    }
  }

  static Future<TransurfingInsightFeedback?> getTransurfingInsightFeedback(
    String insight,
  ) async {
    final trimmed = insight.trim();
    if (trimmed.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getStringList(_keyInsightAccurate) ?? []).contains(trimmed)) {
      return TransurfingInsightFeedback.accurate;
    }
    if ((prefs.getStringList(_keyInsightInaccurate) ?? []).contains(trimmed)) {
      return TransurfingInsightFeedback.inaccurate;
    }
    if ((prefs.getStringList(_keyInsightMuted) ?? []).contains(trimmed)) {
      return TransurfingInsightFeedback.muted;
    }
    return null;
  }

  static Future<Map<String, TransurfingInsightFeedback>>
  getTransurfingInsightFeedbacks(List<String> insights) async {
    final feedbacks = <String, TransurfingInsightFeedback>{};
    for (final insight in insights) {
      final feedback = await getTransurfingInsightFeedback(insight);
      if (feedback != null) {
        feedbacks[insight] = feedback;
      }
    }
    return feedbacks;
  }

  static Future<List<TransurfingInsightRecord>>
  getTransurfingInsightRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final memories = await getAll();
    final insightSet = <String>{
      ...memories.where(_isTransurfingInsight),
      ...(prefs.getStringList(_keyInsightAccurate) ?? const []),
      ...(prefs.getStringList(_keyInsightInaccurate) ?? const []),
      ...(prefs.getStringList(_keyInsightMuted) ?? const []),
    };

    final records = <TransurfingInsightRecord>[];
    for (final insight in insightSet) {
      records.add(
        TransurfingInsightRecord(
          insight: insight,
          feedback: await getTransurfingInsightFeedback(insight),
          inMemory: memories.contains(insight),
          trustScore: await getTransurfingInsightTrustScore(insight),
          // [教練 Agent 2026-07-05] 從洞察文字推斷大腦房間分類
          room: _inferBrainRoom(insight),
        ),
      );
    }

    records.sort((a, b) {
      final statusOrder = _feedbackSortOrder(
        a.feedback,
      ).compareTo(_feedbackSortOrder(b.feedback));
      if (statusOrder != 0) return statusOrder;
      final trustOrder = b.trustScore.compareTo(a.trustScore);
      if (trustOrder != 0) return trustOrder;
      return a.insight.compareTo(b.insight);
    });
    return records;
  }

  static Future<void> markSecondBrainAssociationFeedback(
    String association,
    SecondBrainAssociationFeedback feedback,
  ) async {
    final trimmed = association.trim();
    if (trimmed.isEmpty) return;

    final feedbacks = await _getSecondBrainAssociationFeedbacks();
    feedbacks[trimmed] = feedback;
    await _setSecondBrainAssociationFeedbacks(feedbacks);
  }

  static Future<SecondBrainAssociationFeedback?>
  getSecondBrainAssociationFeedback(String association) async {
    final trimmed = association.trim();
    if (trimmed.isEmpty) return null;
    return (await _getSecondBrainAssociationFeedbacks())[trimmed];
  }

  static Future<Map<String, SecondBrainAssociationFeedback>>
  getSecondBrainAssociationFeedbacks(List<String> associations) async {
    final saved = await _getSecondBrainAssociationFeedbacks();
    final feedbacks = <String, SecondBrainAssociationFeedback>{};
    for (final association in associations) {
      final trimmed = association.trim();
      if (trimmed.isEmpty) continue;
      final feedback = saved[trimmed];
      if (feedback != null) {
        feedbacks[trimmed] = feedback;
      }
    }
    return feedbacks;
  }

  static Future<Map<String, SecondBrainAssociationFeedback>>
  getAllSecondBrainAssociationFeedbacks() async {
    return _getSecondBrainAssociationFeedbacks();
  }

  static Future<void> removeTransurfingInsight(String insight) async {
    final trimmed = insight.trim();
    if (trimmed.isEmpty) return;

    await remove(trimmed);
    await _removeFromKey(_keyInsightAccurate, trimmed);
    await _removeFromKey(_keyInsightInaccurate, trimmed);
    await _removeFromKey(_keyInsightMuted, trimmed);
    await _removeInsightTrustScore(trimmed);
  }

  static Future<int> getTransurfingInsightTrustScore(String insight) async {
    final scores = await _getInsightTrustScores();
    return _trustScoreFor(insight, scores);
  }

  static Future<Map<String, SecondBrainAssociationFeedback>>
  _getSecondBrainAssociationFeedbacks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySecondBrainAssociationFeedbacks);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final feedbacks = <String, SecondBrainAssociationFeedback>{};
      for (final entry in decoded.entries) {
        final feedback = _secondBrainAssociationFeedbackFromName(
          entry.value.toString(),
        );
        if (entry.key.trim().isNotEmpty && feedback != null) {
          feedbacks[entry.key] = feedback;
        }
      }
      return feedbacks;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _setSecondBrainAssociationFeedbacks(
    Map<String, SecondBrainAssociationFeedback> feedbacks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = feedbacks.map(
      (association, feedback) => MapEntry(association, feedback.name),
    );
    await prefs.setString(
      _keySecondBrainAssociationFeedbacks,
      jsonEncode(encoded),
    );
  }

  static SecondBrainAssociationFeedback?
  _secondBrainAssociationFeedbackFromName(String name) {
    for (final feedback in SecondBrainAssociationFeedback.values) {
      if (feedback.name == name) return feedback;
    }
    return null;
  }

  static bool _isTransurfingInsight(String memory) {
    return memory.trim().startsWith('Transurfing洞察：');
  }

  /// [教練 Agent 2026-07-05] 從洞察文字推斷大腦房間分類。
  ///
  /// 洞察文字通常以 "Transurfing洞察：" 開頭，後面可能包含房間關鍵字。
  /// 如果無法推斷，回傳 null（UI 會顯示在「未分類」組）。
  static BrainRoom? _inferBrainRoom(String insight) {
    final lower = insight.toLowerCase();

    // 擺錘警報：焦慮、壓力、比較、急迫
    if (lower.contains('焦慮') ||
        lower.contains('壓力') ||
        lower.contains('比較') ||
        lower.contains('急迫') ||
        lower.contains('恐懼') ||
        lower.contains('擺錘') ||
        lower.contains('匱乏')) {
      return BrainRoom.pendulums;
    }

    // 門的紀錄：機會、專案、目標、計畫
    if (lower.contains('機會') ||
        lower.contains('專案') ||
        lower.contains('目標') ||
        lower.contains('計畫') ||
        lower.contains('專案門') ||
        lower.contains('行動')) {
      return BrainRoom.doors;
    }

    // 心腦對話：理性、感受、價值觀、衝突
    if (lower.contains('理性') ||
        lower.contains('感受') ||
        lower.contains('價值') ||
        lower.contains('衝突') ||
        lower.contains('心腦') ||
        lower.contains('分裂')) {
      return BrainRoom.heartMind;
    }

    // 靈魂頻率：發光、成就、共振、熱情
    if (lower.contains('發光') ||
        lower.contains('成就') ||
        lower.contains('共振') ||
        lower.contains('熱情') ||
        lower.contains('意義') ||
        lower.contains('渴望')) {
      return BrainRoom.fraile;
    }

    // 跨島連結：人際、連結、社群、合作
    if (lower.contains('人際') ||
        lower.contains('連結') ||
        lower.contains('社群') ||
        lower.contains('合作') ||
        lower.contains('關係')) {
      return BrainRoom.bridges;
    }

    // 水流軌跡：日常、能量、流動、生活（預設分類）
    if (lower.contains('日常') ||
        lower.contains('能量') ||
        lower.contains('流動') ||
        lower.contains('生活') ||
        lower.contains('作息')) {
      return BrainRoom.stream;
    }

    // 無法推斷
    return null;
  }

  static int _feedbackSortOrder(TransurfingInsightFeedback? feedback) {
    switch (feedback) {
      case TransurfingInsightFeedback.accurate:
        return 0;
      case null:
        return 1;
      case TransurfingInsightFeedback.muted:
        return 2;
      case TransurfingInsightFeedback.inaccurate:
        return 3;
    }
  }

  static Future<Map<String, int>> _getInsightTrustScores() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyInsightTrustScores);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map((key, value) {
        final score = value is num ? value.round() : _defaultTrustScore;
        return MapEntry(key, _clampTrustScore(score));
      });
    } catch (_) {
      return {};
    }
  }

  static Future<void> _setInsightTrustScores(Map<String, int> scores) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyInsightTrustScores, jsonEncode(scores));
  }

  static Future<void> _ensureInsightTrustScore(String insight) async {
    final scores = await _getInsightTrustScores();
    if (!scores.containsKey(insight)) {
      scores[insight] = _defaultTrustScore;
      await _setInsightTrustScores(scores);
    }
  }

  static Future<void> _adjustInsightTrustScore(
    String insight,
    int delta,
  ) async {
    final scores = await _getInsightTrustScores();
    final current = _trustScoreFor(insight, scores);
    scores[insight] = _clampTrustScore(current + delta);
    await _setInsightTrustScores(scores);
  }

  static Future<void> _removeInsightTrustScore(String insight) async {
    final scores = await _getInsightTrustScores();
    if (scores.remove(insight) != null) {
      await _setInsightTrustScores(scores);
    }
  }

  static int _trustScoreFor(String insight, Map<String, int> scores) {
    return _clampTrustScore(scores[insight] ?? _defaultTrustScore);
  }

  static int _clampTrustScore(int score) {
    return score.clamp(0, 100).toInt();
  }

  static Future<Set<String>> _getSuppressedTransurfingInsights() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      ...(prefs.getStringList(_keyInsightInaccurate) ?? const []),
      ...(prefs.getStringList(_keyInsightMuted) ?? const []),
    };
  }

  static Future<void> _addUnique(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(key) ?? [];
    if (!values.contains(value)) {
      values.add(value);
      await prefs.setStringList(key, values);
    }
  }

  static Future<void> _removeFromKey(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(key) ?? [];
    if (values.remove(value)) {
      await prefs.setStringList(key, values);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // [S24c EntityGraphService] getById / search — R1 實作
  // ═══════════════════════════════════════════════════════════════
  //
  // R1 風險：MemoryStore 目前用 SharedPreferences 存 List<String>（純文字），
  // 沒有 Memory 物件。getById 需要走 SQLite 路徑（BrainDatabase）。
  //
  // 實作策略（雙路徑 + fallback）：
  // 1. 嘗試 SQLite（BrainDatabase.instance）——如果已初始化，直接查 memories 表。
  // 2. 如果 SQLite 不可用（未初始化、測試環境無原生擴充），fallback 到
  //    SharedPreferences 的 Map<id, MemoryJSON> 快取。
  //    快取鍵：bridge_memory_objects_v0
  //    快取在 getAll() 時以 content→Memory 的映射建立（見下方 _buildMemoryObjectCache）。
  //
  // 這樣在正式環境走 SQLite（高效），測試環境走 SharedPreferences（可 mock）。

  /// SharedPreferences 快取鍵：Map<id, MemoryJSON>
  static const String _keyMemoryObjects = 'bridge_memory_objects_v0';

  /// 根據 ID 取得 Memory 物件。
  ///
  /// 優先走 SQLite（BrainDatabase），如果未初始化則 fallback 到
  /// SharedPreferences 快取。
  ///
  /// 回傳 null 如果 ID 不存在。
  static Future<Memory?> getById(String id) async {
    if (id.trim().isEmpty) return null;

    // ── 路徑 1：SQLite ──
    try {
      final db = BrainDatabase.instance;
      if (db.isInitialized) {
        final rows = db.db.select(
          'SELECT * FROM memories WHERE id = ? LIMIT 1',
          [id],
        );
        if (rows.isNotEmpty) {
          return Memory.fromMap(rows.first);
        }
        // SQLite 有初始化但找不到 → 回傳 null（不 fallback，
        // 因為 SQLite 是權威來源）
        return null;
      }
    } catch (e) {
      debugPrint('[MemoryStore.getById] SQLite 查詢失敗，fallback 到 SharedPreferences: $e');
    }

    // ── 路徑 2：SharedPreferences 快取 ──
    final cache = await _loadMemoryObjectCache();
    return cache[id];
  }

  /// 搜尋記憶。在 string list 上做 contains 搜尋。
  ///
  /// [query] 搜尋關鍵字（不分大小寫）。
  /// 回傳匹配的 Memory 列表。如果 SQLite 可用，從 SQLite 載入；
  /// 否則從 SharedPreferences string list 建構 Memory 物件。
  static Future<List<Memory>> search(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];

    // ── 路徑 1：SQLite ──
    try {
      final db = BrainDatabase.instance;
      if (db.isInitialized) {
        final rows = db.db.select(
          "SELECT * FROM memories WHERE archived = 0 AND chunk_index = 0 "
          // [小葵 2026-09-22 v18 temporal filtering] 搜尋只走現行事實
          "AND superseded_by IS NULL "
          "AND (expires_at IS NULL OR expires_at > ?) "
          "AND LOWER(content) LIKE ? ORDER BY importance DESC, created_at DESC LIMIT 50",
          [DateTime.now().millisecondsSinceEpoch, '%$q%'],
        );
        return rows.map((r) => Memory.fromMap(r)).toList();
      }
    } catch (e) {
      debugPrint('[MemoryStore.search] SQLite 查詢失敗，fallback 到 SharedPreferences: $e');
    }

    // ── 路徑 2：SharedPreferences string list ──
    final memories = await getAll();
    final matched = memories
        .where((m) => m.toLowerCase().contains(q))
        .toList();

    // 從 string list 建構簡易 Memory 物件（只有 content + id）
    final cache = await _loadMemoryObjectCache();
    return matched.map((content) {
      // 嘗試從快取找已有的 Memory（有完整欄位）
      final cached = cache.values.where((m) => m.content == content).firstOrNull;
      if (cached != null) return cached;
      // 建構簡易 Memory
      return _createMinimalMemory(content);
    }).toList();
  }

  /// 載入 Memory 物件快取（SharedPreferences JSON）。
  static Future<Map<String, Memory>> _loadMemoryObjectCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyMemoryObjects);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((id, json) {
        final m = Map<String, dynamic>.from(json as Map);
        return MapEntry(id, Memory.fromMap(m));
      });
    } catch (_) {
      return {};
    }
  }

  /// 建構簡易 Memory 物件（只有 content + 自動生成 id）。
  /// 用於 SharedPreferences fallback 路徑。
  static Memory _createMinimalMemory(String content) {
    final now = DateTime.now();
    return Memory(
      id: 'mem-${content.hashCode}',
      content: content,
      room: BrainRoom.stream,
      subCategory: '',
      agent: '',
      companionId: '',
      source: MemorySource.chat,
      project: '',
      tags: const [],
      importance: 3,
      createdAt: now,
      updatedAt: now,
      accessCount: 0,
      archived: false,
      chunkIndex: 0,
      totalChunks: 1,
    );
  }
}

// ===== 批次操作資料結構 — 學習 Hermes atomic operations =====

/// 記憶操作類型。
enum MemoryAction { add, replace, remove }

/// 單筆記憶操作。
class MemoryOp {
  final MemoryAction action;
  final String content;
  final String? oldText;

  const MemoryOp._({
    required this.action,
    required this.content,
    this.oldText,
  });

  /// 新增記憶。
  factory MemoryOp.add(String content) =>
      MemoryOp._(action: MemoryAction.add, content: content);

  /// 替換記憶（找到包含 oldText 的記憶，替換為 content）。
  factory MemoryOp.replace({required String oldText, required String content}) =>
      MemoryOp._(action: MemoryAction.replace, content: content, oldText: oldText);

  /// 刪除記憶（刪除所有包含 content 子字串的記憶）。
  factory MemoryOp.remove(String content) =>
      MemoryOp._(action: MemoryAction.remove, content: content);
}

/// 批次操作結果。
class BatchResult {
  final List<String> added = [];
  final List<String> replaced = [];
  final List<String> removed = [];
  final List<String> blocked = []; // 被安全掃描阻擋的

  bool get hasChanges => added.isNotEmpty || replaced.isNotEmpty || removed.isNotEmpty;

  @override
  String toString() =>
      'BatchResult(added: ${added.length}, replaced: ${replaced.length}, '
      'removed: ${removed.length}, blocked: ${blocked.length})';
}
