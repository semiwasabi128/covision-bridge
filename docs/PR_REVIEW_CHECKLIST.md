# ✅ PR Review Checklist — 橋樑 App

> **版本**：v1.0 · 2026-08-05
> **目標讀者**：Code reviewer、Tech lead
> **目標**：在 merge 前快速確認新 UI 程式碼符合設計系統規範。
> **先決條件**：設計規範見 [BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md)、[BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md](BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)、[BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md](BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md)。

---

## 🚦 一、發 PR 前 — 自我檢查

提交 PR 前，作者必須**自己**跑完這份 checklist：

### 1. 跑 analyze
```bash
flutter analyze
```
- ✅ **Zero error** 才能發 PR
- ⚠️ Info 級別（async gap、prefer_const）可以留，但要在 PR 說明寫理由

### 2. 跑測試
```bash
flutter test
```
- ✅ 既有測試必須全綠
- ⚠️ 新功能沒寫測試要在 PR 說明寫理由

### 3. 視覺驗證
- [ ] 改了什麼畫面 → 自己截圖
- [ ] light theme + dark theme 都看過
- [ ] 用 `golden_toolkit` / 比對截圖（如果有的話）

---

## 🔍 二、Reviewer 檢查清單

### A. 顏色 — 禁寫死

#### ❌ 不可接受的
```dart
// 寫死 hex 顏色
Container(color: Color(0xFF1A1A1A))
Container(color: Colors.white)

// 寫死 Material 顏色
Container(color: Colors.black)

// 用 AppTheme 殘留
Container(color: AppTheme.surfaceElevated)
```

#### ✅ 必須改成
```dart
// 用 BridgeDSColors token
Container(color: BridgeDSColors.of(context).canvas)

// 對應 Tier
style: TierStyle.of(context, Tier.cardTitle)
```

#### 檢查指令
```bash
# 找寫死顏色
grep -rn "Color(0x" lib/
grep -rn "Colors\." lib/

# 找 AppTheme 殘留
grep -rn "AppTheme\." lib/screens/ | grep -v "spacing\|radius"
```

---

### B. 字體 — 禁寫死 fontSize

#### ❌ 不可接受的
```dart
// 寫死字級
Text('Hello', style: TextStyle(fontSize: 16))

// 寫死字重
Text('Hello', style: TextStyle(fontWeight: FontWeight.w700))
```

#### ✅ 必須改成
```dart
// 用 Tier
Text('Hello', style: TierStyle.of(context, Tier.cardTitle))

// 特殊視覺用 helper（要有合理理由）
Text('Special', style: tierBasedStyle(
  context,
  Tier.cardTitle,
  fontSize: 18,
  fontWeight: FontWeight.w900,
))
```

#### 例外（白名單）
如果**真的**需要寫死，必須在 PR 說明寫理由，且 `// [教練 Agent YYYY-MM-DD 理由]` 註解。

#### 檢查指令
```bash
# 找寫死 fontSize
grep -rn "fontSize: [0-9]" lib/screens/

# 找寫死 fontWeight
grep -rn "FontWeight\.w" lib/screens/
```

---

### C. Tier 使用 — 必須語意化

#### 檢查每個新用到的 Tier

| Tier | 適合場景 | 不適合場景 |
|---|---|---|
| `card.title` | 卡片標題 | 對話泡泡（用 `bubble.ai`） |
| `list.item.title` | 列表項主標 | 卡片標題（用 `card.title`） |
| `dialog.title` | 對話框標題 | 區塊標題（用 `block.heading`） |
| `bubble.user` | 使用者對話 | AI 回應（用 `bubble.ai`） |

#### ❌ 不可接受的 Tier 濫用
```dart
// 用 card.title 但語意是「對話泡泡」
Text(aiResponse, style: TierStyle.of(context, Tier.cardTitle))
```

#### ✅ 正確
```dart
Text(aiResponse, style: TierStyle.of(context, Tier.bubbleAi))
```

---

### D. BridgeDSColors — 必須動態查

#### ❌ 不可接受的
```dart
// 寫死顏色 query
final color = BridgeDSColors.of(context);  // 暫存到變數，跨 async gap
await something();
Container(color: color.textPrimary)  // BuildContext 過時！
```

#### ✅ 正確
```dart
// 在 widget 內即時查，或用 mounted check
if (!mounted) return;
final color = BridgeDSColors.of(context).textPrimary;
Container(color: color)
```

---

### E. Manifest 同步

如果新增/修改了 Tier，manifest 必須同步：

```bash
# 改了 lib/theme/tier.dart 必須同步 assets/theme_packs/bridge_default_v2.json
# 改了 Tier 樣式必須同步 manifest
```

#### 檢查指令
```bash
# 比對 Tier 定義跟 manifest
diff <(grep -E "static const Tier" lib/theme/tier.dart) \
     <(jq -r '.tiers | keys[]' assets/theme_packs/bridge_default_v2.json)
```

---

### F. 設計規範 — 5 個必看

#### 1. 色塊規範（[BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md](BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md)）
- [ ] 三層架構（bg/panel/card）有正確區分
- [ ] 顏色對比度 ≥ 4.5:1（WCAG AA）
- [ ] 顏色有動態對應 light/dark

#### 2. 字體規範（[BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md](BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)）
- [ ] 沒有寫死字級
- [ ] 字級是 9 級距之一（10/12/13/14/16/18/24/32/48）
- [ ] 字重是 6 級距之一（w400/w500/w600/w700/w800/w900）

#### 3. Tier 系統（[BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md)）
- [ ] 每個新文字 widget 用 Tier
- [ ] Tier 名在白名單內（見 manifest）
- [ ] 沒開無意義的新 Tier

#### 4. 設計師指南（[DESIGNER_GUIDE.md](DESIGNER_GUIDE.md)）
- [ ] 設計師能透過 manifest 一鍵調整此 UI

#### 5. 響應式（未來）
- [ ] 桌面 / 手機都看過（即使現在沒分，預留擴充空間）

---

## 🚨 三、紅旗（Reject PR）

出現任何一項**直接 reject**：

### 🚩 紅旗 1：寫死顏色
```dart
Container(color: Color(0xFF...))
Container(color: Colors.white)
```
**理由**：違反 Tier System 初衷，設計師改不到。

### 🚩 紅旗 2：寫死字級
```dart
TextStyle(fontSize: 16)
```
**理由**：違反 Typography 規範，設計師改不到。

### 🚩 紅旗 3：用 AppTheme 殘留
```dart
Container(color: AppTheme.surfaceElevated)
```
**理由**：AppTheme 是舊系統，已被 BridgeDSColors + Tier 取代。

### 🚩 紅旗 4：Build error（analyze 沒跑）
直接拒絕。

### 🚩 紅旗 5：改了 manifest 但沒同步 lib
或反過來。

---

## ⚠️ 四、黃旗（要討論）

出現**作者必須解釋**：

### ⚠️ 黃旗 1：用 `tierBasedStyle()` helper
要解釋**為什麼**需要覆寫，而不是開新 Tier。

### ⚠️ 黃旗 2：開新 Tier
要解釋**為什麼**現有 Tier 不夠用，這個新 Tier 的語意是什麼。

### ⚠️ 黃旗 3：用了 `BuildContext` 跨 async gap
要加 `mounted` check 或重新組織程式碼。

### ⚠️ 黃旗 4：PR 包含大型重構
要拆 PR，每個 PR 一個主題。

---

## 📋 五、PR 模板

在 PR 描述裡面回答這些問題：

```markdown
## 改了什麼
- [ ] 新畫面
- [ ] 改既有畫面
- [ ] 改 Tier 系統
- [ ] 改 manifest
- [ ] 重構

## 用到哪些 Tier
（列出 Tier 名 + 為什麼選這個）

## 截圖
（before/after 必填）

## light / dark theme 都看過了嗎
- [ ] light 看過
- [ ] dark 看過

## flutter analyze
- [ ] 跑過，零 error

## flutter test
- [ ] 跑過，全綠

## 設計師可調整性
（解釋設計師改 manifest 會如何影響此 UI）
```

---

## 🔧 六、Reviewer 工具

### 1. 跑設計系統 lint
```bash
# 找寫死顏色
grep -rn "Color(0x" lib/screens/

# 找 AppTheme 殘留
grep -rn "AppTheme\." lib/screens/

# 找寫死 fontSize
grep -rn "fontSize: [0-9]" lib/screens/

# 找寫死 fontWeight
grep -rn "FontWeight\.w" lib/screens/
```

### 2. 比對 Tier 跟 manifest
```bash
# 列 lib/theme/tier.dart 內所有 Tier
grep "static const Tier" lib/theme/tier.dart

# 列 manifest 內所有 tier key
jq '.tiers | keys' assets/theme_packs/bridge_default_v2.json

# 兩個比對
```

### 3. 視覺驗證
- [ ] 在 dev 環境跑起來
- [ ] 切 light/dark theme 看
- [ ] 截圖比對 design spec

---

## 📜 七、版本歷史

- **v1.0** (2026-08-05) — 初版，配合 BRIDGE_TIER_SYSTEM.md + DESIGNER_GUIDE.md

---

## 🔗 相關文件

- [BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md)
- [BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md](BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)
- [BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md](BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md)
- [DESIGNER_GUIDE.md](DESIGNER_GUIDE.md)
- [DESIGN.md](../DESIGN.md)