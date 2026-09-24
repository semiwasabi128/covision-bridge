// lib/theme/tier_registry.dart
//
// [教練 Agent 2026-08-05] TierRegistry — manifest 載入器
//
// 載入 manifest.json 後做驗證：
//   1. 所有 token 名都必須存在於 BridgeDSColors
//   2. 所有 tier 都必須在 Tier enum 內
//   3. 每個 tier 的 textColor/bgColor/borderColor 都必須是合法 token 名
//
// 任一項失敗 → throw FormatException（編譯期錯誤）

import 'dart:convert';

import 'package:flutter/painting.dart';

import 'bridge_design_system.dart';
import 'tier.dart';
import 'tier_style.dart' show TierDefinition;

/// Tier 系統的 manifest 載入器
///
/// 一份 TierRegistry 對應一份主題包。
class TierRegistry {
  /// manifest 內的 token 對應（token 名 → 解析後的 Color）
  final Map<String, Color> tokens;

  /// manifest 內的 tier 對應（tier key → TierDefinition）
  final Map<String, TierDefinition> tiers;

  /// 字型設定
  final Map<String, String> fonts;

  /// metadata
  final String id;
  final String name;
  final String author;
  final String license;

  const TierRegistry({
    required this.id,
    required this.name,
    required this.author,
    required this.license,
    required this.tokens,
    required this.tiers,
    required this.fonts,
  });

  /// 從 manifest JSON 字串載入
  ///
  /// 自動做驗證：
  /// - 所有 token 必須在 BridgeDSColors 內
  /// - 所有 tier key 必須在 Tier enum 內
  /// - 每個 tier 的 color reference 必須是合法 token 名
  factory TierRegistry.fromManifestString(String manifestJson) {
    final json = jsonDecode(manifestJson) as Map<String, dynamic>;
    return TierRegistry.fromJson(json);
  }

  factory TierRegistry.fromJson(Map<String, dynamic> json) {
    // 1. 解析 metadata
    final meta = _parseMetadata(json);

    // 2. 解析 fonts
    final fonts = _parseFonts(json['fonts'] as Map<String, dynamic>?);

    // 3. 解析 tokens + 驗證
    final rawTokens = json['tokens'] as Map<String, dynamic>?;
    if (rawTokens == null) {
      throw const FormatException('manifest 缺少 "tokens" 區塊');
    }
    final tokens = _parseAndValidateTokens(rawTokens);

    // 4. 解析 tiers + 驗證
    final rawTiers = json['tiers'] as Map<String, dynamic>?;
    if (rawTiers == null) {
      throw const FormatException('manifest 缺少 "tiers" 區塊');
    }
    final tiers = _parseAndValidateTiers(rawTiers, tokens);

    return TierRegistry(
      id: meta['id']!,
      name: meta['name']!,
      author: meta['author']!,
      license: meta['license']!,
      tokens: tokens,
      tiers: tiers,
      fonts: fonts,
    );
  }

  static Map<String, String> _parseMetadata(Map<String, dynamic> json) {
    final required = ['id', 'name', 'author', 'license'];
    for (final key in required) {
      if (json[key] == null) {
        throw FormatException('manifest 缺少必要 metadata: "$key"');
      }
    }
    return {
      'id': json['id'] as String,
      'name': json['name'] as String,
      'author': json['author'] as String,
      'license': json['license'] as String,
    };
  }

  static Map<String, String> _parseFonts(Map<String, dynamic>? json) {
    if (json == null) return {};
    return json.map((key, value) => MapEntry(key, value.toString()));
  }

  /// 解析 token 並驗證每個 token 名都存在於 BridgeDSColors
  static Map<String, Color> _parseAndValidateTokens(
      Map<String, dynamic> rawTokens) {
    final result = <String, Color>{};

    // 列出所有合法的 token 名（從 BridgeDSColors 靜態常數抓）
    final validTokenNames = _getValidTokenNames();

    for (final entry in rawTokens.entries) {
      final tokenName = entry.key;
      if (!validTokenNames.contains(tokenName)) {
        throw FormatException(
          'manifest tokens 區塊包含未知的 token: "$tokenName"。\n'
          '合法的 token 名: ${validTokenNames.join(", ")}',
        );
      }
      final hex = entry.value as String;
      result[tokenName] = _parseHexColor(hex);
    }

    return result;
  }

  /// 從 BridgeDSColors 抓出所有 static const Color token 名
  ///
  /// 這裡 hardcode 是必要的（Flutter 沒有 reflection 列出 static fields）
  static Set<String> _getValidTokenNames() {
    return {
      'canvas',
      'surface',
      'surfaceElevated',
      'surfaceHover',
      'borderSubtle',
      'borderDefault',
      'textPrimary',
      'textSecondary',
      'textMuted',
      'accentBlue',
      'accentPurple',
      'accentGreen',
      'accentYellow',
      'accentRed',
      'accentNavy',
      'accentMagenta',
      'accentRuby',
      'accentMiro',
      'success',
      'warning',
      'error',
      'info',
    };
  }

  /// 解析 tiers + 驗證每個 tier key 在 Tier enum 內 + 每個 color ref 是合法 token
  static Map<String, TierDefinition> _parseAndValidateTiers(
    Map<String, dynamic> rawTiers,
    Map<String, Color> tokens,
  ) {
    final result = <String, TierDefinition>{};
    final validTierKeys = Tier.all.map((t) => t.key).toSet();

    for (final entry in rawTiers.entries) {
      final tierKey = entry.key;
      if (!validTierKeys.contains(tierKey)) {
        throw FormatException(
          'manifest tiers 區塊包含未知的 tier: "$tierKey"。\n'
          '合法的 tier key: ${validTierKeys.join(", ")}',
        );
      }

      final defJson = entry.value as Map<String, dynamic>;
      final def = TierDefinition.fromJson(defJson);

      // 驗證每個 color reference 都指向合法 token
      _validateColorRef(def.textColor, 'textColor', tierKey, tokens);
      _validateColorRef(def.bgColor, 'bgColor', tierKey, tokens);
      _validateColorRef(def.borderColor, 'borderColor', tierKey, tokens);

      result[tierKey] = def;
    }

    return result;
  }

  static void _validateColorRef(
    String? colorRef,
    String fieldName,
    String tierKey,
    Map<String, Color> tokens,
  ) {
    if (colorRef == null) return;
    if (!tokens.containsKey(colorRef)) {
      throw FormatException(
        'tier "$tierKey" 的 $fieldName 指向不存在的 token: "$colorRef"。\n'
        'manifest 的 tokens 區塊必須包含 "$colorRef"。',
      );
    }
  }

  /// 解析 hex 顏色 (#RRGGBB 或 #AARRGGBB)
  static Color _parseHexColor(String hex) {
    var clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      clean = 'FF$clean'; // 加 alpha
    }
    if (clean.length != 8) {
      throw FormatException(
        '顏色格式錯誤: "$hex"。應為 #RRGGBB 或 #AARRGGBB。',
      );
    }
    final value = int.tryParse(clean, radix: 16);
    if (value == null) {
      throw FormatException('顏色格式錯誤: "$hex"。');
    }
    return Color(value);
  }

  @override
  String toString() =>
      'TierRegistry(id: $id, name: $name, tiers: ${tiers.length})';
}

/// 從 BridgeDSColors 取實際顏色值的 helper
///
/// manifest 載入時用來解析 token 的 fallback 值。
/// 但通常 manifest 的 token 值優先（社群可以覆寫）。
class TokenResolver {
  /// 從 BridgeDSColors 取得預設 token 值（深色主題）
  static Color defaultValue(String tokenName) {
    // [教練 Agent 2026-08-05] Step 3c 修補 — 用 BridgeDSColors.dark.xxx 拿值
    // 之前寫成 BridgeDSColors.xxx（誤當 static），但實際是 instance field
    const dark = BridgeDSColors.dark;
    switch (tokenName) {
      case 'canvas':
        return dark.canvas;
      case 'surface':
        return dark.surface;
      case 'surfaceElevated':
        return dark.surfaceElevated;
      case 'surfaceHover':
        return dark.surfaceHover;
      case 'borderSubtle':
        return dark.borderSubtle;
      case 'borderDefault':
        return dark.borderDefault;
      case 'textPrimary':
        return dark.textPrimary;
      case 'textSecondary':
        return dark.textSecondary;
      case 'textMuted':
        return dark.textMuted;
      case 'accentBlue':
        return dark.accentBlue;
      case 'accentPurple':
        return dark.accentPurple;
      case 'accentGreen':
        return dark.accentGreen;
      case 'accentYellow':
        return dark.accentYellow;
      case 'accentRed':
        return dark.accentRed;
      case 'accentNavy':
        return dark.accentNavy;
      case 'accentMagenta':
        return dark.accentMagenta;
      case 'accentRuby':
        return dark.accentRuby;
      case 'accentMiro':
        return dark.accentMiro;
      // success/warning/error/info 沒有對應 instance field，用 accent alias
      case 'success':
        return dark.accentGreen;
      case 'warning':
        return dark.accentYellow;
      case 'error':
        return dark.accentRed;
      case 'info':
        return dark.accentBlue;
      default:
        throw StateError('未知的 token: $tokenName');
    }
  }
}