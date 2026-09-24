// BridgeDS Tokens 分組索引 — 階段 C/D 整合 (2026-08-05)
//
// 用途：把 85 個 BridgeDS static const Color token 依語意分組，方便：
//   1. 設計師查找（按用途找 token）
//   2. 驗證（確保各語意分類齊全）
//   3. 文件化（自動生成對照表）
//
// 實際 token 定義仍在 lib/theme/bridge_design_system.dart (BridgeDS class)
//
// 分組依據：V2 Canvas 視覺架構 + 階段 C/D 收斂成果

class BridgeDSTokenGroups {
  BridgeDSTokenGroups._();

  /// 🎨 所有 token 名稱列表（按分組）
  ///
  /// 用法：
  /// ```dart
  /// for (final group in BridgeDSTokenGroups.groups) {
  ///   print('${group.name}: ${group.tokens.length} tokens');
  /// }
  /// ```
  static const List<TokenGroup> groups = [
    // ── 1. Surface（畫布與表面）─────────────────────────
    TokenGroup(
      name: 'Surface',
      description: '畫布、容器、面板底色',
      tokens: [
        'canvas', 'surface', 'surfaceElevated', 'surfaceHover',
        'darkPanel', 'darkCanvas',
      ],
    ),

    // ── 2. Text（文字層級）──────────────────────────────
    TokenGroup(
      name: 'Text',
      description: '文字顏色（5 階 + 純白 + 純黑）',
      tokens: [
        'textPrimary', 'textSecondary', 'textTertiary',
        'textMuted', 'textQuaternary',
        'textOnAccent',
      ],
    ),

    // ── 3. Border（邊框）────────────────────────────────
    TokenGroup(
      name: 'Border',
      description: '邊框 + 半透明疊層',
      tokens: [
        'borderSubtle', 'borderDefault', 'borderStrong',
        'surfaceGlass', 'surfaceGlassHover',
        'dividerIndigo',
      ],
    ),

    // ── 4. Accent（互動強調）────────────────────────────
    TokenGroup(
      name: 'Accent',
      description: '語意化互動色（連結/CTA/焦點）',
      tokens: [
        'accentRed', 'accentBlue', 'accentYellow',
        'accentPurple', 'accentNavy', 'accentMagenta',
        'accentRuby', 'accentMiro',
        'toolPurple', 'toolPurpleLight',
        'brightCyan', 'goldAccent',
      ],
    ),

    // ── 5. Status（狀態色）──────────────────────────────
    TokenGroup(
      name: 'Status',
      description: '成功/錯誤/警告/提示（語意化）',
      tokens: [
        'successGreen', 'successDark', 'softGreen',
        'accentGreen',
        'errorRed', 'alertRed',
        'red500', 'red400', 'red700mat', 'red700', 'berlinRed',
        'green500', 'green400', 'green700',
      ],
    ),

    // ── 6. Tag（狀態標籤）────────────────────────────────
    TokenGroup(
      name: 'Tag',
      description: '狀態標籤專用底色 + 前景色',
      tokens: [
        'tagSuccessBg', 'tagSuccessFg',
        'tagErrorBg', 'tagErrorFg',
        'tagInfoBg', 'tagInfoFg',
        'tagBrainBg', 'tagBrainFg',
        'tagWarnBg', 'tagWarnFg',
      ],
    ),

    // ── 7. Background（背景）────────────────────────────
    TokenGroup(
      name: 'Background',
      description: '淡背景（成功/失敗/hover）',
      tokens: [
        'bgLightRed', 'bgLightGreen', 'bgVeryLightRed',
      ],
    ),

    // ── 8. Node（Canvas 節點配色）─────────────────────
    TokenGroup(
      name: 'Node',
      description: 'Canvas 節點類型對應色',
      tokens: [
        'fileBlue', 'sopOrange', 'pinkAccent',
        'slate', 'teal', 'deepPurple',
        'lightBlue',
      ],
    ),

    // ── 9. Particle（粒子視覺）────────────────────────
    TokenGroup(
      name: 'Particle',
      description: '大腦可視化粒子色',
      tokens: [
        'particle1', 'particle2', 'particle3', 'particle4', 'particleGlow',
      ],
    ),

    // ── 10. Grey（灰階）──────────────────────────────
    TokenGroup(
      name: 'Grey',
      description: '灰階（對應 Material grey.shadeXXX）',
      tokens: [
        'grey300', 'grey400', 'grey600', 'grey700', 'grey800',
        'lightGray',
      ],
    ),

    // ── 11. Material Standard（Material 標準色）────────
    TokenGroup(
      name: 'MaterialStandard',
      description: 'Material Design 標準色（500/400/700）',
      tokens: [
        'blue500', 'blue700',
        'orangeStd', 'orange500', 'orange700', 'orange300',
      ],
    ),

    // ── 12. Hint（提示色）────────────────────────────
    TokenGroup(
      name: 'Hint',
      description: '提示裝飾色',
      tokens: [
        'hintPurple', 'hintPink',
        'googleBlue', 'infoBlue',
      ],
    ),
  ];

  /// 取得總 token 數
  static int get totalTokens {
    return groups.fold(0, (sum, g) => sum + g.tokens.length);
  }

  /// 取得所有 token 名稱（flat list）
  static List<String> get allTokens {
    return groups.expand((g) => g.tokens).toList();
  }

  /// 透過 token 名稱查詢分組
  static TokenGroup? findGroup(String tokenName) {
    for (final g in groups) {
      if (g.tokens.contains(tokenName)) return g;
    }
    return null;
  }
}

/// Token 分組定義
class TokenGroup {
  const TokenGroup({
    required this.name,
    required this.description,
    required this.tokens,
  });

  /// 分組名稱（如 Surface, Text, Border...）
  final String name;

  /// 分組說明
  final String description;

  /// 此分組包含的 token 名稱
  final List<String> tokens;
}
