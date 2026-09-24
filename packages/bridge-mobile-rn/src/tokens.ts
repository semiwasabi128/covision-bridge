// Bridge Design Tokens — 85 colors (TypeScript / RN / Web)
// 自動生成於 2026-08-06，從 lib/theme/bridge_design_system.dart 提取
//
// 用法：
//   import { BridgeTokens, bridgeToken } from '@bridge/mobile'
//   backgroundColor: BridgeTokens.canvas
//   color: bridgeToken('textPrimary', 0.7)  // 帶 alpha

export type HexColor = string; // e.g. '#07080A' or '#FF07080A'

export type BridgeTokenName =
  // Surface (6)
  | 'canvas' | 'surface' | 'surfaceElevated' | 'surfaceHover'
  | 'darkPanel' | 'darkCanvas'
  // Text (6)
  | 'textPrimary' | 'textSecondary' | 'textTertiary' | 'textMuted'
  | 'textQuaternary' | 'textOnAccent'
  // Border (6)
  | 'borderSubtle' | 'borderDefault' | 'borderStrong'
  | 'surfaceGlass' | 'surfaceGlassHover' | 'dividerIndigo'
  // Accent (12)
  | 'accentRed' | 'accentBlue' | 'accentGreen' | 'accentYellow' | 'accentPurple'
  | 'accentNavy' | 'accentMagenta' | 'accentMiro' | 'toolPurple' | 'toolPurpleLight'
  | 'brightCyan' | 'goldAccent'
  // Status (14)
  | 'successGreen' | 'successDark' | 'softGreen' | 'berlinRed'
  | 'errorRed' | 'alertRed' | 'red500' | 'red400' | 'red700mat' | 'red700'
  | 'green500' | 'green400' | 'green700' | 'soft'
  // Tag (10)
  | 'tagSuccessBg' | 'tagSuccessFg' | 'tagErrorBg' | 'tagErrorFg'
  | 'tagInfoBg' | 'tagInfoFg' | 'tagBrainBg' | 'tagBrainFg'
  | 'tagWarnBg' | 'tagWarnFg'
  // Background (3)
  | 'bgLightRed' | 'bgLightGreen' | 'bgVeryLightRed'
  // Node (7)
  | 'fileBlue' | 'sopOrange' | 'pinkAccent' | 'slate' | 'teal' | 'deepPurple' | 'lightBlue'
  // Particle (5)
  | 'particle1' | 'particle2' | 'particle3' | 'particle4' | 'particleGlow'
  // Grey (6)
  | 'grey300' | 'grey400' | 'grey600' | 'grey700' | 'grey800' | 'lightGray'
  // MaterialStd (6)
  | 'blue500' | 'blue700' | 'orangeStd' | 'orange500' | 'orange700' | 'orange300'
  // Hint (4)
  | 'hintPurple' | 'hintPink' | 'googleBlue' | 'infoBlue';

export const BridgeTokens: Record<BridgeTokenName, HexColor> = {
  // ── Surface ──
  canvas: '#07080A',
  surface: '#101111',
  surfaceElevated: '#1B1C1E',
  surfaceHover: '#252829',
  darkPanel: '#181922',
  darkCanvas: '#0B0C0E',

  // ── Text ──
  textPrimary: '#F9F9F9',
  textSecondary: '#CECECE',
  textTertiary: '#9C9C9D',
  textMuted: '#6A6B6C',
  textQuaternary: '#434345',
  textOnAccent: '#FFFFFF',

  // ── Border ──
  borderSubtle: '#0DFFFFFF',   // 0x0F alpha
  borderDefault: '#1AFFFFFF',  // 0x1A alpha
  borderStrong: '#33FFFFFF',   // 0x33 alpha
  surfaceGlass: '#0DFFFFFF',   // 0x0D alpha
  surfaceGlassHover: '#14FFFFFF', // 0x14 alpha
  dividerIndigo: '#2A2A4A',

  // ── Accent ──
  accentRed: '#FF6363',
  accentBlue: '#55B3FF',
  accentGreen: '#5FC992',
  accentYellow: '#FFBC33',
  accentPurple: '#533AFD',
  accentNavy: '#061B31',
  accentMagenta: '#F96BEE',
  accentMiro: '#5B76FE',
  toolPurple: '#7C4DFF',
  toolPurpleLight: '#B388FF',
  brightCyan: '#00D4FF',
  goldAccent: '#FFD700',

  // ── Status ──
  successGreen: '#6B8E6B',
  successDark: '#2E7D32',
  softGreen: '#81C784',
  berlinRed: '#C8102E',
  errorRed: '#EF5350',
  alertRed: '#FF1744',
  red500: '#F44336',
  red400: '#EF5350',
  red700mat: '#D32F2F',
  red700: '#D32F2F',
  green500: '#4CAF50',
  green400: '#66BB6A',
  green700: '#388E3C',
  soft: '#8B5CF6',

  // ── Tag ──
  tagSuccessBg: '#0E1B12', // 0x14 alpha deep
  tagSuccessFg: '#B8E8CC',
  tagErrorBg: '#1B0E0E',
  tagErrorFg: '#FFADAD',
  tagInfoBg: '#0E151B',
  tagInfoFg: '#B3DCFF',
  tagBrainBg: '#0E0A1B',
  tagBrainFg: '#B9B9F9',
  tagWarnBg: '#1B160E',
  tagWarnFg: '#FFD580',

  // ── Background ──
  bgLightRed: '#FFF3F2',
  bgLightGreen: '#F1F8E9',
  bgVeryLightRed: '#FFF8F7',

  // ── Node ──
  fileBlue: '#4A9EFF',
  sopOrange: '#FFB454',
  pinkAccent: '#FF6B9D',
  slate: '#8E9AAF',
  teal: '#4ECDC4',
  deepPurple: '#7C89FF',
  lightBlue: '#42A5F5',

  // ── Particle ──
  particle1: '#533AFD',
  particle2: '#F96BEE',
  particle3: '#55B3FF',
  particle4: '#5FC992',
  particleGlow: '#40533AFD', // 0x40 alpha

  // ── Grey ──
  grey300: '#E0E0E0',
  grey400: '#BDBDBD',
  grey600: '#757575',
  grey700: '#616161',
  grey800: '#424242',
  lightGray: '#E0E0E0',

  // ── MaterialStandard ──
  blue500: '#2196F3',
  blue700: '#1976D2',
  orangeStd: '#FF9800',
  orange500: '#FF9800',
  orange700: '#F57C00',
  orange300: '#FFB74D',

  // ── Hint ──
  hintPurple: '#8888AA',
  hintPink: '#CE93D8',
  googleBlue: '#1A73E8',
  infoBlue: '#4A90D9',
};

/**
 * 把 hex string 從 8 位 RGBA 變成 React Native 可用的 rgba()
 * 因為 RN StyleSheet 對 8 位 hex 支援不一，轉 rgba() 較可靠
 */
export function bridgeToken(
  name: BridgeTokenName,
  opacity: number = 1.0,
): string {
  const hex = BridgeTokens[name];
  // 8 位 hex (#AABBCCDD): AA=alpha, BBCCDD=RGB
  if (hex.length === 9) {
    const a = parseInt(hex.slice(1, 3), 16) / 255;
    const r = parseInt(hex.slice(3, 5), 16);
    const g = parseInt(hex.slice(5, 7), 16);
    const b = parseInt(hex.slice(7, 9), 16);
    const finalAlpha = a * opacity;
    return `rgba(${r}, ${g}, ${b}, ${finalAlpha.toFixed(3)})`;
  }
  // 6 位 hex (#AABBCC): 純 RGB，套用 opacity
  if (opacity !== 1.0) {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${opacity.toFixed(3)})`;
  }
  return hex;
}

/**
 * 為 React Native StyleSheet 批次建立 tokens
 *
 * 用法：
 *   const colors = bridgeStyle(['canvas', 'textPrimary'])
 *   <View style={{ backgroundColor: colors.canvas }} />
 */
export function bridgeColors<K extends BridgeTokenName>(
  names: K[],
): Pick<Record<BridgeTokenName, HexColor>, K> {
  const result = {} as Pick<Record<BridgeTokenName, HexColor>, K>;
  for (const name of names) {
    result[name] = BridgeTokens[name];
  }
  return result;
}

/**
 * React Native StyleSheet helper
 * 用法：const styles = bridgeStyle(['bgCanvas': '#07080A', 'textPrimary': '#F9F9F9'])
 */
export function bridgeStyle(styles: Record<string, string | number>) {
  return styles;
}

// 統計 token 數
export const BRIDGE_TOKEN_COUNT = 85;
