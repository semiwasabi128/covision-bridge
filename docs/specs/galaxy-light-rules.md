# 星系燈光規則（Light Rules）— v284 燈光權威令

> Blue 2026-09-06：「到底哪些東西要同步、哪些要亮、哪些要按照時序亮，
> 這些規則要寫在規則裡面。建立一個規則，讓規則去運行。」

## 鐵則：單一權威

**hub 光球（泡泡/核心/錨點）的 opacity 與 visible，只由 `lightAuthority(t)` 每幀寫。**
其他任何系統（LOD 淡出、G 群設定面板、模式進出、river 時序、pulse 壓暗）
**一律只提供輸入參數，不得直接寫值。**

## 公式

```
最終亮度 = __op(建構基準) × 模式係數 × 距離衰減 × 設定倍率
visible  = 最終亮度 > 0.02
```

### 模式係數（唯一由 VIZ.mode 決定）

| 模式 | 係數 | 說明 |
|---|---|---|
| galaxy 全景 | 1 | 全亮（信任距離衰減） |
| river 時間之河 | 誕生時序 | 名次制：房間最早記憶名次前=隱形，誕生後 30 名次淡入（`__hubBornRank`） |
| pulse 影響力脈動 | `GPARAMS.riverHub` | 深海壓暗（與河中共用參數） |

### 距離衰減（全模式一致）

- 世界座標投影螢幕半徑 rpx
- `rpx < 2.5` → 0（遠端退場，省 GPU）
- `rpx ≥ 64` → 0（近看退場，看清節點）
- 之間線性：`(64-rpx)/(64-20)`
- **用世界座標（galaxy.localToWorld）**——v276 教訓：本地座標投影=星系一轉全錯

### 設定倍率

- 泡泡 `glowSoftOp`／核心錨點 `glowSelfOp`（G 群面板）——只透過權威生效

## 星（檔案星/金球光雲）的規則（非 hub，另行管理）

- **金球光雲**（glowPts shader）：`uBornCut`（river 誕生顯隱）＋ shader 內建遠近增強（遠→亮大 5.2x，恆星令：永不熄滅）
- **檔案星**（stars Points color buffer）：
  - galaxy=PRISTINE 色值
  - river=誕生時序（starRank 名次制）
  - pulse=深海劇場（pulseStep：靜息藍綠呼吸/多米諾爆閃/聚焦極暗）
  - 退出任何模式=還原 PRISTINE 快照（唯讀）
- **線系**：uOpacity（材質 uniform）＋ uBornCut/uGrowCtl 誕生時序——river 快照/還原

## 模式切換語意（setVizMode）

1. 進任何模式前：星色還原 PRISTINE、線 opacity 還原快照原值、label=1
2. 進 galaxy：鏡頭回預設全景視角（光暈按遠亮設計自然在）
3. 進 river：riverSaveMaterials 快照＋tCursor 歸零（時序從頭播放）
4. 進 pulse：buildPulse（儀表板/心電圖/靜息態）
5. hub 一律不在此處寫——權威每幀接管

## 已退役的寫手（勿復活）

| 舊寫手 | 位置 | 為何退役 |
|---|---|---|
| LOD apply（hub 部分） | animate 100ms 節流 | 與 G 群/模式互蓋=閃屏 |
| G 群直寫 opacity | `__gparamApply` | 同上 |
| buildPulse hub 壓暗 | buildPulse | 權威內建 |
| river hub 時序直寫 | riverStep | 權威內建（__hubBornRank 預計算保留） |
| setVizMode hub 還原 | v275b 還原段 | 權威自動 |

## 新增燈光效果的規則

1. 想加「模式係數」→ 改 lightAuthority 的模式表
2. 想加「設定」→ 加 GPARAMS 參數，權威讀取
3. 想加「新視覺系統」→ 只寫自己的材質/uniform，不碰 hubSprites

*小葵 2026-09-06 v284*
