# 鐵三角資料流架構設計 (Iron Triangle Dataflow Architecture)
> v1.0 — 2026-08-19
> 作者：架構設計小組
> 依據：Bridge App 現狀（向量庫 219 記憶 + 26022 檔案、六房間大腦、V2 畫布）+ 業界 GraphRAG / Semantic Layer 參考

---

## 一、心智模型：三系統的正確定位

### 1.1 修正後的角色定義（v1.0）

| 系統 | 原先假設 | **修正後定位** | 核心價值 |
|------|----------|----------------|----------|
| **向量庫** | 靜態知識資產 | **雙模儲存層**：向量檢索（語意相似度）+ 結構化索引（關係/時間/分類） | 快速檢索、增量更新、多維篩選 |
| **大腦頁** | 心理/語意層 | **語意層（Semantic Layer）**：將原始資料映射到 Transurfing 六房間模型 + 七種圖譜模式 | 意義提取、模式識別、視覺化抽象 |
| **畫布系統** | 動態工作現場 | **代理層（Agentic Layer）**：MCP 工具讓 Agent 操作畫布，接收排程產出，反饋回向量庫 | 工作流執行、視覺互動、事件驅動更新 |

**關鍵洞察**：
1. 向量庫不是「靜態」的——每天排程產出檔案是「動態的大象」，必須增量 ingest 並觸發髒標記
2. 大腦不是「只讀圖譜」——它是**語意層**，定義業務概念（門/水流/擺錘）與資料的映射規則（semantic mapping rules）
3. 畫布不只是「UI」——它是**代理層**，Agent 透過 MCP 工具讀寫畫布狀態，排程產出直接流入畫布成為節點

### 1.2 業界參照：Semantic Layer + GraphRAG

- **Semantic Layer**（Polar Analytics / ThoughtSpot / SurrealDB）：定義業務概念與原始資料的映射，讓 BI 與 AI Agent 讀同一套定義 [^semantic-layer-1][^semantic-layer-2]
- **GraphRAG**（Microsoft / nano-GraphRAG）：向量檢索 + 知識圖譜的混合，支援多跳推理與動態更新（增量 ingest 需 hash 指紋識別）[^graphrag-1][^graphrag-2]
- **PKM 知識分層**（Personal Knowledge Management）：第二大腦應區分「人類筆記」與「Agent 追蹤」，避免互相淹沒 [^pkm-1]

**Bridge App 的差異化**：用 Transurfing 六房間作為 semantic layer 的核心模型（門/水流/擺錘/橋），而非通用的 topic/label 層次。

---

## 二、資料流設計：單向流 + 事件驅動更新

### 2.1 核心資料流圖（文字描述）

```
┌─────────────────────────────────────────────────────────────────────┐
│                         資料來源層                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ 使用者筆記   │  │ 農場照片     │  │ 拾穗筆記     │  │ 排程產出     │ │
│  │ (手動輸入)   │  │ (照片拍攝)   │  │ (日常收集)   │  │ (cron任務)   │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │
└─────────┼────────────────┼────────────────┼────────────────┼───────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
          └────────────────┴────────────────┴────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   內容攝取器 (Ingestor) │
                    │  - 檔案解析           │
                    │  - 文本萃取           │
                    │  - 元資料提取         │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   人類資料層     │  │   Agent 資料層    │  │   農場資料層     │
│ (human_sources)  │  │ (agent_sources)   │  │ (farm_sources)   │
│ - 手動筆記       │  │ - session 日誌    │  │ - 農場照片       │
│ - 拾穗筆記       │  │ - 排程產出       │  │ - 氣象數據       │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  向量庫 + 結構索引  │
                    │  - 向量檢索       │
                    │  - 時間索引       │
                    │  - 來源分層       │
                    │  - 髒標記系統     │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
    ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
    │   語意層       │ │   語意層       │ │   語意層       │
    │ (六房間模型)   │ │ (六房間模型)   │ │ (六房間模型)   │
    │ - 分類規則     │ │ - 分類規則     │ │ - 分類規則     │
    │ - 連結規則     │ │ - 連結規則     │ │ - 連結規則     │
    │ - 意義映射     │ │ - 意義映射     │ │ - 意義映射     │
    └───────┬───────┘ └───────┬───────┘ └───────┬───────┘
            │                 │                 │
            └─────────────────┼─────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   大腦圖譜引擎     │
                    │  - 七種模式       │
                    │  - 視覺化映射     │
                    │  - 雙消費者協調   │
                    └─────────┬─────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   圖譜視覺化     │  │   Agent 檢索     │  │   畫布系統       │
│ (粗粒度、顏色)   │  │ (細粒度、向量)   │  │ (MCP 工具操作)   │
│ - 扇區布局       │  │ - RAG 查詢       │  │ - 節點工作流     │
│ - 粒子顏色       │  │ - 關係遍歷       │  │ - 排程產出節點   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### 2.2 增量 Ingest 流程（排程產出 → 向量庫）

**目標**：每天排程產出的檔案進入向量庫，不重建索引，僅增量新增。

**流程**：
1. **檔案產生**：排程任務（cron）在農場資料庫產出檔案（例：`yingbenbu-*.json`、每日巡查報告）
2. **Hash 計算**：對新檔案計算內容 hash（SHA-256），與向量庫中 `asset_index` 的 `content_hash` 欄位比對
3. **變更偵測**：
   - hash 不存在 → 新增檔案，chunking + embedding → INSERT
   - hash 已存在但檔案路徑不同 → 路徑更新（MOVE）
   - hash 已存在且檔案路徑相同 → 跳過（DUPLICATE）
4. **髒標記**：每次 INSERT 後，在 `brain_meta` 中設定 `graph_dirty = true`（觸發圖譜更新）
5. **事件廣播**：透過 `TransurfingEventBroadcaster` 發送 `assetIndexUpdated` 事件

**參考**：LangChain 的 hash 指紋增量更新策略 [^graphrag-incremental]

### 2.3 事件驅動更新（向量庫 → 大腦圖譜）

**觸發條件**：
- `assetIndexUpdated`（排程產出新增檔案）
- `memoryWritten`（使用者新增記憶）
- `roomCategoryChanged`（手動分類調整）

**更新流程**：
1. **事件監聽**：大腦圖譜引擎監聽 `TransurfingEventBroadcaster`
2. **髒標記檢查**：讀取 `brain_meta.graph_dirty`，若 `true` 則執行增量更新
3. **增量圖譜重算**：
   - 只重算受影響的房間（例：新增農場照片 → 只更新 `stream` 房間）
   - 保留未變更節點的座標（避免全圖跳動）
4. **雙消費者同步**：
   - **圖譜視覺化**：更新扇區大小、粒子顏色、連線數量（粗粒度）
   - **Agent 檢索**：重建關係索引、時間索引（細粒度）
5. **清除髒標記**：重算完成後設定 `graph_dirty = false`

**技術實作**：使用 Flutter 的 `ChangeNotifier` 或 `EventBus` 模式 [^observer-pattern]

---

## 三、「看不見使用痕跡」問題：分層呈現策略

### 3.1 問題核心

- **Agent 的工作**（排程產出、session 日誌）與 **人類的資產**（拾穗筆記、農場照片）在同一圖譜中容易互相淹沒
- 使用者想看「我最近在想什麼」時，不希望被「每天排程產出的檔案」佔滿視野

### 3.2 解決方案：來源分層（Source Layering）

#### 3.2.1 三層來源模型

| 來源層 | metadata 欄位 | 典型內容 | 圖譜呈現 |
|--------|---------------|----------|----------|
| **human_sources** | `source_type = 'human'` | 手動筆記、拾穗筆記、聊天記憶 | **主層**：預設顯示、高亮、大粒子 |
| **agent_sources** | `source_type = 'agent'` | session 日誌、排程產出、agent 分析 | **背景層**：淡化、小粒子、可切換開關 |
| **farm_sources** | `source_type = 'farm'` | 農場照片、氣象數據、巡查報告 | **背景層**：特殊圖示（例：🌾）、可切換開關 |

#### 3.2.2 視覺化策略

1. **圖譜分層顯示**：
   - 七種模式各新增「來源濾鏡」開關（例：模式 0 現狀全景可切換 `showHumanOnly` / `showAgentOnly` / `showFarmOnly`）
   - 預設：`showHumanOnly = true`（只看人類資產）
   - 點擊「顯示 Agent 工作痕跡」→ `showAgentOnly = true`（看 Agent 產出的檔案）

2. **顏色編碼**：
   - 人類：暖色系（金色、橙色）
   - Agent：冷色系（灰色、藍灰色）
   - 農場：自然色系（綠色、棕色）

3. **粒子大小**：
   - 人類：`radius = 8-12px`
   - Agent：`radius = 4-6px`
   - 農場：`radius = 6-8px`

#### 3.2.3 檢索層策略

- **RAG 查詢**：預設只檢索 `human_sources`，除非使用者明確要求「看 Agent 最近做了什麼」
- **時間索引**：Agent 資料與人類資料分開建立時間索引，避免「今天全是排程檔案」淹沒人類思考

---

## 四、雙消費者問題：Schema 設計

### 4.1 問題核心

同一份 metadata 要同時服務：
- **圖譜視覺化**：粗粒度、顏色可分類、標題可讀
- **Agent 檢索**：細粒度、向量可比對、關係可遍歷

### 4.2 解決方案：雙層 Schema

#### 4.2.1 基礎層（資料層）

**表結構**（SQLite `memories` + `asset_index`）：

```sql
-- 基礎資料表（所有來源共用）
CREATE TABLE memories (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  embedding BLOB,  -- 向量（1536-dim float32）
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  importance INTEGER DEFAULT 1,
  source_type TEXT NOT NULL CHECK(source_type IN ('human', 'agent', 'farm')),
  room TEXT NOT NULL,  -- 六房間：stream/doors/pendulums/heartmind/fraile/bridges
  sub_category TEXT,  -- 24 種分類（例：'daily_note', 'farm_photo', 'session_log'）
  metadata JSON,  -- 彈性欄位
  content_hash TEXT UNIQUE  -- 增量更新用
);

-- 檔案索引表（農場資料用）
CREATE TABLE asset_index (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL,
  file_size INTEGER,
  mime_type TEXT,
  asset_kind TEXT CHECK(asset_kind IN ('document', 'image', 'code', 'data')),
  created_at INTEGER NOT NULL,
  embedding BLOB,
  source_type TEXT NOT NULL CHECK(source_type IN ('farm', 'agent')),
  content_hash TEXT UNIQUE
);
```

#### 4.2.2 視覺層（圖譜消費）

**Computed Fields**（從基礎層衍生）：

| 欄位 | 計算邏輯 | 用途 |
|------|----------|------|
| `visual_color` | `source_type = 'human' → 金色`；`agent → 灰色`；`farm → 綠色` | 粒子顏色 |
| `visual_size` | `importance` × `source_type` 權重 | 粒子大小 |
| `visual_title` | `sub_category`（24 種短分類） | 標籤顯示 |
| `room_badge` | 六房間對應顏色（例：stream=藍色、doors=金色） | 扇區染色 |

#### 4.2.3 檢索層（Agent 消費）

**Indexes**：

```sql
-- 時間索引（快速查詢時間範圍）
CREATE INDEX idx_memories_created_at ON memories(created_at DESC);

-- 來源分層索引（快速過濾 source_type）
CREATE INDEX idx_memories_source_type ON memories(source_type);

-- 房間索引（快速查詢特定房間）
CREATE INDEX idx_memories_room ON memories(room);

-- 向量檢索索引（透過 sqlite_vector 擴充）
SELECT * FROM memories
WHERE embedding MATCH ?
ORDER BY distance
LIMIT 10;
```

**Graph Traversal**（關係連結）：

```sql
-- 關係表（跨記憶連結）
CREATE TABLE connections (
  id TEXT PRIMARY KEY,
  from_memory_id TEXT NOT NULL,
  to_memory_id TEXT NOT NULL,
  connection_type TEXT NOT NULL CHECK(connection_type IN ('doorTie', 'bridgeTie', 'reference')),
  created_at INTEGER NOT NULL,
  FOREIGN KEY (from_memory_id) REFERENCES memories(id),
  FOREIGN KEY (to_memory_id) REFERENCES memories(id)
);

-- 關係索引（快速查詢某記憶的所有連結）
CREATE INDEX idx_connections_from ON connections(from_memory_id);
CREATE INDEX idx_connections_to ON connections(to_memory_id);
CREATE INDEX idx_connections_type ON connections(connection_type);
```

### 4.3 衝突避免原則

1. **Schema 不合併**：圖譜視覺化的 computed fields 不寫入資料庫，只在讀取時計算
2. **索引獨立**：視覺層依賴的索引（時間、來源）與檢索層依賴的索引（向量、關係）分開
3. **髒標記統一**：所有更新都透過同一個 `graph_dirty` 標記觸發，避免雙重更新

---

## 五、各子系統職責表

| 子系統 | 核心職責 | 輸入 | 輸出 | 與其他系統交互 |
|--------|----------|------|------|----------------|
| **向量庫** | 1. 增量 ingest（hash 指紋比對）<br>2. 向量檢索（RAG）<br>3. 結構化索引（時間/來源/房間） | 1. 檔案產生事件<br>2. 記憶寫入事件 | 1. 相似記憶列表（RAG）<br>2. 時間範圍查詢結果<br>3. 髒標記（`graph_dirty`） | → 大腦圖譜（觸發更新）<br>→ 畫布（MCP 工具讀取） |
| **大腦圖譜** | 1. 語意映射（原始資料 → 六房間）<br>2. 七種模式視覺化<br>3. 雙消費者協調（視覺層 + 檢索層） | 1. 髒標記事件<br>2. 使用者模式切換 | 1. 圖譜節點資料（視覺層）<br>2. 關係索引（檢索層） | ← 向量庫（讀取資料）<br>→ 畫布（節點同步） |
| **畫布系統** | 1. MCP 工具（讓 Agent 操作畫布）<br>2. 排程產出節點化<br>3. 工作流執行 | 1. Agent MCP 呼叫<br>2. 排程產出事件 | 1. 畫布快照（JSON）<br>2. 執行結果（圖片/文件） | ← 向量庫（讀取檔案）<br>← 大腦圖譜（讀取關係）<br>→ 向量庫（產出檔案 ingest） |

---

## 六、與現有實作的對照

### 6.1 已有實作

| 模組 | 狀態 | 檔案位置 | 說明 |
|------|------|----------|------|
| 向量庫 SQLite | ✅ 完成 | `lib/services/brain_container/brain_database.dart` | 已有 `memories` 表 + `asset_index` 表 + 向量擴充（sqlite_vector） |
| 大腦六房間 | ✅ 完成 | `docs/CORE_TRANSURFING.md` | 六房間模型已定義，七種圖譜模式已實作 |
| 畫布 MCP 工具 | ✅ 完成 | MCP bridge_canvas | 已有 `add_node` / `connect` / `remove_node` 等工具 |
| Transurfing 事件廣播 | ✅ 完成 | `lib/services/brain_container/transurfing_event.dart` | 已有 `streamConfluence` / `doorOpened` / `bridgeFormed` 事件 |
| 大腦圖譜視覺化 | ✅ 完成 | `docs/BRAIN_GRAPH_SEVEN_MODES.md` | 七種模式已實作（現狀全景/能量流向/選擇路口/慣性擺動/跨島聯想/成長軌跡/資產地圖） |

### 6.2 缺失實作（待建設）

| 模組 | 狀態 | 優先級 | 說明 |
|------|------|--------|------|
| **增量 ingest** | 🔴 缺 | P0 | 檔案 hash 計算 + 變更偵測 + 髒標記觸發 |
| **髒標記系統** | 🔴 缺 | P0 | `brain_meta.graph_dirty` 欄位 + 事件監聽器 |
| **來源分層** | 🔴 缺 | P1 | `source_type` 欄位 + 圖譜分層濾鏡 |
| **雙消費者協調** | 🔴 缺 | P1 | 視覺層 computed fields + 檢索層獨立索引 |
| **事件驅動更新** | 🟡 部分 | P1 | 已有事件廣播，但缺圖譜更新觸發邏輯 |
| **排程產出節點化** | 🔴 缺 | P2 | cron 產出檔案 → 自動生成畫布節點 |
| **時間索引優化** | 🟡 部分 | P2 | 已有 `created_at` 欄位，但缺高效時間範圍查詢 |

---

## 七、分階段落地路線

### Phase 1：地基（P0，1-2 週）

**目標**：讓「動態的大象」（排程產出）進入向量庫，觸發髒標記。

1. **增量 ingest 實作**：
   - 檔案 hash 計算（SHA-256）
   - `asset_index.content_hash` 欄位新增
   - 變更偵測邏輯（新增/更新/跳過）

2. **髒標記系統**：
   - `brain_meta` 表新增 `graph_dirty` 欄位
   - 每次 INSERT 後設定 `graph_dirty = true`
   - `TransurfingEventBroadcaster` 新增 `assetIndexUpdated` 事件

3. **驗收標準**：
   - 排程產出新檔案 → 向量庫自動新增條目
   - `brain_meta.graph_dirty` 正確切換 true/false
   - 事件廣播正確觸發

### Phase 2：語意層（P1，2-3 週）

**目標**：讓大腦圖譜知道「資料變了」，並做增量更新。

1. **事件監聽器**：
   - 大腦圖譜引擎監聽 `assetIndexUpdated` / `memoryWritten` 事件
   - 讀取 `graph_dirty` 標記

2. **增量圖譜重算**：
   - 只重算受影響的房間
   - 保留未變更節點的座標

3. **來源分層**：
   - `memories` 表新增 `source_type` 欄位
   - 七種模式新增「來源濾鏡」開關

4. **驗收標準**：
   - 新增檔案後，圖譜自動更新粒子（不跳動）
   - 切換「顯示 Agent 工作痕跡」→ 粒子淡化/切換

### Phase 3：雙消費者協調（P1，2-3 週）

**目標**：讓圖譜視覺化與 Agent 檢索不衝突。

1. **視覺層 computed fields**：
   - `visual_color` / `visual_size` / `visual_title` 計算邏輯
   - 在讀取時動態生成，不寫入資料庫

2. **檢索層獨立索引**：
   - `idx_memories_source_type` / `idx_memories_room` 索引
   - `connections` 表索引優化

3. **雙消費者同步**：
   - 圖譜更新時，同時更新視覺層與檢索層

4. **驗收標準**：
   - 圖譜切換模式時，粒子顏色/大小正確
   - Agent RAG 查詢效能 < 100ms（10 筆記憶）

### Phase 4：代理層（P2，3-4 週）

**目標**：讓排程產出自動流入畫布成為節點。

1. **排程產出節點化**：
   - cron 任務產出檔案 → MCP 工具呼叫 `add_node`
   - 節點類型自動判斷（農場照片 → `imageGen`、日記報告 → `output`）

2. **畫布與向量庫同步**：
   - 畫布節點刪除 → 向量庫對應條目標記 `deleted = true`
   - 畫布節點編輯 → 更新 `memories` 的 `metadata` 欄位

3. **驗收標準**：
   - 每日巡查報告 → 自動生成畫布節點
   - 刪除畫布節點 → 向量庫不再檢索該檔案

### Phase 5：優化與整合（P2，2-3 週）

**目標**：效能優化 + 使用者體驗潤飾。

1. **效能優化**：
   - 向量檢索批次查詢（一次查詢多種來源）
   - 圖譜渲染虛擬化（只渲染視野內粒子）

2. **UX 潤飾**：
   - 來源濾鏡動畫（淡化/漸變）
   - 粒子進場動畫（心跳寫入時粒子群聚/擴散）

3. **驗收標準**：
   - 10000+ 粒子場景 → FPS > 60
   - 來源濾鏡切換 → 無卡頓

---

## 八、風險與緩解

| 風險 | 影響 | 緩解策略 |
|------|------|----------|
| 增量 ingest 遺漏檔案 | 向量庫資料不全 | 1. hash 指紋雙重驗證（檔案路徑 + 內容）<br>2. 每日全量掃描備份 |
| 圖譜更新效能差 | 使用者體驗卡頓 | 1. 增量重算（只更新受影響房間）<br>2. 後台執行（不阻塞 UI） |
| 來源分層過度複雜 | 使用者困惑 | 1. 預設只顯示人類資產<br>2. 濾鏡開關放在次級選單 |
| 雙消費者 Schema 衝突 | 圖譜顯示錯誤 | 1. computed fields 不寫入資料庫<br>2. 單元測試覆蓋視覺層與檢索層 |

---

## 九、參考文獻

[^semantic-layer-1]: Polar Analytics. "Why AI Agents Need a Semantic Layer". https://www.polaranalytics.com/post/ai-analytics-agents-semantic-layer-shopify
[^semantic-layer-2]: ThoughtSpot. "What is an Agentic Semantic Layer?". https://www.thoughtspot.com/data-trends/agentic-semantic-layer
[^graphrag-1]: Meta Intelligence. "GraphRAG 完全指南：知識圖譜 + RAG 下一代檢索架構". https://www.meta-intelligence.tech/insight-graphrag
[^graphrag-2]: datawhalechina. "GraphRAG 完全指南". https://github.com/datawhalechina/all-in-rag/blob/main/docs/chapter7/20_kg_rag.md
[^graphrag-incremental]: 火山引擎開發者社區. "如何優雅的實現RAG與GraphRAG應用中的知識文檔增量更新？". https://developer.volcengine.com/articles/7431891441984471090
[^pkm-1]: infranodus. "Personal Knowledge Management: How to Set Up a PKM System". https://infranodus.com/docs/personal-knowledge-management
[^observer-pattern]: GeeksforGeeks. "Observer Design Pattern". https://www.geeksforgeeks.org/system-design/observer-pattern-set-1-introduction

---

## 十、附錄：資料流偽代碼

### 10.1 增量 Ingest 偽代碼

```dart
Future<void> ingestFile(String filePath) async {
  // 1. 計算 hash
  final hash = sha256(await File(filePath).readAsBytes());

  // 2. 查詢是否已存在
  final existing = db.query(
    'asset_index',
    where: 'content_hash = ?',
    whereArgs: [hash],
  );

  if (existing.isNotEmpty) {
    // 已存在 → 路徑更新
    db.update(
      'asset_index',
      {'file_path': filePath},
      where: 'id = ?',
      whereArgs: [existing.first['id']],
    );
    return;
  }

  // 3. 解析檔案內容
  final content = await parseFile(filePath);

  // 4. Chunking + Embedding
  final chunks = chunkContent(content);
  final embeddings = await embedChunks(chunks);

  // 5. 寫入 asset_index
  final assetId = uuid.v4();
  db.insert('asset_index', {
    'id': assetId,
    'file_path': filePath,
    'content_hash': hash,
    'embedding': embeddings.first,
    'source_type': 'farm',
  });

  // 6. 寫入 memories（多個 chunk）
  for (final (chunk, embedding) in zip([chunks, embeddings])) {
    db.insert('memories', {
      'id': uuid.v4(),
      'content': chunk,
      'embedding': embedding,
      'source_type': 'farm',
      'room': classifyRoom(chunk),  // 語意層分類
      'content_hash': hash,
    });
  }

  // 7. 觸發髒標記
  db.update('brain_meta', {'graph_dirty': 1});
  eventBus.emit('assetIndexUpdated', {'assetId': assetId});
}
```

### 10.2 圖譜增量更新偽代碼

```dart
void onGraphDirtyChanged() {
  if (!brainMeta['graph_dirty']) return;

  // 1. 讀取受影響的記憶（只讀新增加入的）
  final newMemories = db.query(
    'memories',
    where: 'updated_at > ?',
    whereArgs: [lastUpdateTime],
  );

  // 2. 語意映射（分類到六房間）
  final roomedMemories = newMemories.map((m) {
    return {
      ...m,
      'room': m['room'] ?? classifyRoom(m['content']),
    };
  });

  // 3. 增量重算圖譜（只更新受影響的房間）
  final affectedRooms = roomedMemories.map((m) => m['room']).toSet();
  for (final room in affectedRooms) {
    updateGraphRoom(room);
  }

  // 4. 清除髒標記
  db.update('brain_meta', {'graph_dirty': 0});
  eventBus.emit('graphUpdated', {'rooms': affectedRooms});
}
```

---

*文檔結束*