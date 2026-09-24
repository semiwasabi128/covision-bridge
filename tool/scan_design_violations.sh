#!/usr/bin/env bash
# tool/scan_design_violations.sh
#
# [小葵 2026-08-04] 設計違規掃描器（Phase E+ 問題 1）
#
# 用途：自動偵測違規字體/顏色用法，給開發者在交付前修。
#
# 規則（R1-R7）：
#   R1: 硬編碼 fontSize (應用 BridgeDS token)
#   R2: 用 Colors.white/black/red 等 Material 預設色（必須用 BridgeDSColors）
#   R3: 硬編碼 Color(0xFF...) (必須用 token)
#   R4: 沒走 BridgeDSColors (但檔案有用顏色)
#   R5: 用 Container+BoxDecoration 而非 BridgeCard
#   R6: 硬編碼 fontWeight: FontWeight.bold (應用 token)
#   R7: 硬編碼 padding/margin 數字 (應用 BridgeDS.space*)

set -u

LIB_DIR="${1:-lib}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "════════════════════════════════════════════════════════════════"
echo "  設計違規掃描器 — Bridge Design System"
echo "  掃描目錄: $LIB_DIR"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 收集檔案列表到暫存檔（避開 bash 3 不支援 mapfile）
TMP_FILES=$(mktemp)
find "$LIB_DIR" \
  -type f \
  -name '*.dart' \
  ! -path '*/theme/*' \
  ! -path '*/widgets/bridge_cards/*' \
  ! -path '*/widgets/bridge_*' \
  ! -path '*/widgets/adaptive_*' \
  ! -path '*/generated/*' \
  ! -path '*.g.dart' \
  ! -path '*.freezed.dart' \
  > "$TMP_FILES"

TOTAL=$(wc -l < "$TMP_FILES" | tr -d ' ')

# 統計（bash 3 相容）
R1_COUNT=0
R2_COUNT=0
R3_COUNT=0
R4_COUNT=0
R5_COUNT=0
R6_COUNT=0
R7_COUNT=0

# 暫存所有違規
TMP_VIOL=$(mktemp)

while IFS= read -r f; do
  [ -z "$f" ] && continue
  content=$(cat "$f")
  [ -z "$content" ] && continue

  # R1: 硬編碼 fontSize
  R1=$(echo "$content" | grep -nE 'fontSize:\s*[0-9]+(\.[0-9]+)?' | \
       grep -vE 'fontSize:\s*0\b' || true)
  if [ -n "$R1" ]; then
    echo "$R1" | while IFS= read -r line; do
      printf '%s|%s|R1: 硬編碼 fontSize（應用 BridgeDS.display/heading*/body*/...）\n' \
        "$f" "$line" >> "$TMP_VIOL"
    done
    R1_COUNT=$(( R1_COUNT + $(echo "$R1" | wc -l | tr -d ' ') ))
  fi

  # R2: Material Colors
  R2=$(echo "$content" | grep -nE 'Colors\.(white|black|red|blue|green|yellow|grey|gray|orange|purple|pink|cyan|teal|brown)\b' | \
       grep -vE 'Colors\.transparent|Colors\.black\.with|Colors\.white\.with|Colors\.black2[6-9]|Colors\.black5[0-9]|Colors\.black8[0-9]|Colors\.white[0-9]+' || true)
  if [ -n "$R2" ]; then
    echo "$R2" | while IFS= read -r line; do
      printf '%s|%s|R2: Material Colors.xxx（應用 BridgeDSColors token）\n' \
        "$f" "$line" >> "$TMP_VIOL"
    done
    R2_COUNT=$(( R2_COUNT + $(echo "$R2" | wc -l | tr -d ' ') ))
  fi

  # R3: 硬編碼 Color(0xFF...)
  R3=$(echo "$content" | grep -nE 'Color\(0x[0-9a-fA-F]+\)' | \
       grep -vE 'borderSide:.*Color\(0xff' || true)
  if [ -n "$R3" ]; then
    echo "$R3" | while IFS= read -r line; do
      printf '%s|%s|R3: 硬編碼 Color (應用 BridgeDSColors token)\n' \
        "$f" "$line" >> "$TMP_VIOL"
    done
    R3_COUNT=$(( R3_COUNT + $(echo "$R3" | wc -l | tr -d ' ') ))
  fi

  # R4: 有 Color 但沒用 BridgeDSColors
  if echo "$content" | grep -qE '\bColor\b' && \
     ! echo "$content" | grep -qE 'BridgeDSColors\.of'; then
    R4=$(echo "$content" | grep -nE 'Color\b' | head -3 || true)
    if [ -n "$R4" ]; then
      echo "$R4" | while IFS= read -r line; do
        printf '%s|%s|R4: 檔案有用 Color 但完全沒用 BridgeDSColors.of()\n' \
          "$f" "$line" >> "$TMP_VIOL"
      done
      R4_COUNT=$(( R4_COUNT + $(echo "$R4" | wc -l | tr -d ' ') ))
    fi
  fi

  # R5: Container+BoxDecoration
  R5=$(echo "$content" | grep -nE 'Container\(' | \
       grep -vE 'Container\(\s*\)|child:|color:.*ds\.|//.*Container' | head -5 || true)
  if [ -n "$R5" ]; then
    echo "$R5" | while IFS= read -r line; do
      L=$(echo "$line" | cut -d: -f1)
      CTX=$(echo "$content" | sed -n "${L},$((L+5))p" 2>/dev/null || true)
      if echo "$CTX" | grep -qE 'BoxDecoration|borderRadius|gradient'; then
        printf '%s|%s|R5: Container+BoxDecoration（考慮用 BridgeCard）\n' \
          "$f" "$line" >> "$TMP_VIOL"
      fi
    done
    R5_COUNT=$(( R5_COUNT + $(echo "$R5" | wc -l | tr -d ' ') ))
  fi

  # R6: FontWeight.bold
  R6=$(echo "$content" | grep -nE 'fontWeight:\s*FontWeight\.bold\b' || true)
  if [ -n "$R6" ]; then
    echo "$R6" | while IFS= read -r line; do
      printf '%s|%s|R6: 硬編碼 FontWeight.bold (應用 token 的字重)\n' \
        "$f" "$line" >> "$TMP_VIOL"
    done
    R6_COUNT=$(( R6_COUNT + $(echo "$R6" | wc -l | tr -d ' ') ))
  fi

  # R7: 硬編碼 padding/margin
  R7=$(echo "$content" | grep -nE 'padding:\s*const\s+EdgeInsets\.\w+\(\s*[0-9]+(\.[0-9]+)?(,.*[0-9])?\s*\)' | \
       head -10 || true)
  if [ -n "$R7" ]; then
    echo "$R7" | while IFS= read -r line; do
      printf '%s|%s|R7: 硬編碼 padding (應用 BridgeDS.space*)\n' \
        "$f" "$line" >> "$TMP_VIOL"
    done
    R7_COUNT=$(( R7_COUNT + $(echo "$R7" | wc -l | tr -d ' ') ))
  fi
done < "$TMP_FILES"

TOTAL_VIOL=$(wc -l < "$TMP_VIOL" | tr -d ' ')

echo "════════════════════════════════════════════════════════════════"
echo "  規則違規統計"
echo "════════════════════════════════════════════════════════════════"
printf "  R1 (硬編碼 fontSize)        : %4d\n" "$R1_COUNT"
printf "  R2 (Colors.xxx)             : %4d\n" "$R2_COUNT"
printf "  R3 (Color(0x...))           : %4d\n" "$R3_COUNT"
printf "  R4 (沒用 BridgeDSColors)    : %4d\n" "$R4_COUNT"
printf "  R5 (Container+BoxDecoration): %4d\n" "$R5_COUNT"
printf "  R6 (FontWeight.bold)        : %4d\n" "$R6_COUNT"
printf "  R7 (硬編碼 padding/margin)  : %4d\n" "$R7_COUNT"
echo ""
echo "  總掃描檔案: $TOTAL"
echo "  總違規數:   $TOTAL_VIOL"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "  違規 Top 50（按檔案 group）"
echo "════════════════════════════════════════════════════════════════"

# 排序：先按檔案，再按行號
sort -t'|' -k1,1 -k2,2n "$TMP_VIOL" > "${TMP_VIOL}.sorted"

# 統計每檔違規數
echo "════════════════════════════════════════════════════════════════"
echo "  每檔違規數排行（Top 30）"
echo "════════════════════════════════════════════════════════════════"
cut -d'|' -f1 "${TMP_VIOL}.sorted" | sort | uniq -c | sort -rn | head -30 | \
  awk '{printf "  %4d  %s\n", $1, $2}'
echo ""

# 顯示前 100 條
echo "════════════════════════════════════════════════════════════════"
echo "  違規清單（按檔案 group，前 100 條）"
echo "════════════════════════════════════════════════════════════════"
head -100 "${TMP_VIOL}.sorted" | while IFS='|' read -r f line rule; do
  printf "  %s\n      %s\n      └─ %s\n\n" "$f" "$line" "$rule"
done

if [ "$TOTAL_VIOL" -gt 100 ]; then
  echo ""
  echo "  ... (還有 $((TOTAL_VIOL - 100)) 條違規未顯示)"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  完成 ✅"
echo "════════════════════════════════════════════════════════════════"

rm -f "$TMP_FILES" "$TMP_VIOL" "${TMP_VIOL}.sorted"