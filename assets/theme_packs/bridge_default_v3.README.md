# Bridge Default v3

> 自動生成於 2026-08-06T01:23:40.633954
> 授權：MIT

## 📊 內容

- **85** color tokens
- **5** tier 定義
- **3** 字型設定

## 🎨 安裝方式

1. 把 `assets/theme_packs/bridge_default_v3.json` 放到 `assets/theme_packs/` 目錄
2. 透過 `ThemePackService.instance.loadPack('assets/theme_packs/bridge_default_v3.json')` 載入
3. 透過 `TierTheme.fromManifest(TierRegistry.fromJson(...))` 套用

## 📦 Token 對照表

見 `lib/theme/bridge_design_system.dart` 內 `BridgeDS` class。

## 🔄 更新方式

```
dart run tool/generate_theme_pack.dart \
  bridge_default_v3 \
  "Bridge Default v3" \
  "Bridge Design System" \
  MIT
```
