import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/second_brain_file_index.dart';
import '../models/second_brain_trace.dart';

class SecondBrainFileIndexStore {
  static const String _key = 'bridge_second_brain_file_index_v1';

  const SecondBrainFileIndexStore();

  Future<List<SecondBrainFileEntry>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                SecondBrainFileEntry.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((entry) => entry.id.isNotEmpty && entry.path.isNotEmpty)
          .toList()
        ..sort((a, b) => b.indexedAt.compareTo(a.indexedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(SecondBrainFileEntry entry) async {
    final all = List<SecondBrainFileEntry>.of(await getAll());
    final normalized = _normalizeEntry(entry);
    final index = all.indexWhere(
      (existing) =>
          existing.id == normalized.id || existing.path == normalized.path,
    );
    if (index >= 0) {
      all[index] = normalized;
    } else {
      all.add(normalized);
    }
    await _save(all);
  }

  Future<List<SecondBrainFileEntry>> search(
    String query, {
    int limit = 3,
    Map<String, SecondBrainAssociationFeedback> associationFeedbacks = const {},
    String? agentId, // [以利沙 P0 修復十七輪 2026-06-27] 依 agent 篩選
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final tokens = _tokensFor(trimmed);
    if (tokens.isEmpty) return const [];

    final scored = <({SecondBrainFileEntry entry, int score, int agentPriority})>[];
    for (final entry in await getAll()) {
      if (entry.muted) continue;
      // [以利沙 P0 修復十七輪 2026-06-27] agentId 篩選（entry.agentId 為 null 時不過濾，向後相容）
      // [以利沙 P2 修復二十一輪 2026-06-27] 降低跨 Agent 污染：有指定 agentId 時，
      // 同 agentId 的結果優先（agentPriority=0），null 的降級（agentPriority=1），不同 agentId 的排除
      if (agentId != null && entry.agentId != null && entry.agentId != agentId) continue;
      final agentPriority = (agentId != null && entry.agentId == null) ? 1 : 0;
      final haystack =
          '${entry.title} ${entry.path} ${entry.room.label} ${entry.room.zhLabel} '
                  '${entry.summary} ${entry.contentDigest} ${entry.contentExcerpt} '
                  '${entry.tags.join(' ')} ${entry.keywords.join(' ')}'
              .toLowerCase();
      var score = 0;
      for (final token in tokens) {
        if (haystack.contains(token)) score += token.length >= 4 ? 3 : 2;
      }
      score += _associationBiasScore(haystack, associationFeedbacks);
      score += _digitalAssetSearchBias(entry, tokens);
      if (score > 0) {
        score += entry.trustScore ~/ 25;
        score += entry.useCount.clamp(0, 5);
        score += entry.usefulFeedbackCount.clamp(0, 6);
        if (entry.pinned) score += 8;
        score -= entry.irrelevantFeedbackCount.clamp(0, 5);
        scored.add((entry: entry, score: score, agentPriority: agentPriority));
      }
    }

    scored.sort((a, b) {
      // [以利沙 P2 修復二十一輪 2026-06-27] 同 agentId 優先，null 的排後面
      final priorityOrder = a.agentPriority.compareTo(b.agentPriority);
      if (priorityOrder != 0) return priorityOrder;
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return b.entry.indexedAt.compareTo(a.entry.indexedAt);
    });
    return scored.take(limit).map((item) => item.entry).toList();
  }

  int _digitalAssetSearchBias(SecondBrainFileEntry entry, List<String> tokens) {
    if (!entry.path.startsWith('brain://digital-assets/')) return 0;
    final asksForAssetLayer = tokens.any(
      (token) =>
          token.contains('資產') ||
          token.contains('創意') ||
          token.contains('引用') ||
          token.contains('重用') ||
          token.contains('玩法') ||
          token.contains('模板') ||
          token.contains('registry'),
    );
    return asksForAssetLayer ? 6 : -10;
  }

  Future<void> markUsed(List<SecondBrainFileEntry> entries) async {
    if (entries.isEmpty) return;
    final all = await getAll();
    final usedIds = entries.map((entry) => entry.id).toSet();
    final now = DateTime.now();
    final updated = all.map((entry) {
      if (!usedIds.contains(entry.id)) return entry;
      return entry.copyWith(lastUsedAt: now, useCount: entry.useCount + 1);
    }).toList();
    await _save(updated);
  }

  Future<void> applyMemoryFeedback(
    SecondBrainMemoryTrace memory,
    SecondBrainMemoryFeedback feedback,
  ) async {
    final all = await getAll();
    if (all.isEmpty) return;

    final memoryPath = memory.sourcePath?.trim();
    final index = all.indexWhere((entry) {
      if (memoryPath != null && memoryPath.isNotEmpty) {
        return entry.path == memoryPath || entry.id == _idFor(memoryPath);
      }
      return entry.title == memory.sourceLabel;
    });
    if (index < 0) return;

    final now = DateTime.now();
    final entry = all[index];
    final updated = switch (feedback) {
      SecondBrainMemoryFeedback.useful => entry.copyWith(
        trustScore: entry.trustScore + 6,
        usefulFeedbackCount: entry.usefulFeedbackCount + 1,
        useCount: entry.useCount + 1,
        muted: false,
        lastUsedAt: now,
        lastFeedbackLabel: feedback.label,
        lastFeedbackAt: now,
      ),
      SecondBrainMemoryFeedback.pin => entry.copyWith(
        trustScore: entry.trustScore + 8,
        usefulFeedbackCount: entry.usefulFeedbackCount + 1,
        pinned: true,
        muted: false,
        lastFeedbackLabel: feedback.label,
        lastFeedbackAt: now,
      ),
      SecondBrainMemoryFeedback.irrelevant => entry.copyWith(
        trustScore: entry.trustScore - 12,
        irrelevantFeedbackCount: entry.irrelevantFeedbackCount + 1,
        lastFeedbackLabel: feedback.label,
        lastFeedbackAt: now,
      ),
      SecondBrainMemoryFeedback.mute => entry.copyWith(
        trustScore: entry.trustScore - 20,
        irrelevantFeedbackCount: entry.irrelevantFeedbackCount + 1,
        pinned: false,
        muted: true,
        lastFeedbackLabel: feedback.label,
        lastFeedbackAt: now,
      ),
    };

    all[index] = _normalizeEntry(updated);
    await _save(all);
  }

  Future<void> moveMemoryToRoom(
    SecondBrainMemoryTrace memory,
    SecondBrainRoom room,
  ) async {
    final all = await getAll();
    if (all.isEmpty) return;

    final index = _indexForMemory(all, memory);
    if (index < 0) return;

    final now = DateTime.now();
    final entry = all[index];
    all[index] = _normalizeEntry(
      entry.copyWith(
        room: room,
        trustScore: entry.trustScore + 4,
        lastFeedbackLabel: '移到${room.zhLabel}',
        lastFeedbackAt: now,
      ),
    );
    await _save(all);
  }

  Future<void> clearMemoryCorrection(SecondBrainMemoryTrace memory) async {
    final all = await getAll();
    if (all.isEmpty) return;

    final index = _indexForMemory(all, memory);
    if (index < 0) return;

    final entry = all[index];
    all[index] = _normalizeEntry(
      entry.copyWith(
        pinned: false,
        muted: false,
        lastFeedbackLabel: '',
        clearLastFeedbackAt: true,
      ),
    );
    await _save(all);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _save(List<SecondBrainFileEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  SecondBrainFileEntry _normalizeEntry(SecondBrainFileEntry entry) {
    final title = entry.title.trim().isEmpty
        ? entry.path.split('/').last
        : entry.title.trim();
    final path = entry.path.trim();
    final id = entry.id.trim().isEmpty ? _idFor(path) : entry.id.trim();
    return entry.copyWith(
      id: id,
      title: title,
      path: path,
      summary: entry.summary.trim(),
      contentDigest: entry.contentDigest.trim(),
      contentExcerpt: entry.contentExcerpt.trim(),
      tags: entry.tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(),
      keywords: entry.keywords
          .map((keyword) => keyword.trim())
          .where((keyword) => keyword.isNotEmpty)
          .toSet()
          .toList(),
      trustScore: entry.trustScore.clamp(0, 100),
      usefulFeedbackCount: entry.usefulFeedbackCount.clamp(0, 9999),
      irrelevantFeedbackCount: entry.irrelevantFeedbackCount.clamp(0, 9999),
      lastFeedbackLabel: entry.lastFeedbackLabel.trim(),
    );
  }

  int _indexForMemory(
    List<SecondBrainFileEntry> entries,
    SecondBrainMemoryTrace memory,
  ) {
    final memoryPath = memory.sourcePath?.trim();
    return entries.indexWhere((entry) {
      if (memoryPath != null && memoryPath.isNotEmpty) {
        return entry.path == memoryPath || entry.id == _idFor(memoryPath);
      }
      return entry.title == memory.sourceLabel;
    });
  }

  String _idFor(String path) {
    return path.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
      '_',
    );
  }

  List<String> _tokensFor(String query) {
    final normalized = query.toLowerCase();
    final tokens = normalized
        .split(RegExp(r'[\s，。！？、,.;:：/\\|()[\]{}<>「」『』]+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2)
        .toSet()
        .toList();
    if (tokens.isEmpty && normalized.length >= 2) return [normalized];
    return tokens;
  }

  int _associationBiasScore(
    String haystack,
    Map<String, SecondBrainAssociationFeedback> associationFeedbacks,
  ) {
    var score = 0;
    for (final entry in associationFeedbacks.entries) {
      final tokens = _tokensFor(
        entry.key,
      ).where((token) => !_associationStopWords.contains(token)).toList();
      if (tokens.isEmpty) continue;

      final hits = tokens.where(haystack.contains).length;
      if (hits == 0) continue;

      final strength = hits.clamp(1, 3);
      score += switch (entry.value) {
        SecondBrainAssociationFeedback.useful => strength * 4,
        SecondBrainAssociationFeedback.wrong => -(strength * 8),
      };
    }
    return score;
  }

  static const Set<String> _associationStopWords = {
    '第二大腦',
    '關聯',
    '本輪',
    '目前',
    '系統',
    '已經',
    '使用者',
    '任務',
    '回到',
    '相關',
    'adapter',
    '完成',
    '訊號',
    '完成訊號',
    '原本',
    '卡點',
  };
}
