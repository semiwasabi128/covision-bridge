# 🎨 Bridge 色塊設計規範 — 從 V2 Canvas 抽出

> **狀態**：v1.1（2026-08-05 更新）
> **來源**：Bridge App V2 Canvas（`lib/widgets/canvas/v2/*`）— 使用者 確認「眼睛舒服」的參考標準
> **適用**：所有 Bridge App 桌面 UI
> **違規處罰**：PR 不可 merge
> **v1.1 更新**：新增 48 個 BridgeDS color token（狀態/節點/灰階/Material 標準色）

> **📱 手機版刪除宣告（2026-08-10）**：
> - 手機版已正式宣告刪除，本規範專注於桌面版 UI
> - 未來手機版將重新設計，可能調整色塊規則以適應行動裝置

---

## 📚 為什麼需要這份文件？

之前所有頁面（夥伴館、設定、Vault 等）的色塊配色各做各的，看起來不一致。

V2 Canvas 是少數經過 使用者 眼睛驗證「舒服」的設計。

本文件**把 V2 的色塊結構抽象成規則**，其他頁面照著做。

---

## 🧱 三層視覺架構

V2 的畫面分**三個視覺層級**（由外到內）：

```
┌─────────────────────────────────────────────┐
│  ① 畫布主體（Canvas）         ds.canvas     │ ← 最外層
│  ┌─────────────────────────────────────┐    │
│  │ ② 卡片表面（Card/Section） ds.surfaceElevated │ ← 中層容器
│  │  ┌─────────────────────────────┐    │    │
│  │  │ ③ 強調區塊（Hot zone）       │    │    │
│  │  │   ds.surfaceHover /         │    │    │
│  │  │   ds.accent使用者.withValues() │    │    │
│  │  └─────────────────────────────┘    │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### 規則

| 層級 | Token | 用途 | 範例 |
|---|---|---|---|
| **① 主背景** | `ds.canvas` | App 最外層（無 padding）| Scaffold background |
| **② 卡片** | `ds.surfaceElevated` | 區塊容器（比 canvas 亮一級）| Card, Section, Panel |
| **③ 強調區** | `ds.surfaceHover` 或 `ds.accent使用者.withValues(alpha: 0.18)` | 高亮、hover、selected | selected state, hover state |

---

## 🎨 配色規則（語意 → Token 對應）

### 文字層級（由強到弱）

```dart
// 主標題：最重要
TextStyle(color: ds.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)

// 副標題：次要
TextStyle(color: ds.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)

// 內文：主體
TextStyle(color: ds.textPrimary, fontSize: 14)

// 註腳 / 弱化
TextStyle(color: ds.textSecondary, fontSize: 14)

// 提示 / placeholder
TextStyle(color: ds.textMuted, fontSize: 14)
```

### 強調色（語意）

```dart
// 連結 / 主要 CTA / 焦點
ds.accent使用者

// 大腦 / 向量專用（V2 大量使用）
ds.accentPurple

// 成功 / 完成
ds.accentGreen

// 警告
ds.accentYellow

// 錯誤 / 刪除
ds.accentRed
```

### 狀態色（v1.1 新增）

```dart
// Agent Loop 進度條
ds.toolPurple         // 強調色
ds.toolPurpleLight    // 提示文字
ds.softGreen          // 成功色

// 警示
ds.errorRed           // 標準錯誤
ds.alertRed           // 嚴重警告
ds.successGreen       // 沉靜綠
ds.successDark        // 深綠強調

// 背景
ds.bgLightRed         // 失敗背景
ds.bgLightGreen       // 成功背景
ds.bgVeryLightRed     // hover 失敗
```

### 節點配色（v1.1 新增）

```dart
// Canvas 節點類型對應
ds.file使用者      // 檔案節點
ds.sopOrange     // SOP 節點
ds.pinkAccent    // 子分析節點
ds.slate         // 預設節點
ds.teal          // 感知節點
ds.deepPurple    // 記憶節點
```

### 灰階（v1.1 新增）

```dart
ds.grey300  // 0xFFE0E0E0
ds.grey400  // 0xFFBDBDBD
ds.grey600  // 0xFF757575
ds.grey700  // 0xFF616161
ds.grey800  // 0xFF424242
```

### Material 標準色（v1.1 新增）

```dart
ds.red500      ds.red400      ds.red700mat
ds.green500    ds.green700    ds.green400
ds.blue500     ds.blue700
ds.orangeStd   ds.orange700
```

### 面板 / Divider（v1.1 新增）

```dart
ds.darkPanel      // CanvasDoodle 深色 (0xFF1E1E2E)
ds.darkCanvas     // Agent Loop 深背景 (0xFF0D0D1A)
ds.dividerIndigo  // Divider 分隔線 (0xFF2A2A4A)
ds.textOnAccent   // 純白按鈕前景
```

### 背景層級

```dart
// 最外層（深色幾乎是黑）
ds.canvas

// 容器（亮一級）
ds.surface

// 凸起卡（亮更多）
ds.surfaceElevated

// hover / pressed（亮最多）
ds.surfaceHover

// 半透明強調（背景 + 一點藍）
ds.accent使用者.withValues(alpha: 0.18)
```

### 邊框

```dart
// 細線
ds.borderSubtle

// 一般
ds.borderDefault

// 強調
ds.accent使用者 (width: 1.5)
```

---

## 📦 卡片標準結構（從 V2 抽出）

```dart
Container(
  padding: const EdgeInsets.all(12),  // 統一 12
  decoration: BoxDecoration(
    color: BridgeDSColors.of(context).surfaceElevated,
    borderRadius: BorderRadius.circular(8),  // 統一 8
    border: Border.all(
      color: BridgeDSColors.of(context).borderSubtle,
      width: 1,
    ),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.lightbulb_outline,
              size: 16,
              color: BridgeDSColors.of(context).accentPurple),
          const SizedBox(width: 6),
          Text('標題',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: BridgeDSColors.of(context).textPrimary,
              )),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '內文',
        style: TextStyle(
          fontSize: 14,
          height: 1.6,  // 行高 1.6 增加可讀性
          color: BridgeDSColors.of(context).textSecondary,
        ),
      ),
    ],
  ),
)
```

### 規則摘要

1. **padding 統一 `12`**（小卡）/ `16`（中卡）/ `24`（大區塊）
2. **圓角統一 `8`**（小）/ `12`（中）/ `16`（大）
3. **行高 `1.4-1.6`**（內文）
4. **icon size `14-16`**（小）/ `20`（中）/ `24`（大）
5. **icon + 標題組合**：`Icon + SizedBox(6) + Text`（永遠 6px gap）

---

## 🚫 違規（不要做的事）

```dart
// ❌ 用 AppTheme.xxx (不會跟主題變)
color: AppTheme.textSecondary
backgroundColor: AppTheme.primary

// ❌ 用 Colors.white/black
color: Colors.white
color: Colors.black

// ❌ 硬編碼 hex
color: Color(0xFF2A9D8F)

// ❌ 字體小於 14（使用者 規定）
fontSize: 12
fontSize: 13

// ❌ 用 const TextStyle 在 context-dependent 的地方
const TextStyle(color: BridgeDSColors.of(context).textPrimary)  // 會 throw!
```

---

## ✅ 檢查清單（每個 PR 都要過）

- [ ] 沒有 `AppTheme.xxx` 用於顏色（除了尺寸常數 spacingM, radiusLarge 等）
- [ ] 沒有 `Colors.white` / `Colors.black` / `Colors.red` 等 Material 預設色
- [ ] 沒有 `Color(0xFF...)` 硬編碼
- [ ] 沒有 `fontSize < 14`
- [ ] 顏色全部來自 `BridgeDSColors.of(context).xxx`
- [ ] 字體 token 來自 `BridgeDS.xxx`（display / headingL/M/S / bodyL / body / bodyTight / button / labelMono / caption / small）
- [ ] 卡片結構符合上方的標準模板

---

## 🔍 自動掃描工具

執行 `tool/scan_design_violations.sh lib` 一鍵檢查所有規則。

---

## 📊 V2 Canvas 驗證（眼睛舒服）

| 區塊 | V2 用法 |
|---|---|
| 畫布主體 | `ds.canvas` |
| 卡片 | `ds.surfaceElevated` + `ds.borderSubtle` |
| 強調區塊 | `ds.surfaceHover` 或 `ds.accent使用者.withValues(alpha: 0.18)` |
| 主標題 | `ds.textPrimary` + `bold` + icon `ds.accentPurple` |
| 內文 | `ds.textSecondary` + `fontSize: 14` + `height: 1.6` |
| CTA 按鈕 | `ds.accent使用者` 背景 + 白字 |
| 錯誤 snackbar | `ds.accentRed` 背景 |
| 成功 snackbar | `ds.accentGreen` 背景 |

**結論**：V2 是「正確」的參考實作。其他頁面照這個改即可。