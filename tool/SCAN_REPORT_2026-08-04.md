# 🔍 設計違規掃描報告 — 2026-08-04

**工具**：`tool/scan_design_violations.sh`
**目標**：找違規字體 / 顏色 / padding 用法

---

## 📊 全專案統計

```
總掃描檔案: 484
總違規數:   2196

R1 (硬編碼 fontSize)        : 1290
R2 (Colors.xxx)             :  134
R3 (Color(0x...))           :  211
R4 (沒用 BridgeDSColors)    :   60
R5 (Container+BoxDecoration):  299
R6 (FontWeight.bold)        :   45
R7 (硬編碼 padding/margin)  :  202
```

---

## 🔴 問題頁面（Blue 提的「夥伴館 + 召喚夥伴」）

### 1️⃣ `lib/screens/companion_create_screen.dart` — 召喚夥伴
- **5639 行**（極大檔案）
- **fontSize: 83 條違規** ← 最嚴重
- **EdgeInsets.padding: 51 條違規**
- 還在用舊 `AppTheme.primary`（已廢棄，應該用 `BridgeDSColors`）

### 2️⃣ `lib/screens/companion_list_screen.dart` — 夥伴館列表
- fontSize: 35
- Color(0x...): 1
- EdgeInsets.padding: 23

### 3️⃣ `lib/screens/summon_screen.dart` — 召喚（手機版）
- fontSize: 9
- **Colors.xxx: 13** ← 違規 Material 預設色
- **Color(0x...): 18** ← 硬編碼顏色

### 4️⃣ `lib/screens/desktop_summon_screen.dart` — 召喚（桌面版）
- fontSize: 15
- EdgeInsets.padding: 25

---

## 📈 其他高違規檔案（Top 10）

| 違規數 | 檔案 |
|---|---|
| 139 | lib/screens/settings_screen.dart |
| 110 | lib/widgets/brain_reflection_panel.dart |
| 97 | lib/screens/companion_create_screen.dart |
| 83 | lib/screens/bridge_desktop_screen.dart |
| 69 | lib/services/theme_pack_service.dart |
| 62 | lib/widgets/local_llm_runtime_card.dart |
| 59 | lib/screens/vault_screen.dart |
| 57 | lib/widgets/canvas/v2/canvas_v2_workspace.dart |
| 51 | lib/screens/desktop/desktop_chat_panel.dart |
| 50 | lib/screens/desktop/system_pages/restore_history_page.dart |

---

## 🎯 修復優先順序（Blue 提案）

### P0 — 影響主題切換正確性
- **companion_create_screen.dart**：83 fontSize + 51 padding
- **summon_screen.dart**：18 Color(0x...) + 13 Colors.xxx ← 切換主題後這些會壞掉

### P1 — 一致性問題
- **companion_list_screen.dart**：夥伴館
- **desktop_summon_screen.dart**：桌面版召喚

### P2 — 之後處理
- 其他檔案（settings, brain_reflection 等）

---

## 💡 修復策略

### 機械化替換（自動）
- `fontSize: 14` → `BridgeDS.body.copyWith(color: ...)`
- `fontSize: 16` → `BridgeDS.bodyL.copyWith(color: ...)`
- `fontSize: 18` → `BridgeDS.headingS.copyWith(color: ...)`
- `fontSize: 20` → `BridgeDS.headingM.copyWith(color: ...)`
- `Color(0xFF...)` → 對應 BridgeDSColors token
- `Colors.white/black/...` → 對應 token

### 手動處理
- 結構問題（Container+BoxDecoration）→ 判斷是否該用 BridgeCard
- 整體視覺分類（依 Blue 報紙編排原則）→ 需要設計判斷

---

## ⏭️ 下一步

**B.4**：開始自動修復 P0 檔案（companion_create_screen.dart）
**B.5**：自動修復 P0 (summon_screen.dart)
**B.6**：跑一次掃描確認違規數下降
**B.7**：報告結果給 Blue review

---

**工具使用方式**：
```bash
# 掃全專案
bash tool/scan_design_violations.sh lib

# 掃指定檔案
bash tool/scan_design_violations.sh lib/screens/companion_create_screen.dart
```