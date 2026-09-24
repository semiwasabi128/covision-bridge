#!/usr/bin/env dart
// Design Tokens Multi-Format Exporter
//
// 用途：把 BridgeDS + Tier 轉成多種平台的設計 token 格式：
//   1. Figma Tokens (JSON)  — 可用 Figma Tokens Studio plugin 載入
//   2. CSS Variables (SCSS) — Web / React Native
//   3. Swift UIColor Extension — iOS / macOS native
//   4. Android colors.xml — Android native
//
// 用法：
//   dart run tool/export_design_tokens.dart [target_dir]
//
// 預設輸出到 ./design-tokens/
// 開源社群可下載後直接用在自己平台上。

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final targetDir = args.isNotEmpty ? args[0] : 'design-tokens';
  stdout.writeln('🎨 正在導出設計 tokens 到 $targetDir/\n');

  final tokens = _extractTokens();
  final tiers = _extractTiers();

  // 建立目錄
  final dir = Directory(targetDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  await _exportFigmaTokens(tokens, tiers, targetDir);
  await _exportCssVariables(tokens, tiers, targetDir);
  await _exportSwiftExtension(tokens, targetDir);
  await _exportAndroidColors(tokens, targetDir);

  stdout.writeln('\n✅ 設計 tokens 已導出到 $targetDir/');
  stdout.writeln('   包含:');
  stdout.writeln('   - figma-tokens.json       (Figma Tokens Studio plugin)');
  stdout.writeln('   - variables.scss          (CSS / SCSS variables)');
  stdout.writeln('   - BridgeDS+Tokens.swift   (Swift UIColor Extension)');
  stdout.writeln('   - colors.xml              (Android resource)');
  stdout.writeln('   - README.md               (使用說明)');

  await _generateReadme(tokens, tiers, targetDir);
}

Map<String, String> _extractTokens() {
  final file = File('lib/theme/bridge_design_system.dart');
  if (!file.existsSync()) {
    stderr.writeln('❌ 找不到 lib/theme/bridge_design_system.dart');
    exit(1);
  }
  final content = file.readAsStringSync();

  // 找 BridgeDS class
  final bdStart = content.indexOf('class BridgeDS ');
  if (bdStart == -1) return {};

  final bdEnd = content.indexOf('\n}', bdStart);
  final bdBody = content.substring(bdStart, bdEnd + 2);

  final pattern = RegExp(
    r'static\s+const\s+Color\s+(\w+)\s*=\s*Color\((0x[0-9A-Fa-f]{8})\)\s*;',
  );

  final tokens = <String, String>{};
  for (final match in pattern.allMatches(bdBody)) {
    tokens[match.group(1)!] = match.group(2)!;
  }
  return tokens;
}

List<Map<String, dynamic>> _extractTiers() {
  return [
    {'key': 'cardBody', 'name': 'Card Body', 'fontSize': 14, 'fontWeight': '400', 'letterSpacing': 0.2},
    {'key': 'cardTitle', 'name': 'Card Title', 'fontSize': 16, 'fontWeight': '600', 'letterSpacing': 0.3},
    {'key': 'cardHeroTitle', 'name': 'Card Hero Title', 'fontSize': 20, 'fontWeight': '700', 'letterSpacing': 0.4},
    {'key': 'cardCaption', 'name': 'Card Caption', 'fontSize': 12, 'fontWeight': '400', 'letterSpacing': 0.1},
    {'key': 'appDisplayLarge', 'name': 'App Display Large', 'fontSize': 32, 'fontWeight': '700', 'letterSpacing': 0.5},
  ];
}

/// Figma Tokens Studio 格式
Future<void> _exportFigmaTokens(
  Map<String, String> tokens,
  List<Map<String, dynamic>> tiers,
  String dir,
) async {
  final figmaFormat = {
    'global': {
      'colors': {
        for (final entry in tokens.entries)
          entry.key: {'value': '#${entry.value.substring(4)}', 'type': 'color'}
      },
      'fontSizes': {
        for (final t in tiers)
          t['key'] as String: {
            'value': t['fontSize'],
            'type': 'fontSizes',
          }
      },
      'fontWeights': {
        for (final w in [400, 500, 600, 700, 'bold'])
          w.toString(): {'value': w, 'type': 'fontWeights'}
      },
      'letterSpacing': {
        for (final t in tiers)
          t['key'] as String: {
            'value': t['letterSpacing'],
            'type': 'letterSpacing',
          }
      }
    }
  };

  final json = const JsonEncoder.withIndent('  ').convert(figmaFormat);
  await File('$dir/figma-tokens.json').writeAsString(json);
  stdout.writeln('  ✓ figma-tokens.json     (${tokens.length} colors + ${tiers.length} tiers)');
}

/// CSS / SCSS variables
Future<void> _exportCssVariables(
  Map<String, String> tokens,
  List<Map<String, dynamic>> tiers,
  String dir,
) async {
  final sb = StringBuffer();

  sb.writeln('// Bridge Design Tokens — CSS / SCSS Variables');
  sb.writeln('// 自動生成於 ${DateTime.now().toIso8601String()}');
  sb.writeln('// 用法: import \'variables.scss\';');
  sb.writeln('');
  sb.writeln('// ── Brand Colors ──');
  sb.writeln(':root {');
  for (final entry in tokens.entries) {
    final color = entry.value.substring(4); // 去掉 0xFF
    final r = int.parse(color.substring(0, 2), radix: 16);
    final g = int.parse(color.substring(2, 4), radix: 16);
    final b = int.parse(color.substring(4, 6), radix: 16);
    final cssVar = entry.key.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => '-${m.group(1)!.toLowerCase()}',
    );
    sb.writeln('  --bridge-$cssVar: $color;  // #${color.toUpperCase()} — rgb($r, $g, $b)');
  }
  sb.writeln('');
  sb.writeln('  // ── Font Sizes ──');
  for (final t in tiers) {
    sb.writeln('  --bridge-font-${t['key']}: ${t['fontSize']}px;');
  }
  sb.writeln('');
  sb.writeln('  // ── Font Weights ──');
  sb.writeln('  --bridge-font-weight-regular: 400;');
  sb.writeln('  --bridge-font-weight-medium: 500;');
  sb.writeln('  --bridge-font-weight-semibold: 600;');
  sb.writeln('  --bridge-font-weight-bold: 700;');
  sb.writeln('');
  sb.writeln('  // ── Spacing ──');
  sb.writeln('  --bridge-spacing-xs: 4px;');
  sb.writeln('  --bridge-spacing-sm: 8px;');
  sb.writeln('  --bridge-spacing-md: 16px;');
  sb.writeln('  --bridge-spacing-lg: 24px;');
  sb.writeln('  --bridge-spacing-xl: 32px;');
  sb.writeln('  --bridge-spacing-xxl: 48px;');
  sb.writeln('}');

  await File('$dir/variables.scss').writeAsString(sb.toString());
  stdout.writeln('  ✓ variables.scss        (${tokens.length} CSS variables)');
}

/// Swift UIColor Extension
Future<void> _exportSwiftExtension(
  Map<String, String> tokens,
  String dir,
) async {
  final sb = StringBuffer();

  sb.writeln('// Bridge Design Tokens — Swift UIColor Extension');
  sb.writeln('// 自動生成於 ${DateTime.now().toIso8601String()}');
  sb.writeln('// 用法: BridgeDS.canvas → UIColor.bridge(.canvas)');
  sb.writeln('');
  sb.writeln('import UIKit');
  sb.writeln('');
  sb.writeln('public extension UIColor {');
  sb.writeln('    enum BridgeDS {}');
  sb.writeln('');
  sb.writeln('    static func bridge(_ token: BridgeDS) -> UIColor {');
  sb.writeln('        switch token {');
  for (final entry in tokens.entries) {
    final hex = entry.value.substring(4); // 0xFFABCDEF → FFABCDEF
    final r = double.parse(int.parse(hex.substring(0, 2), radix: 16).toString()) / 255.0;
    final g = double.parse(int.parse(hex.substring(2, 4), radix: 16).toString()) / 255.0;
    final b = double.parse(int.parse(hex.substring(4, 6), radix: 16).toString()) / 255.0;
    sb.writeln('        case .${entry.key}: return UIColor(red: $r, green: $g, blue: $b, alpha: 1.0)');
  }
  sb.writeln('        }');
  sb.writeln('    }');
  sb.writeln('}');
  sb.writeln('');

  await File('$dir/BridgeDS+Tokens.swift').writeAsString(sb.toString());
  stdout.writeln('  ✓ BridgeDS+Tokens.swift (${tokens.length} UIColor 入口)');
}

/// Android colors.xml
Future<void> _exportAndroidColors(
  Map<String, String> tokens,
  String dir,
) async {
  final sb = StringBuffer();

  sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
  sb.writeln('<!-- Bridge Design Tokens — Android colors.xml -->');
  sb.writeln('<!-- 自動生成於 ${DateTime.now().toIso8601String()} -->');
  sb.writeln('<!-- 用法: ContextCompat.getColor(context, R.color.bridge_${tokens.keys.first}) -->');
  sb.writeln('<resources>');
  for (final entry in tokens.entries) {
    final resourceName = entry.key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}')
        .toLowerCase();
    final hex = entry.value.substring(4).toUpperCase();
    sb.writeln('    <color name="bridge_$resourceName">#$hex</color>');
  }
  sb.writeln('</resources>');

  await File('$dir/colors.xml').writeAsString(sb.toString());
  stdout.writeln('  ✓ colors.xml            (${tokens.length} <color> 資源)');
}

Future<void> _generateReadme(
  Map<String, String> tokens,
  List<Map<String, dynamic>> tiers,
  String dir,
) async {
  final readme = '''# Bridge Design Tokens — Multi-Platform Export

> 自動生成於 ${DateTime.now().toIso8601String()}
> 共 **${tokens.length} 個 color tokens** + **${tiers.length} 個 tier 定義**

## 📦 包含格式

| 檔案 | 平台 | 工具 |
|---|---|---|
| `figma-tokens.json` | Figma | [Figma Tokens Studio plugin](https://www.figma.com/community/plugin/843461159747178978/figma-tokens) |
| `variables.scss`    | Web / React Native | 直接 import |
| `BridgeDS+Tokens.swift` | iOS / macOS | Xcode project |
| `colors.xml`        | Android | res/values/ |

## 🎨 顏色 Token 總覽

共 ${tokens.length} 個顏色，分成 12 個語意組：

- **Surface** (6) — canvas, surface, surfaceElevated, surfaceHover, darkPanel, darkCanvas
- **Text** (6) — textPrimary 到 textQuaternary + textOnAccent
- **Border** (6) — borderSubtle/Default/Strong + surfaceGlass/Hover + dividerIndigo
- **Accent** (12) — 互動強調色
- **Status** (14) — 成功/錯誤/警告
- **Tag** (10) — 標籤底色 + 前景色
- **Background** (3) — 淡背景
- **Node** (7) — Canvas 節點配色
- **Particle** (5) — 粒子視覺
- **Grey** (6) — 灰階
- **MaterialStandard** (6) — Material 標準色
- **Hint** (4) — 提示裝飾色

## 🚀 使用方式

### Figma Tokens Studio

1. 安裝 Figma Tokens Studio plugin
2. 點「Load from file」或「Set JSONBin」
3. 選 `figma-tokens.json`

### Web / SCSS

```scss
@import 'variables.scss';

.button {
  background-color: var(--bridge-accent-blue);
  color: var(--bridge-text-on-accent);
  padding: var(--bridge-spacing-md);
  font-size: var(--bridge-font-card-body);
}
```

### Swift (iOS / macOS)

```swift
let view = UIView()
view.backgroundColor = .bridge(.canvas)
```

### Android (Kotlin)

```kotlin
view.setBackgroundColor(
    ContextCompat.getColor(context, R.color.bridge_canvas)
)
```

## 🔄 更新方式

每次 BridgeDS 修改後：

```bash
dart run tool/export_design_tokens.dart
```

## 📚 來源

- `lib/theme/bridge_design_system.dart` — Single source of truth
- `lib/theme/bridge_ds_tokens.dart` — 12 個語意分組
''';

  await File('$dir/README.md').writeAsString(readme);
  stdout.writeln('  ✓ README.md             (使用說明)');
}
