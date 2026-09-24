# 刀 2：夥伴身份卡（Companion Identity Card）— 設計稿 v1

> 設計師：小葵  
> 日期：2026-09-08  
> 對應報告：docs/specs/2026-09-08-buzz-grokbot-optimization-report.md §4.2  
> 狀態：拍板前不動 code（**拍板即落地**）

---

## 一、這一刀解決什麼（G2）

夥伴系統升級為 **Buzz 式成員模型**：每個夥伴一張身份卡——
**自己的人格、自己的對話史、自己的審計軌跡、自己的權限範圍**。

現況：CompanionStore 有完整人格檔案（MBTI/角色/外觀/聲音），但「這個夥伴做過什麼、花多少、成功幾次」**沒有以夥伴為單位的呈現**——審計資料都在 BudgetLedger，缺的是歸屬維度。

---

## 二、資料層補釘：LedgerEntry 加 companionId

- `LedgerEntry` 加 `companionId` 欄位（nullable——舊資料/非夥伴動作為 null）
- `BudgetLedger.record()` 加可選參數 `companionId`
- `BudgetLedger.statsFor(String companionId)` 新查詢：該夥伴的 total/ok/failed/waste——身份卡審計區數據源
- JSON 向後相容：`fromJson` 缺欄位=null
- 接線：`chat_controller.dart` `dispatchTask()` → `PaidActionGate` 呼叫鏈帶入 `_activeCompanion?.id`（派工一定知道是誰做的）

## 三、UI：身份卡升級（companion_control_center_screen）

在既有 `_buildIdentityCard` 下新增 **「工作實績」區塊**（審計軌跡）：

```
┌──────────────────────────────────────────────┐
│ 📋 工作實績（審計軌跡）                        │
│                                              │
│ 🛡️ 信任：███░░ 62% 中信任                     │
│    ↑ 跟全域 TrustMeter 同公式（以夥伴為單位）  │
│                                              │
│ 📊 累計    總 128 筆 · 成功 119 · 失敗 6      │
│ 💰 近期付費 圖像生成 ×12 · 語音 ×4            │
│ 🚀 最近任務 「鹿角蕨照護計畫」✅ 09-08 14:32  │
│    「Logo 設計迭代」✅ 09-07                  │
│                                              │
│ [查看完整 Ledger]                             │
└──────────────────────────────────────────────┘
```

- 信任條重用 `computeTrustScore`（K6.2 公式——以夥伴 stats 代入）
- 「最近任務」讀 TaskDispatcher 既有 session（filter conversationId 對應的派工）
- 完整 Ledger：BottomSheet 列出該夥伴最近 30 筆（intent/status/時間）

## 四、權限範圍（成員式管理——本刀先呈現不擴權）

身份卡顯示「這個隊友可以進哪些房間、動哪些資產」的**現況聲明**（唯讀）：
- 可用工具（Agent Tool Registry 已註冊的工具清單）
- 付費額度（PaidActionGate cap——現行值直接顯示）
- 房間存取（全房間——本刀不縮權，只是誠實聲明現況）

> 擴權/縮權的編輯介面列刀 7 開放層（涉及羅盤雙層所有權，需要 Blue 親自調）。

## 五、落地切片

| # | 內容 | 檔案 |
|---|---|---|
| D2.1 | LedgerEntry.companionId＋record 參數＋statsFor 查詢 | budget_ledger.dart |
| D2.2 | 接線：派工鏈帶 companionId | chat_controller.dart / paid_action_gate.dart |
| D2.3 | 身份卡「工作實績」區塊（信任條+統計+任務史） | companion_control_center_screen.dart |
| D2.4 | 完整 Ledger BottomSheet | 同上 |
| D2.5 | 權限範圍聲明區塊（唯讀） | 同上 |

## 六、驗收

- 身份卡顯示該夥伴的信任條（真實 stats，不是假數）
- 派工跑一次 → 該夥伴實績數字 +1
- 舊 Ledger 資料（無 companionId）不炸、顯示為「未標記」
- lib/ 零 error；測試 ≥ 4 條綠；profile build 成功

## 七、一句話

**夥伴不只是人格檔案——是有工作實績、有審計軌跡、有信任積分的團隊成員。**
