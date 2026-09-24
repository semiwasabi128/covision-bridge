#!/bin/bash
# build_macos.sh — wrapper that runs flutter build + copies LiteRT dylibs
# Usage: ./scripts/build_macos.sh
set -e

cd "$(dirname "$0")/.."
echo "=== flutter build macos --release ==="
flutter build macos --release

echo "=== Copying LiteRT companion dylibs ==="
./scripts/copy_litert_dylibs.sh

echo "=== Build complete ==="
echo "App: build/macos/Build/Products/Release/bridge_app.app"
