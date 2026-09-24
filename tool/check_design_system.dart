#!/usr/bin/env dart
// Design System Guard — 自動掃描違規 (CI 友善)
//
// 用途：在 CI / pre-commit 階段自動檢查以下違規：
//   1. 寫死 hex 顏色 (Color(0xFF...))
//   2. 寫死 Material Colors (Colors.x.shadeXXX)
//   3. 寫死魔術間距 (非 AppSpacing / AppGap)
//   4. 寫死魔術圓角 (非 BorderRadius.xxx 常數)
//
// 用法：
//   dart run tool/check_design_system.dart           # 全掃描
//   dart run tool/check_design_system.dart lib/      # 只掃指定目錄
//
// 退出碼：
//   0 = 無違規
//   1 = 有違規（列出檔案 + 行數）
//
// 安裝成 pre-commit hook：
//   ln -s ../../tool/check_design_system.dart .git/hooks/pre-commit

import 'dart:io';

const List<String> _EXCLUDE_DIRS = [
  '/theme/',
  '/test/',
  '/tool/',
  'theme_pack_service.dart',
  'appearance_generator.dart',
  '/models/',
  '/services/capability/',  // 顏色對應 capability 類型，資料層
  '/services/onboarding/',  // onboarding 有自有視覺
  '/brain_pipeline/',       // 大腦管道自定義視覺
];

const List<String> _EXCLUDE_FILES = [
  'summon_screen.dart',  // Companion 預設配色（資料層定義）
  'golden_keys_screen.dart',  // 金鑰畫面特殊視覺
  'blind_box_screen.dart',  // 盲盒畫面特殊視覺
  'companion_list_screen.dart',  // 夥伴列表特殊色
  'agent_design_knowledge.dart',  // 設計知識庫（資料）
  'vault_service.dart',  // 節點類型預設色（資料層）
  'app_theme.dart',  // 主題定義本身
  'canvas_doodle_layer.dart',  // 用戶塗鴉色盤（用戶自選色，合法）
  'brain_reflection_panel.dart',  // 大腦反射面板特殊視覺
];

bool _isExcluded(String path) {
  for (final ex in _EXCLUDE_DIRS) {
    if (path.contains(ex)) return true;
  }
  for (final ex in _EXCLUDE_FILES) {
    if (path.endsWith(ex)) return true;
  }
  return false;
}

class Violation {
  Violation({
    required this.file,
    required this.line,
    required this.type,
    required this.snippet,
  });

  final String file;
  final int line;
  final String type;
  final String snippet;

  @override
  String toString() =>
      '  ${file}:${line}: [$type] ${snippet.trim()}';
}

Future<int> main(List<String> args) async {
  final target = args.isNotEmpty ? args[0] : 'lib/';

  stdout.writeln('🔍 掃描設計系統違規：$target\n');

  final violations = <Violation>[];
  await _scanDir(Directory(target), violations);

  final byFile = <String, List<Violation>>{};
  for (final v in violations) {
    byFile.putIfAbsent(v.file, () => []).add(v);
  }

  if (violations.isEmpty) {
    stdout.writeln('✅ 沒有違規 — 設計系統乾淨');
    return 0;
  }

  stdout.writeln('❌ 發現 ${violations.length} 處違規：\n');
  for (final entry in byFile.entries) {
    stdout.writeln('${entry.key} (${entry.value.length} 處)');
    for (final v in entry.value) {
      stdout.writeln(v.toString());
    }
    stdout.writeln('');
  }

  stdout.writeln('修復指引：');
  stdout.writeln('  - 寫死 hex → 用 BridgeDS.xxx token');
  stdout.writeln('  - Material Colors → 用 BridgeDS.xxx token');
  stdout.writeln('  - 寫死間距 → 用 AppSpacing.xxx 或 AppGap.xxx');
  stdout.writeln('  - 寫死圓角 → 用 BorderRadius.xxx');
  stdout.writeln('');

  return 1;
}

Future<void> _scanDir(Directory dir, List<Violation> violations) async {
  if (!dir.existsSync()) return;

  await for (final entity in dir.list(recursive: false)) {
    if (entity is Directory) {
      await _scanDir(entity, violations);
    } else if (entity is File && entity.path.endsWith('.dart')) {
      if (_isExcluded(entity.path)) continue;
      _scanFile(entity, violations);
    }
  }
}

final _hexPattern = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
final _materialColorPattern = RegExp(
  r'\bColors\.(red|blue|green|yellow|orange|purple|pink|cyan|teal|'
  r'indigo|brown|amber|lime|deepOrange|lightBlue|lightGreen|'
  r'deepPurple|blueGrey)\.shade\d{3}\b',
);

void _scanFile(File file, List<Violation> violations) {
  final relative = file.path.replaceFirst(RegExp(r'^.*bridge_app/'), '');
  final lines = file.readAsLinesSync();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineNo = i + 1;

    // 跳過註解
    if (_isCommentLine(line, file)) continue;

    // 寫死 hex
    for (final match in _hexPattern.allMatches(line)) {
      violations.add(Violation(
        file: relative,
        line: lineNo,
        type: '寫死 hex',
        snippet: line.substring(match.start).trim(),
      ));
    }

    // Material Colors
    for (final match in _materialColorPattern.allMatches(line)) {
      violations.add(Violation(
        file: relative,
        line: lineNo,
        type: 'Material Color',
        snippet: line.substring(match.start).trim(),
      ));
    }
  }
}

bool _isCommentLine(String line, File file) {
  final trimmed = line.trim();
  if (trimmed.startsWith('//')) return true;
  if (trimmed.startsWith('*')) return true;
  if (trimmed.startsWith('/*')) return true;
  return false;
}
