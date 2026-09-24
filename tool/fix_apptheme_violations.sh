#!/usr/bin/env bash
# tool/fix_apptheme_violations.sh
#
# [小葵 2026-08-04] 把 AppTheme.xxx 改成 BridgeDSColors.of(context).xxx
#
# 對應表（基於 token 系統）：
#   AppTheme.primary        → BridgeDSColors.of(context).accentBlue
#   AppTheme.primaryDark    → BridgeDSColors.of(context).accentNavy
#   AppTheme.accent         → BridgeDSColors.of(context).accentNavy
#   AppTheme.secondary      → BridgeDSColors.of(context).accentYellow
#   AppTheme.textPrimary    → BridgeDSColors.of(context).textPrimary
#   AppTheme.textSecondary  → BridgeDSColors.of(context).textSecondary
#   AppTheme.textMuted      → BridgeDSColors.of(context).textMuted
#   AppTheme.warning        → BridgeDSColors.of(context).accentYellow
#   AppTheme.success        → BridgeDSColors.of(context).accentGreen
#   AppTheme.error          → BridgeDSColors.of(context).accentRed
#   AppTheme.background     → BridgeDSColors.of(context).canvas
#   AppTheme.surface        → BridgeDSColors.of(context).surface
#   AppTheme.border         → BridgeDSColors.of(context).borderSubtle
#   AppTheme.divider        → BridgeDSColors.of(context).borderSubtle

set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# 目標檔案（夥伴館 + 子頁面）
FILES=(
  "lib/screens/companion_list_screen.dart"
  "lib/screens/companion_create_screen.dart"
  "lib/screens/companion_appearance_screen.dart"
)

# 只處理「顏色相關」的 AppTheme.xxx
# 排除 spacingM, radiusLarge, cardShadow 等尺寸常數
COLOR_TOKENS=(
  "primary:accentBlue"
  "primaryDark:accentNavy"
  "accent:accentNavy"
  "secondary:accentYellow"
  "textPrimary:textPrimary"
  "textSecondary:textSecondary"
  "textMuted:textMuted"
  "warning:accentYellow"
  "success:accentGreen"
  "error:accentRed"
  "background:canvas"
  "surface:surface"
  "border:borderSubtle"
  "divider:borderSubtle"
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  echo "=== 處理 $f ==="
  BEFORE=$(grep -cE "AppTheme\.(primary|primaryDark|accent|secondary|textPrimary|textSecondary|textMuted|warning|success|error|background|surface|border|divider)\b" "$f" || echo 0)
  echo "  AppTheme 顏色違規: $BEFORE"

  for mapping in "${COLOR_TOKENS[@]}"; do
    src="${mapping%%:*}"
    dst="${mapping##*:}"
    # 只在 BuildContext 範圍內替換（保守做法：包含 "color:" 或 "backgroundColor:" 或 "foregroundColor:" 上下文）
    perl -i -pe "s{AppTheme\.${src}\b(?!\w)}{BridgeDSColors.of(context).${dst}}g" "$f"
  done

  AFTER=$(grep -cE "AppTheme\.(primary|primaryDark|accent|secondary|textPrimary|textSecondary|textMuted|warning|success|error|background|surface|border|divider)\b" "$f" || echo 0)
  echo "  修復後: $AFTER"
  echo ""
done

echo "完成 ✅"