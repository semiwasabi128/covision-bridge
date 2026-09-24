#!/bin/bash
# scripts/patch_litert_dylib.sh
# [小葵 2026-07-25] 永久修復 LiteRtLm dylib 載入問題
#
# 問題：flutter_gemma_embeddings 的 litert_bindings.dart 在 macOS 上只搜尋
#   1. LiteRtLm.framework/LiteRtLm（相對路徑，worker isolate cwd 不對）
#   2. {project}/native/litert_lm/prebuilt/macos_arm64/libLiteRtLm.dylib
#
#   app bundle 裡有 LiteRtLm.framework 但 worker isolate 的 cwd 不是 app bundle，
#   所以 dlopen 找不到。
#
# 解法：在 litert_bindings.dart 加一個候選路徑用 Platform.resolvedExecutable
#   算出 app bundle 的 Frameworks 目錄。
#
# 使用：flutter pub get 後自動執行（透過 pubspec.yaml hooks 或手動）
#   bash scripts/patch_litert_dylib.sh

set -e

# 找 flutter_gemma_embeddings 套件路徑
PACKAGE_DIR=$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -type d -name 'flutter_gemma_embeddings-*' | sort -V | tail -1)

if [ -z "$PACKAGE_DIR" ]; then
  echo "[patch_litert] flutter_gemma_embeddings not found in pub-cache, skipping"
  exit 0
fi

BINDINGS_FILE="$PACKAGE_DIR/lib/src/litert/litert_bindings.dart"

if [ ! -f "$BINDINGS_FILE" ]; then
  echo "[patch_litert] litert_bindings.dart not found, skipping"
  exit 0
fi

# 檢查是否已經 patch 過
if grep -q 'Platform.resolvedExecutable' "$BINDINGS_FILE"; then
  echo "[patch_litert] Already patched ✓"
  exit 0
fi

# Patch：在 candidates 裡加 resolvedExecutable 路徑
# 原始：
#     final candidates = <String>[
#       'LiteRtLm.framework/LiteRtLm',
#       '${Directory.current.path}/native/litert_lm/prebuilt/macos_arm64/libLiteRtLm.dylib',
#     ];
#
# Patched：
#     final exeDir = File(Platform.resolvedExecutable).parent.path;
#     final candidates = <String>[
#       'LiteRtLm.framework/LiteRtLm',
#       '@executable_path/../Frameworks/LiteRtLm.framework/LiteRtLm',
#       '$exeDir/../Frameworks/LiteRtLm.framework/LiteRtLm',
#       '${Directory.current.path}/native/litert_lm/prebuilt/macos_arm64/libLiteRtLm.dylib',
#     ];

# 用 sed 做 in-place patch
# macOS sed 需要 -i ''
sed -i '' "/final candidates = <String>\[/i\\
    final exeDir = File(Platform.resolvedExecutable).parent.path;
" "$BINDINGS_FILE"

sed -i '' "s|'LiteRtLm.framework/LiteRtLm',|'LiteRtLm.framework/LiteRtLm',\\\n      '@executable_path/../Frameworks/LiteRtLm.framework/LiteRtLm',\\\n      '\$exeDir/../Frameworks/LiteRtLm.framework/LiteRtLm',|" "$BINDINGS_FILE"

# 驗證 patch
if grep -q 'Platform.resolvedExecutable' "$BINDINGS_FILE"; then
  echo "[patch_litert] Patched ✓ ($BINDINGS_FILE)"
else
  echo "[patch_litert] Patch FAILED ✗"
  exit 1
fi
