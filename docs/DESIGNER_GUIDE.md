# 🎨 橋樑 App 設計師指南（Designer Guide）

> **版本**：v1.0 · 2026-08-05
> **目標讀者**：設計師、設計系統維護者、開源社群主題包作者
> **目標**：讓**不懂 Flutter 程式碼的設計師**也能透過 manifest 一鍵調整全 App 視覺。
> **先決條件**：請先讀 [BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md) 了解三層架構。

---

## 🧭 一、5 分鐘上手

### 情境：你想把所有「卡片標題」從 16 變 18

#### 步驟 1：打開 manifest
```
assets/theme_packs/bridge_default_v2.json
```

#### 步驟 2：找到 `card.title`
```json
{
  "tiers": {
    "card.title": {
      "textColor": "textPrimary",
      "fontSize": 16,        ← 改成 18
      "fontWeight": "w700"
    }
  }
}
```

#### 步驟 3：存檔
完成！全 App 所有「卡片標題」會從 16 → 18，**不用碰任何 widget 程式碼**。

---

## 🎯 二、認識 Tier（語意化設計 token）

### Tier 是什麼？
一個 Tier = 一個**視覺語意角色**，例如：
- `card.title` — 卡片標題
- `list.item.title` — 列表項標題
- `numeric.emphasis` — 數字強調
- `status.warning` — 警告訊息

**不是**字級（fontSize）或顏色（color），而是**「這個文字在 UI 中扮演什麼角色」**。

### 為什麼用語意而不是數值？
| 寫法 | 壞處 |
|---|---|
| ❌ `style: TextStyle(fontSize: 16, fontWeight: w700)` | 設計師改字級要 grep 200+ 個地方 |
| ✅ `style: TierStyle.of(context, Tier.cardTitle)` | 設計師改 manifest 一行，全 App 跟著變 |

### 36 個 Tier 速查表

| 類別 | Tier | 預設樣式 | 用途 |
|---|---|---|---|
| **卡片** | `card.title` | 16/w700/textPrimary | 卡片標題 |
| | `card.body` | 14/w400/textPrimary | 卡片內文 |
| | `card.caption` | 12/w400/textMuted | 卡片小字 |
| | `card.captionHeavy` | 12/w900/accentYellow | 強調數字（粗） |
| | `card.captionBold` | 12/w700/textPrimary | 強調小字 |
| | `card.captionEmphasized` | 13/w700/textSecondary | 設定提示 |
| **列表** | `list.item.title` | 16/w400/textPrimary | 列表項主標 |
| | `list.item.subtitle` | 13/w400/textSecondary | 列表項副標 |
| | `list.item.meta` | 12/w400/textMuted | 列表項 meta（時間/作者） |
| **對話** | `dialog.title` | 18/w700/textPrimary | 對話框標題 |
| | `dialog.body` | 14/w400/textPrimary | 對話框內文 |
| | `bubble.user` | 14/w400/textOnAccent | 對話泡泡（使用者） |
| | `bubble.ai` | 14/w400/textPrimary | 對話泡泡（AI） |
| **應用** | `app.title` | 24/w700/textPrimary | 應用主標題 |
| | `app.tagline` | 13/w400/textSecondary | 應用副標 |
| **狀態** | `status.success` | 12/w700/accentGreen | 成功訊息 |
| | `status.warning` | 12/w600/accentYellow | 警告訊息 |
| | `status.error` | 12/w700/accentRed | 錯誤訊息 |
| **背景** | `bg.panel.base` | (color only) | 面板底色 |
| | `bg.panel.elevated` | (color only) | 凸起面板 |
| | `bg.canvas` | (color only) | 畫布底色 |
| **邊框** | `border.subtle` | (color only) | 細邊框 |
| | `border.default` | (color only) | 一般邊框 |
| | `border.strong` | (color only) | 強調邊框 |
| **圖示** | `icon.tiny` | size 12 | 極小圖示 |
| | `icon.small` | size 14 | 小圖示 |
| | `icon.medium` | size 16 | 中圖示 |
| | `icon.large` | size 20 | 大圖示 |
| | `icon.xLarge` | size 24 | 特大圖示 |
| | `icon.huge` | size 32 | 巨大圖示 |
| **Wizard 專用** ✨ | `step.summary` | 12/w500/accent使用者 | Wizard 步驟摘要 |
| | `block.heading` | 18/w700/textPrimary | Wizard 區塊大標 |
| | `block.subheading` | 13/w700/textPrimary | Wizard 區塊副標 |
| | `numeric.emphasis` | 12/w900/accentYellow | 數字強調 |
| **表單** | `form.label` | 13/w700/textPrimary | Form label |
| | `form.input` | 14/w500/textPrimary | Form input 文字 |

> ✨ = 2026-08-05 Step 4 推廣新增

完整列表見 [`BRIDGE_TIER_SYSTEM.md`](BRIDGE_TIER_SYSTEM.md) 的「完整 Tier 列表」章節。

---

## 📐 三、設計 9 大場景速查

### 場景 1：新畫面需要文字
**問自己 3 個問題**：
1. 這文字是「標題」「內文」「小字」？→ 決定 card.* 或 list.item.*
2. 這文字有沒有「語意強調」（粗/警告/數字）？→ 看有沒有 `Bold`/`Emphasis`/`status.*`
3. 這文字有沒有「唯一特殊視覺」？→ 用 `tierBasedStyle()` + copyWith

### 場景 2：想改色但保持視覺
只改 `textColor` 欄位，例如：
```json
{
  "card.title": {
    "textColor": "textSecondary"  // 原本 textPrimary
  }
}
```
其他 widget 程式碼**完全不用動**。

### 場景 3：想改字型家族
整個 manifest 加 `fontFamily` 欄位（全域）：
```json
{
  "global": {
    "fontFamily": "Inter"  // 整個 App 換字型
  },
  "tiers": { ... }
}
```
> 注意：Tier 內也可以覆寫 `fontFamily`，針對單一 Tier。

### 場景 4：想做深色/淺色切換
不用動 Tier，改 **BridgeDSColors token**（底層）：
```json
{
  "colors": {
    "textPrimary": "#FFFFFF"  // 深色模式用白
  }
}
```
所有用 `textPrimary` 的 Tier 自動跟著變。

### 場景 5：想做「節日/季節」主題包
複製 manifest → 改 Tier 樣式 → 存成新檔：
```
assets/theme_packs/bridge_default_v2.json    ← 預設
assets/theme_packs/bridge_spring_v1.json     ← 春季版
assets/theme_packs/bridge_christmas_v1.json  ← 聖誕版
```
切換時只要改 `MaterialApp.theme.extensions` 的 source。

### 場景 6：建立自己的 Tier（進階）
如果現有 36 個 Tier 都不符合你的需求：
1. 在 `lib/theme/tier.dart` 加新 Tier const
2. 在 `Tier.all` 列表內加新 Tier
3. 在 manifest 加對應樣式
4. Widget 用 `TierStyle.of(context, Tier.yourNewTier)`
5. PR 內附 screenshot + 說明為什麼需要新語意

⚠️ **警告**：開太多 Tier = Tier 失去語意 = 退化成「另一套數值 token」。每個新 Tier 都應該對應**唯一的視覺意圖**。

---

## ⚠️ 四、3 個常見踩坑

### 踩坑 1：把 Tier 當字級用
❌ 錯：
```dart
Text('這是標題', style: TierStyle.of(context, Tier.dialogTitle))  // 18/w700
Text('這也是標題', style: TierStyle.of(context, Tier.appTitle))    // 24/w700
```
如果兩者只是「視覺差不多」但**語意不同**，就會出現「兩個 Tier 樣式一樣」的怪現象。

✅ 對：
- 如果都是「區塊標題」→ 用 `block.heading`
- 如果是「應用標題」→ 用 `app.title`
- 問自己：**讀者會把這個文字當成什麼角色？**

### 踩坑 2：把 `tierBasedStyle()` 當萬用
`tierBasedStyle()` 是**特殊視覺覆寫 helper**，不是首選：
```dart
// ⚠️ 只有真的需要覆寫時才用
style: tierBasedStyle(context, Tier.cardTitle, fontSize: 18, fontWeight: w900)
```
如果你的設計需要「特殊字級」當新 Tier，**應該開新 Tier**，而不是用 helper 偷改。

### 踩坑 3：忘記更新 manifest
改了 widget 程式碼（例如把 `Tier.dialogTitle` 換成 `Tier.blockHeading`），但忘了更新 manifest 的樣式。

✅ 流程：
1. 改 widget 程式碼
2. 同步更新 manifest 的兩個 Tier（保留舊的避免破壞依賴，或 deprecate 標記）
3. 跑 `flutter analyze` 確認無 error
4. PR review 時確認 Tier 樣式是**有意義的差異**

---

## 🧪 五、測試你的調整

### 1. 跑 analyze
```bash
flutter analyze
```
如果 Tier 名拼錯，會立刻 build 失敗（防呆 2）。

### 2. 視覺驗證清單
跑 App 後**必須**檢查的畫面：
- [ ] `chat_screen.dart` — 對話泡泡（最常用）
- [ ] `companion_create_screen.dart` — Wizard（最複雜）
- [ ] `home_screen.dart` — 首頁
- [ ] `settings_screen.dart` — 設定頁
- [ ] dialog / bottom sheet — 跨平台元件

### 3. 主題切換測試
切換 light/dark theme 後，所有 Tier 樣式都應該跟著變（透過 token 連動）。

---

## 📦 六、發布主題包

### 結構
```
my-theme-pack/
├── manifest.json           ← Tier 樣式定義
├── README.md               ← 設計說明、適用 App 版本
├── screenshots/            ← 各畫面預覽
│   ├── chat.png
│   ├── home.png
│   └── wizard.png
└── LICENSE
```

### manifest.json 範例
```json
{
  "version": "1.0",
  "appVersion": ">=0.5.0",
  "name": "高對比無障礙主題",
  "description": "為視障使用者設計的高對比主題",
  "colors": {
    "textPrimary": "#000000",
    "bgPanelBase": "#FFFFFF"
  },
  "tiers": {
    "card.title": {
      "fontSize": 18,
      "fontWeight": "w900"
    },
    "card.caption": {
      "fontSize": 14,
      "fontWeight": "w700"
    }
  }
}
```

### 上架檢查清單
- [ ] `manifest.json` 通過 `TierRegistry.fromManifestString()` 解析
- [ ] 所有用到的 Tier 都有對應樣式（**未定義 throw**）
- [ ] 沒有寫死顏色 hex（必須用 BridgeDSColors token）
- [ ] 截圖涵蓋 5 個主要畫面
- [ ] README 說明設計意圖、配色原則、適用 App 版本
- [ ] 開源授權（建議 MIT / Apache 2.0）

---

## 🔗 七、相關文件

### 必讀
- [BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md) — Tier 三層架構完整規範
- [BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md](BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md) — 字體 9 級距 + 圖示 6 級距
- [BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md](BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md) — 色塊設計規範
- [DESIGN.md](../DESIGN.md) — 5 套設計系統融合的原始規範

### 給工程師
- [PR_REVIEW_CHECKLIST.md](PR_REVIEW_CHECKLIST.md) — 給 code reviewer 的 checklist
- [`lib/theme/tier_style.dart`](../lib/theme/tier_style.dart) — `tierBasedStyle()` helper 原始碼
- [`assets/theme_packs/bridge_default_v2.json`](../assets/theme_packs/bridge_default_v2.json) — 預設 manifest

---

## 💬 八、問問題

### 設計相關
- Slack: `#design-system`
- Discord: `#bridge-design`
- Issue: GitHub `label:design`

### 發現 bug 或建議
- GitHub issue with `label:design-system`

---

## 📜 版本歷史

- **v1.0** (2026-08-05) — 初版，36 個 Tier，Step 4 推廣完成後定稿