# 節點體系擴充路線（Node System Extension Roadmap）

> [教練 Agent 2026-08-21] 起源：使用者 想圖生圖時發現沒有圖進圖出的節點形式，
> 進而看見本質問題——「工作流給全世界的人用，有千奇百怪的想法與需求，
> 這樣不是要有巨量種類的節點嗎？」
> 本文是調研（ComfyUI / n8n）＋我們現況盤點後的路線圖。

## 一、業界兩種答案

### ComfyUI：開放生態（讓全世界幫你寫節點）

- 核心節點幾百個，custom node 機制開放——任何人用 Python 寫節點包上 GitHub
- 社群節點包上萬（WAS 套件 212 節點、Impact-Pack 165）
- ComfyUI-Manager 一鍵安裝管理
- **代價**：依賴地獄（有人裝 100+ 套件）、來路不明程式碼安全性、
  套件間衝突。他們社群自己有公開抱怨文（github.com/Comfy-Org/ComfyUI discussions #2635）

### n8n：少量通用節點＋逃生艙（不跟需求賽跑）

- 幾百個節點型別覆蓋大多數場景，靠兩個法寶：
  1. **HTTP Request 節點**——任何有 API 的服務都能接，一個節點＝無限整合
  2. **Code 節點**——寫幾行 JS 做任何資料轉換
- 現在還加了 Text-to-Workflow（描述直接生成整條工作流）
- **哲學**：與其列舉需求，給你原料自己拼

### 共同地基：型別化 port 系統

兩家節點能自由組合的基礎是連線有型別（image/text/...）——
節點宣告「吃什麼吐什麼」，組合可能性是指數級。

## 二、我們的現況（2026-08-21）

### 已有的好底子
- `WorkflowNodeType` enum（14 型）＋ `NodeTypePorts.portsFor` 型別化 port
  （`PortDataType`: text/image/audio/video/json/file/any）
- Adapter 注入架構（`WorkflowImageGenerator` 等介面，與 ComfyUI
  client-server 分工同構）
- executor 的 `UpstreamData` 天然支援多源收集（文字合併/圖片清單）
- 付費閘門（PaidActionGate）貫穿所有生成路徑

### 本波已落地（2026-08-21）
1. **imageGen 圖生圖**：image 輸入 port＋上游有圖走
   `generateImageWithReference`（OpenAI images/edits），無圖走純文生圖。
   支援鏈式圖生圖（imageGen 輸出 → 下一個 imageGen image 輸入）。
2. **多線接入全面解除**：任何 input port 可接多條線（原「新線踢舊線」
   行為移除）。語意＝隱式 merge，上游全收。

### 已知缺口（優先序）
1. **圖生圖的 provider 覆蓋**：目前 reference 路徑只支援 OpenAI
   （`service.id.startsWith('openai')` 走 images/edits）。Gemini 原生
   image edit、Replicate img2img（Flux/IP-Adapter）尚未接——
   這是 characterLock 的三層方案（08-01 設計）尚未走完的部分。
2. **URL 參考圖**：上游圖若只有 URL（非 b64）目前不支援 reference
   （需先下載轉 b64）。
3. **多參考圖**：`generateImageWithReference` 只吃一張——
   OpenAI edits 支援多張，是 API 層的簡單擴充。

## 三、路線圖（三層）

### Layer 1：把現有節點補完整（本月）

每個節點的 port 完備化——不是加新節點，是讓現有節點的輸入輸出
能力對齊其底層 API 的真實能力：

- imageGen：圖生圖 ✅（本波）→ 多參考圖、Gemini/Replicate 路徑
- videoGen：圖生影片（image → video，Runway/Kling 都支援首幀圖）
- tts：語音克隆參考音檔輸入
- vision：多圖輸入（目前單圖）

### Layer 2：通用節點（開源前後）

n8n 哲學——少數通用原料，需求自己拼：

| 節點 | 作用 | 覆蓋的需求面 |
|---|---|---|
| `httpRequest` | 打任何 REST API | 無限外部整合（天氣/匯率/任何 SaaS） |
| `transform` | JSON 映射/文字模板/regex | 資料形狀轉換 |
| `code`（遠期） | 沙箱內小段 script | 完全逃生艙 |

加了這兩個（httpRequest＋transform），配合多線接入的隱式 merge，
「千奇百怪需求」的 80% 不需要我們加任何新節點。

### Layer 3：agent 即節點產生器（我們的王牌）

n8n 的 Text-to-Workflow 是雲端生成式補丁；我們的畫布上本來就住著
agent（原生 Agent）。使用者說「幫我做一個監控資料夾、新照片自動用我的
風格重繪的工作流」——agent 用通用節點當積木當場搭。

實作面：`mcp_canvas_tools` 的 add_node/connect 工具已齊，
缺的是「工作流意圖 → 節點圖譜」的 agent prompt 層。這是
「兩個意識共同看見」的兌現現場，也是與 ComfyUI/n8n 的真正差異化。

### Layer 4（遠期）：開放節點生態

開源後若社群有需求——Dart plugin 或宣告式節點包（JSON 定義
port/params/HTTP 呼叫，不需要寫 Dart）。學 ComfyUI 的開放但
用 n8n 的紀律：宣告式優先，杜絕任意程式碼執行的安全性問題。

## 四、決策記錄

| 決策 | 理由 |
|---|---|
| 多線接入＝隱式 merge（不擋） | UpstreamData 天然多源；擋了反而讓「第二條線踢掉第一條」的困惑行為存在 |
| 型別系統嚴格把關（text 不能硬接 image） | 組合自由的前提是型別誠實——鬆了會出現靜默錯誤 |
| reference 路徑復用 characterLock 的 generateImageWithReference | 同一底層能力（圖+prompt→圖），不重複造輪；付費閘門自動貫穿 |
| 不做「每需求一節點」 | n8n 教訓：跟需求賽跑的節點庫是維護地獄；通用原料+agent 拼裝才是規模解 |
| 多參考圖比例＝自然語言描述，不做數字權重 | 使用者 拍板（08-21）：prompt 能描述就能控制即可。API 型圖編輯的順序錨定（越前面權重越重）已足夠；數字權重是潛空間混合（L4 遠期）的事 |
