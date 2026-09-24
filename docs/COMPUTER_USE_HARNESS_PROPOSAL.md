# 橋樑代操引擎（Bridge Computer-Use Harness）架構提案 v0.1

> **立案日**：2026-09-11
> **提案人**：小葵（應 Blue 2026-09-11 指令展開）
> **一句話**：用「harness 開源、模型可插拔」的路線，讓 GLM API 組出 GPT-6 Astra 等級的跨軟體代操體驗——而且靠畫布＋羅盤，做出 Astra 沒有的兩張牌。
> **北極星**：AI 自由 + Token 自由 + 數位資產主權（橋樑宣言）。Astra 的體驗不該被鎖在單一閉源模型上。

---

## 0. 為什麼可行（問題定義）

Astra 的「風靡全球的操作體驗」拆開來看 = **四個零件**：

| 零件 | Astra 的做法 | 我們有沒有 |
|---|---|---|
| 眼（視覺判讀） | 專門 RL 訓練的視覺 grounding | ✅ GLM-4.6V（原生 bbox grounding＋原生多模態工具調用） |
| 腦（規劃/自癒） | 長序列 agent RL | ✅ GLM-5.3（agent loop 推理，小葵本人即在跑） |
| 手（動作執行） | OpenAI harness 內建 | ✅ macOS 本地：cliclick / AppleScript / Accessibility API，零模型成本 |
| 記憶（跨任務） | 沒有——上下文結束即忘 | ✅ 羅盤 compass_store.db（Astra 反而沒有） |

**關鍵認知**：Astra 的體驗 = 模型（眼＋腦）× harness（手＋迴圈＋記憶）。模型買得到（GLM API），harness 是工程——工程正是橋樑 App 的主場。

---

## 1. 分層架構（三層）

```
┌────────────────────────────────────────────────────────┐
│  第三層：腦 Brain — 任務規劃與指揮                          │
│  模型：GLM-5.3（z.ai API，語言旗艦）                       │
│  職責：目標分解 → 步驟排程 → 派工 → 驗收 → 出錯自癒 → 回報    │
├────────────────────────────────────────────────────────┤
│  第二層：眼 Eyes — 感知與定位（三通道，優先序如下）           │
│  ① 結構通道：MCP CanvasSnapshot（App 內免截圖，JSON 直讀）     │
│  ② 腳本通道：DXF 解析 / bpy / Ruby / GDScript 直取軟體資料     │
│  ③ 視覺通道：GLM-4.6V 截圖 grounding → bbox → 座標映射（最後手段）│
│  視覺模型：GLM-4.6V（多模態旗艦）                           │
│  路由規則：能用結構不用腳本，能用腳本不截圖；視覺僅 GUI-only 場景 │
├────────────────────────────────────────────────────────┤
│  第一層：手 Hands — 動作執行（純本地，零 token）              │
│  cliclick（滑鼠/鍵盤）＋ AppleScript（App 操控）             │
│  ＋ Accessibility API（UI element 查詢，輔助定位驗證）        │
└────────────────────────────────────────────────────────┘
        ↑ 每步動作後：再截圖 → GLM-4.6V 驗證 → 回報腦層
```

### 1.1 模型路由表（每層用該 API 的最高模型）

| 層 | 模型 | 為什麼是它 | 備援（fallback） |
|---|---|---|---|
| 腦（規劃） | **GLM-5.3** | 語言旗艦，agent loop／分解／自癒最強 | GLM-4.6（文字）或本地模型 |
| 眼（grounding） | **GLM-4.6V** | 原生視覺 grounding（bbox 輸出）＋截圖可直接作為工具參數，免文字轉譯 | 結構通道（App 內）；UI-TARS 開源權重（本地 DGX） |
| 手（執行） | 無模型 | 純本地系統呼叫 | — |
| 記憶 | 無模型（羅盤 SQLite＋向量） | 跨任務經驗持久化 | — |

> **金鑰匙原則適用**：GLM key 一把設好，三層自動偵測可用（5.3 走 chat API、4.6V 走多模態 API，同一把 key）。鑰匙＝能力。

### 1.2 主迴圈（Agent Loop）

```
使用者目標
   │
   ▼
[腦 GLM-5.3] 分解成步驟清單（寫入任務狀態機）
   │  每個步驟：
   ▼
[眼] 感知：結構通道（App內）or 截圖→GLM-4.6V grounding
   ▼
[腦] 決定動作：click(x,y) / type(text) / hotkey / scroll / wait
   ▼
[手] 本地執行
   ▼
[眼] 再感知（驗證動作結果）──失敗──→ [腦] 重新規劃此步（最多 N 次）
   │ 成功
   ▼
下一步 …… 全部完成 → [腦] 彙總回報 + [羅盤] 寫入本次操作經驗
```

---

## 2. 橋樑獨有的兩張牌（對 Astra 的差異化）

### 牌一：畫布 = 結構化共視（混合通道）
Astra 只有一條視覺通道：所有東西都靠截圖（慢、貴、會認錯）。
橋樑 App 操作**自己內部**時走 MCP CanvasSnapshot——節點/連線/狀態直接是 JSON，零截圖、零 grounding 誤差、毫秒級。只有操作**外部軟體**（Premiere、Excel、瀏覽器…）才降級到視覺通道。
→ **自家主場比 Astra 快且準；外部戰場與 Astra 同規格。**

### 牌二：羅盤 = 跨任務操作記憶
Astra 每次任務都從零開始。橋樑代操引擎每次完成任務後把經驗寫入羅盤：
- 這個軟體的選單路徑、按鈕位置慣例、常見陷阱
- 下次操作同一軟體 → `compass_seek` 直接查表，跳過摸索期
→ 這正是「活 loop：做事→回報→檢討→升級→再做事」鐵則的代操版。

---

## 2.5 專業軟體整合矩陣（Blue 2026-09-11 指令場景）

| 場景 | 首選通道 | Agent 做法 | 可行度 | 誠實邊界 |
|---|---|---|---|---|
| AutoCAD 核對尺寸 | 腳本（DXF 直析） | `ezdxf` 讀 DIMENSION 標稱值 vs 幾何實測值比對，不開 GUI | ★★★★★ | 人類圖很髒（覆寫標註/圖層亂/比例跑掉）→ 產異常清單給人裁決，agent 不擅自改圖 |
| Blender 3D 室內/建築 | 腳本（bpy） | LLM 寫 Python 參數化建模（牆/門/窗/櫃），GLM-5.3 主場 | ★★★★★ | 結構層成熟（BenchCAD 路線已驗證）；美感層（燈光/材質）接世界模型 Marble 管線＋影像生成引擎 |
| SketchUp 3D 模型 | 腳本（Ruby API） | LLM 寫 Ruby 餵 Ruby console | ★★★★☆ | Ruby 生態較薄，LLM 生成品質需驗證迴圈；複雜案子建議導 Blender 路線 |
| Godot 遊戲角色（骨架能動） | 腳本（Blender Rigify → glTF → Godot headless） | 自動綁骨架 → 匯出 → GDScript 搭 AnimationPlayer＋狀態機 | ★★★★☆ | 「能走能跳能打」成立（可玩級）；電影級動捕品質不承諾 |

**通道優先序鐵則**：能用結構不用腳本，能用腳本不截圖。視覺通道只留給 GUI-only 軟體。

---

## 3. 安全與信任設計（不可妥協區）

1. **破壞性操作權力在使用者**：刪檔、送出表單、付款類動作 → dry-run 預覽＋明確確認才執行（既有鐵則直接套用）。
2. **UI 誠實鐵則**：每一步動作在畫布/任務面板上可見（做了什麼、看到什麼、成功/失敗），壞 token 必顯紅字，絕不假成功。
3. **背景化診斷**：所有截圖與動作日誌落盤，事後可完整回放（审计）。
4. **權限範圍**：代操引擎僅在獲授權的 App 清單內動作（macOS 螢幕錄製＋Accessibility 權限引導一次設定）。

---

## 4. 誠實的差距聲明（不吹）

- GLM-4.6V 的 grounding 強，但**長序列 agent RL 密度**不如 Astra（Astra OSWorld 72.6%、每任務快 47% 是大量專項訓練的結果）。Zhipu 自家 AutoGLM 已驗證這條路（DeviceUse 超過 ChatGPT Agent / Claude 4 Sonnet），但那是 phone/web 場景。
- 預期產品體驗曲線：**單步操作很準（第一天就成立）→ 三五步跨 App 流程可用（harness 驗證迴圈補）→ 數小時長任務（靠斷點續跑＋羅盤記憶逐步逼近）**。
- 這正是開源打法：模型會換（GLM→下一代→本地權重），harness 資產（迴圈＋記憶＋安全設計）留在橋樑。

---

## 5. 分期路線圖

### P0 — 視覺通道 MVP（證明「眼看手到」）
- `screencapture` → GLM-4.6V grounding → 座標映射 → cliclick 執行 → 再截圖驗證
- 交付驗收：對指定外部 App 完成 3 步操作（開 App → 點某按鈕 → 讀取結果回報）
- 驗證哲學：紅隊自測——出題攻自己的 grounding 準確度與驗證迴圈

### P1 — 腦層任務狀態機 + 混合通道
- GLM-5.3 規劃層上線（步驟分解/派工/自癒）
- CanvasSnapshot 結構通道接入：App 內操作零截圖
- 任務面板 UI：步驟清單＋每步成敗＋可中斷

### P2 — 羅盤記憶 + 長任務
- 操作經驗寫入羅盤（compass_organs 新增 `computer_use` 系統群組；軟體操作訣竅進 compass_pitfalls）
- 斷點續跑：任務狀態持久化，App 重啟可續
- 經驗命中率指標：同軟體第二次任務的步數/token 消耗應顯著下降

### P3 — 開源社群與本地化
- 模型可插拔介面（provider registry 既有機制）：GLM / 開源權重（GLM-4.6V 權重已開源，vLLM/SGLang 可跑）→ DGX Spark 全本地
- 招式系統整合：一次成功代操可存成「招式」重複使出

---

## 6. 與既有系統的接點

| 既有系統 | 接法 |
|---|---|
| 能力中心 capability_center | 新增「代操引擎」能力卡＋GLM 金鑰狀態 |
| MCP server（Dart shelf） | 新增 `screen_capture` / `grounding` / `act` 三個 tool endpoint |
| 羅盤 compass_store.db | P2 起：compass_organs 新系統群組＋經驗寫入 |
| 畫布 CanvasSnapshot | P1 起：結構通道感知來源 |
| provider registry | 模型路由表落地處（每層可獨立換模型） |

---

## 7. 風險清單

| 風險 | 緩解 |
|---|---|
| grounding 座標誤差（高解析度/Retina 縮放） | 座標映射明確處理 scale factor；Accessiblity API 交叉驗證 |
| 長任務 context 爆炸 | 每步只留「動作+結果摘要」，截圖不長駐 context |
| API 費用失控 | 每任務 token 預算上限＋面板即時顯示消耗 |
| 誤點破壞性按鈕 | §3 安全設計：dry-run＋確認閘門 |

---

*本文件為提案（proposal），實作啟動時：①進 APP_ARCHITECTURE_MAP ②寫入羅盤 ③更新本文件版本號。*
