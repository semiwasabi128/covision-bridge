#!/usr/bin/env bash
# tool/fix_nonstandard_font_size.sh
#
# [小葵 2026-08-04] 非標準字級 → 標準字級
#
# 規則（往最近的 token 對齊）：
#   15  → 14    (15-14 = 1, 偏 body)
#   17  → 18    (17-16 = 1, 偏 headingS)
#   22  → 24    (22-20 = 2, 偏 headingL)
#   14.5 → 14
#   19 → 20     (headingM)
#
# 注意：fontSize >= 26 (display) 不動

set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "════════════════════════════════════════════════════════════════"
echo "  非標準字級修正工具"
echo "════════════════════════════════════════════════════════════════"

# 找出非標準字級
TMP_BEFORE=$(mktemp)
find lib -type f -name '*.dart' \
  ! -path '*/theme/*' \
  ! -path '*/widgets/bridge_cards/*' \
  ! -path '*/widgets/bridge_*' \
  ! -path '*/widgets/adaptive_*' \
  ! -path '*.g.dart' \
  ! -path '*.freezed.dart' \
  -exec grep -lE 'fontSize:[[:space:]]*(15|17|19|22|14\.5|15\.5|11\.3)\b' {} \; > "$TMP_BEFORE"

BEFORE_COUNT=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  N=$(grep -cE 'fontSize:[[:space:]]*(15|17|19|22|14\.5|15\.5|11\.3)\b' "$f" || echo 0)
  BEFORE_COUNT=$(( BEFORE_COUNT + N ))
done < "$TMP_BEFORE"

echo "  修復前違規數: $BEFORE_COUNT"
echo "  影響檔案數: $(wc -l < "$TMP_BEFORE" | tr -d ' ')"
echo ""

echo "  開始替換..."

while IFS= read -r f; do
  [ -z "$f" ] && continue
  perl -i -pe '
    s{fontSize:\s*(15|17|19|22|14\.5|15\.5|11\.3)\b}{
      my $n = $1;
      my %map = (
        "15" => 14, "15.5" => 14, "14.5" => 14,
        "11.3" => 14,
        "17" => 18, "19" => 20, "22" => 24,
      );
      "fontSize: " . $map{$n};
    }ge;
  ' "$f"
done < "$TMP_BEFORE"

# 驗證
TMP_AFTER=$(mktemp)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -nE 'fontSize:[[:space:]]*(15|17|19|22|14\.5|15\.5|11\.3)\b' "$f" 2>/dev/null
done < "$TMP_BEFORE" > "$TMP_AFTER"

AFTER_COUNT=$(wc -l < "$TMP_AFTER" | tr -d ' ')

echo ""
echo "  修復後違規數: $AFTER_COUNT"
echo "  修復: $((BEFORE_COUNT - AFTER_COUNT)) 條"
echo ""

rm -f "$TMP_BEFORE" "$TMP_AFTER"

echo "════════════════════════════════════════════════════════════════"
echo "  完成 ✅"
echo "════════════════════════════════════════════════════════════════"