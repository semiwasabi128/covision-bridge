import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'managed_folder_rule_store.dart';

class ManagedFolderGuardFile {
  final String name;
  final String path;
  final String kind;
  final int sizeBytes;
  final DateTime modifiedAt;

  const ManagedFolderGuardFile({
    required this.name,
    required this.path,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  String get fingerprint =>
      '$path|$sizeBytes|${modifiedAt.millisecondsSinceEpoch}';

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'path': path,
      'kind': kind,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }
}

class ManagedFolderGuardCheck {
  final ManagedFolderRule rule;
  final bool initialized;
  final DateTime checkedAt;
  final int fileCount;
  final int knownFileCount;
  final List<ManagedFolderGuardFile> newFiles;
  final Map<String, int> categoryCounts;

  const ManagedFolderGuardCheck({
    required this.rule,
    required this.initialized,
    required this.checkedAt,
    required this.fileCount,
    required this.knownFileCount,
    required this.newFiles,
    required this.categoryCounts,
  });

  bool get hasNewFiles => newFiles.isNotEmpty;
}

class ManagedFolderGuardStore {
  static const String _key = 'bridge_managed_folder_guard_state_v0';

  const ManagedFolderGuardStore();

  Future<List<ManagedFolderGuardCheck>> checkRules(
    List<ManagedFolderRule> rules,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final state = _decodeState(prefs.getString(_key));
    final checks = <ManagedFolderGuardCheck>[];
    var changed = false;

    for (final rule in rules) {
      if (!rule.isValid || rule.isBuiltIn) continue;
      final directory = Directory(rule.folderPath);
      if (!await directory.exists()) continue;

      final files = await _scan(directory);
      final previous = _stateForRule(state, rule.id);
      final previousFingerprints = previous.fingerprints;
      final initialized = previous.initialized;
      final newFiles = initialized
          ? files
                .where(
                  (file) => !previousFingerprints.contains(file.fingerprint),
                )
                .toList(growable: false)
          : const <ManagedFolderGuardFile>[];

      checks.add(
        ManagedFolderGuardCheck(
          rule: rule,
          initialized: initialized,
          checkedAt: DateTime.now(),
          fileCount: files.length,
          knownFileCount: previousFingerprints.length,
          newFiles: newFiles,
          categoryCounts: _counts(files),
        ),
      );

      state[rule.id] = _GuardState(
        initialized: true,
        lastCheckedAt: DateTime.now(),
        fingerprints: files.map((file) => file.fingerprint).toSet(),
      );
      changed = true;
    }

    if (changed) {
      await prefs.setString(_key, _encodeState(state));
    }
    return checks;
  }

  Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<List<ManagedFolderGuardFile>> _scan(Directory root) async {
    final files = <ManagedFolderGuardFile>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = _fileNameFromPath(entity.path);
      if (_shouldIgnore(name)) continue;
      final stat = await entity.stat();
      files.add(
        ManagedFolderGuardFile(
          name: name,
          path: entity.path,
          kind: _kindFor(name),
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
      if (files.length >= 300) break;
    }
    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  bool _shouldIgnore(String name) {
    return name.startsWith('Bridge整理紀錄-') ||
        name == '.DS_Store' ||
        name.startsWith('.');
  }

  Map<String, int> _counts(List<ManagedFolderGuardFile> files) {
    final result = <String, int>{};
    for (final file in files) {
      result[file.kind] = (result[file.kind] ?? 0) + 1;
    }
    return result;
  }

  Map<String, _GuardState> _decodeState(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        return MapEntry(
          key.toString(),
          _GuardState.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      });
    } catch (_) {
      return {};
    }
  }

  String _encodeState(Map<String, _GuardState> state) {
    return jsonEncode(state.map((key, value) => MapEntry(key, value.toJson())));
  }

  _GuardState _stateForRule(Map<String, _GuardState> state, String id) {
    return state[id] ?? const _GuardState();
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(Platform.pathSeparator);
    if (parts.isEmpty) return path;
    final name = parts.last.trim();
    return name.isEmpty ? path : name;
  }

  String _kindFor(String name) {
    final lower = name.toLowerCase();
    final extension = lower.contains('.') ? lower.split('.').last : '';
    if ([
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'heic',
      'svg',
    ].contains(extension)) {
      return '圖片';
    }
    if ([
      'md',
      'txt',
      'pdf',
      'doc',
      'docx',
      'pages',
      'rtf',
    ].contains(extension)) {
      return '文件';
    }
    if (['mp4', 'mov', 'm4v', 'avi', 'webm'].contains(extension)) {
      return '影片';
    }
    if (['mp3', 'wav', 'm4a', 'flac', 'aac'].contains(extension)) {
      return '音訊';
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) {
      return '壓縮檔';
    }
    if ([
      'dart',
      'js',
      'ts',
      'py',
      'json',
      'yaml',
      'yml',
      'html',
      'css',
    ].contains(extension)) {
      return '程式碼';
    }
    return '其他';
  }
}

class _GuardState {
  final bool initialized;
  final DateTime? lastCheckedAt;
  final Set<String> fingerprints;

  const _GuardState({
    this.initialized = false,
    this.lastCheckedAt,
    this.fingerprints = const {},
  });

  Map<String, Object?> toJson() {
    return {
      'initialized': initialized,
      'lastCheckedAt': lastCheckedAt?.toIso8601String(),
      'fingerprints': fingerprints.toList()..sort(),
    };
  }

  factory _GuardState.fromJson(Map<String, dynamic> json) {
    final rawFingerprints = json['fingerprints'];
    return _GuardState(
      initialized: json['initialized'] == true,
      lastCheckedAt: DateTime.tryParse(json['lastCheckedAt']?.toString() ?? ''),
      fingerprints: rawFingerprints is List
          ? rawFingerprints.map((item) => item.toString()).toSet()
          : const {},
    );
  }
}
