# 圖片任務與資產治理：分期裁決

> **狀態**：2026-08-07 · Design decision
> **目的**：避免把圖片生成問題拆散成「UI、provider、資料夾、向量資料庫、vision」五條同時施工的支線。
> **核心準則**：使用者信任先於功能數量。任何可見的 provider、模型、檔案與結果，都必須可由實際 execution receipt 證明。

---

## 主線定義

目前主線不是「支援更多模型」，也不是「做更多聊天卡片」。

```text
一個使用者請求生成圖片
  → 明確知道實際文字模型、實際圖片 provider、成功或失敗原因
  → 成功後能立刻在對話預覽圖片
  → 不必找 App 沙盒路徑
```

這稱為 **P0.5：可信的媒體交付（Trustworthy Media Handoff）**。

---

## P0.5 — 現在做：可信的媒體交付

### 目標

一輪圖片任務結束時，使用者不會被假 provider、半句錯誤、路徑文字或無限等待誤導。

### 範圍內

| 項目 | 狀態 | 理由 |
|---|---|---|
| 明確指定的 provider 沒有 adapter 時直接拒絕 | 已修 | 禁止假裝送出 API request |
| `generate_image` 失敗即結束，不能偏航到 screenshot / vision | 已修 | 一個圖片任務必須有明確終點 |
| 中間 LLM output 不得漏到 UI | 已修 | XML、半句、engine turn 都不是使用者資訊 |
| 圖片以 `Message.imagePath` 附件交付，不以絕對路徑寫進回覆 | 已修 | 圖片要出現在對話裡 |
| 對話圖片縮圖 + 點擊放大預覽 | 已修 | 使用者先看見結果 |
| **Execution receipt / provenance**：文字模型、圖片 provider、實際 model、結果 ID | **本階段 blocker** | `kimi-k3` 目前是設定推測，不能代表實際執行 |
| Desktop Chat 顯示安全的圖片任務結果資訊 | **本階段 blocker** | Desktop 有獨立 renderer，不能只修 `/chat` |

### P0.5b — 圖片任務的真實階段回饋（現在做）

圖片任務在完成前，使用者需要看見**可驗證事件**；這不是顯示 LLM 的內心獨白。

```text
圖片描述已確認
→ 已送出至 OpenAI / Replicate
→ 等待 provider 回傳
→ 圖片已收到
→ 已保存到 Bridge 資產位置
→ 已顯示於對話
```

#### 可以顯示

- 使用者可讀的「送出圖片描述」（可展開看完整 prompt）；
- 真實 tool start / request sent / response received / media persisted 事件；
- provider、image model、最終成功／失敗；
- 可重試的簡短失敗原因。

#### 絕對不可顯示

- 原始 LLM intermediate output、XML tags、tool-call JSON；
- 系統 prompt、API token、絕對路徑、完整 provider response body；
- 沒有 API 事實佐證的「OpenAI 已接受／正在製作」。

> OpenAI 現有圖片 endpoint 在本 App 是同步呼叫：未取得 202 / request id / provider job status 前，UI 只能誠實顯示「已送出，等待 OpenAI 回傳」，不可說它已開始製作。Replicate 若取得 prediction id/status，才可顯示對應的 provider 已受理狀態。

### P0.5 明確不做

- Gemini / MiniMax 圖片 API adapter
- 全新資產根目錄與安裝 onboarding
- 向量資料庫的資產索引
- 另存、刪除、移動原檔的完整生命週期
- 讓 Agent 自動分析剛生成的圖片

> P0.5 完成條件：畫面上的 provider／model 不是猜測；圖片任務成功或失敗都可讓使用者一眼判定；圖片能直接看見。

---

### 模型標示不是裝飾，必須保留

對話泡泡必須保留模型標示；使用者有權知道每一輪是由誰完成。修正不是移除，而是把目前「Settings 預設 provider 推測」改成真實 execution receipt：

```text
文字：<實際 LLM provider> · <實際 model>
圖片：<實際 image provider> · <實際 image model>
```

若一輪同時有文字與圖片，兩者分開顯示。不得用 `StorageService.getProvider()` 或任何 UI 設定值冒充實際 request 來源。

---

## P0.6 — 下一階段：Bridge 資產櫃（Asset Cabinet）

這一階段才解決「安裝後預設資料夾、使用者可選位置、Agent 有規可循、向量資料庫能找到檔案」。

### 以現有系統升級，不造第二個檔案／索引宇宙

現有 `BridgeMediaStore` 已有 `bridge_media/images`、`documents`、`videos`、`audio` 類別路徑；`AssetIndexService` 已有 `AssetKind.image`、manifest、hash、`VisionEmbeddingPipeline` 與 embedding 狀態。P0.6 的工作是把它們統合：

```text
BridgeMediaStore
  → 可設定的 Bridge Asset Root / 分類資料夾
  → 註冊為 AssetIndexService 的受管根目錄
  → AssetRecord + manifest + VisionEmbeddingPipeline
  → SecondBrainFileEntry / Vector DB
```

生成成功與 embedding 必須非同步分離：先交付圖片，再建立 caption / tags / embedding；索引失敗可重試但不得讓圖片任務看起來失敗。

### 應建立的結構

```text
<Bridge Asset Root>                         # 初次啟動建議；使用者可改一次
├── images/                                 # Agent / 使用者圖片資產
├── documents/                              # txt / md / pdf / docx
├── datasets/                               # csv / xlsx / json
├── audio/                                  # 音訊與音樂
├── video/                                  # 影片
├── imports/                                # 使用者匯入、尚未分類
└── .bridge/
    ├── asset-manifest.json                 # asset id → 相對路徑、hash、來源、生成時間
    ├── provenance/                         # 每個 asset 的 execution receipt sidecar
    └── index/                              # 索引狀態；不是原始檔案本體
```

### 向量資料庫的正確角色

向量資料庫**不存圖片二進位檔**。它要存的是：

```text
assetId
relativePath
content hash
產生者（provider / model / job id）
使用者命名與 tags
OCR / 圖像描述 / metadata
embedding
```

向量結果回來後再指向 Asset Cabinet 的原檔。這樣可搬遷、可重建 index、可刪除、也不會讓資料庫與檔案系統互相偽裝。

### P0.6 交付物

- 首次安裝／事後設定的 Asset Root 選擇器
- 空資料夾建立與可遷移 manifest
- 生成資產自動進正確類別
- 預覽卡的「另存」「在 Finder 顯示」「刪除」；**對話泡泡與 Asset Inspector Window 都必須提供這些動作**，不得只有其中一個入口能管理資產。
- 兩個入口必須呼叫同一個以 `assetId` 為核心的 `AssetActionService`：同一份 reference-count、確認 dialog、實際檔案操作與 Conversation / manifest 更新，避免跨視窗狀態不一致。
- **Asset Inspector Window**：由 Asset ID 開啟的獨立 macOS 視窗，不是 chat Dialog；可拖曳、自由調整大小、最大化、全螢幕，關閉不影響主 Bridge 對話。
  - 內容：原始圖片／影音／文件預覽、真實 execution receipt、Asset Root 相對位置、向量索引狀態。
  - 動作：另存副本、在 Finder 顯示、刪除受管原檔、重新索引。
  - 實作前提：Bridge 現有 `window_manager` 只管理主視窗；P0.6 必須先評估／引入可安全承載 second Flutter window 的 macOS multi-window 方案，不能把主視窗 API 誤當多視窗能力。
- delete 前的 asset reference-count 與確認
- metadata / caption 的非同步 embedding；索引失敗不得阻擋生成交付

---

## P1 — Provider Capability 真正擴充

MiniMax / Gemini 生圖屬於這一階段，而非 P0.5 hotfix。

每一個新 adapter 的完成條件：

1. 官方 API 文件與當前 model / endpoint 經驗證；
2. BridgeAdapterRegistry 註冊對應 `generateImage` 能力；
3. 設定頁只列出**已實作**的圖片 provider；
4. 真正 request 的 provider / model / request ID 寫入 execution receipt；
5. integration test 用 mock 驗證 request payload、成功與完整失敗文案；
6. 不允許只因 token 存在就顯示「可生成圖片」。

在 P1 之前，Gemini / MiniMax 的圖像請求應明確回報「adapter 未實作」，絕不能假裝即將開始。

---

## P2 — Vision Capability 合約

本地 Gemma vision 與生成後再分析歸這個階段。

- 啟動前 probe llama-server 是否接受 vision multimodal request；
- 讀取 runtime 實際 model id，不可只看 catalog label；
- timeout 設定與顯示文字使用同一個值；
- vision success / failure 必須有最終 user-facing 回覆；
- 不可因為 image generation 失敗就自動轉 vision；
- 若使用者要求「分析這張生成圖」，才由使用者意圖啟動 Vision Job。

---

## P3 — 泛用任務證據（Task Evidence）

圖片證據先在 P0.5 做到可信交付；搜尋、檔案、Canvas、子代理則等 Asset / receipt 合約穩定後再擴充。

```text
web search   → 來源與時間戳
canvas       → 節點 / 連線差異
file action  → asset id、位置與回復動作
subagent     → 子任務結果與 artifacts
```

不再做「思考中」的裝飾卡；只顯示可以驗證、可以行動、可以回頭找的結果。

---

## 目前的裁決

| 問題 | 分配 | 狀態 |
|---|---|---|
| `kimi-k3` 假 model label | P0.5 | ✅ 完成 |
| 預設圖片 provider 實際是誰 | P0.5 | ✅ 完成（execution receipt） |
| 圖片直接顯示與放大 | P0.5 | ✅ 完成（macOS Preview） |
| 另存、Finder、刪除 | P0.6 | ✅ 完成（AssetActionService） |
| 預設分類資料夾與可換 root | P0.6 | ❌ 取消（macOS Preview 替代） |
| 生成圖自動 embedding | P0.6c | ✅ 完成 |
| Gemini 生圖 adapter | P1 | ✅ 完成（遷移至 Nano Banana 2） |
| MiniMax 生圖 adapter | P1 | ✅ 完成 |
| OpenAI 生圖 adapter | P1 | ✅ 完成（清理為 gpt-image-2 唯一） |
| Replicate 生圖 adapter | P1 | ✅ 完成（flux-schnell） |
| Gemma 本地 vision probe | P2 | ✅ 完成（VisionProbe + timeout 統一） |
| 搜尋／檔案／Canvas 任務結果卡 | P3 | ⏳ search ✅ / canvas 待功能成熟 / subagent 待功能成熟 |
