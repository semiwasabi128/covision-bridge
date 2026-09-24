#!/usr/bin/env dart
// Token Reference Doc Generator
//
// 用途：把 BridgeDSTokenGroups + 實際 token 定義自動生成
//       完整 docs/BRIDGE_TOKEN_REFERENCE.md。
//
// 用法：
//   dart run tool/generate_token_reference.dart

import 'dart:io';

void main() async {
  stdout.writeln('📖 正在生成 Bridge Token Reference...\n');

  final tokens = _extractTokens();
  final groups = _extractGroups();
  final colorMap = _buildColorMap(tokens);

  final outputPath = 'docs/BRIDGE_TOKEN_REFERENCE.md';
  final outputFile = File(outputPath);
  if (!outputFile.parent.existsSync()) {
    outputFile.parent.createSync(recursive: true);
  }

  final content = _generateMarkdown(groups, colorMap);
  await outputFile.writeAsString(content);

  stdout.writeln('✅ Token Reference 已生成：');
  stdout.writeln('   路徑：$outputPath');
  stdout.writeln('   tokens: ${tokens.length}');
  stdout.writeln('   groups: ${groups.length}');
}

/// 從 BridgeDS class 提取所有 token
List<MapEntry<String, String>> _extractTokens() {
  final file = File('lib/theme/bridge_design_system.dart');
  if (!file.existsSync()) {
    stderr.writeln('❌ 找不到 lib/theme/bridge_design_system.dart');
    exit(1);
  }

  final content = file.readAsStringSync();
  final bdStart = content.indexOf('class BridgeDS ');
  if (bdStart == -1) {
    stderr.writeln('❌ 找不到 BridgeDS class');
    exit(1);
  }

  final bdEnd = content.indexOf('\n}', bdStart);
  final bdBody = content.substring(bdStart, bdEnd + 2);

  final pattern = RegExp(
    r'static\s+const\s+Color\s+(\w+)\s*=\s*Color\((0x[0-9A-Fa-f]{8})\)\s*;',
  );

  return pattern.allMatches(bdBody)
      .map((m) => MapEntry(m.group(1)!, m.group(2)!))
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
}

/// 從 BridgeDSTokenGroups 提取分組定義
List<Map<String, dynamic>> _extractGroups() {
  final file = File('lib/theme/bridge_ds_tokens.dart');
  if (!file.existsSync()) return [];

  final content = file.readAsStringSync();

  final groups = <Map<String, dynamic>>[];
  final pattern = RegExp(
    r"TokenGroup\(\s*name:\s*'([^']+)',\s*description:\s*'([^']*)',\s*tokens:\s*\[\s*([\s\S]*?)\s*\],",
    multiLine: true,
  );

  for (final match in pattern.allMatches(content)) {
    final name = match.group(1)!;
    final desc = match.group(2)!;
    final tokensStr = match.group(3)!;

    final tokens = tokensStr
        .split(',')
        .map((s) => s.trim().replaceAll("'", '').replaceAll(',', ''))
        .where((s) => s.isNotEmpty)
        .toList();

    groups.add({
      'name': name,
      'description': desc,
      'tokens': tokens,
    });
  }

  return groups;
}

Map<String, String> _buildColorMap(List<MapEntry<String, String>> tokens) {
  return {for (final entry in tokens) entry.key: entry.value};
}

String _generateMarkdown(
  List<Map<String, dynamic>> groups,
  Map<String, String> colorMap,
) {
  final sb = StringBuffer();

  // Header
  sb.writeln('# Bridge Token Reference');
  sb.writeln('');
  sb.writeln('> 自動生成於 ${DateTime.now().toIso8601String()}');
  sb.writeln('> 從 lib/theme/bridge_design_system.dart 自動提取');
  sb.writeln('> 共 **${colorMap.length} 個 color tokens**，分成 **${groups.length} 個語意組**');
  sb.writeln('');
  sb.writeln('---');
  sb.writeln('');

  // 統計
  sb.writeln('## 📊 總覽');
  sb.writeln('');
  final groupedTokenSet = <String>{};
  for (final g in groups) {
    for (final t in g['tokens'] as List) {
      groupedTokenSet.add(t.toString());
    }
  }

  sb.writeln('| 指標 | 數值 |');
  sb.writeln('|---|---|');
  sb.writeln('| 總 token 數 | ${colorMap.length} |');
  sb.writeln('| 分組數 | ${groups.length} |');
  sb.writeln('| 已分組 | ${groupedTokenSet.length} |');
  sb.writeln('| 未分組 | ${colorMap.length - groupedTokenSet.length} |');
  sb.writeln('');
  sb.writeln('### 分組分佈');
  sb.writeln('');
  sb.writeln('| # | 分組 | 數量 | 用途 |');
  sb.writeln('|---|---|---|---|');
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    sb.writeln('| ${i + 1} | **${group['name']}** | ${(group['tokens'] as List).length} | ${group['description']} |');
  }
  sb.writeln('');
  sb.writeln('---');
  sb.writeln('');

  // 各分組詳情
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final name = group['name'] as String;
    final desc = group['description'] as String;
    final tokens = group['tokens'] as List;

    sb.writeln('## ${i + 1}. $name');
    sb.writeln('');
    sb.writeln('> $desc');
    sb.writeln('');
    sb.writeln('Token 數量：${tokens.length}');
    sb.writeln('');
    sb.writeln('| Token | Hex 值 | RGB | 視覺 | 用途 |');
    sb.writeln('|---|---|---|---|---|');

    for (final token in tokens) {
      final tokenName = token.toString();
      final hex = colorMap[tokenName] ?? 'N/A';
      final rgb = _hexToRgbString(hex);
      final displayHex = '#${hex.replaceFirst('0xFF', '').toUpperCase()}';
      final visual = _colorBlockVisual(tokenName, hex);
      final useCase = _useCase(tokenName);
      sb.writeln('| `$tokenName` | `$hex` ($displayHex) | $rgb | $visual | $useCase |');
    }

    sb.writeln('');
  }

  sb.writeln('---');
  sb.writeln('');

  // 未分組警告
  final ungrouped = colorMap.keys.where((k) => !groupedTokenSet.contains(k)).toList();
  if (ungrouped.isNotEmpty) {
    sb.writeln('## ⚠️ 未分組 Token');
    sb.writeln('');
    sb.writeln('這些 token 還沒被分配到任何語意分組，是**技術債**，應被分類。');
    sb.writeln('');
    sb.writeln('| Token | Hex |');
    sb.writeln('|---|---|');
    for (final name in ungrouped) {
      final hex = colorMap[name]!;
      final displayHex = '#${hex.replaceFirst('0xFF', '').toUpperCase()}';
      sb.writeln('| `$name` | `$hex` ($displayHex) |');
    }
    sb.writeln('');
  } else {
    sb.writeln('## ✅ 所有 token 已分組');
    sb.writeln('');
    sb.writeln('100% 覆蓋率，無技術債！');
    sb.writeln('');
  }

  // 設計原則
  sb.writeln('---');
  sb.writeln('');
  sb.writeln('## 📐 設計原則');
  sb.writeln('');
  sb.writeln('### 1. 語意化命名');
  sb.writeln('');
  sb.writeln('Token 名稱應該**表達用途**，而不是表達顏色：');
  sb.writeln('');
  sb.writeln('- ✅ 好：`textPrimary`、`accentBlue`、`surfaceElevated`');
  sb.writeln('- ❌ 差：`darkGray`、`lightBlue`、`medium`');
  sb.writeln('');
  sb.writeln('### 2. 三層架構不可破');
  sb.writeln('');
  sb.writeln('```');
  sb.writeln('Widget UI → Tier Manifest → BridgeDS Token (你正在看這層)');
  sb.writeln('```');
  sb.writeln('');
  sb.writeln('### 3. 禁寫死');
  sb.writeln('');
  sb.writeln('凡 `Color(0xFF...)`、`Colors.xxx.shadeNN` 都是違規，會被 CI 自動掃描。');
  sb.writeln('');
  sb.writeln('### 4. 12 個分組覆蓋率');
  sb.writeln('');
  sb.writeln('每個分組都是語意類別，**所有 token 必須歸類**。');
  sb.writeln('');

  // 相關文件
  sb.writeln('---');
  sb.writeln('');
  sb.writeln('## 🔗 相關文件');
  sb.writeln('');
  sb.writeln('- [BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md](BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)');
  sb.writeln('- [BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md](BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md)');
  sb.writeln('- [BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md)');
  sb.writeln('- [DESIGN_SYSTEM_EVOLUTION.md](DESIGN_SYSTEM_EVOLUTION.md)');
  sb.writeln('');
  sb.writeln('---');
  sb.writeln('');
  sb.writeln('**更新方式**：`dart run tool/generate_token_reference.dart`');

  return sb.toString();
}

String _hexToRgbString(String hex) {
  if (hex.length < 8) return 'N/A';
  var cleaned = hex.replaceFirst('0x', '');
  if (cleaned.startsWith('FF')) {
    cleaned = cleaned.substring(2);
  }
  if (cleaned.length < 6) return 'N/A';
  try {
    final r = int.parse(cleaned.substring(0, 2), radix: 16);
    final g = int.parse(cleaned.substring(2, 4), radix: 16);
    final b = int.parse(cleaned.substring(4, 6), radix: 16);
    return 'rgb($r, $g, $b)';
  } catch (_) {
    return 'N/A';
  }
}

String _colorBlockVisual(String tokenName, String hex) {
  if (hex.length < 8) return '[N/A]';
  var cleaned = hex.replaceFirst('0x', '');
  if (cleaned.startsWith('FF')) {
    cleaned = cleaned.substring(2);
  }
  return '[$tokenName](#$cleaned)';
}

String _useCase(String tokenName) {
  if (tokenName.startsWith('text')) return '文字';
  if (tokenName.startsWith('surface')) return '容器';
  if (tokenName.startsWith('dark')) return '深色';
  if (tokenName.startsWith('canvas')) return '畫布';
  if (tokenName.startsWith('border')) return '邊框';
  if (tokenName.startsWith('divider')) return '分隔線';
  if (tokenName.startsWith('accent')) return '互動強調';
  if (tokenName.startsWith('success') || tokenName.contains('Green')) return '成功';
  if (tokenName.startsWith('error') || tokenName.contains('Red')) return '錯誤';
  if (tokenName.startsWith('alert')) return '警告';
  if (tokenName.startsWith('warning')) return '警告';
  if (tokenName.startsWith('tag')) return '標籤';
  if (tokenName.startsWith('bg')) return '背景';
  if (tokenName.startsWith('file') || tokenName == 'sopOrange' || tokenName == 'pinkAccent' || tokenName == 'slate' || tokenName == 'teal' || tokenName == 'deepPurple') return 'Canvas 節點';
  if (tokenName.startsWith('particle')) return '粒子';
  if (tokenName.startsWith('grey') || tokenName == 'lightGray') return '灰階';
  if (tokenName.startsWith('red') || tokenName.startsWith('green') || tokenName.startsWith('blue') || tokenName.startsWith('orange')) return 'Material 標準色';
  if (tokenName.startsWith('hint')) return '提示裝飾';
  return '其他';
}
