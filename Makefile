# Makefile — 橋樑 App 開發常用指令
# [小葵 2026-07-25] 確保新使用者第一次 build 就能成功載入嵌入模型

.PHONY: setup run build clean test patch

## setup — 首次安裝：pub get + patch LiteRT dylib + pod install
setup:
	flutter pub get
	bash scripts/patch_litert_dylib.sh
	cd macos && pod install
	@echo "✅ Setup complete. Run 'make run' to start the app."

## run — 啟動 debug build
run:
	flutter run -d macos

## build — release build
build:
	flutter build macos

## clean — 完整清除（含 flutter_gemma 快取）
clean:
	flutter clean
	rm -rf ~/Library/Caches/flutter_gemma/native
	@echo "✅ Clean complete. Run 'make setup' before running."

## test — 跑測試
test:
	flutter test

## patch — 手動修復 LiteRT dylib 路徑（pub get 後執行）
patch:
	bash scripts/patch_litert_dylib.sh
