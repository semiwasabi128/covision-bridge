# 生命樹統一迴路設計（Life Tree Unified Loop — R 階梯）

> v1.0 · 2026-09-21 · Blue 拍板「動手前先把 K/W 兩階梯對上，不要各自造階梯」
> 本文取代兩份舊設計的分散狀態，統合為一條迴路：
> - 舊 K 階梯（2026-09-20，夢境沉思設計案＋生命樹雙主幹）
> - 舊 W 階梯（2026-09-17，羅盤軍醫解剖圖 W1-W5）

---

## 0. 統一原則（Blue 2026-09-21）

**一條迴路、五刀、兩個舊階梯全部吸收、沒有孤兒。** 以終為始：先描述可驗證的終點畫面，再倒推施工順序。

## 1. 終點畫面（可驗證現實，非願望）

1. 使用者問「小葵生日」→ K1 判 need（<0.15s）→ 向量檢索命中 → 回答。
2. Agent 修 bug 撞牆兩次 → W4 自動立案 → 修好 → 藥方自動入庫 → 下一次 preFlight 出診就看得到（不靠人手寫）。
3. 每週夢境（K5）讀 K1 錯題＋W4 新藥＋遺憾清單 → 結論卡掛生命樹雙主幹 → 回饋 K1 閾值。
4. compass.self 儀表：諮詢率、藥效、K1 漏查率——整個循環活著、使用者看得到。

## 2. 吸收對照表（新舊映射，無孤兒）

| R 刀 | 內容 | 吸收的舊項 | 狀態 |
|---|---|---|---|
| R1 | 生命樹 schema（dream＋thought_branch 雙主幹表＋唯一寫入口） | K5 的地基、9/20 雙主幹設計 | ✅ 2026-09-21 完成 |
| R2 | W4 補完：傷口自癒（失敗≥2 立案 → 修復 → compass_propose 自動草擬藥方） | W4（9/17 拍板的殺手級驗收） | 待工 |
| R3 | K1 實作上線（decision/ 三檔＋規則層＋escalate 0.7＋樣本入 ledger） | K1（設計稿 v0.1 `3ef13a2d`，97% 實證） | 待工 |
| R4 | compass.self 儀表（K1 漏查/誤查/escalate 率＋W4 藥效＋覆蓋率） | W5＋K4（兩個觀察者合一） | 待工 |
| R5 | K5 夢境沉思 MVP（讀儀表線索＋雙主幹 → 結論卡 → 回饋） | K5、K2/K3（回放併入議程生成） | 待工 |

既有已落地件（不重做）：
- W1 intent_index v7 ✅、W3 出診三觸發點（compass_medic 244 行全接線）✅
- W2 藥箱 81 規則＋40 坑卡 🟡（R2 自癒上線後自然增長，不另開刀）
- 向量檢索地基（2026-09-21 `1a59387a` 三斷點修復）✅

## 3. 迴路圖

```
        使用者訊息 / Agent 工具呼叫
                  │
     ┌────────────┼────────────┐
     ▼            ▼            
   K1 守門員    W3 出診(preFlight/撞牆)
     │ 判斷       │ 注入藥卡
     ▼            ▼
   路由/escalate  執行 → agent_causal_ledger（歷史主幹・主枝幹）
     │                        │
     │ 錯題樣本                │ 失敗≥2 → W4 立案 pending pitfall
     ▼                        ▼
   ledger ←────────── 修復成功 → compass_propose 藥方入庫
     │                        │
     │                        ▼
     │              R4 compass.self 儀表（紅燈=精靈線索）
     │                        │
     ▼                        ▼
   K1 自訓練（線性頭重訓）   K5 夢境沉思（議程=紅燈+K1錯題+遺憾清單）
     │                        │
     │                        ▼
     │              結論卡 → life_tree_dreams（夢境主幹）
     │              重評遺憾 → life_tree_thought_branches.revisit
     ▼                        │
   判斷力變準  ←──────────────┘ 結論回饋閾值/規則
     ↺ 完整迴路
```

## 4. 各刀規格要點

### R1（已完成）
- 表：`life_tree_dreams`（夢境主幹）、`life_tree_thought_branches`（歷史主幹子枝幹）建於 causal_ledger.db
- 唯一寫入口：`lib/services/life_tree/life_tree_store.dart`（gate 家族模式）
- 回歸鎖：`test/life_tree_store_test.dart`（真 DB 往返 3 項）

### R2 傷口自癒
- 觸發：同工具連續 success=0 ≥2（ledger 既有資料）
- 立案：compass_pitfalls 新增 pending 卡（症狀=context_digest、藥方=空）
- 閉環：同工具後續 success=1 且脈絡相近 → 自動 compass_propose 帶「這次怎麼解的」
- 驗收（Blue 9/17 殺手級）：修復測試後查羅盤，應看到新坑卡 pending→草擬→入庫全鏈自動——**自癒層沒過＝羅盤只是圖書館**

### R3 K1 實作
- 詳規格：`docs/K1_DECISION_GATEKEEPER_DESIGN.md`（escalate 0.7 已拍板）
- 樣本寫入掛 R1 表（錯題=thought_branch 素材）

### R4 儀表
- compass.self 器官：K1 漏查率/誤查率/escalate 率＋W4 藥效（出診後同工具失敗率降幅）＋覆蓋率
- 精靈複驗（K4）不另建——儀表紅燈即精靈線索，進 R5 議程

### R5 夢境 MVP
- 議程三源：儀表紅燈＋K1 錯題本＋遺憾清單（unrevisitedBranches）
- 結論卡三選一：maintain / propose / escalate_to_user
- 文風鐵則沿用 9/20 設計案（≤5 行、禁工程術語、白話結論）
- 動態冷門時段（Blue 9/20 令：不固定 23:00，依使用者使用習慣找最冷門時段）

## 5. 驗收（迴路整體，以終為始）

| # | 哨兵 | 通過標準 |
|---|---|---|
| 1 | 生日題端到端 | K1 判 need + 向量命中 + 回答正確（$9 同款題不再燒錢） |
| 2 | 撞牆自癒 | 故意撞牆兩次→修復→羅盤出現新坑卡（全自動） |
| 3 | 夢境閉環 | 一場夢產出結論卡入 life_tree_dreams＋遺憾清單少一條 |
| 4 | 儀表活著 | compass.self 四指標有真實數字（非零非靜態） |
