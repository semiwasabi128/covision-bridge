// 橋樑 App — 全局主題與設計規範
// 設計風格：藍綠色調、白色背景、圓角卡片、簡潔現代
//
// 雙模式：lightTheme（預設）+ darkTheme（新增 2026-07-20）
// 漸進遷移：舊的 static const 仍為淺色值，新 widget 用 ThemeExtension

import 'package:flutter/material.dart';

/// AppThemeColors — 手機版 ThemeExtension for light/dark mode
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.accent,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.divider,
    required this.success,
    required this.warning,
    required this.error,
  });

  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color accent;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color surfaceHighlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color divider;
  final Color success;
  final Color warning;
  final Color error;

  /// 淺色 token（與舊 static const 一致）
  static const light = AppThemeColors(
    primary: Color(0xFF2A9D8F),
    primaryDark: Color(0xFF21867A),
    primaryLight: Color(0xFF4DBFB1),
    accent: Color(0xFF264653),
    secondary: Color(0xFFE9C46A),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF8F9FA),
    surfaceHighlight: Color(0xFFE8F5F3),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF6B7280),
    textMuted: Color(0xFF9CA3AF),
    border: Color(0xFFE5E7EB),
    divider: Color(0xFFF3F4F6),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFEF4444),
  );

  /// 暗色 token — 手機版專屬暗色，不是桌面 BridgeDS 暗色
  /// 背景用深藍灰，保留藍綠主色調但稍微提亮以適應暗底
  static const dark = AppThemeColors(
    primary: Color(0xFF4DBFB1),       // 主色提亮（暗底要亮）
    primaryDark: Color(0xFF2A9D8F),   // 原 primary 成為 dark
    primaryLight: Color(0xFF6BD4C6),  // 更亮
    accent: Color(0xFFB8D4DC),         // 深藍灰提亮
    secondary: Color(0xFFF0D178),      // 暖黃提亮
    background: Color(0xFF232830),     // 原 #1B2128 → 再提亮
    surface: Color(0xFF2D353D),        // 原 #252D36 → 再提亮
    surfaceHighlight: Color(0xFF353F4B), // 原 #2D3742 → 再提亮
    textPrimary: Color(0xFFD8DCE0),    // [教練 Agent 2026-08-12] 近白 → 灰白（不再銳利）
    textSecondary: Color(0xFFB0B6BD),
    textMuted: Color(0xFF787E85),
    border: Color(0xFF2D3640),         // 深灰邊框
    divider: Color(0xFF232B34),        // 更深分隔
    success: Color(0xFF34D399),        // 提亮
    warning: Color(0xFFFBBF24),        // 提亮
    error: Color(0xFFF87171),          // 提亮
  );

  static AppThemeColors of(BuildContext context) =>
      Theme.of(context).extension<AppThemeColors>() ?? light;

  @override
  AppThemeColors copyWith({
    Color? primary,
    Color? primaryDark,
    Color? primaryLight,
    Color? accent,
    Color? secondary,
    Color? background,
    Color? surface,
    Color? surfaceHighlight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? divider,
    Color? success,
    Color? warning,
    Color? error,
  }) {
    return AppThemeColors(
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryLight: primaryLight ?? this.primaryLight,
      accent: accent ?? this.accent,
      secondary: secondary ?? this.secondary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHighlight: surfaceHighlight ?? this.surfaceHighlight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  AppThemeColors lerp(AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHighlight: Color.lerp(surfaceHighlight, other.surfaceHighlight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

class AppTheme {
  // 核心色板
  static const Color primary = Color(0xFF2A9D8F); // 主色：藍綠
  static const Color primaryDark = Color(0xFF21867A); // 主色深
  static const Color primaryLight = Color(0xFF4DBFB1); // 主色淺
  static const Color accent = Color(0xFF264653); // 強調：深藍灰
  static const Color secondary = Color(0xFFE9C46A); // 次要：暖黃

  // 背景
  static const Color background = Color(0xFFFFFFFF); // 主背景白
  static const Color surface = Color(0xFFF8F9FA); // 卡片背景淺灰
  static const Color surfaceHighlight = Color(0xFFE8F5F3); // 強調淺綠

  // 文字
  static const Color textPrimary = Color(0xFF1A1A2E); // 主文字
  static const Color textSecondary = Color(0xFF6B7280); // 次要文字
  static const Color textMuted = Color(0xFF9CA3AF); // 弱化文字

  // 邊框與分隔
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF3F4F6);

  // 功能色
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // 漸層
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFFF0FDFB), Color(0xFFFFFFFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // 陰影
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.02),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  // 圓角
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double radiusXL = 24;

  // 間距
  static const double spacingXS = 4;
  static const double spacingS = 8;
  static const double spacingM = 16;
  static const double spacingL = 24;
  static const double spacingXL = 32;

  static const List<String> fontFallback = [
    'MaterialIcons',  // [教練 Agent 2026-07-30] 修復：Icon 圖示問號——必須在 BridgeCJK 前面，
                      // 否則 BridgeCJK 會先匹配到圖示碼點，用中文字型渲染成問號
    'BridgeCJK',
    'Arial Unicode MS',
    'PingFang TC',
    'PingFang SC',
    'Heiti TC',
    'STHeiti',
    'Noto Sans TC',
    'Noto Sans CJK TC',
    'Microsoft JhengHei',
  ];

  // 主題資料

  /// [小葵 2026-09-09 Blue 令] Material textTheme 對齊 Tier 尺寸表——
  /// M3 預設（bodyLarge 16/titleLarge 22/headlineSmall 24）整體偏大，
  /// 導致 PopupMenu/ListTile/SwitchListTile/Dialog 等用預設的元件
  /// 字級失控（Blue 回報「最大的字都有太大的問題」）。
  /// 尺寸邏輯：最小字 12（caption/meta）、一般 14（body）、卡片主文 16、
  /// 標題 18、大標 20——對齊 bridge_default_v2 tier manifest。
  static TextTheme _tierAlignedTextTheme(Color textPrimary) {
    const ff = fontFallback;
    return TextTheme(
      // display/headline：對話框大標題等（原 24-32 → 18-20）
      displaySmall: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      headlineLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      headlineMedium: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      headlineSmall: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      // title：原 titleLarge 22 → 16（與 card.title 對齊）
      titleLarge: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      titleMedium: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      titleSmall: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: ff),
      // body：原 bodyLarge 16 → 14
      bodyLarge: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary, fontFamilyFallback: ff),
      bodyMedium: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary, fontFamilyFallback: ff),
      bodySmall: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400, color: textPrimary, fontFamilyFallback: ff),
      // label：PopupMenu 選項、按鈕文字——原 labelLarge 14 維持
      labelLarge: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary, fontFamilyFallback: ff),
      labelMedium: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: textPrimary, fontFamilyFallback: ff),
      labelSmall: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, color: textPrimary, fontFamilyFallback: ff),
    );
  }

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'BridgeCJK',
    fontFamilyFallback: fontFallback,
    textTheme: _tierAlignedTextTheme(textPrimary),
    popupMenuTheme: PopupMenuThemeData(
      // [小葵 2026-09-09] PopupMenu 選項文字對齊 14——原預設偏大
      textStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary, fontFamilyFallback: fontFallback),
    ),
    listTileTheme: ListTileThemeData(
      // [小葵 2026-09-09] ListTile title 對齊 14
      titleTextStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary, fontFamilyFallback: fontFallback),
      subtitleTextStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400, color: textPrimary.withValues(alpha: 0.6), fontFamilyFallback: fontFallback),
    ),
    dialogTheme: DialogThemeData(
      // [小葵 2026-09-09] Dialog 標題對齊 18（原 titleLarge 22 過大）
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary, fontFamilyFallback: fontFallback),
      contentTextStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary, fontFamilyFallback: fontFallback),
    ),
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      surface: background,
      onSurface: textPrimary,
      error: error,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        fontFamilyFallback: fontFallback,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(48, 48), // [P1-14 修復 2026-06-30] 觸控區 ≥48pt
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48), // [P1-14] 觸控區 ≥48pt
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary, width: 1.5),
        minimumSize: const Size(48, 48), // [P1-14] 觸控區 ≥48pt
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        // [P1-14 修復 2026-06-30] 觸控區統一 48×48，icon 視覺仍 24px
        // 來源：Material Design 3 + Apple HIG + WCAG AAA 共識
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      // [教練 Agent 2026-08-05 Step 3b] 強制寫死黑色，確保 light theme 下 wizard 表單文字清楚
      // Material default theme 的 hintStyle/labelStyle 對比度不到 WCAG AA
      // [教練 Agent 2026-08-05 Step 3b] light theme 用 AppTheme.textPrimary（近黑）
      labelStyle: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        floatingLabelStyle: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        hintStyle: TextStyle(color: textPrimary),
      ),
      chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primary.withValues(alpha: 0.15),
      labelStyle: const TextStyle(fontSize: 13, color: textSecondary),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXL),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      color: background,
    ),
    extensions: [
      AppThemeColors.light,
    ],
  );

  // 主題資料（手機深色）
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'BridgeCJK',
    fontFamilyFallback: fontFallback,
    textTheme: _tierAlignedTextTheme(AppThemeColors.dark.textPrimary),
    popupMenuTheme: PopupMenuThemeData(
      textStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: AppThemeColors.dark.textPrimary, fontFamilyFallback: fontFallback),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: AppThemeColors.dark.textPrimary, fontFamilyFallback: fontFallback),
      subtitleTextStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400, color: AppThemeColors.dark.textPrimary.withValues(alpha: 0.6), fontFamilyFallback: fontFallback),
    ),
    dialogTheme: DialogThemeData(
      titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: AppThemeColors.dark.textPrimary, fontFamilyFallback: fontFallback),
      contentTextStyle: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400, color: AppThemeColors.dark.textPrimary, fontFamilyFallback: fontFallback),
    ),
    colorScheme: ColorScheme.dark(
      primary: AppThemeColors.dark.primary,
      onPrimary: Colors.black,
      secondary: AppThemeColors.dark.accent,
      surface: AppThemeColors.dark.surface,
      onSurface: AppThemeColors.dark.textPrimary,
      error: AppThemeColors.dark.error,
    ),
    scaffoldBackgroundColor: AppThemeColors.dark.background,
    appBarTheme: AppBarTheme(
      backgroundColor: AppThemeColors.dark.background,
      foregroundColor: AppThemeColors.dark.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppThemeColors.dark.textPrimary,
        fontFamilyFallback: fontFallback,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppThemeColors.dark.primary,
        foregroundColor: Colors.black,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppThemeColors.dark.primary,
        side: BorderSide(color: AppThemeColors.dark.primary, width: 1.5),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppThemeColors.dark.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(color: AppThemeColors.dark.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(color: AppThemeColors.dark.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(color: AppThemeColors.dark.primary, width: 2),
      ),
      // [教練 Agent 2026-08-05 Step 3b] dark theme 用 AppThemeColors.dark.textPrimary（近白）
      labelStyle: TextStyle(
        color: AppThemeColors.dark.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      floatingLabelStyle: TextStyle(
        color: AppThemeColors.dark.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      hintStyle: TextStyle(color: AppThemeColors.dark.textPrimary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppThemeColors.dark.surface,
      selectedColor: AppThemeColors.dark.primary.withValues(alpha: 0.25),
      labelStyle: TextStyle(fontSize: 13, color: AppThemeColors.dark.textSecondary),
      side: BorderSide(color: AppThemeColors.dark.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXL),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      color: AppThemeColors.dark.surface,
    ),
    extensions: [
      AppThemeColors.dark,
    ],
  );
}
