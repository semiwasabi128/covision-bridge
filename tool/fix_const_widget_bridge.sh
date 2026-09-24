#!/usr/bin/env bash
# tool/fix_const_widget_bridge.sh
#
# [小葵 2026-08-04] 把 const Icon/BoxDecoration/Border... 內含 BridgeDSColors.of(context) 的拿掉 const
#
# 對應 widget：
#   const Icon(...BridgeDSColors.of(context)...) → Icon(...)
#   const BoxDecoration(...BridgeDSColors.of(context)...) → BoxDecoration(...)
#   const Border.all(...BridgeDSColors.of(context)...) → Border.all(...)
#
# 策略：掃描所有 "const XXX(...)" 直到對應的 ")"
# 中間包含 BridgeDSColors.of(context) → 拿掉 const

set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

FILES=(
  "lib/screens/companion_list_screen.dart"
  "lib/screens/companion_create_screen.dart"
  "lib/screens/companion_appearance_screen.dart"
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  echo "=== 處理 $f ==="
  BEFORE=$(grep -cE "^\s*const Icon\(|^\s*const BoxDecoration\(|^\s*const Border\." "$f" || echo 0)
  echo "  const Widget 數: $BEFORE"

  perl -i -0pe '
    # 多行：const Icon(\n  ...\n  BridgeDSColors.of(context)...\n  )
    s{
      (const\s+(?:Icon|BoxDecoration|Border\.all)\(
        (?:[^()]|\([^()]*\))*
        BridgeDSColors\.of\(context\)
        (?:[^()]|\([^()]*\))*
      \))
    }{
      my $whole = $1;
      $whole =~ s/^const\s+//;
      $whole;
    }gsex;
  ' "$f"

  AFTER=$(grep -cE "^\s*const Icon\(|^\s*const BoxDecoration\(|^\s*const Border\." "$f" || echo 0)
  echo "  修復後 const Widget 數: $AFTER"
  echo ""
done

echo "完成 ✅"