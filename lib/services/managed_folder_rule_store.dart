import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/second_brain_file_index.dart';
import 'bridge_media_store.dart';
import 'managed_folder_rule_namer.dart';
import 'second_brain_file_index_store.dart';

class ManagedFolderRule {
  final String id;
  final String folderPath;
  final String folderLabel;
  final String rulePath;
  final String ruleTitle;
  final String ruleSource;
  final String categorySummary;
  final String mode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ManagedFolderRule({
    required this.id,
    required this.folderPath,
    required this.folderLabel,
    required this.rulePath,
    required this.ruleTitle,
    required this.ruleSource,
    this.categorySummary = '',
    this.mode = 'suggest_only',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isValid =>
      folderPath.trim().isNotEmpty && rulePath.trim().isNotEmpty;

  bool get isBuiltIn => ruleSource == 'built_in';

  String get modeLabel {
    switch (mode) {
      case 'auto_after_confirm':
        return '確認後自動整理';
      case 'suggest_only':
      default:
        return '安全模式：先偵測與建議';
    }
  }

  ManagedFolderRule copyWith({
    String? id,
    String? folderPath,
    String? folderLabel,
    String? rulePath,
    String? ruleTitle,
    String? ruleSource,
    String? categorySummary,
    String? mode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ManagedFolderRule(
      id: id ?? this.id,
      folderPath: folderPath ?? this.folderPath,
      folderLabel: folderLabel ?? this.folderLabel,
      rulePath: rulePath ?? this.rulePath,
      ruleTitle: ruleTitle ?? this.ruleTitle,
      ruleSource: ruleSource ?? this.ruleSource,
      categorySummary: categorySummary ?? this.categorySummary,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'folderPath': folderPath,
      'folderLabel': folderLabel,
      'rulePath': rulePath,
      'ruleTitle': ruleTitle,
      'ruleSource': ruleSource,
      'categorySummary': categorySummary,
      'mode': mode,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ManagedFolderRule.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return ManagedFolderRule(
      id: json['id']?.toString() ?? '',
      folderPath: json['folderPath']?.toString() ?? '',
      folderLabel: json['folderLabel']?.toString() ?? '',
      rulePath: json['rulePath']?.toString() ?? '',
      ruleTitle: json['ruleTitle']?.toString() ?? '',
      ruleSource: json['ruleSource']?.toString() ?? '',
      categorySummary: json['categorySummary']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'suggest_only',
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ManagedFolderRuleStore {
  static const String _key = 'bridge_managed_folder_rules_v0';
  static const _namer = ManagedFolderRuleNamer();

  final SecondBrainFileIndexStore secondBrainStore;

  const ManagedFolderRuleStore({
    this.secondBrainStore = const SecondBrainFileIndexStore(),
  });

  Future<List<ManagedFolderRule>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ManagedFolderRule.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.isValid)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<ManagedFolderRule?> findByFolderPath(String folderPath) async {
    final normalized = _normalizePath(folderPath);
    if (normalized.isEmpty) return null;
    for (final rule in await loadAll()) {
      if (_normalizePath(rule.folderPath) == normalized) return rule;
    }
    return null;
  }

  Future<ManagedFolderRule> upsert(ManagedFolderRule rule) async {
    final normalized = _normalize(rule);
    final all = List<ManagedFolderRule>.of(await loadAll());
    final index = all.indexWhere(
      (item) =>
          item.id == normalized.id ||
          _normalizePath(item.folderPath) ==
              _normalizePath(normalized.folderPath),
    );
    if (index >= 0) {
      final existing = all[index];
      all[index] = normalized.copyWith(createdAt: existing.createdAt);
    } else {
      all.add(normalized);
    }
    await _save(all);
    await _upsertSecondBrainEntry(normalized);
    return normalized;
  }

  Future<void> ensureBuiltInRules() async {
    final now = DateTime.now();
    final specs = <({String category, String label, String title})>[
      (category: '', label: '文件總管', title: '文件總管整理規則'),
      (category: '報告', label: '報告資料夾', title: '報告資料夾整理規則'),
      (category: '規則', label: '規則資料夾', title: '規則資料夾整理規則'),
      (category: '摘要', label: '摘要資料夾', title: '摘要資料夾整理規則'),
      (category: '簡報', label: '簡報大綱資料夾', title: '簡報大綱資料夾整理規則'),
      (category: '清單', label: '清單資料夾', title: '清單資料夾整理規則'),
      (category: '需求', label: '規格需求資料夾', title: '規格需求資料夾整理規則'),
      (category: '企劃', label: '企劃資料夾', title: '企劃資料夾整理規則'),
    ];

    for (final spec in specs) {
      final String? folderPath;
      try {
        folderPath = await BridgeMediaStore.documentDirectoryPath(
          category: spec.category.isEmpty ? null : spec.category,
        );
      } catch (_) {
        continue;
      }
      if (folderPath == null || folderPath.trim().isEmpty) continue;
      final existing = await findByFolderPath(folderPath);
      if (existing != null && !existing.isBuiltIn) continue;
      await upsert(
        ManagedFolderRule(
          id: _idFor(folderPath),
          folderPath: folderPath,
          folderLabel: spec.label,
          rulePath: '$folderPath/.bridge_builtin_folder_rule.md',
          ruleTitle: spec.title,
          ruleSource: 'built_in',
          categorySummary: 'Bridge 內建輸出資料夾；依文件類型自動分區存放。',
          mode: 'suggest_only',
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _save(List<ManagedFolderRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(rules.map((rule) => rule.toJson()).toList()),
    );
  }

  ManagedFolderRule _normalize(ManagedFolderRule rule) {
    final folderPath = _normalizePath(rule.folderPath);
    final rulePath = rule.rulePath.trim();
    final now = DateTime.now();
    return rule.copyWith(
      id: rule.id.trim().isEmpty ? _idFor(folderPath) : rule.id.trim(),
      folderPath: folderPath,
      folderLabel: rule.folderLabel.trim().isEmpty
          ? _basename(folderPath)
          : rule.folderLabel.trim(),
      rulePath: rulePath,
      ruleTitle: rule.ruleTitle.trim().isEmpty
          ? _namer.title(
              folderLabel: _basename(folderPath),
              categorySummary: rule.categorySummary,
              source: rule.ruleSource,
            )
          : rule.ruleTitle.trim(),
      ruleSource: rule.ruleSource.trim().isEmpty
          ? 'generated'
          : rule.ruleSource.trim(),
      categorySummary: rule.categorySummary.trim(),
      mode: rule.mode.trim().isEmpty ? 'suggest_only' : rule.mode.trim(),
      createdAt: rule.createdAt.millisecondsSinceEpoch <= 0
          ? now
          : rule.createdAt,
      updatedAt: now,
    );
  }

  Future<void> _upsertSecondBrainEntry(ManagedFolderRule rule) {
    return secondBrainStore.upsert(
      SecondBrainFileEntry(
        id: 'managed-folder-rule-${rule.id}',
        title: '受管資料夾：${rule.folderLabel}',
        path: rule.folderPath,
        room: SecondBrainRoom.files,
        summary: '資料夾「${rule.folderPath}」已登記整理規則；後續新檔案會先依規則判斷，再請使用者確認。',
        contentDigest:
            '模式：${rule.modeLabel}。來源：${_sourceLabel(rule.ruleSource)}。${rule.categorySummary}',
        contentExcerpt: '規則文件：${rule.ruleTitle}\n規則位置：${rule.rulePath}',
        tags: const ['受管資料夾', '整理規則', '任務收尾歸檔', '檔案房間'],
        keywords: [
          rule.folderLabel,
          rule.folderPath,
          rule.ruleTitle,
          rule.rulePath,
          '受管資料夾',
          '整理規則',
          '歸檔',
        ],
        indexedAt: rule.updatedAt,
        trustScore: rule.isBuiltIn ? 72 : 82,
        pinned: !rule.isBuiltIn,
      ),
    );
  }

  static String _normalizePath(String path) {
    var value = path.trim();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _basename(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return '資料夾';
    return normalized.split('/').where((part) => part.isNotEmpty).last;
  }

  static String _idFor(String path) {
    final bytes = utf8.encode(_normalizePath(path).toLowerCase());
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _sourceLabel(String source) {
    switch (source) {
      case 'built_in':
        return 'Bridge 內建規則';
      case 'imported':
        return '使用者匯入規則';
      case 'generated':
      default:
        return '本次整理產生規則';
    }
  }
}
