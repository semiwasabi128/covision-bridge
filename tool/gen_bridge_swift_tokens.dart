#!/usr/bin/env dart
// bridge-mobile iOS Swift token generator
//
// 從 lib/theme/bridge_design_system.dart 自動生成完整的 UIColor extension
// 把 85 個 BridgeDS token 全部包含
//
// 用法：
//   dart run tool/gen_bridge_swift_tokens.dart [output.swift]
//
// 預設輸出：
//   packages/bridge-mobile/ios/BridgeMobile+Tokens.swift

import 'dart:io';

void main(List<String> args) async {
  stdout.writeln('🍎 正在生成 iOS Swift UIColor bridge tokens...\n');

  final tokens = _extractTokens();
  final grouped = _extractGroups();

  final outputPath = args.isNotEmpty
      ? args[0]
      : 'packages/bridge-mobile/ios/BridgeMobile+Tokens.swift';

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);

  final sw = StringBuffer();
  sw.writeln('// BridgeMobile+Tokens.swift — iOS Swift Design Tokens');
  sw.writeln('// 自動生成於 ${DateTime.now().toIso8601String()}');
  sw.writeln('// 從 lib/theme/bridge_design_system.dart 提取');
  sw.writeln('// 共 **${tokens.length} 個 UIColor bridge() token**');
  sw.writeln('//');
  sw.writeln('// 用法：');
  sw.writeln('//   view.backgroundColor = .bridge(.canvas)');
  sw.writeln('//   label.textColor = .bridge(.textPrimary)');
  sw.writeln('//');
  sw.writeln('// 重新生成：`dart run tool/gen_bridge_swift_tokens.dart`');
  sw.writeln('');
  sw.writeln('#if canImport(UIKit)');
  sw.writeln('import UIKit');
  sw.writeln('');
  sw.writeln('public extension UIColor {');
  sw.writeln('    /// Bridge Design System 枚舉');
  sw.writeln('    enum BridgeDS {}');
  sw.writeln('');
  sw.writeln('    /// 把 UIColor.bridge(.tokenName) 對應到 BridgeDS token');
  sw.writeln('    static func bridge(_ token: BridgeDS) -> UIColor {');
  sw.writeln('        switch token {');

  for (final group in grouped) {
    final groupName = group['name'] as String;
    final groupTokens = group['tokens'] as List;

    sw.writeln('');
    sw.writeln('        // MARK: - $groupName (${groupTokens.length})');

    for (final t in groupTokens) {
      final tokenName = t.toString();
      final hex = tokens[tokenName];
      if (hex == null) continue;
      final rgb = _hexToRgbComponents(hex);
      final alpha = _hexToAlphaFloat(hex);
      final caseName = _tokenNameToCase(tokenName);
      sw.writeln(
        '        case .$caseName: return UIColor(red: ${rgb[0]}, green: ${rgb[1]}, blue: ${rgb[2]}, alpha: $alpha)',
      );
    }
  }

  sw.writeln('        }');
  sw.writeln('    }');
  sw.writeln('}');
  sw.writeln('#endif');

  await outputFile.writeAsString(sw.toString());

  stdout.writeln('✅ Swift tokens 已生成：');
  stdout.writeln('   路徑：$outputPath');
  stdout.writeln('   tokens: ${tokens.length} 個 UIColor 入口');
  stdout.writeln('   groups: ${grouped.length} 個分組');
}

/// 從 BridgeDS class 提取所有 tokens (name -> Color(0xFF...))
Map<String, String> _extractTokens() {
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

  final result = <String, String>{};
  for (final m in pattern.allMatches(bdBody)) {
    result[m.group(1)!] = m.group(2)!;
  }
  return result;
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
    final tokensStr = match.group(3)!;

    final tokens = tokensStr
        .split(',')
        .map((s) => s.trim().replaceAll("'", '').replaceAll(',', ''))
        .where((s) => s.isNotEmpty)
        .toList();

    groups.add({
      'name': name,
      'tokens': tokens,
    });
  }

  return groups;
}

/// 把 hex String 轉成 [r, g, b] 三個 0.0–1.0 double 字串（alpha 給 1.0）
List<String> _hexToRgbComponents(String hex) {
  var cleaned = hex.replaceFirst('0x', '');
  if (cleaned.length != 8) {
    return ['0', '0', '0'];
  }
  // 不動 alpha，直接抓後 6 位 RGB
  cleaned = cleaned.substring(2);
  final r = int.parse(cleaned.substring(0, 2), radix: 16);
  final g = int.parse(cleaned.substring(2, 4), radix: 16);
  final b = int.parse(cleaned.substring(4, 6), radix: 16);

  return [
    _toSwiftDouble(r),
    _toSwiftDouble(g),
    _toSwiftDouble(b),
  ];
}

/// 把 hex String 轉成 alpha float (0.0–1.0) 字串
String _hexToAlphaFloat(String hex) {
  var cleaned = hex.replaceFirst('0x', '');
  if (cleaned.length != 8) return '1.0';
  final alpha = int.parse(cleaned.substring(0, 2), radix: 16);
  return (alpha / 255.0).toStringAsFixed(3);
}

/// 把 0–255 整數轉成 Swift 的 double 字串
String _toSwiftDouble(int value) {
  // 化為分數表示 (e.g. 7/255.0)
  final whole = value ~/ 255;
  final fraction = value % 255;
  if (fraction == 0) {
    return '$whole/255';
  }
  return '$value/255.0';
}

/// BridgeDS field `darkPanel` -> Swift case `.darkPanel`
String _tokenNameToCase(String name) {
  // Swift case 名稱要保留原駝峰
  return _camelToCamel(name); // 同名，直接用
}

String _camelToCamel(String name) {
  return name; // Already camelCase
}
