#!/usr/bin/env bash
# tool/fix_const_widget_bridge_v2.sh
#
# [小葵 2026-08-04] 更通用的版本 — 任何 const widget 內含 BridgeDSColors.of(context) 就拿掉 const
#
# 策略：掃每個檔案，找所有 "const " 開頭的 widget call 一直延伸到匹配的 ")"
# 如果整段內含 BridgeDSColors.of(context) → 拿掉最外層的 const

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
  BEFORE=$(grep -cE "const (Icon|Text|BoxDecoration|Border|Expanded|Row|Column|Container|SizedBox|Padding|EdgeInsets|Stack|Positioned|Wrap|Flexible|Align|Center)\(" "$f" || echo 0)
  echo "  const Widget 總數: $BEFORE"

  # 簡化策略：找每個 "const XXX(" 開頭，找到對應 ")"
  # 中間包含 BridgeDSColors.of(context) → 拿掉這個 const
  # 用 awk + 狀態機

  perl -i -0pe '
    # 多行：const <WidgetName>(\n  ...\n  BridgeDSColors.of(context)\n  )
    # 用 Perl 遞歸子模式 (?R) 處理任意深度括號
    s{
      (?<![A-Za-z0-9_])
      const\s+
      (Icon|Text|BoxDecoration|Border\.all|Expanded|Row|Column|Container|SizedBox|Padding|EdgeInsets|Stack|Positioned|Wrap|Flexible|Align|Center)\(
        ((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)
        BridgeDSColors\.of\(context\)
        ((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)
      \)
    }{
      my $name = $1;
      my $pre = $2;
      my $post = $3;
      "$name($pre$`BridgeDSColors.of(context)$'$post)";
    }gsex;
  ' "$f"

  AFTER=$(grep -cE "const (Icon|Text|BoxDecoration|Border|Expanded|Row|Column|Container|SizedBox|Padding|EdgeInsets|Stack|Positioned|Wrap|Flexible|Align|Center)\(" "$f" || echo 0)
  echo "  修復後 const Widget 總數: $AFTER"
  echo ""
done

echo "完成 ✅"