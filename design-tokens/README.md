# Bridge Design Tokens — Multi-Platform Export

> 自動生成於 2026-08-06T01:31:03.569115
> 共 **85 個 color tokens** + **5 個 tier 定義**

## 📦 包含格式

| 檔案 | 平台 | 工具 |
|---|---|---|
| `figma-tokens.json` | Figma | [Figma Tokens Studio plugin](https://www.figma.com/community/plugin/843461159747178978/figma-tokens) |
| `variables.scss`    | Web / React Native | 直接 import |
| `BridgeDS+Tokens.swift` | iOS / macOS | Xcode project |
| `colors.xml`        | Android | res/values/ |

## 🎨 顏色 Token 總覽

共 85 個顏色，分成 12 個語意組：

- **Surface** (6) — canvas, surface, surfaceElevated, surfaceHover, darkPanel, darkCanvas
- **Text** (6) — textPrimary 到 textQuaternary + textOnAccent
- **Border** (6) — borderSubtle/Default/Strong + surfaceGlass/Hover + dividerIndigo
- **Accent** (12) — 互動強調色
- **Status** (14) — 成功/錯誤/警告
- **Tag** (10) — 標籤底色 + 前景色
- **Background** (3) — 淡背景
- **Node** (7) — Canvas 節點配色
- **Particle** (5) — 粒子視覺
- **Grey** (6) — 灰階
- **MaterialStandard** (6) — Material 標準色
- **Hint** (4) — 提示裝飾色

## 🚀 使用方式

### Figma Tokens Studio

1. 安裝 Figma Tokens Studio plugin
2. 點「Load from file」或「Set JSONBin」
3. 選 `figma-tokens.json`

### Web / SCSS

```scss
@import 'variables.scss';

.button {
  background-color: var(--bridge-accent-blue);
  color: var(--bridge-text-on-accent);
  padding: var(--bridge-spacing-md);
  font-size: var(--bridge-font-card-body);
}
```

### Swift (iOS / macOS)

```swift
let view = UIView()
view.backgroundColor = .bridge(.canvas)
```

### Android (Kotlin)

```kotlin
view.setBackgroundColor(
    ContextCompat.getColor(context, R.color.bridge_canvas)
)
```

## 🔄 更新方式

每次 BridgeDS 修改後：

```bash
dart run tool/export_design_tokens.dart
```

## 📚 來源

- `lib/theme/bridge_design_system.dart` — Single source of truth
- `lib/theme/bridge_ds_tokens.dart` — 12 個語意分組
