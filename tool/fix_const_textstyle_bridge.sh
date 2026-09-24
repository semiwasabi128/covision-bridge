#!/usr/bin/env bash
# tool/fix_const_textstyle_bridge.sh
#
# [小葵 2026-08-04] 把多行的 const TextStyle(...BridgeDSColors.of(context)...)
# 改成非 const

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
  BEFORE=$(grep -cE "const TextStyle" "$f" || echo 0)
  echo "  const TextStyle 數: $BEFORE"

  # 用 perl 多行模式：把每個 `const TextStyle(\n...\nBridgeDSColors.of(context)\n...)` 的 const 拿掉
  # 策略：找 "const TextStyle(" 開始，掃到對應 ")"，中間有 BridgeDSColors.of 就拿掉 const
  perl -i -0pe '
    # 多行：const TextStyle(\n  ...\n  BridgeDSColors.of(context)...\n  )
    s{
      const\s+TextStyle\(
        ((?:[^()]|\([^()]*\))*)
        BridgeDSColors\.of\(context\)
        ((?:[^()]|\([^()]*\))*)
      \)
    }{
      my $body = $1 . "BridgeDSColors.of(context)" . $2;
      "TextStyle(\n        $body\n      )";
    }gsex;
  ' "$f"

  AFTER=$(grep -cE "const TextStyle" "$f" || echo 0)
  echo "  修復後 const TextStyle 數: $AFTER"
  echo ""
done

echo "完成 ✅"