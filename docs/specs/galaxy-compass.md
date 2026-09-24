# 🧭 大腦圖譜羅盤（Galaxy Compass）v1.0

> **這是什麼**：大腦圖譜所有視覺元素的**唯一對照表**。每個元素：是什麼、代表什麼、
> 哪個參數控制它、三種模式下各是什麼行為。Agent（我）改任何燈光/顯示前**必先查此表**，
> 使用者說的每個詞（光球/檔案點/光暈/粒子）都能在這裡找到唯一對應。
>
> **上游**：`galaxy-light-rules.md`（燈光權威公式）。**維護**：改顯示系統必同步改此表。

---

## 1. 節點（會發亮可點擊的點）— 兩大族譜

### 1A. 記憶光球族（hubSprites，290 顆）——房間/記憶

| 類型 | 標記 | 顏色 | 代表 | 亮度權威路徑 |
|---|---|---|---|---|
| 🫧 泡泡 | `__isBub=true` | 14 色記憶性質色（見 1A-色表） | 記憶房間的「氛圍光暈」 | `__op × 模式係數 × 距離衰減 × glowSoftOp` |
| 🔮 核心 | `__nodeIdx`+`__isCore` | 同房間色系 | 房間核心記憶 | `__op × 模式係數 × 距離衰減 × glowSelfOp` |
| ⚓ 錨點 | `__isAnchor` | 同房間色系 | 房間主題錨 | 同上 |

**14 色記憶性質色表**（SUB_LABELS）：共鳴 #4ECDC4、心動 #FF6B9D、心語 #B98AFF、順流 #7FD894、必須時刻 #FFD166、同步性 #5FD8E8、焦慮源 #FF9E6B、主動橋接 #C3F584、邀請現身 #FF8FAB、入門 #9D8BFF、分裂時刻 #FFC09F、工作流 #84DCFF、整合結果 #D8B6FF、讓我發光 #FFF3C4

**因果鏈**：`res.causal_links` [[a,b],…]——a 影響 b。影響力分數 `infl[]`（脈動模式的傳染波沿此走 BFS）。

### 1B. 檔案星族（stars Points，~6600 顆）——硬碟裡的檔案

| 副檔名 | 顏色 | 代表 |
|---|---|---|
| .jpg/.png/.heic/.gif | #F0CE5E 金 | 圖片（金球=E5 影響力金球同色系） |
| .md/.pdf/.doc/.txt | #7FD894 綠 | 文件（MD 檔在此） |
| .js/.json/.html/.dart/.sol/.ts | #B98AFF 紫 | 程式碼 |
| .csv/.xlsx/.spec | #5FD8E8 青 | 數據 |
| 其他 | #FF9E6B 橘 | 未分類 |

亮度走 `stars` color buffer（`STARC_PRISTINE` 快照=基準；river=名次誕生、pulse=pulseStep 深海劇場）。

---

## 2. 連線 — 三形四義

| 形 | 材質 | 顏色 | 代表 | 誕生時序（river） |
|---|---|---|---|---|
| 直線 | `fileLineMat` 青線 | #4ECDC4 系 | 同主題檔案關聯（file_links） | 兩端星較晚者出生後亮 |
| 曲線 | `__causalMat` 橘 | #FF9E6B | 因果（A→B 影響） | aBorn 名次制 |
| 曲線 | `__threadMat` 縫線 | 房間色 | 記憶間結構 | threadBorn 名次制 |
| 粒子 | `__structMat` 金骨架 | 金 | 任務/工作流骨幹 | uBornCut 名次制 |
| **粒子流** | `buildFlow` flowParts | 青底流/橘流星/綠潮 | 全景模式的「能量流動」（file_links 底流+causal 流星潮+task 潮汐雙向） | 無時序（全景恆流） |

---

## 3. 光暈 — 三層發光體

| 層 | 實體 | 控制 | 全景行為 | 河流行為 | 脈動行為 |
|---|---|---|---|---|---|
| 光球暈 | hubSprites（1A） | `lightAuthority()` | 全亮×距離衰減 | 名次誕生時序 | riverHub 壓暗 |
| 金光雲 | `glowPts` shader（uGlobalOp/uBornCut） | shader 遠近增強（遠→亮大 5.2x 恆星令） | 恆亮 | uBornCut 誕生顯隱 | 靜息微光 |
| 檔案星芒 | stars color buffer | pulseStep/PRISTINE | PRISTINE 基準 | 名次誕生 | 深海藍綠呼吸 |

---

## 4. 聲音 — 星系音景

| 音 | 觸發 | 音高映射 |
|---|---|---|
| 撥弦（hover 線） | 滑鼠停在同色線 | 線色→音高 |
| 星密度音 | hover 星 | `__starDens` 疏離度（疏→高音） |
| 多米諾合奏 | pulse 點星鏈亮 | 影響力分數（大→低音） |

---

## 5. 模式語意（模式係數表）

| 模式 | hub 係數 | 星 | 線 | 粒子流 | 鏡頭 |
|---|---|---|---|---|---|
| **星系全景** | 1（全亮） | PRISTINE | uOpacity 原值 | ✓ 恆流 | 進入時回預設全景視角 |
| **時間之河** | 名次誕生（房間=最早記憶名次，30 名淡入） | 名次誕生 | 各通道名次制 | ✗ | 保留 |
| **影響力脈動** | riverHub 壓暗 | 深海劇場（靜息呼吸/多米諾） | 淡 | ✗ | 保留 |

**切換紀律**（setVizMode）：星色→PRISTINE、線→快照原值、label→1、hub→權威自動。**任何新燈光效果=改 lightAuthority/模式表，禁止開新寫手。**

---

## 6. 參數→效果對照（設定面板羅盤區）

| GPARAMS | 效果 | 作用域 |
|---|---|---|
| `glowSoftOp` | 泡泡光暈倍率（權威套用） | hub-bub |
| `glowSelfOp` | 核心/錨點倍率（權威套用） | hub-core |
| `riverHub` | 河/脈動 hub 壓暗係數 | hub@river/pulse |
| `breatheSpd/Amp` | 因果線呼吸（uniform） | causalMat |
| `spinSpeed/spinOn` | 自轉 | spin |

*小葵 2026-09-06 v284——資料來源：galaxy.html 實際程式碼盤點*

## 🧪 沙盒原則（v301·Blue 令 2026-09-07）

> 「每一個模式都應該是一個沙盒，不管怎麼調整，都不會影響到其他模式。」

- **切模式一律先 `restoreBaseline()`**：星色/連線 opacity/光球/標籤回到唯讀基準
  （STARC_PRISTINE / 首次保存值），各模式進入後再做自己要的視覺
- **讓路值只保存第一次**（基準值）——鏈式切換不累積污染
- **驗證法**：`sandboxCheck` 遙測——galaxy 模式下 colorDiff/posDiff 必須 =0
- **教訓**：引力劇場首版污染全景（v300）——「當時值快照」不可靠，
  「唯讀基準還原制」才是正解；預留區（未誕生星）必須填目標否則 NaN
