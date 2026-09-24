# 🎯 Bridge Tier System — 設計規範

> **狀態**：v1.0（2026-08-05 建立）
> **目標**：讓開源社群能下載主題包「一鍵對齊」全 App 的字色 / 字級 / 字型，App 不需重新編譯。
> **基礎**：BridgeDSColors token（30 個 token）+ 9 級距字體 token。
> **適用平台**：橋樑 App 桌面版（macOS / Windows / Linux）

> **📱 手機版刪除宣告（2026-08-10）**：
> - 手機版已正式宣告刪除，本 Tier 系統專注於桌面版實作
> - 未來手機版將重新設計，可能調整 Tier 結構以適應行動裝置

---

## 🧠 為什麼需要 Tier System？

### 現況問題

```
1. 每個 widget 自己寫 TextStyle(color: BridgeDSColors.of(context).textPrimary)
2. → 全 App 有 200+ 個 TextStyle
3. → 開源社群下載主題包「改 token 值」會讓 200 個 widget 都跟著變
4. → 但「字要多大」「字型用哪個」「粗體還細體」這種**排版意圖**沒對應規則
5. → 社群想改字級 → 沒標準介面
```

### Tier System 解法

```
Widget 程式碼：   style: TierStyle.of(context, Tier.list.item.title)
                          ↓ 查找
Tier Manifest:   tier.list.item.title → { textColor: textPrimary, fontSize: 16, ... }
                          ↓ 引用
BridgeDSColors:  textPrimary → #FFFFFF (深色) / #000000 (淺色)
```

**社群改主題包**：只改 tier manifest 跟 token 值，不用碰 widget 程式碼。

---

## 🎨 三層架構

```
┌─────────────────────────────────────────────┐
│ L1 設計稿（語意層）                             │
│   「夥伴館左側欄第 1 行 = list.item.title」    │
│   「夥伴館視窗底色 = role.panel.base」        │
└──────────────────┬──────────────────────────┘
                   ↓ 編譯期驗證
┌──────────────────┴──────────────────────────┐
│ L2 Widget 程式碼（介接層）                      │
│   final style = TierStyle.of(                │
│     context,                                  │
│     Tier.list.item.title,                    │
│   );                                          │
└──────────────────┬──────────────────────────┘
                   ↓ 動態查找
┌──────────────────┴──────────────────────────┐
│ L3 主題包（資料層）                             │
│   {                                           │
│     "tiers": {                                │
│       "list.item.title": {                   │
│         "textColor": "textPrimary",          │ ← 只填 token 名，不填 hex
│         "fontSize": 16,                      │
│         "fontWeight": "w600",                │
│         "fontFamily": "base"                 │
│       }                                       │
│     },                                        │
│     "tokens": {                               │
│       "textPrimary": "#000000"               │ ← 真實顏色
│     }                                         │
│   }                                           │
└─────────────────────────────────────────────┘
```

---

## 📚 Tier 命名規則

### 格式

```
{namespace}.{element}.{role}[.{variant}]
```

| 部分 | 規則 | 範例 |
|---|---|---|
| `namespace` | 全 App 跨頁面共用 vs 單頁面專用 | `app` / `card` / `list` / `sidebar` / `dialog` / `form` |
| `element` | widget 類型 | `title` / `subtitle` / `body` / `meta` / `caption` |
| `role` | 在 layout 中的角色 | `primary` / `secondary` / `tertiary` |
| `variant` | 變體（選用）| `hover` / `selected` / `disabled` |

### 完整 Tier 列表（v1.0，29 個）

```dart
// App 全域
app.title           // App 大標題（頁面 H1）
app.subtitle        // App 副標題（頁面 H2）

// Sidebar / 導覽列
sidebar.row.title       // sidebar 列表項主文字
sidebar.row.subtitle    // sidebar 列表項副文字
sidebar.row.meta        // sidebar 列表項 metadata（時間、tag）

// Card / 卡片
card.title          // 卡片標題
card.body           // 卡片內文
card.caption        // 卡片註腳（小字）

// List item / 列表項
list.item.title     // 列表項主文字
list.item.subtitle  // 列表項副文字
list.item.meta      // 列表項 metadata

// Form / 表單
form.label          // 表單欄位 label
form.input          // 表單輸入文字
form.helper         // 表單 helper text

// Dialog / 對話框
dialog.title        // 對話框標題
dialog.body         // 對話框內文

// Button / 按鈕
button.primary      // 主按鈕文字
button.secondary    // 次按鈕文字

// Status / 狀態色
status.success      // 成功（綠）
status.warning      // 警告（黃）
status.error        // 錯誤（紅）
status.info         // 資訊（藍）

// Background / 背景角色（用於 Container）
bg.panel.base       // 視窗主背景
bg.panel.elevated   // 卡片表面（亮一級）
bg.panel.hover      // hover 狀態（亮更多）
bg.panel.selected   // selected 狀態（強調色背景）

// Border / 邊框
border.subtle       // 細線
border.default      // 一般
border.strong       // 強調
```

**總計 33 個 tier**，覆蓋全 App。

---

## 🛡️ 三大安全防呆（杜絕設定錯誤）

### 防呆 1: Tier 不能寫死顏色

```dart
// ❌ 編譯失敗：TierStyle.textColor 只接受 String
TierStyle.of(context, Tier.list.item.title).copyWith(textColor: Color(0xFF000000))

// ✅ 編譯通過：textColor 指向 token 名
TierStyle.of(context, Tier.list.item.title).copyWith(textColor: 'textPrimary')
```

實作：`textColor` 參數型別是 `String`（token 名），不接受 `Color`。

### 防呆 2: Token 名拼錯立即 build 失敗

```json5
// ❌ manifest 載入時 throw FormatException
{
  "tiers": {
    "list.item.title": {
      "textColor": "textPrimery"  // 拼錯
    }
  }
}
```

實作：TierManifest.load() 比對 `tokens.keys` 與每個 tier 的 `textColor/bgColor/borderColor` 值，**任何不在 tokens 內的字串立刻 throw**。

### 防呆 3: 所有 Tier 必須有 default fallback

```dart
// 編譯期強制：每個 Tier 都要在 manifest 內定義，否則 TierStyle.of() 拋例外
final style = TierStyle.of(context, Tier.app.title);
// 如果 manifest 沒定義 app.title → throw StateError
```

實作：TierStyle.of() 內部 `assert(manifest.containsTier(tier), 'tier $tier 未定義')`。

---

## 📦 主題包 manifest 格式（完整版）

```json
{
  "id": "bridge_default_v2",
  "name": "橋樑預設 v2",
  "version": "1.0.0",
  "author": "Bridge Team",
  "license": "MIT",
  "minBridgeVersion": "1.0.0",
  "targetModes": ["dark", "light"],

  "fonts": {
    "base": "Inter",
    "mono": "JetBrainsMono",
    "baseFile": "fonts/Inter-Regular.ttf",
    "monoFile": "fonts/JetBrainsMono-Regular.ttf"
  },

  "tokens": {
    "canvas": "#0A0A14",
    "surface": "#14141F",
    "surfaceElevated": "#1F1F2E",
    "surfaceHover": "#2A2A3D",
    "borderSubtle": "#2A2A3D",
    "borderDefault": "#3D3D52",
    "textPrimary": "#FFFFFF",
    "textSecondary": "#B8B8C8",
    "textMuted": "#888899",
    "accent使用者": "#55B3FF",
    "accentPurple": "#533AFD",
    "accentGreen": "#5FC992",
    "accentYellow": "#FFBC33",
    "accentRed": "#FF6363",
    "accentNavy": "#061B31",
    "accentMagenta": "#F96BEE",
    "accentRuby": "#EA2261",
    "accentMiro": "#5B76FE",
    "success": "#5FC992",
    "warning": "#FFBC33",
    "error": "#FF6363",
    "info": "#55B3FF"
  },

  "tiers": {
    "app.title": {
      "textColor": "textPrimary",
      "fontSize": 24,
      "fontWeight": "w700",
      "fontFamily": "base",
      "lineHeight": 1.4
    },
    "app.subtitle": {
      "textColor": "textSecondary",
      "fontSize": 16,
      "fontWeight": "w500",
      "fontFamily": "base"
    },
    "sidebar.row.title": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "sidebar.row.subtitle": {
      "textColor": "textSecondary",
      "fontSize": 13,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "sidebar.row.meta": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "mono"
    },
    "card.title": {
      "textColor": "textPrimary",
      "fontSize": 16,
      "fontWeight": "w700",
      "fontFamily": "base"
    },
    "card.body": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w400",
      "fontFamily": "base",
      "lineHeight": 1.6
    },
    "card.caption": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "list.item.title": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "list.item.subtitle": {
      "textColor": "textSecondary",
      "fontSize": 13,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "list.item.meta": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "mono"
    },
    "form.label": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "form.input": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "form.helper": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "dialog.title": {
      "textColor": "textPrimary",
      "fontSize": 18,
      "fontWeight": "w700",
      "fontFamily": "base"
    },
    "dialog.body": {
      "textColor": "textSecondary",
      "fontSize": 14,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "button.primary": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "button.secondary": {
      "textColor": "textSecondary",
      "fontSize": 14,
      "fontWeight": "w500",
      "fontFamily": "base"
    },
    "status.success": {
      "textColor": "success",
      "fontSize": 14,
      "fontWeight": "w500"
    },
    "status.warning": {
      "textColor": "warning",
      "fontSize": 14,
      "fontWeight": "w500"
    },
    "status.error": {
      "textColor": "error",
      "fontSize": 14,
      "fontWeight": "w600"
    },
    "status.info": {
      "textColor": "info",
      "fontSize": 14,
      "fontWeight": "w500"
    },
    "bg.panel.base": {
      "bgColor": "canvas"
    },
    "bg.panel.elevated": {
      "bgColor": "surfaceElevated"
    },
    "bg.panel.hover": {
      "bgColor": "surfaceHover"
    },
    "bg.panel.selected": {
      "bgColor": "accent使用者"
    },
    "border.subtle": {
      "borderColor": "borderSubtle",
      "borderWidth": 1
    },
    "border.default": {
      "borderColor": "borderDefault",
      "borderWidth": 1
    },
    "border.strong": {
      "borderColor": "textPrimary",
      "borderWidth": 2
    }
  }
}
```

---

## 📘 使用範例

### Widget 程式碼

```dart
// ❌ 舊寫法：直接寫 token
Text('夥伴名', style: TextStyle(
  color: BridgeDSColors.of(context).textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w600,
))

// ✅ 新寫法：用 tier
Text('夥伴名', style: TierStyle.of(context, Tier.list.item.title).toTextStyle)
```

### Container 程式碼

```dart
// ❌ 舊寫法
Container(
  color: BridgeDSColors.of(context).canvas,
  child: ...,
)

// ✅ 新寫法：用 tier
Container(
  decoration: TierStyle.of(context, Tier.bg.panel.base).toBoxDecoration,
  child: ...,
)
```

### ⚠️ AlertDialog / 新元件的鐵則（2026-09-21 Blue 抓包）

**事件**：回收桶 dialog 用了 Material 預設的 `Theme.of(context).textTheme`
（AlertDialog 原生字級），結果：①dialog 標題字大於 App 大選單標題
②內文說明字反而比標題大——層級邏輯全倒。

**鐵則：任何新元件（特別是 AlertDialog/SnackBar/彈出面板），
文字層級一律走 Tier 系統，顏色一律走 BridgeDSColors.of(context)——
禁止 `Theme.of(context).textTheme`、禁止 `colorScheme.error`（用
`BridgeDSColors.of(context).accentRed`）、禁止 Material 預設。**

Dialog 內建議對應（`assets/theme_packs/bridge_default_v2.json`）：

| 元素 | Tier | 字級/字重 |
|---|---|---|
| dialog 標題 | `Tier.dialogTitle` | 18 / w700 |
| dialog 內文 | `Tier.dialogBody` | 16 / w400 |
| 列表項標題 | `Tier.listItemTitle` | 14 / w600 |
| 列表項 meta（時間、數量）| `Tier.listItemMeta` | 12 / mono |
| 日期分組標題 | `Tier.listItemMeta` + w600 | 12 / mono（必小於列表項）|
| 按鈕 | `Tier.buttonSecondary` | — |
| 危險操作色 | `accentRed` | — |
| dialog 背景 | `surfaceElevated` | — |

---

## ✅ 驗收清單

- [ ] Tier API 編譯期禁止傳 `Color`（只能傳 token 名 String）
- [ ] TierManifest.load() 編譯期驗證所有 token 名存在
- [ ] 每個 tier 都要有 fallback（未定義就 throw）
- [ ] 範例 widget 改用 tier，驗證深淺色切換正常
- [ ] 範例主題包匯入後，全 App 一鍵對齊
- [ ] 故意寫錯 tier 名 → build 失敗

---

## 🔗 相關文件

- `docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md` — 9 級距字體 + 33 token
- `docs/BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md` — V2 canvas 抽出的色塊規則
- `lib/theme/bridge_design_system.dart` — BridgeDSColors 定義
- `lib/theme/tier.dart` — Tier enum
- `lib/theme/tier_style.dart` — TierStyle API
- `lib/theme/tier_registry.dart` — manifest 載入

---

**作者**：教練 Agent（MiniMax-M3），2026-08-05
**審查**：使用者 CEO
**版本**：v1.0