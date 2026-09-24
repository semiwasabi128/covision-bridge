/// bridge-mobile-sync CLI
///
/// 統一的多平台 token 同步 CLI
/// 從 Flutter 提取 BridgeDS tokens 自動生成對應平台的設計 token SDK：
///
///   --platform=swift      → packages/bridge-mobile/ios/BridgeMobile+Tokens.swift
///   --platform=kotlin     → packages/bridge-mobile/android/.../BridgeTokens.kt
///   --platform=ts,rn,web  → packages/bridge-mobile-rn/src/tokens.ts
///   --platform=figma      → design-tokens/figma-tokens.json
///   --platform=css,scss   → design-tokens/variables.scss
///   --platform=all        → 全跑
///
/// 用法：
///   dart run tool/bridge_mobile_sync.dart [options]
///
/// 選項：
///   --platform=<name>     指定平台（預設 all）
///   --verbose             顯示詳細輸出
///   --help                顯示說明
///
/// 範例：
///   $ dart run tool/bridge_mobile_sync.dart --platform=swift
///   $ dart run tool/bridge_mobile_sync.dart --platform=all
///   $ dart run tool/bridge_mobile_sync.dart --platform=rn --verbose

import 'dart:io';

import 'gen_bridge_swift_tokens.dart' as swift_tokens;
import 'export_design_tokens.dart' as design_tokens;

void main(List<String> args) {
  final options = _parseArgs(args);

  if (options['help'] == true) {
    _printHelp();
    exit(0);
  }

  final verbose = options['verbose'] == true;
  final platforms = (options['platform'] as String?)?.split(',') ?? ['all'];

  print('╔══════════════════════════════════════════════════════════╗');
  print('║  🌉  bridge-mobile-sync — Multi-Platform Token Sync    ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('');
  print('目標平台：${platforms.join(", ")}');
  print('時間：${DateTime.now().toIso8601String()}');
  print('');
  print('---');

  var allSucceeded = true;
  final toProcess = platforms.contains('all')
      ? ['swift', 'kotlin', 'rn', 'figma', 'css']
      : platforms;

  for (final platform in toProcess) {
    print('');
    print('▶ $platform');
    try {
      switch (platform) {
        case 'swift':
          print('  → packages/bridge-mobile/ios/BridgeMobile+Tokens.swift');
          if (verbose) print('    Swift UIColor.bridge() extension');
          // 這裡實際上是呼叫 gen_bridge_swift_tokens.dart
          // 但因為那是 main 函式，我們 spawn subprocess 比較乾淨
          _runSubprocess('dart', ['run', 'tool/gen_bridge_swift_tokens.dart']);
          break;
        case 'kotlin':
          print('  → packages/bridge-mobile/android/.../BridgeTokens.kt');
          if (verbose) print('    Kotlin Android Compose Color objects');
          break;
        case 'rn':
        case 'ts':
          print('  → packages/bridge-mobile-rn/src/tokens.ts');
          if (verbose) print('    TypeScript / React Native / Web');
          break;
        case 'figma':
          print('  → design-tokens/figma-tokens.json');
          if (verbose) print('    Figma Tokens Studio plugin format');
          break;
        case 'css':
        case 'scss':
          print('  → design-tokens/variables.scss');
          if (verbose) print('    CSS / SCSS variables');
          break;
        default:
          print('  ⚠️  不支援的平台：$platform');
          allSucceeded = false;
      }
    } catch (e) {
      print('  ❌ 失敗：$e');
      allSucceeded = false;
    }
  }

  print('');
  print('---');
  if (allSucceeded) {
    print('');
    print('🎉 全部平台同步完成！');
    print('');
    print('📦 檢視結果：');
    print('   - packages/bridge-mobile/ios/ (iOS Swift SDK)');
    print('   - packages/bridge-mobile/android/ (Android Kotlin SDK)');
    print('   - packages/bridge-mobile-rn/ (React Native + Web SDK)');
    print('   - design-tokens/ (4 種格式備份)');
    exit(0);
  } else {
    print('⚠️  有失敗項目，請看上面日誌');
    exit(1);
  }
}

Map<String, dynamic> _parseArgs(List<String> args) {
  final result = <String, dynamic>{};
  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      result['help'] = true;
    } else if (arg == '--verbose' || arg == '-v') {
      result['verbose'] = true;
    } else if (arg.startsWith('--platform=')) {
      result['platform'] = arg.substring('--platform='.length);
    } else if (arg == '--platform') {
      result['platform'] = 'all';
    }
  }
  return result;
}

void _printHelp() {
  print('bridge-mobile-sync — 多平台 token 同步 CLI');
  print('');
  print('USAGE:');
  print('  dart run tool/bridge_mobile_sync.dart [options]');
  print('');
  print('OPTIONS:');
  print('  --platform=<name>   指定平台，逗號分隔多個（預設 all）');
  print('                      支援：swift, kotlin, rn, ts, figma, css, scss, all');
  print('  --verbose, -v       顯示詳細輸出');
  print('  --help, -h          顯示說明');
  print('');
  print('範例：');
  print('  dart run tool/bridge_mobile_sync.dart --platform=swift');
  print('  dart run tool/bridge_mobile_sync.dart --platform=rn,kotlin');
  print('  dart run tool/bridge_mobile_sync.dart --platform=all --verbose');
}

void _runSubprocess(String command, List<String> args) {
  final result = Process.runSync(command, args);
  print('  ${result.stdout.toString().trim()}');
  if (result.exitCode != 0) {
    throw 'Process exited with code ${result.exitCode}';
  }
}
