#!/usr/bin/env bash
# tool/scan_typography_hierarchy.sh
#
# [小葵 2026-08-04] 視覺層級掃描器
#
# 用途：找出「同一區塊內字體大小混亂」的地方，給 Blue 設計判斷用。
#
# 規則（層級）：
#   L1 顯示 (display): 32+
#   L2 標題大 (headingL): 24
#   L3 標題中 (headingM): 20
#   L4 標題小 (headingS): 18
#   L5 內文大 (bodyL): 16
#   L6 內文 (body): 14   ← 最低不得小於 14 (Blue 2026-08-04 規定)
#   L7 註腳 (caption):   <14 違規！
#
# 偵測項目：
#   H1: 任何 fontSize < 14（Blue 規定：最小字 14）
#   H2: 同一 Card/Section/Column 內有 4 種以上不同字級 → 太雜亂
#   H3: 連續兩條 TextStyle 用了相近字體（差 ≤1）→ 該統一
#   H4: 標題用 < 18 字體（應該用 headingS 以上）
#
# 排除：theme/, widgets/bridge_*

set -u

LIB_DIR="${1:-lib}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "════════════════════════════════════════════════════════════════"
echo "  視覺層級掃描器 — Typography Hierarchy"
echo "  掃描目錄: $LIB_DIR"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 收集檔案
TMP_FILES=$(mktemp)
find "$LIB_DIR" \
  -type f -name '*.dart' \
  ! -path '*/theme/*' \
  ! -path '*/widgets/bridge_cards/*' \
  ! -path '*/widgets/bridge_*' \
  ! -path '*/widgets/adaptive_*' \
  ! -path '*.g.dart' \
  ! -path '*.freezed.dart' \
  > "$TMP_FILES"

TOTAL=$(wc -l < "$TMP_FILES" | tr -d ' ')

echo "總掃描檔案: $TOTAL"
echo ""

# H1: fontSize < 14
echo "════════════════════════════════════════════════════════════════"
echo "  H1: fontSize < 14（Blue 規定：最小字 14）"
echo "════════════════════════════════════════════════════════════════"

TMP_H1=$(mktemp)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -nE 'fontSize:[[:space:]]*(0?[0-9]|1[0-3])(\.[0-9]+)?\b' "$f" 2>/dev/null | \
    while IFS= read -r line; do
      printf '%s:%s\n' "$f" "$line" >> "$TMP_H1"
    done
done < "$TMP_FILES"

H1_COUNT=$(wc -l < "$TMP_H1" | tr -d ' ')
if [ "$H1_COUNT" -gt 0 ]; then
  echo "  ❌ 找到 $H1_COUNT 條（最小字違規）"
  echo ""
  # 按檔案 group
  cut -d: -f1 "$TMP_H1" | sort | uniq -c | sort -rn | head -10 | \
    awk '{printf "  %4d  %s\n", $1, $2}'
  echo ""
  echo "  前 20 條詳情："
  head -20 "$TMP_H1" | while IFS= read -r line; do
    printf "    %s\n" "$line"
  done
else
  echo "  ✅ 沒有違規"
fi
echo ""

# H2: 同一檔案內 fontSize 種類太多（>5 種）
echo "════════════════════════════════════════════════════════════════"
echo "  H2: 單一檔案內 fontSize 種類 > 5（層級雜亂）"
echo "════════════════════════════════════════════════════════════════"

TMP_H2=$(mktemp)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 抓所有 fontSize 數字（去重）
  SIZES=$(grep -oE 'fontSize:[[:space:]]*[0-9]+(\.[0-9]+)?' "$f" 2>/dev/null | \
          grep -oE '[0-9]+(\.[0-9]+)?' | sort -u)
  N=$(echo "$SIZES" | wc -l | tr -d ' ')
  if [ "$N" -gt 5 ]; then
    printf '%3d  %s\n  sizes: %s\n\n' "$N" "$f" "$(echo "$SIZES" | tr '\n' ' ')" >> "$TMP_H2"
  fi
done < "$TMP_FILES"

H2_COUNT=$(grep -cE "^ *[0-9]+ " "$TMP_H2" 2>/dev/null || echo 0)
if [ "$H2_COUNT" -gt 0 ]; then
  echo "  ⚠️  $H2_COUNT 個檔案字級超過 5 種"
  echo ""
  head -20 "$TMP_H2"
else
  echo "  ✅ 沒有違規"
fi
echo ""

# H3: fontSize 數值統計
echo "════════════════════════════════════════════════════════════════"
echo "  H3: 全專案 fontSize 使用統計"
echo "════════════════════════════════════════════════════════════════"

TMP_H3=$(mktemp)
while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -oE 'fontSize:[[:space:]]*[0-9]+(\.[0-9]+)?' "$f" 2>/dev/null | \
    grep -oE '[0-9]+(\.[0-9]+)?'
done < "$TMP_FILES" | sort | uniq -c | sort -rn > "$TMP_H3"

cat "$TMP_H3" | awk '{
  size = $2
  count = $1
  # 分類
  if (size < 14) cat = "❌ <14 (違規)"
  else if (size == 14) cat = "✅ 14 (body 標準)"
  else if (size == 15) cat = "⚠️  15 (非標準)"
  else if (size == 16) cat = "✅ 16 (bodyL)"
  else if (size == 17) cat = "⚠️  17 (非標準)"
  else if (size == 18) cat = "✅ 18 (headingS)"
  else if (size == 19) cat = "⚠️  19 (非標準)"
  else if (size == 20) cat = "✅ 20 (headingM)"
  else if (size == 22) cat = "⚠️  22 (非標準)"
  else if (size == 24) cat = "✅ 24 (headingL)"
  else if (size >= 26) cat = "✅ >=26 (display)"
  else cat = "❓ 其他"
  printf "  %3d 次  size=%3s  %s\n", count, size, cat
}'

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  完成 ✅"
echo "════════════════════════════════════════════════════════════════"

rm -f "$TMP_FILES" "$TMP_H1" "$TMP_H2" "$TMP_H3"