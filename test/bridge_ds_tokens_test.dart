import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/theme/bridge_ds_tokens.dart';

void main() {
  group('BridgeDS Token Groups', () {
    test('應該有 12 個分組', () {
      expect(BridgeDSTokenGroups.groups.length, 12);
    });

    test('所有 token 名稱不應重複', () {
      final all = BridgeDSTokenGroups.allTokens;
      expect(all.length, all.toSet().length,
          reason: 'token 名稱重複：'
              '${all.where((t) => all.where((x) => x == t).length > 1).toSet()}');
    });

    test('所有列出的 token 都應該在 known list 中', () {
      for (final token in BridgeDSTokenGroups.allTokens) {
        expect(_knownTokens.contains(token), true,
            reason: 'Token "$token" 未在 _knownTokens 列表');
      }
    });

    test('Surface 分組應有 6 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Surface',
      );
      expect(group.tokens.length, 6);
    });

    test('Text 分組應有 6 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Text',
      );
      expect(group.tokens.length, 6);
    });

    test('Border 分組應有 6 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Border',
      );
      expect(group.tokens.length, 6);
    });

    test('Accent 分組應有 12 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Accent',
      );
      expect(group.tokens.length, 12);
    });

    test('Status 分組應有 14 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Status',
      );
      expect(group.tokens.length, 14);
    });

    test('Tag 分組應有 10 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Tag',
      );
      expect(group.tokens.length, 10);
    });

    test('Background 分組應有 3 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Background',
      );
      expect(group.tokens.length, 3);
    });

    test('Node 分組應有 7 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Node',
      );
      expect(group.tokens.length, 7);
    });

    test('Particle 分組應有 5 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Particle',
      );
      expect(group.tokens.length, 5);
    });

    test('Grey 分組應有 6 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Grey',
      );
      expect(group.tokens.length, 6);
    });

    test('MaterialStandard 分組應有 6 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'MaterialStandard',
      );
      expect(group.tokens.length, 6);
    });

    test('Hint 分組應有 4 個 token', () {
      final group = BridgeDSTokenGroups.groups.firstWhere(
        (g) => g.name == 'Hint',
      );
      expect(group.tokens.length, 4);
    });

    test('所有 token 數量加總應為 85', () {
      expect(BridgeDSTokenGroups.totalTokens, 85);
    });

    test('findGroup 應能找到已知 token', () {
      expect(BridgeDSTokenGroups.findGroup('canvas')!.name, 'Surface');
      expect(BridgeDSTokenGroups.findGroup('textPrimary')!.name, 'Text');
      expect(BridgeDSTokenGroups.findGroup('accentRed')!.name, 'Accent');
    });

    test('findGroup 對未知 token 應回傳 null', () {
      expect(BridgeDSTokenGroups.findGroup('unknown_token'), isNull);
    });
  });
}

/// 86 個 BridgeDS tokens 完整列表
/// （來源：lib/theme/bridge_design_system.dart BridgeDS class）
const Set<String> _knownTokens = {
  // Surface (6)
  'canvas', 'surface', 'surfaceElevated', 'surfaceHover',
  'darkPanel', 'darkCanvas',
  // Text (6)
  'textPrimary', 'textSecondary', 'textTertiary',
  'textMuted', 'textQuaternary', 'textOnAccent',
  // Border (6)
  'borderSubtle', 'borderDefault', 'borderStrong',
  'surfaceGlass', 'surfaceGlassHover', 'dividerIndigo',
  // Accent (12)
  'accentRed', 'accentBlue', 'accentGreen', 'accentYellow',
  'accentPurple', 'accentNavy', 'accentMagenta',
  'accentRuby', 'accentMiro',
  'toolPurple', 'toolPurpleLight',
  'brightCyan', 'goldAccent',
  // Status (13)
  'successGreen', 'successDark', 'softGreen',
  'errorRed', 'alertRed',
  'red500', 'red400', 'red700mat', 'red700', 'berlinRed',
  'green500', 'green400', 'green700',
  // Tag (10)
  'tagSuccessBg', 'tagSuccessFg',
  'tagErrorBg', 'tagErrorFg',
  'tagInfoBg', 'tagInfoFg',
  'tagBrainBg', 'tagBrainFg',
  'tagWarnBg', 'tagWarnFg',
  // Background (3)
  'bgLightRed', 'bgLightGreen', 'bgVeryLightRed',
  // Node (7)
  'fileBlue', 'sopOrange', 'pinkAccent',
  'slate', 'teal', 'deepPurple',
  'lightBlue',
  // Particle (5)
  'particle1', 'particle2', 'particle3', 'particle4', 'particleGlow',
  // Grey (6)
  'grey300', 'grey400', 'grey600', 'grey700', 'grey800',
  'lightGray',
  // MaterialStandard (6)
  'blue500', 'blue700',
  'orangeStd', 'orange500', 'orange700', 'orange300',
  // Hint (4)
  'hintPurple', 'hintPink', 'googleBlue', 'infoBlue',
};
