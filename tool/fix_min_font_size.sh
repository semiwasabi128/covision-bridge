#!/usr/bin/env bash
# tool/fix_min_font_size.sh
#
# [小葵 2026-08-04] 把所有 fontSize < 14 修正為 14
#
# Blue 2026-08-04 規定：最小字不小於 14
#
# 規則（單純數值替換）：
#   fontSize: 8  → fontSize: 14
#   fontSize: 9  → fontSize: 14
#   fontSize: 10 → fontSize: 14
#   fontSize: 11 → fontSize: 14
#   fontSize: 12 → fontSize: 14
#   fontSize: 13 → fontSize: 14
#   fontSize: 13.5 → fontSize: 14
#   fontSize: 11.2 → fontSize: 14
#   ... (任何 <14 的都改)
#
# 排除：
#   - fontSize: 0 （特殊用途：自動計算）
#   - theme/ 目錄（token 定義）
#   - tool/ 自身
#   - *.g.dart, *.freezed.dart（自動生成）

set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "════════════════════════════════════════════════════════════════"
echo "  fontSize < 14 修正工具"
echo "  規則：任何 < 14 的字體大小 → 改為 14"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 先掃一次
TMP_BEFORE=$(mktemp)
find lib -type f -name '*.dart' \
  ! -path '*/theme/*' \
  ! -path '*/widgets/bridge_cards/*' \
  ! -path '*/widgets/bridge_*' \
  ! -path '*/widgets/adaptive_*' \
  ! -path '*.g.dart' \
  ! -path '*.freezed.dart' \
  -exec grep -lE 'fontSize:[[:space:]]*([0-9]|1[0-3])(\.[0-9]+)?\b' {} \; > "$TMP_BEFORE"

BEFORE_COUNT=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  N=$(grep -cE 'fontSize:[[:space:]]*([0-9]|1[0-3])(\.[0-9]+)?\b' "$f" || echo 0)
  BEFORE_COUNT=$(( BEFORE_COUNT + N ))
done < "$TMP_BEFORE"

echo "  修復前違規數: $BEFORE_COUNT"
echo "  影響檔案數: $(wc -l < "$TMP_BEFORE" | tr -d ' ')"
echo ""

# 用 perl 做替換（macOS 內建，比 sed 更精準）
# 規則: fontSize: 後接的數字，如果 <14，改成 14
# 但保留 fontSize: 0 不變
echo "  開始替換..."

while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 用 perl 處理
  # -i: 原地編輯
  # -pe: 對每行執行替換
  perl -i -pe '
    s{fontSize:\s*([0-9]+(?:\.[0-9]+)?)\b}{
      my $n = $1;
      if ($n > 0 && $n < 14) {
        "fontSize: 14";
      } else {
        "fontSize: $n";
      }
    }ge;
  ' "$f"
done < "$TMP_BEFORE"

# 驗證
TMP_AFTER=$(mktemp)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -nE 'fontSize:[[:space:]]*([0-9]|1[0-3])(\.[0-9]+)?\b' "$f" 2>/dev/null
done < "$TMP_BEFORE" > "$TMP_AFTER"

AFTER_COUNT=$(wc -l < "$TMP_AFTER" | tr -d ' ')

echo ""
echo "  修復後違規數: $AFTER_COUNT"
echo "  修復: $((BEFORE_COUNT - AFTER_COUNT)) 條"
echo ""

if [ "$AFTER_COUNT" -gt 0 ]; then
  echo "  ⚠️  還有違規（前 20 條）："
  head -20 "$TMP_AFTER"
fi

rm -f "$TMP_BEFORE" "$TMP_AFTER"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  完成 ✅"
echo "════════════════════════════════════════════════════════════════"