// lib/models/theme_pack.dart
//
// [教練 Agent 2026-08-04] ThemePack v1.0 — 對應「橋樑排版設計原則 v1.0」
//
// 主題包 = 一份可下載/匯入的設計資產包，內含：
//   - 30 個 BridgeDSColors token
//   - 可選字型覆寫（仍受 9 級距規則限制）
//   - preview 縮圖
//   - metadata（id, name, author, license）
//
// manifest.json 結構見 docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md §5.3

import 'dart:convert';

import 'package:flutter/painting.dart';

import '../theme/bridge_design_system.dart';

/// 主題包 metadata
class ThemePack {
  final String id;
  final String name;
  final String author;
  final String license;
  final String description;
  final String minBridgeVersion;
  final List<String> targetModes; // ['dark'] / ['light'] / ['dark', 'light']
  final String? previewImageBase64; // 可選預覽縮圖
  final Map<String, Color> colors; // 30 個 token
  final String? fontFamilyBase; // 可選
  final String? fontFamilyMono; // 可選
  final String? fontFileBase; // 相對路徑, ex: 'fonts/Inter-Regular.ttf'
  final String? fontFileMono;

  ThemePack({
    required this.id,
    required this.name,
    required this.author,
    required this.license,
    required this.description,
    required this.minBridgeVersion,
    required this.targetModes,
    required this.colors,
    this.previewImageBase64,
    this.fontFamilyBase,
    this.fontFamilyMono,
    this.fontFileBase,
    this.fontFileMono,
  });

  /// 從 manifest.json (Map) 解析
  factory ThemePack.fromManifestJson(Map<String, dynamic> json) {
    // 驗證必要欄位
    final required = ['id', 'name', 'author', 'license', 'colors'];
    for (final key in required) {
      if (!json.containsKey(key)) {
        throw FormatException('ThemePack manifest 缺少必要欄位: $key');
      }
    }

    // 解析 colors — 必須 30 個 token 全填
    final colorsJson = json['colors'] as Map<String, dynamic>;
    final colors = <String, Color>{};
    const requiredTokens = [
      'canvas', 'surface', 'surfaceElevated', 'surfaceHover',
      'textPrimary', 'textSecondary', 'textTertiary', 'textMuted', 'textQuaternary',
      'accentRed', 'accentBlue', 'accentGreen', 'accentYellow', 'accentPurple',
      'accentNavy', 'accentMagenta', 'accentRuby', 'accentMiro',
      'borderSubtle', 'borderDefault', 'borderStrong',
      'surfaceGlass', 'surfaceGlassHover',
      'tagSuccessBg', 'tagSuccessFg', 'tagErrorBg', 'tagErrorFg',
      'tagInfoBg', 'tagInfoFg', 'tagBrainBg', 'tagBrainFg',
      'tagWarnBg', 'tagWarnFg',
    ];
    for (final token in requiredTokens) {
      if (!colorsJson.containsKey(token)) {
        throw FormatException(
          'ThemePack manifest colors 缺少 token: $token（共需 ${requiredTokens.length} 個）',
        );
      }
      final hex = colorsJson[token] as String;
      colors[token] = _parseHexColor(hex);
    }

    // 解析 engine（可選）
    final engine = json['engine'] as Map<String, dynamic>?;
    final minVersion = engine?['min_bridge_version'] as String? ?? '1.0';
    final targetModes = (engine?['target_modes'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        ['dark', 'light'];

    // 解析 typography（可選）
    final typo = json['typography'] as Map<String, dynamic>?;
    final fontBase = typo?['fontFamilyBase'] as String?;
    final fontMono = typo?['fontFamilyMono'] as String?;
    final fontFileBase = typo?['fontFileBase'] as String?;
    final fontFileMono = typo?['fontFileMono'] as String?;

    return ThemePack(
      id: json['id'] as String,
      name: json['name'] as String,
      author: json['author'] as String,
      license: json['license'] as String,
      description: json['description'] as String? ?? '',
      minBridgeVersion: minVersion,
      targetModes: targetModes,
      colors: colors,
      fontFamilyBase: fontBase,
      fontFamilyMono: fontMono,
      fontFileBase: fontFileBase,
      fontFileMono: fontFileMono,
      previewImageBase64: json['preview_base64'] as String?,
    );
  }

  /// 轉成 manifest.json 字串
  String toManifestJsonString() {
    final colorsMap = <String, String>{};
    colors.forEach((k, v) {
      colorsMap[k] = _colorToHex(v);
    });

    final map = <String, Object>{
      'type': 'theme-pack',
      'version': '1.0',
      'id': id,
      'name': name,
      'author': author,
      'license': license,
      'description': description,
      'engine': <String, Object>{
        'min_bridge_version': minBridgeVersion,
        'target_modes': targetModes,
      },
      'colors': colorsMap,
    };
    if (fontFamilyBase != null || fontFamilyMono != null) {
      map['typography'] = {
        if (fontFamilyBase != null) 'fontFamilyBase': fontFamilyBase,
        if (fontFamilyMono != null) 'fontFamilyMono': fontFamilyMono,
        if (fontFileBase != null) 'fontFileBase': fontFileBase,
        if (fontFileMono != null) 'fontFileMono': fontFileMono,
      };
    }
    if (previewImageBase64 != null) {
      map['preview_base64'] = previewImageBase64!;
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 轉成 BridgeDSColors（套用到 App 主題用）
  BridgeDSColors toBridgeDSColors() {
    return BridgeDSColors(
      canvas: colors['canvas']!,
      surface: colors['surface']!,
      surfaceElevated: colors['surfaceElevated']!,
      surfaceHover: colors['surfaceHover']!,
      textPrimary: colors['textPrimary']!,
      textSecondary: colors['textSecondary']!,
      textTertiary: colors['textTertiary']!,
      textMuted: colors['textMuted']!,
      textQuaternary: colors['textQuaternary']!,
      accentRed: colors['accentRed']!,
      accentBlue: colors['accentBlue']!,
      accentGreen: colors['accentGreen']!,
      accentYellow: colors['accentYellow']!,
      accentPurple: colors['accentPurple']!,
      accentNavy: colors['accentNavy']!,
      accentMagenta: colors['accentMagenta']!,
      accentRuby: colors['accentRuby']!,
      accentMiro: colors['accentMiro']!,
      borderSubtle: colors['borderSubtle']!,
      borderDefault: colors['borderDefault']!,
      borderStrong: colors['borderStrong']!,
      surfaceGlass: colors['surfaceGlass']!,
      surfaceGlassHover: colors['surfaceGlassHover']!,
      tagSuccessBg: colors['tagSuccessBg']!,
      tagSuccessFg: colors['tagSuccessFg']!,
      tagErrorBg: colors['tagErrorBg']!,
      tagErrorFg: colors['tagErrorFg']!,
      tagInfoBg: colors['tagInfoBg']!,
      tagInfoFg: colors['tagInfoFg']!,
      tagBrainBg: colors['tagBrainBg']!,
      tagBrainFg: colors['tagBrainFg']!,
      tagWarnBg: colors['tagWarnBg']!,
      tagWarnFg: colors['tagWarnFg']!,
    );
  }

  /// 驗證設計鐵則（§5.6）
  /// 1. 30 token 全填（建構時已驗證）
  /// 2. WCAG AA 對比度（textPrimary vs canvas, textSecondary vs surface）
  List<String> validateDesignRules() {
    final violations = <String>[];

    final textPrimary = colors['textPrimary']!;
    final canvas = colors['canvas']!;
    final ratioTextCanvas = _contrastRatio(textPrimary, canvas);
    if (ratioTextCanvas < 4.5) {
      violations.add(
        'textPrimary 與 canvas 對比度 ${ratioTextCanvas.toStringAsFixed(2)}:1 '
        '低於 WCAG AA 4.5:1',
      );
    }

    final textSecondary = colors['textSecondary']!;
    final surface = colors['surface']!;
    final ratioTextSec = _contrastRatio(textSecondary, surface);
    if (ratioTextSec < 4.5) {
      violations.add(
        'textSecondary 與 surface 對比度 ${ratioTextSec.toStringAsFixed(2)}:1 '
        '低於 WCAG AA 4.5:1',
      );
    }

    return violations;
  }

  /// WCAG 對比度計算
  static double _contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a);
    final l2 = _relativeLuminance(b);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    double r = (color.r);
    double g = (color.g);
    double b = (color.b);
    final channels = [r, g, b];
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i];
      channels[i] = c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) * 2.4;
    }
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  }

  /// 解析 hex color (#RRGGBB 或 #AARRGGBB)
  static Color _parseHexColor(String hex) {
    var cleanHex = hex.replaceAll('#', '').toUpperCase();
    if (cleanHex.length == 6) {
      cleanHex = 'FF$cleanHex'; // 加 alpha
    }
    if (cleanHex.length != 8) {
      throw FormatException('無效的 hex color: $hex（需 #RRGGBB 或 #AARRGGBB）');
    }
    return Color(int.parse(cleanHex, radix: 16));
  }

  static String _colorToHex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    final a = (color.a * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$a$r$g$b'.toUpperCase();
  }

  @override
  String toString() => 'ThemePack($id, $name, by $author)';
}