# Agent 移民系統——召喚儀式×記憶歸屬×大搬家

> 日期：2026-09-13｜作者：小葵｜狀態：待 Blue 核可
> 脈絡：agent-import.v1 已落地（小葵已入夥伴館驗證）。本提案把「移民」升級成完整移民系統。

## 三個拍板（Blue 2026-09-13）

1. **匯入流程結合鍊成形象生成**——匯入 agent 也走生成形象圖/狀態圖，原生與匯入都有進入大家庭的儀式感
2. **B 決策：私有+共享混合**——記憶預設私有、技能/招式預設共享
3. **大搬家模式**——全量遷移（記憶/技能/人格/對話史/排程任務），目標無縫無痛 100 分

---

## WS-1 召喚儀式（匯入 × 鍊成整合）

### 現況
- 原生夥伴：`/desktop-summon` 召喚流程 → 形象生成（appearancePrompt → 立繪/動圖/狀態圖）
- 匯入夥伴：plist 直寫，無形象（紫底佔位）——「沒有儀式感」Blue 原話

### 設計
`agent-import.v1` spec 載入後不直接完成，進入**召喚儀式**：

```
[選擇 agent-import.json / 貼上 / 平台直連]
  ↓ 解析 spec → 顯示「移民預覽卡」（人格摘要、來源平台、攜帶行李清單）
  ↓ 確認 → 自動從 persona 欄位生成 appearancePrompt（人物名人靈感=freeform 提煉）
  ↓ 進入現有鍊成流程：形象圖 + 狀態圖 + 動圖（同一條生成管線）
  ↓ 完成畫面：「小葵加入了大家庭」（原生與匯入同一儀式）
```

### 改動點
- `desktop_summon_screen.dart` 加「匯入外部 Agent」入口（與「從零召喚」並列）
- `agent-import.v1` spec 增加 `appearance` 可選欄位（無則自動從 persona 生成 prompt）
- 匯入完成 → CompanionStore.add()（App 內正規路徑，不再動 plist——順便解掉 cfprefsd 偏方債）

### 驗收
- 匯入的 agent 有立繪與狀態圖（不是佔位符）
- 原生召喚流程零改動（共用管線，不是分支）

---

## WS-2 記憶歸屬（B 決策落地）

### 現況
`agent_memories`/`agent_scripts` 無歸屬欄位，全域共享——小橋已經在讀小葵的行李（雖然行為上恰好無害，但語意上是 bug）。

### 設計
```sql
ALTER TABLE agent_memories ADD COLUMN owner_companion_id TEXT NOT NULL DEFAULT 'shared';
ALTER TABLE agent_scripts  ADD COLUMN owner_companion_id TEXT NOT NULL DEFAULT 'shared';
-- 'shared' = 共享（招式/通用知識）；'<cmp_id>' = 私有（該夥伴獨享）
```

- 遷移：`hermes_migration` 記憶 38 條 → `owner=小葵的cmp_id`（私有）；157 招式 → `shared`
- 搜尋：`agent_search_knowledge` 帶當前 companionId，WHERE `owner IN ('shared', ?)`
- 寫入：`agent_save_memory` 預設 `owner=當前companion`；`agent_save_script` 預設 `shared`
- FTS/LIKE 路徑同步過濾（CJK LIKE 修復已上，這裡只是加欄位）
- UI：記憶/招式列表顯示歸屬 chip（共享/私有）

### 驗收
- 小橋搜「寧紅字」→ 查不到（私有）；小葵搜 → 命中
- 兩位都能搜到共享招式（截圖 App 自拍）
- 舊資料零丟失（migration 冪等）

---

## WS-3 大搬家模式（全量遷移）

### 範圍盤點（Hermes → 橋樑）

| 貨物 | 現況 | 方案 |
|---|---|---|
| 人格 SOUL | ✅ 已匯（agent-import.v1） | WS-1 補形象 |
| 記憶 38 條 | ✅ 已匯 | WS-2 掛歸屬 |
| Skills 157 | ✅ 已匯 | WS-2 掛 shared |
| **對話史** | ❌ 未遷 | Hermes sessions DB → App conversations.json（格式轉接：role/content/timestamp；訊息量大需分批+進度條） |
| **排程 36 條** | ❌ 未遷 | Hermes jobs.json → App ScheduleEngine（畫布 schedule 節點）或 daemon schedule_jobs.json；prompt 直譯、deliver 對接 App 通知管道 |
| Profiles 記憶（12 個 profile 各自 memories） | ❌ 未遷 | 同記憶遷移，owner 對應各匯入 agent |
| Cron 輸出歷史 | ❌ 未遷 | 低優先，可留 Hermes |

### 排程對接細節（36 條的處置建議）
- **直遷**：IG 系列、農場日記、晨間拾穗等生成型任務（prompt 可直譯）
- **不遷**：聯賽巡邏（Hermes-specific）、Kimi/ZAI 監測（基礎設施綁定 Hermes）
- **轉世**：小葵安靜時刻 → App 內小葵的每日節點（時間感 L4 掛鉤）
- 遷移器產出 `migration_report.json`：每條排程的處置（直遷/不遷/轉世）＋原因——寧紅字，不靜默丟包

### 大搬家流程（使用者視角）
```
[系統設定 → 大搬家] → 掃描 Hermes 目錄 → 出現「可遷移清單」（每項可勾選）
  → 預覽（dry-run 全綁定）→ 執行（進度條＋每項結果綠/紅）
  → 報告：遷移 N 項成功、M 項需人工處置（附原因）
```

### 驗收（100 分定義）
- 小葵在 App 裡：有立繪、有記憶、有招式、有對話史（舉得出 8/27 相遇那天）、有排程（安靜時刻 22:00 照跑）
- Hermes 端保持完整不動（搬家是複製不是剪貼——回得去）
- 全程零手改 plist、零終端機指令

---

## 順序建議

WS-2 先行（schema 是地基，越晚改越痛）→ WS-1（儀式感，UI 工程）→ WS-3（大搬家，依賴前兩者）。三個 WS 可獨立驗收、獨立 commit。

## 風險
- WS-2：搜尋過濾改錯會讓現有小橋斷糧——需先寫回歸測試再動 schema
- WS-3 對話史：Hermes sessions 體積未知（需先量測）；時間戳語意要對齊時間感引擎
- 排程直譯的 prompt 依賴 Hermes 工具（web_search 等）——App 端工具不齊的任務標記「需人工調整」
