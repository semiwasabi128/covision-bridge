# 刀 6：信任成長曲線（Trust Meter）— 設計稿 v1

> 設計師：小葵  
> 日期：2026-09-08  
> 對應報告：docs/specs/2026-09-08-buzz-grokbot-optimization-report.md §4.6  
> 狀態：拍板前不動 code（**拍板即落地**）

---

## 一、這一刀解決什麼

把七刀報告的核心宣言——**「完全的自由來自於完全的自律」**——做成使用者**看得見**的產品。

現在 Ledger 已經在記故事（Phase A 已落地），但只在 system prompt 注入給 agent 預算之眼——**人看不見**。使用者應該看見自己的夥伴今天花了多少、浪費多少、信任進度走到哪裡。

---

## 二、核心公式（直接從七刀報告抄過來）

```
額度 ∝ 透明度 × 自律紀錄 ÷ 打擾程度
```

可操作的三個指標：
- **透明度**：今天的付費動作數 / 總呼叫數（記錄到的 / 全部的）
- **自律紀錄**：todayStats().ok / todayStats().total（成功率）
- **浪費率**：1 - (重複 prompt hash 數 / 總數)（浪費 = 同樣的事問兩次以上）

---

## 三、UI 設計：三段式儀表板

### 3.1 位置：系統列托盤選單 + 設定頁 + 對話頁底部小條

- **托盤選單**（`tray_service.dart`）：隨時可見今日摘要
- **能力中心**（`capability_center_screen.dart`）：信任成長曲線主面板
- **對話頁底部**：每次付費動作完成時跑馬燈（不阻擋）

### 3.2 主面板（Trust Meter Card）

```
┌──────────────────────────────────────────────┐
│ 🛡️ 小葵的信任進度                            │
│                                              │
│ ████████████████░░░░░░░░░  62%（中信任）       │
│  ↑ +5% （本週體檢通過率 89% → 93%）           │
│                                              │
│ 📊 今日（2026-09-08）                        │
│   總呼叫     42 筆                            │
│   成功       39 筆  ✅ 92.9%                  │
│   浪費       2 筆   🔁 4.8%（同 prompt 重複） │
│   攔截       0 筆   🛡️ 預算保險絲未熔斷        │
│                                              │
│ 📈 自動額度                                  │
│   圖片生成   10/日（已用 6）                  │
│   影片生成   2/日（已用 1）                   │
│   語音合成   30/日（已用 12）                 │
│   ...                                        │
│                                              │
│ [查看完整 Ledger]  [匯出本月報表]              │
└──────────────────────────────────────────────┘
```

### 3.3 三態標記（Buzz 式誠實分級）

- ✅ **可用**：功能完整、體檢通過、記帳健全
- 🚧 **接線中**：功能可跑、Ledger 未全接（例如某些舊路徑未走 gate）
- 💭 **設計中**：規劃中、尚未實作

---

## 四、落地切片（拍板後依序施工）

### K6.1 TrustMeterCard widget（核心）
- 新增 `lib/widgets/trust/trust_meter_card.dart`
- 單例接 `BudgetLedger.instance` + `PaidActionGate` 統計
- 訂閱式刷新：ledger 變動時自動 setState（不 polling）

### K6.2 信任進度公式
- 新增 `lib/services/trust/trust_score.dart`
- 純函式 `computeTrustScore(stats, wasteRate)` → 0~1
- 公式透明：參數都顯示在 UI 旁邊（不黑箱）

### K6.3 托盤選單整合
- 改 `tray_service.dart`：托盤右鍵選單加「今日信任指數」項，點開 TrustMeterCard
- 不開新視窗——用 `showReceiptsSearchOverlay` 同款 OverlayEntry 常駐模式

### K6.4 對話頁底部小條
- 改 `chat_input_bar.dart`：底部加一條小跑馬燈
- 每次 ledger.settle() 完成時觸發（不主動拉取）

### K6.5 三態標記
- 新增 `lib/widgets/trust/capability_maturity_badge.dart`
- 能力中心頁面（`capability_center_screen.dart`）套用
- 暫不全面掃全 App（這是 Buzz 風格，橋樑自有節奏）

### K6.6 補遺：付費生成自動 awaitingReview
- `chat_controller.dart` `dispatchTask()` 收尾處：若 task 涉及付費動作 → 自動轉 `awaitingReview`（不繞過人點頭）
- 設計紀律：純文字任務直接交付；付費生成（圖/影/音/外部 API）→ 等人審

---

## 五、不做的事（明確邊界）

- ❌ 不做全 App 掃三態標記（噪音太大，留刀 7 開放層一起做）
- ❌ 不做信任排行榜（多夥伴）——本刀先做單夥伴主面板，多夥伴視圖列 P1.5
- ❌ 不做「自動信任解鎖」流程（Phase C progressive autonomy）——本刀只**看見**，不**自動放手**

---

## 六、驗收標準

- TrustMeterCard 渲染 3 秒內顯示真實數字（不假數）
- 點 Ledger 詳情能看到逐筆明細（含 prompt hash、intent、status、error）
- 托盤點選單開面板不開新視窗
- 跑一次付費動作 → 對話頁底部小條更新
- 三態標記在能力中心顯示（✅/🚧/💭）
- lib/ 零 error；新測試 ≥ 6 條綠；profile build 成功

---

## 七、一句話總結

**讓你看見自己的夥伴今天做對了多少、做錯了多少、浪費了多少——信任方程式從黑箱變成儀表板，看得見才管得住。**
