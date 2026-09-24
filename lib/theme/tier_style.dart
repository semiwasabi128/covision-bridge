// lib/theme/tier_style.dart
//
// [教練 Agent 2026-08-05] TierStyle API — 給 widget 用的 tier 查詢介面
//
// 三大防呆實作：
//   1. textColor/bgColor/borderColor 只接受 String token 名（編譯期禁 Color）
//   2. TierManifest.load() 編譯期驗證所有 token 名存在
//   3. TierStyle.of() 未定義的 tier → throw StateError
//
// 使用範例：
//   final style = TierStyle.of(context, Tier.list.item.title);
//   Text('hello', style: style.toTextStyle(context));
//   Container(decoration: TierStyle.of(context, Tier.bg.panel.base).toBoxDecoration());

import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'bridge_design_system.dart'; // [D002 2026-08-10] BridgeDSColors
import 'tier.dart';
import 'tier_registry.dart';

/// Tier 的完整型別設定（解析後的最終值）
@immutable
class TierStyle {
  /// 字色（已解析為實際 Color）
  final Color? textColor;

  /// 背景色（已解析為實際 Color）
  final Color? bgColor;

  /// 邊框色（已解析為實際 Color）
  final Color? borderColor;

  /// 字級
  final double? fontSize;

  /// 字重
  final FontWeight? fontWeight;

  /// 字型 family 名（對應 manifest.fonts.base/mono）
  final String? fontFamily;

  /// 行高
  final double? lineHeight;

  /// 邊框寬度
  final double? borderWidth;

  /// 邊框圓角
  final double? borderRadius;

  const TierStyle({
    this.textColor,
    this.bgColor,
    this.borderColor,
    this.fontSize,
    this.fontWeight,
    this.fontFamily,
    this.lineHeight,
    this.borderWidth,
    this.borderRadius,
  });

  /// 從 BuildContext 取得指定 tier 的樣式
  ///
  /// [D002 2026-08-10] 動態解析——顏色跟隨 light/dark mode 切換
  /// 不再用 registry.tokens（載入時固定的 dark hex），而是從
  /// BridgeDSColors.of(context) 動態取得當前模式的顏色值
  static TierStyle of(BuildContext context, Tier tier) {
    final theme = Theme.of(context).extension<TierTheme>();
    if (theme == null) {
      throw StateError(
        'TierTheme not registered. Wrap your app with TierTheme.fromManifest(...).',
      );
    }
    final colors = BridgeDSColors.of(context);
    return theme.resolve(tier, colors: colors);
  }

  /// 轉成 Flutter TextStyle
  TextStyle toTextStyle({TextStyle? base}) {
    return (base ?? const TextStyle()).copyWith(
      color: textColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontFamily: fontFamily,
      height: lineHeight,
    );
  }

  /// 轉成 Flutter BoxDecoration
  BoxDecoration toBoxDecoration({BoxDecoration? base}) {
    return (base ?? const BoxDecoration()).copyWith(
      color: bgColor,
      border: borderColor != null && borderWidth != null
          ? Border.all(color: borderColor!, width: borderWidth!)
          : null,
      borderRadius: borderRadius != null
          ? BorderRadius.circular(borderRadius!)
          : null,
    );
  }

  @override
  String toString() =>
      'TierStyle(textColor: $textColor, fontSize: $fontSize, fontWeight: $fontWeight)';
}

/// ThemeExtension 包裝 TierRegistry，讓 Theme.of(context).extension<TierTheme>() 可用
@immutable
class TierTheme extends ThemeExtension<TierTheme> {
  final TierRegistry registry;

  const TierTheme({required this.registry});

  /// 從 manifest 載入
  factory TierTheme.fromManifest(TierRegistry registry) {
    return TierTheme(registry: registry);
  }

  /// 解析一個 tier（如果 manifest 沒定義該 tier → throw）
  ///
  /// [D002 2026-08-10] colors 參數：傳入當前模式的 BridgeDSColors
  /// 如果不傳，fallback 到 registry.tokens（dark hex）
  TierStyle resolve(Tier tier, {BridgeDSColors? colors}) {
    final definition = registry.tiers[tier.key];
    if (definition == null) {
      throw StateError(
        'Tier "$tier" 未在主題包 manifest 中定義。請在 tier manifest 加入 "$tier" 設定。',
      );
    }
    return _resolveStyle(definition, colors);
  }

  TierStyle _resolveStyle(TierDefinition def, [BridgeDSColors? colors]) {
    return TierStyle(
      textColor: def.textColor != null ? _lookupToken(def.textColor!, colors) : null,
      bgColor: def.bgColor != null ? _lookupToken(def.bgColor!, colors) : null,
      borderColor:
          def.borderColor != null ? _lookupToken(def.borderColor!, colors) : null,
      fontSize: def.fontSize,
      fontWeight: _parseFontWeight(def.fontWeight),
      fontFamily: def.fontFamily,
      lineHeight: def.lineHeight,
      borderWidth: def.borderWidth,
      borderRadius: def.borderRadius,
    );
  }

  Color _lookupToken(String tokenName, [BridgeDSColors? colors]) {
    // [D002 2026-08-10] 動態模式：從當前 BridgeDSColors 取值（light/dark mode 切換生效）
    if (colors != null) {
      final dynamicColor = _resolveFromBridgeDSColors(tokenName, colors);
      if (dynamicColor != null) return dynamicColor;
    }
    // fallback：manifest 載入時的固定值（dark hex）
    final token = registry.tokens[tokenName];
    if (token == null) {
      throw StateError(
        'Token "$tokenName" 不存在於 BridgeDSColors。'
        'Tier manifest 引用了不存在的 token。請檢查 manifest 的 tokens 區塊。',
      );
    }
    return token;
  }

  /// [D002 2026-08-10] 從 BridgeDSColors 動態取得 token 值
  /// 這是讓 Tier 系統跟隨 light/dark mode 切換的關鍵
  Color? _resolveFromBridgeDSColors(String tokenName, BridgeDSColors colors) {
    switch (tokenName) {
      case 'canvas':
        return colors.canvas;
      case 'surface':
        return colors.surface;
      case 'surfaceElevated':
        return colors.surfaceElevated;
      case 'surfaceHover':
        return colors.surfaceHover;
      case 'textPrimary':
        return colors.textPrimary;
      case 'textSecondary':
        return colors.textSecondary;
      case 'textTertiary':
        return colors.textTertiary;
      case 'textMuted':
        return colors.textMuted;
      case 'textQuaternary':
        return colors.textQuaternary;
      case 'accentRed':
        return colors.accentRed;
      case 'accentBlue':
        return colors.accentBlue;
      case 'accentGreen':
        return colors.accentGreen;
      case 'accentYellow':
        return colors.accentYellow;
      case 'accentPurple':
        return colors.accentPurple;
      case 'accentNavy':
        return colors.accentNavy;
      case 'accentMagenta':
        return colors.accentMagenta;
      case 'accentRuby':
        return colors.accentRuby;
      case 'accentMiro':
        return colors.accentMiro;
      case 'borderSubtle':
        return colors.borderSubtle;
      case 'borderDefault':
        return colors.borderDefault;
      case 'borderStrong':
        return colors.borderStrong;
      case 'success':
        return colors.accentGreen;
      case 'warning':
        return colors.accentYellow;
      case 'error':
        return colors.accentRed;
      case 'info':
        return colors.accentBlue;
      default:
        return null;
    }
  }

  FontWeight? _parseFontWeight(String? weight) {
    if (weight == null) return null;
    switch (weight.toLowerCase()) {
      case 'w100':
        return FontWeight.w100;
      case 'w200':
        return FontWeight.w200;
      case 'w300':
        return FontWeight.w300;
      case 'w400':
        return FontWeight.w400;
      case 'w500':
        return FontWeight.w500;
      case 'w600':
        return FontWeight.w600;
      case 'w700':
        return FontWeight.w700;
      case 'w800':
        return FontWeight.w800;
      case 'w900':
        return FontWeight.w900;
      default:
        throw StateError(
          '未知的 fontWeight: $weight。應為 w100-w900 之一。',
        );
    }
  }

  @override
  TierTheme copyWith({TierRegistry? registry}) {
    return TierTheme(registry: registry ?? this.registry);
  }

  @override
  TierTheme lerp(ThemeExtension<TierTheme>? other, double t) {
    // Tier 不做 lerp，切換主題時直接換掉
    return this;
  }
}

/// TierDefinition 是 manifest 內一筆 tier 設定的原始資料型別
///
/// 注意：textColor / bgColor / borderColor 都是 String（token 名），不是 Color
@immutable
class TierDefinition {
  final String? textColor;
  final String? bgColor;
  final String? borderColor;
  final double? fontSize;
  final String? fontWeight;
  final String? fontFamily;
  final double? lineHeight;
  final double? borderWidth;
  final double? borderRadius;

  const TierDefinition({
    this.textColor,
    this.bgColor,
    this.borderColor,
    this.fontSize,
    this.fontWeight,
    this.fontFamily,
    this.lineHeight,
    this.borderWidth,
    this.borderRadius,
  });

  factory TierDefinition.fromJson(Map<String, dynamic> json) {
    return TierDefinition(
      textColor: json['textColor'] as String?,
      bgColor: json['bgColor'] as String?,
      borderColor: json['borderColor'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontWeight: json['fontWeight'] as String?,
      fontFamily: json['fontFamily'] as String?,
      lineHeight: (json['lineHeight'] as num?)?.toDouble(),
      borderWidth: (json['borderWidth'] as num?)?.toDouble(),
      borderRadius: (json['borderRadius'] as num?)?.toDouble(),
    );
  }
}

/// [教練 Agent 2026-08-05] Step 3c — 載入預設 tier manifest 並包成 TierTheme
///
/// 從 Flutter asset (`assets/theme_packs/bridge_default_v2.json`) 載入預設 manifest，
/// 然後包成 ThemeExtension。給 MaterialApp.theme.extensions 用。
///
/// 使用方式（在 app.dart）：
/// ```dart
/// extensions: [await loadDefaultTierTheme()],
/// ```
/// 記憶化：主題包是不可變資產，全 App 只該載一次。
/// 額外修正 flutter_test 環境的跨測試卡死——同一 test 檔內第二個
/// testWidgets 再呼叫 rootBundle.loadString 時，FakeAsync 環境下
/// platform message 永遠不回來（曾讓多個測試檔 600s hang）。
Future<TierTheme>? _cachedTierThemeFuture;
final Object _cachedTierThemeLock = Object();

Future<TierTheme> loadDefaultTierTheme() async {
  final cached = _cachedTierThemeFuture;
  if (cached != null) {
    return cached;
  }
  // 先佔位再載入：並發呼叫共享同一個 Future，避免重複載入/競態。
  final completer = Completer<TierTheme>();
  _cachedTierThemeFuture = completer.future;
  try {
    const assetPath = 'assets/theme_packs/bridge_default_v2.json';
    final manifestString = await rootBundle.loadString(assetPath);
    final registry = TierRegistry.fromManifestString(manifestString);
    final theme = TierTheme.fromManifest(registry);
    completer.complete(theme);
    return theme;
  } catch (e, s) {
    // 載入失敗要清快取，否則之後永遠拿到壞 Future
    _cachedTierThemeFuture = null;
    completer.completeError(e, s);
    rethrow;
  }
}

/// [教練 Agent 2026-08-05] Step 4 推廣 — 從 Tier 拿 base style 後覆寫字級/字重
///
/// 用途：當設計師調整 Tier 樣式時，這個 helper 讓 widget 既能遵守 Tier
/// 語意歸類，又能覆寫特殊字級/字重（不歸類到標準 tier）。
///
/// 範例：
/// ```dart
/// // 想要 card.title 的顏色 + textPrimary，但 fontSize 18 + w900
/// style: tierBasedStyle(
///   context,
///   Tier.cardTitle,
///   fontSize: 18,
///   fontWeight: FontWeight.w900,
/// ),
/// ```
TextStyle tierBasedStyle(
  BuildContext context,
  Tier tier, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  final base = TierStyle.of(context, tier).toTextStyle();
  return base.copyWith(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}