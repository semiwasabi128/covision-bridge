# Bridge App Sub-Agent 編排架構設計

> **狀態**：2026-08-07 · Design draft
> **目的**：在 Bridge App 裡建造白盒、可稽核的 sub-agent 編排架構，讓使用者能看見、控制、驗證 AI 的多代理人協作。
> **代號**：Bridge Orchestration Layer（暫稱「橋樑編排層」）

---

## 1. 為什麼不直接用別人的

### Kimi Agent Swarm
- **黑盒編排**：模型 server-side 自己拆 sub-agent，你只拿到最終結果
- 沒有獨立 API endpoint 控制 sub-agent 數量、分工、路由
- 看不到中間 sub-agent 的狀態、log、失敗原因
- **無法稽核**：你不能知道它拆了幾個 agent、各自做了什麼

### Kimi Code CLI 的 Sub-Agents（可參考的設計）
- 三個 built-in sub-agent：`coder`（通用）、`explore`（唯讀探索）、`plan`（純規劃）
- Main Agent 自動排程 sub-agent，也可手動指定
- 每個 sub-agent 有獨立 context window
- Permission 從 main agent 繼承
- Custom agents 用 Markdown 定義（frontmatter + system prompt）
- Sub-agent 的中間過程不回到 main agent，只有結論回傳

### Claude Code 的 Sub-Agents
- 核心理念：**parent 只收結論，不收過程**
- Sub-agent = 獨立 Claude instance，自己的 context、system prompt、tool access、permissions
- 支援平行 fan-out
- Agent Teams = 多個 sub-agent 互相協調，不只是 parent → child

### Hermes delegate_task（我們現有的）
- Per-turn delegation，spawn child AIAgent instances
- Concurrency cap: 3 children（可設定）
- Spawn depth cap: 1（leaf 不能再 delegate，orchestrator 可以）
- Parent blocks until children return summaries
- Leaf children 不能 delegate、clarify、memory、send_message、execute_code

---

## 2. Bridge App 的獨特定位

Bridge App 不是 CLI coding agent，它是一個**為全人類搭橋的桌面 App**。

它的 sub-agent 編排必須滿足：

| 要求 | 說明 |
|---|---|
| **白盒可稽核** | 使用者能看見每個 sub-agent 在做什麼、花了多少 token、成功或失敗 |
| **畫布可視化** | Sub-agent 的 spawn / run / complete 應該能在 Bridge Canvas 上呈現 |
| **能力導向** | 使用者選「我想做什麼」，系統列出可用 agent，不是選 provider |
| **本地優先** | 簡單任務用本地模型，只有需要大模型時才花雲端 token |
| **開源透明** | 編排邏輯是使用者可審查的程式碼，不是 server-side 黑盒 |

---

## 3. 架構設計

### 3.1 三層架構

```
┌─────────────────────────────────────────┐
│  UI Layer（對話 / 畫布）                  │
│  使用者看見 sub-agent 的進度、結果、成本   │
├─────────────────────────────────────────┤
│  Orchestration Layer（編排層）            │
│  決定何時拆、拆幾個、各自做什麼            │
│  管理 sub-agent 生命週期、結果聚合         │
├─────────────────────────────────────────┤
│  Execution Layer（執行層）                │
│  每個 sub-agent 實際呼叫 LLM / 工具        │
│  可以是本地模型、雲端 API、或混合           │
└─────────────────────────────────────────┘
```

### 3.2 Core Concepts

#### BridgeSubAgent
一個 sub-agent 實例。包含：
- `id`：唯一識別
- `name`：人類可讀名稱（e.g. "前端探索員"、"測試撰寫員"）
- `role`：leaf | orchestrator
- `goal`：任務描述
- `context`：隔離的 context（不繼承 parent 的對話歷史）
- `toolAccess`：可用工具白名單
- `model`：使用的 LLM model（可與 parent 不同）
- `status`：pending | running | completed | failed | cancelled
- `startedAt` / `completedAt`
- `result`：最終結論（只有結論，不是過程）
- `tokenUsage`：消耗的 token 數

#### BridgeOrchestrator
編排器。負責：
- 接收使用者的複合任務
- 決定是否需要拆分（不是所有任務都需要 sub-agent）
- 建立 sub-agent 實例、分配任務
- 管理並行（concurrency cap）
- 聚合 sub-agent 結果
- 回報進度給 UI

#### BridgeAgentTemplate
可重用的 agent 模板（參考 Kimi Code 的 custom agents）：
- Markdown 定義：frontmatter（name, description, tools）+ body（system prompt）
- 內建模板：`explore`（唯讀探索）、`implement`（寫程式）、`review`（程式審查）、`test`（測試）
- 使用者可自訂模板
- 存放在 `~/.bridge/agents/` 或專案 `.bridge/agents/`

### 3.3 與 Hermes delegate_task 的關係

Hermes 的 `delegate_task` 是這個架構的**第一個真實實作**——但它目前只在 Hermes Agent 層面運作，不在 Bridge App 裡。

目標演進：

```
Phase 1（現在）：Hermes delegate_task 在外部幫 Bridge 做重活
Phase 2（目標）：Bridge App 內建自己的 Orchestration Layer
Phase 3（未來）：Bridge 的 Orchestration Layer 可以反過來呼叫 Hermes
```

---

## 4. 與現有系統的接點

### 4.1 BridgeActionExecutor

現有的 `BridgeActionExecutor` 已經有：
- `progressStream`（P0.5b 剛接上 UI）
- Adapter registry（OpenAI / Replicate image adapter）
- Execution decision service

Sub-agent orchestration 是 BridgeActionExecutor 的**自然延伸**：
- `generateImage` → 呼叫一個 adapter
- `delegateTask` → 呼叫一個 sub-agent
- `exploreCodebase` → 呼叫一個 explore sub-agent

### 4.2 Bridge Canvas

Sub-agent 的 spawn / run / complete 可以在畫布上呈現為節點：
- 父任務是一個節點
- 每個 sub-agent 是子節點
- 連線代表「spawn → result」
- 節點狀態用顏色標示（pending / running / done / failed）

### 4.3 Task Evidence Card

Sub-agent 完成後，結果以 Task Evidence Card 呈現在對話泡泡裡：
- sub-agent 名稱
- 任務描述
- 結論摘要
- token 消耗
- 耗時

---

## 5. 分期實施

### Phase O-1：設計地基（現在）
- 本文件定義架構
- 確認與 Hermes delegate_task 的邊界
- 確認與 BridgeActionExecutor 的接點

### Phase O-2：最小可用編排（ Bridge App 內）
- 實作 `BridgeSubAgent` model
- 實作 `BridgeOrchestrator`（單層，leaf-only，concurrency=2）
- 一個內建模板：`explore`（唯讀，不修改檔案）
- UI：在對話中顯示 sub-agent 進度（復用 progressStream 機制）
- 測試：mock sub-agent 驗證 spawn → run → result 流程

### Phase O-3：多模板 + 平行
- 加入 `implement`、`review`、`test` 模板
- 支援平行 fan-out
- 畫布上呈現 sub-agent 節點

### Phase O-4：使用者自訂 agent
- Markdown agent template 載入
- `~/.bridge/agents/` 目錄掃描
- UI 讓使用者選擇 agent 模板

### Phase O-5：雙向接 Hermes
- Bridge 的 Orchestrator 可以呼叫 Hermes delegate_task
- Hermes 的 delegate_task 結果可以回到 Bridge 對話

---

## 6. 不做什麼

- 不做 server-side 黑盒編排（Kimi Agent Swarm 那種）
- 不做遞歸無限深度（depth=1 起步， orchestrator 可選）
- 不讓 sub-agent 直接跟使用者對話
- 不讓 sub-agent 的中間過程污染 parent context
- 不在 P0.5/P0.6 階段做（先完成圖片資產主線）

---

## 7. 參考系統比較

| 特性 | Kimi Agent Swarm | Kimi Code CLI | Claude Code | Hermes delegate_task | **Bridge（目標）** |
|---|---|---|---|---|---|
| 編排位置 | Server-side | Client-side | Client-side | Client-side | **Client-side** |
| 可稽核 | ❌ | ✅ | ✅ | ✅ | **✅** |
| 可視化 | ❌ | Terminal | Terminal | Discord/CLI | **對話+畫布** |
| 平行 | ✅ 300 | ✅ | ✅ | ✅ 3 | **✅ 可設定** |
| 深度限制 | 不透明 | 有 | 有 | depth=1 | **depth=1 起步** |
| 自訂 agent | ❌ | ✅ Markdown | ✅ Markdown | ❌ | **✅ Markdown** |
| 模型選擇 | 固定 | Kimi only | Claude only | 任何 | **任何** |
| 本地模型 | ❌ | ❌ | ❌ | ✅ | **✅** |
| 開源 | 權重開源 | Apache 2.0 | 閉源 | 開源 | **開源** |

---

## 8. 下一步行動

1. ✅ 本文件作為「門」——每次等 subagent 時回到這裡推進
2. ✅ 確認 BridgeActionExecutor 的擴展介面設計（見 §3.3）
3. ✅ 確認現有 AgentTool / AgentToolCall / AgentToolResult 體系（見下）
4. 實作 `BridgeSubAgent` model（純 data class，不含邏輯）
5. 實作 `BridgeOrchestrator`（最小版本：spawn 1 個 leaf agent）
6. 接上 progressStream（sub-agent 的 spawn/run/complete 也是 progress event）

---

## 9. 現有體系確認（2026-08-07）

### AgentTool 體系（已存在，sub-agent 直接復用）

Bridge App 已有完整的 tool call 體系：

```dart
// lib/services/agent_loop/agent_tool.dart
abstract class AgentTool {
  String get name;                    // snake_case identifier
  String get description;             // 注入 system prompt
  List<AgentToolParamSpec> get paramSpecs;
  Future<AgentToolResult> execute(Map<String, dynamic> args);
}

class AgentToolCall {
  final String name;
  final Map<String, dynamic> args;
}

class AgentToolResult {
  final bool success;
  final String content;               // 餵回 LLM 的文字摘要
  final String? mediaUrl;             // 媒體 URL（圖片等）
  final Map<String, dynamic>? metadata;
}
```

### Sub-agent 的接點

Sub-agent orchestration = 在 AgentTool 體系上加一個 `delegate_task` tool：

```dart
// 概念設計（尚未實作）
class DelegateTaskTool extends AgentTool {
  @override
  String get name => 'delegate_task';

  @override
  String get description => '派發子任務給獨立的 sub-agent。sub-agent 在隔離的 context 中工作，只回傳結論。';

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    // args: { goal, context?, role?, model? }
    // 1. 建立 BridgeSubAgent 實例
    // 2. 給它獨立的 context + tool access
    // 3. 執行（呼叫 LLM）
    // 4. 等待完成
    // 5. 回傳 AgentToolResult（只含結論，不含過程）
  }
}
```

### BridgeActionExecutor 的 progressStream（已接上 UI）

P0.5b 已完成的 `BridgeActionExecutor.progressStream` 機制可以直接擴充：

```dart
// 現有：圖片任務進度
enum BridgeActionProgressStage {
  adapterSelected,
  requestAboutToSend,
  responseReceived,
  mediaPersisted,
}

// 擴充：sub-agent 任務進度（Phase O-2 加入）
// delegateSpawned    → 已建立 sub-agent
// delegateRunning    → sub-agent 正在執行
// delegateCompleted  → sub-agent 已完成，結論已回傳
// delegateFailed     → sub-agent 執行失敗
```

### 設計決策

1. **Sub-agent 是 AgentTool，不是新體系**——復用現有的 tool call / registry / prompt injection
2. **Sub-agent 的 LLM 呼叫走現有 ApiService**——不另建 LLM client
3. **Sub-agent 的進度走現有 progressStream**——不另建 event channel
4. **Sub-agent 的結果走現有 AgentToolResult**——不另建 result type
5. **Sub-agent 的 context 隔離用獨立 conversation**——不共享 parent 的 message history
