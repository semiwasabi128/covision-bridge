# 🔧 Modding Guide — 把 Bridge 改成你的樣子

> 這台車生來就是給你改的。
> 換烤漆、調引擎、加渦輪——四個改裝層，由淺到深，全部合法。

Bridge 的核心信念之一：**你的 App 是你的**。我們把「可改裝性」當功能來設計，
不是事後補丁。這份指南按改裝深度分四層——L1 十分鐘見效，L4 是真正的引擎改裝。

---

## 改裝層總覽

| 層 | 改什麼 | 要重新編譯？ | 適合誰 |
|---|---|---|---|
| **L1** | 主題包（顏色/字級/字型） | ❌ 免編譯 | 所有人 |
| **L2** | 大腦星系調校（視覺/音效/物理） | ❌ 免編譯 | 所有人 |
| **L3** | 內容與流程（畫布/範本/夥伴） | ❌ 免編譯 | 所有人 |
| **L4** | 原始碼（新按鈕/新節點/新指令） | ✅ 需重編 | 開發者 |

---

## L1 · 主題包 — 一鍵換全 App 外觀

**原理**：Bridge 不允許任何 widget 寫死顏色。所有 UI 走三層架構：

```
widget 呼叫 TierStyle.of(context, Tier.cardBody)
  → tier manifest（33 個語意層級：list.item.title、bg.panel.base…）
    → BridgeDSColors token（實際色值）
```

所以**改 token 值 = 200+ 個 widget 同時變色**，一行 widget 程式碼都不用碰。

**改法**：
1. 到 App 內：系統設定 → 主題 → 自訂主題包
2. 或直接編輯 tier manifest JSON，App 重啟即載入

**規範**：[`docs/BRIDGE_TIER_SYSTEM.md`](../BRIDGE_TIER_SYSTEM.md)（含 AlertDialog 鐵則）
**設計語言**：[`docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md`](../BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)

> 💡 深色/淺色/任何主題包下 UI 都要正確顯示——這是所有 PR 的驗收標準。

---

## L2 · 大腦星系調校 — 你的資料宇宙，你的物理律

大腦星系圖譜（3D Brain Galaxy）所有視覺與聽覺都是參數，即時生效：

- **視覺**：自轉速度、呼吸節奏、光暈、星點大小、弦的弧度
- **音效**：撥弦音量/音域/殘響、星音（副檔名決定音高家族——程式碼是 C6、文件是 A5 🎵）
- **顏色**：每種記憶性質的代表色，改色 1 秒內全場換裝

**改法**：星系右上設定窗拉桿即時預覽，或 `POST /galaxy_params`（App 內建 MCP :8420）。
參數持久化在 `galaxy_params.json`，**每個模式（全景/時間之河/作戰）參數獨立**——
時間之河調暗不妨礙全景明亮。

**系統解剖圖**（改星系前必讀）：羅盤規則 `galaxy.structureCatalog`——九大子系統
（資料/場景/渲染/互動/模式/音效/參數/橋接/擴充）各自的真相源與鐵則。

---

## L3 · 內容與流程 — 不改碼發明新用法

**畫布工作流**：節點＋連線＝你自由組裝的管道。LLM → 生圖 → 願景分析 → 定案圖組，
任何組合都是合法工作流。範本只是起點。

**範本改裝**：`lib/services/semicanvas/vault_templates.dart` 內建範本（角色設定圖組等）
——複製一份改 prompt、改流程，就是你的新範本。

**夥伴（Companions）**：每個 AI 夥伴的外觀、聲音、人格設定都是資料不是程式碼。
召喚你的、捏成你要的樣子。

---

## L4 · 原始碼改裝 — 打開引擎蓋

### 長一顆星系新按鈕/新模式

星系的三個模式按鈕（全景/時間之河/作戰）就是三個前例。第七步誕生術：
1. `VIZ_NAMES` 註冊新模式名——按鈕自動長出來
2. 實作放獨立 layer 檔（範本：`swarm_layer` 的 `__warEnter/__warExit` 委託模式）
3. **沙盒令**：進場做自己、出場回基準（A 模式不得污染 B 模式）
4. hover/音效走既有 raycast 鏈，勿另建
5. 分幀拾取（每幀 1/8 星）是效能命脈，勿改回全量
6. 出廠參數加進 `GPARAMS` ＋模式參數包
7. rebuild ＋破快取，完成

完整規則：羅盤 `galaxy.modeExtension`。

### 長一顆畫布新節點

1. `NodeTypePorts.portsFor` 註冊節點型別與接頭
2. `node_widget.dart` 加渲染 case
3. executor 加執行分支
4. 畫布上它就是一等公民——可連線、可單跑、可進定案圖組

### 長一條 MCP 新指令

App 內建 MCP server（:8420）已示範 `/galaxy_params`、`/galaxy_ping`（遙測+遠端指令）。
照 pattern 加 router 條目，外部 agent 立即可用。

---

## ⚖️ 改裝憲法（不可違反）

1. **禁寫死顏色**——一律走 Tier token，違規 PR 不可 merge
2. **沙盒令**——新模式退出必須完整還原基準，不留殘留態
3. **效能紀律**——GPU ≤ 5% / CPU ≤ 8%（氣氛層）
4. **衝突裁決**——功能骨架 → 關係推演 → 事件氣氛，三層不反轉

## 🗺️ 更多地圖

- 架構地圖（想改 X 去哪改）：[`docs/APP_ARCHITECTURE_MAP.md`](../APP_ARCHITECTURE_MAP.md)
- 設計統合：[`docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md`](../BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)
- 排版：[`docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md`](../BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)

> 改完記得回到 App 的羅盤（Compass）看看——你的改裝心得可以寫成規則，
> 讓未來的 Agent 直接繼承。這台車的說明書，是所有改車人一起寫的。
