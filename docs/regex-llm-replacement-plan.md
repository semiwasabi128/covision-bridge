# Regex → LLM 替換分析報告

> **產出日期**：2026-07-10
> **資料來源**：`regex-semantic-understanding-audit.md`（18 處用正則做語意理解的系統級 audit）
> **目前架構**：`SemanticIntentService` 三層瀑布（L1 規則 → L2 stub → L3 LLM），feature flag `semantic_intent_enabled` 預設開啟（commit fa75082）
> **範圍**：僅分析，不改碼

---

## 執行摘要

18 處 regex 依替換可行性分為三類：

| 分類 | 數量 | 說明 |
|------|------|------|
| ✅ **可安全替換** | 8 處 | SemanticIntentService 已有對應方法或可直接擴充，風險低 |
| ⚠️ **需 使用者 確認成本** | 6 處 | 涉及 LLM 延遲/成本，需確認 UX 可接受度或需新增 L3 方法 |
| 🛡️ **應保留 regex** | 4 處 | 正則在此處是正確工具（快車道、本地無 API 需求、或 LLM 價值低） |

### Phase 現況

| Phase | 範圍 | SemanticIntentService 方法 | 接線狀態 |
|-------|------|--------------------------|---------|
| Phase 1（門系統 6 處） | #1-6 | `detectDoorIntent` / `extractDoorTitle` / `detectDoorDrift` | ✅ 已接線（chat_controller.dart L1184-1302） |
| Phase 2（路由 8 處） | #7-14 | `classifyRoutingIntent` / `inferBridgeAction` / `detectDocumentType` | ❌ 尚未實作 |
| Phase 3（記憶 5 處） | #15-18 | `extractMemoryItems` / `detectEmotion` / `extractOpenIntention` | ❌ 尚未實作 |

---

## 詳細分析：18 處 Regex

### 類別一：門系統（6 處，#1-6）

---

#### #1 `explicitProjectDoorTitleFromText()` — 門命名正則

| 項目 | 內容 |
|------|------|
| **檔案** | `chat_controller.dart` |
| **行號** | L974-1023 |
| **現狀** | 4 層正則優先序：叫做+引號 → 叫做無引號 → 純引號 → 動詞+後綴。已修 4 輪仍無法覆蓋自然語言多樣性 |
| **SemanticIntentService** | `extractDoorTitle()` 已實作（L1 四規則 + L3 LLM） |
| **接線狀態** | ✅ 已接線。`detectProjectDoorProposalAsync()` L1198 呼叫 `extractDoorTitle()` 覆寫 title |
| **替換判定** | ✅ **可安全替換** |
| **分析** | Phase 1 已完成。正則仍作為同步快車道保留（`detectProjectDoorProposal()` 先跑），語意版在 feature flag 開啟時覆寫。設計正確：L1 短路明確格式（引號命名），L3 LLM 處理自然語言。**正則可保留為 L1 快車道，不需刪除** |
| **風險** | 低。已有 A/B log 比對 L1 vs L3 差異 |
| **成本** | LLM 呼叫 200-500ms，已由 async 接線吸收 |

---

#### #2 `detect()` wantsToStart — 門偵測關鍵字

| 項目 | 內容 |
|------|------|
| **檔案** | `project_door_signal_service.dart` |
| **行號** | L28-64 |
| **現狀** | 64 個 `_containsAny` 關鍵字判斷是否要建門。問句「這個專案要如何開始呢？」被誤判 |
| **SemanticIntentService** | `detectDoorIntent()` 已實作（L1 明確指令 + L3 LLM） |
| **接線狀態** | ✅ 已接線。`detectProjectDoorProposalAsync()` L1229 在正則版未命中時呼叫 `detectDoorIntent()` |
| **替換判定** | ✅ **可安全替換** |
| **分析** | Phase 1 已完成。正則版 `detect()` 作為同步 base card 生成器保留，語意版在 base card 為 null 時接手。但注意：`detect()` 仍被 `detectProjectDoorProposal()` 同步呼叫（L1313），語意版只在 async 版中追加。**目前架構正確：同步版先跑，語意版補漏** |
| **風險** | 低。feature flag 關閉時零回歸 |
| **成本** | 正則版命中時不觸發 LLM（成本零）；正則版未命中時才走 LLM |

---

#### #3 `titleForContext()` — 門標題硬編碼

| 項目 | 內容 |
|------|------|
| **檔案** | `project_door_signal_service.dart` |
| **行號** | L122-145 |
| **現狀** | 硬編碼 semidao→SemiDAO、直播→直播帶貨…否則「新的橋樑專案」。完全不根據使用者實際說的話命名 |
| **SemanticIntentService** | `extractDoorTitle()` L3 LLM 已可生成語意化標題 |
| **接線狀態** | ✅ 間接已接線。`detectProjectDoorProposalAsync()` L1198 用 `extractDoorTitle()` 覆寫 `titleForContext()` 的結果 |
| **替換判定** | ✅ **可安全替換** |
| **分析** | `titleForContext()` 的輸出被 `extractDoorTitle()` 的 LLM 結果覆寫。硬編碼仍作為 L1 fallback 保留，但在 feature flag 開啟時會被 LLM 結果取代。**設計正確，不需額外修改** |
| **風險** | 低 |
| **成本** | 無額外成本（與 #1 共用 LLM 呼叫） |

---

#### #4 `_looksLikeProjectDoor()` — 意圖脊服務門偵測

| 項目 | 內容 |
|------|------|
| **檔案** | `intent_spine_service.dart` |
| **行號** | L286-311 |
| **現狀** | `hasProjectWord && hasStartOrFork` 關鍵字交集。問句/假設句會誤觸發 |
| **SemanticIntentService** | `detectDoorIntent()` 已實作，但 IntentSpineService 是同步服務 |
| **接線狀態** | ⚠️ 未直接接線。`IntentSpineService.analyze()` 是同步方法，無法直接呼叫 async 的 `detectDoorIntent()` |
| **替換判定** | ⚠️ **需 使用者 確認成本** |
| **分析** | `IntentSpineService.analyze()` 被 `chat_intent_router.dart` L78 和 `transurfing_brain_service.dart` L111 同步呼叫。要改用 LLM 需要將 `analyze()` 改為 async，或在上層（chat_controller）先跑 async 語意偵測再傳入。**這是 Phase 2 的工作**。需要新增 `SemanticIntentService.classifyRoutingIntent()` 方法，或在 `IntentSpineService` 中注入 async 門偵測結果。影響面較大——`analyze()` 的呼叫者多達 5 處 |
| **風險** | 中。`IntentSpineService` 是核心路由服務，改為 async 會影響多個呼叫鏈 |
| **成本** | 若每次 `analyze()` 都走 LLM，每則訊息 +200-500ms。需要 L1 短路大部分情況 |
| **建議** | 不改 `analyze()` 簽名。在 chat_controller 層先跑 `detectDoorIntent()`，將結果作為參數傳入 `analyze()`，讓 `_looksLikeProjectDoor()` 變成 L1 fallback |

---

#### #5 `detect()` — 門漂移偵測

| 項目 | 內容 |
|------|------|
| **檔案** | `door_drift_detector.dart` |
| **行號** | L14 |
| **現狀** | CJK/英文詞頻比對，粗糙的規則版 |
| **SemanticIntentService** | `detectDoorDrift()` 已實作（L1 關鍵詞 + L3 LLM 二次確認） |
| **接線狀態** | ✅ 已接線。`_checkDoorDriftIfNeeded()` L1287 呼叫 `detectDoorDrift()` |
| **替換判定** | ✅ **可安全替換** |
| **分析** | Phase 1.3 已完成。`door_drift_detector.dart` 在 git 中已不存在（搜索結果為空），已被 SemanticIntentService 取代。漂移偵測在背景執行，不攔截使用者操作，延遲可接受 |
| **風險** | 低。背景執行，失敗不影響流程 |
| **成本** | LLM 呼叫 200-500ms，背景執行無 UX 影響 |

---

#### #6 `bridgesForContext()` — 橋接需求判斷

| 項目 | 內容 |
|------|------|
| **檔案** | `project_door_signal_service.dart` |
| **行號** | L147-168 |
| **現狀** | 6 組 `_containsAny` 判斷需要哪些橋。使用者描述方式一變就匹配不到 |
| **SemanticIntentService** | 尚無對應方法 |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ⚠️ **需 使用者 確認成本** |
| **分析** | 橋接需求判斷影響門的 `requiredBridges` 欄位，進而影響 UI 顯示哪些橋接卡。目前是同步純關鍵字。要用 LLM 需新增 `SemanticIntentService.inferRequiredBridges()` 方法，且需要與門偵測流程整合。**問題**：橋接判斷的結果是否真的需要 LLM？使用者說「我要做影片」→「影片生成橋」這種對應其實相對固定。LLM 的價值在於理解「我想弄個動態內容」→ 也應該觸發影片生成橋 |
| **風險** | 中。錯誤的橋接判斷會讓使用者看到不相關的橋接卡 |
| **成本** | 新增 L3 方法 + prompt 設計。可與 `detectDoorIntent()` 合併（一次 LLM 呼叫同時輸出 projectName + requiredBridges） |
| **建議** | 延後到 Phase 2。可考慮將 `requiredBridges` 納入 `detectDoorIntent()` 的 JSON 輸出，不需單獨方法 |

---

### 類別二：意圖路由（4 處，#7-10）

---

#### #7 `_looksLikeAssetReuse()` — 資產重用偵測

| 項目 | 內容 |
|------|------|
| **檔案** | `intent_spine_service.dart` |
| **行號** | L313-341 |
| **現狀** | reuseVerb + assetNoun 關鍵字交集 |
| **SemanticIntentService** | 尚無對應方法（Phase 2 `classifyRoutingIntent()` 計畫中） |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ⚠️ **需 使用者 確認成本** |
| **分析** | 與 #4 同架構問題——`IntentSpineService.analyze()` 是同步的。`_looksLikeAssetReuse()` 判斷 `IntentSpineMode.assetReuse`，影響是否顯示資產重用 UI。誤判成本：顯示不相關的資產重用卡（低）或漏掉該顯示的卡（中） |
| **風險** | 中。影響 UI 顯示但不影響資料正確性 |
| **成本** | 若改為 LLM，每則訊息 +200-500ms。建議與 #4/#8/#9/#10 合併為一次 LLM 呼叫（`classifyRoutingIntent()` 一次輸出所有路由旗標） |
| **建議** | Phase 2 實作 `classifyRoutingIntent()`，一次 LLM 呼叫輸出 projectDoor / assetReuse / managedFolderRule / capabilitySetup / goalNeedsIntake 五個布林值 + 信心度 |

---

#### #8 `_looksLikeManagedFolderRuleReuse()` — 規則重用偵測

| 項目 | 內容 |
|------|------|
| **檔案** | `intent_spine_service.dart` |
| **行號** | L343-387 |
| **現狀** | reuseVerb + ruleNoun + savedSignal 三重關鍵字交集 |
| **SemanticIntentService** | 尚無對應方法 |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ⚠️ **需 使用者 確認成本** |
| **分析** | 三重交集比雙重更嚴格，但也更容易漏判。使用者說「用上次那套整理方式」→「上次」+「整理方式」勉強命中，但「照之前的方式整理」→ 可能命中 reuseVerb「照之前」但 ruleNoun 只有「方式」不在清單中 |
| **風險** | 中。漏判會讓使用者無法觸發規則重用流程 |
| **成本** | 同 #7，建議合併到 `classifyRoutingIntent()` |
| **建議** | 同 #7 |

---

#### #9 `_looksLikeCapabilitySetup()` — 能力設定偵測

| 項目 | 內容 |
|------|------|
| **檔案** | `intent_spine_service.dart` |
| **行號** | L402-413 |
| **現狀** | 7 個關鍵字。「我想接 API」不包含「接橋」→ 不觸發 |
| **SemanticIntentService** | 尚無對應方法 |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ✅ **可安全替換**（合併到 `classifyRoutingIntent()`） |
| **分析** | 7 個關鍵字覆蓋面極窄。「設定 API key」「接上服務」「開通能力」這些明確指令正則能抓，但「我想接 OpenAI」「怎麼設定 GPT」這類自然表達完全漏判。LLM 在此處價值明確 |
| **風險** | 低。誤判只會多顯示一個能力設定入口 |
| **成本** | 同 #7，合併呼叫 |
| **建議** | Phase 2 合併到 `classifyRoutingIntent()` |

---

#### #10 `_looksLikeGoalButNeedsIntake()` — 目標釐清偵測

| 項目 | 內容 |
|------|------|
| **檔案** | `intent_spine_service.dart` |
| **行號** | L415-425 |
| **現狀** | 7 個關鍵字。太寬鬆，幾乎所有對話都觸發 |
| **SemanticIntentService** | 尚無對應方法 |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ✅ **可安全替換**（合併到 `classifyRoutingIntent()`） |
| **分析** | 「我想」「我要」「目標」這些詞幾乎涵蓋所有使用者輸入。當前正則太寬鬆導致過度觸發釐清模式，反而阻礙使用者。LLM 能區分「我想了解直播帶貨」（查詢）vs「我想做直播帶貨」（目標需釐清） |
| **風險** | 低。改善誤判只會減少不必要的釐清問題 |
| **成本** | 同 #7，合併呼叫 |
| **建議** | Phase 2 合併到 `classifyRoutingIntent()` |

---

### 類別三：橋接路由（4 處，#11-14）

---

#### #11 `isAnalysisOrFeasibilityQuestion()` — 分析問題判斷

| 項目 | 內容 |
|------|------|
| **檔案** | `chat_intent_router.dart` |
| **行號** | L16-46 |
| **現狀** | 28 個關鍵字。「怎麼做」→ 分析？還是指令？ |
| **SemanticIntentService** | 尚無對應方法（Phase 2 `classifyRoutingIntent()` 可涵蓋） |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ✅ **可安全替換**（合併到 `classifyRoutingIntent()`） |
| **分析** | 與 `IntentSpineService._looksLikeAnalysisOrDecision()` 高度重疊（L121-153 幾乎相同的關鍵字清單）。兩處重複維護。`isAnalysisOrFeasibilityQuestion()` 被 `shouldSkipCapabilityGapForRequest()` 呼叫，決定是否跳過能力卡顯示。誤判會導致使用者該看到能力卡時看不到，或不該看到時跳出來 |
| **風險** | 低-中。影響 UI 顯示時機 |
| **成本** | 同 #7，合併呼叫 |
| **建議** | Phase 2 合併到 `classifyRoutingIntent()`，同時消除與 `IntentSpineService` 的重複 |

---

#### #12 `isRealtimeLookupQuestion()` — 即時查詢判斷

| 項目 | 內容 |
|------|------|
| **檔案** | `chat_intent_router.dart` |
| **行號** | L48-67 |
| **現狀** | 16 個關鍵字。「最近過得好嗎」包含「最近」→ 誤判 |
| **SemanticIntentService** | 尚無對應方法 |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | 🛡️ **應保留 regex** |
| **分析** | 即時查詢判斷的關鍵字（今天/現在/最新/天氣/股價等）是高度結構化的——這些詞幾乎只在需要即時資訊時出現。「最近過得好嗎」的誤判可通過增加排除規則修復（排除「最近過得」「最近好」等社交語句）。LLM 在此處的邊際效益低，但每則訊息都呼叫 LLM 的成本高。此函數被 `inferChatBridgeActionForRequest()` 和 `shouldSkipCapabilityGapForRequest()` 呼叫，影響是否觸發瀏覽橋 |
| **風險** | 若改 LLM：每則訊息 +200-500ms。若保留正則+修復：零成本，修排除規則即可 |
| **成本** | LLM 不划算 |
| **建議** | 保留正則，修復「最近過得好嗎」誤判（加排除條件）。若 Phase 2 `classifyRoutingIntent()` 實作後，可作為 L1 短路規則保留 |

---

#### #13 `inferChatBridgeActionForRequest()` — 橋接行動推斷

| 項目 | 內容 |
|------|------|
| **檔案** | `chat_intent_router.dart` |
| **行號** | L71-199 |
| **現狀** | 大量 `containsAnyText` 判斷要觸發哪種橋接行動（影片/音樂/文件/瀏覽/桌面檔案） |
| **SemanticIntentService** | Phase 2 計畫 `inferBridgeAction()` |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ⚠️ **需 使用者 確認成本** |
| **分析** | 這是橋接系統的核心路由函數，決定使用者訊息觸發哪個橋。目前 6 種橋接類型各用一組關鍵字判斷。問題是使用者描述方式多樣：「弄個影片」不包含「影片生成」→ 不觸發。但此函數已整合 `IntentSpineService.analyze()` 的 `shouldAnalyzeBeforeBridge` 旗標，有部分語意理解。**關鍵問題**：橋接路由的延遲敏感——使用者在等回應，+500ms 的 LLM 呼叫會明顯影響體驗 |
| **風險** | 中-高。核心路由函數，影響所有橋接觸發 |
| **成本** | 若每次都走 LLM：每則訊息 +200-500ms。需要 L1 短路 80%+ 的情況 |
| **建議** | Phase 2 實作 `inferBridgeAction()`，但 L1 正則必須保留為快車道。LLM 只在 L1 未命中時觸發。可考慮 L1 信心 ≥0.9 時直接回傳，否則走 L3 |

---

#### #14 意圖描述推斷 — Transurfing 思維面板

| 項目 | 內容 |
|------|------|
| **檔案** | `transurfing_brain_service.dart` |
| **行號** | L115-127 |
| **現狀** | `_containsAny` 判斷 AI服務/繼續/值得/卡住等意圖，影響思維面板顯示文字 |
| **SemanticIntentService** | 尚無對應方法 |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | 🛡️ **應保留 regex** |
| **分析** | 這是 `_clarifyIntent()` 方法中的意圖描述推斷，用於生成思維面板的顯示文字（如「想把外部 AI 服務轉成自己的可用能力」）。這不是路由決策——是 UI 文字生成。已有 `IntentSpineService.analyze()` 的 `userFacingSummary` 作為主要來源，`_containsAny` 只是 fallback 細化。LLM 在此處的邊際效益極低——生成的描述文字差異不大，但每則訊息 +200-500ms 成本明顯 |
| **風險** | 低。僅影響 UI 顯示文字 |
| **成本** | LLM 不划算。UI 文字生成的精度需求低 |
| **建議** | 保留正則。未來可考慮用 LLM 生成更豐富的思維面板描述，但不是替換現有正則，而是新增功能 |

---

### 類別四：記憶/意識（4 處，#15-18）

---

#### #15 未完成意圖偵測 — BridgeConsciousness

| 項目 | 內容 |
|------|------|
| **檔案** | `bridge_consciousness.dart` |
| **行號** | L57-75 |
| **現狀** | 3 個 RegExp 抓「我之後要…」「記得之後…」「等我再…」。「我之後要回家」也會被抓 |
| **SemanticIntentService** | Phase 3 計畫 `extractOpenIntention()` |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ✅ **可安全替換** |
| **分析** | `BridgeConsciousness.observeConversation()` 已是 async 方法，可直接呼叫 async 的 LLM 服務。誤判「我之後要回家」會產生噪音觀察記錄，不影響核心流程。LLM 能區分「我之後要寫完那份企劃」（未完成意圖）vs「我之後要回家」（無關）。此處 LLM 呼叫在背景執行，不影響使用者體驗 |
| **風險** | 低。背景執行，觀察記錄不影響流程 |
| **成本** | LLM 呼叫 200-500ms，背景執行無 UX 影響 |
| **建議** | Phase 3 實作 `extractOpenIntention()` |

---

#### #16 情緒偵測 — BridgeConsciousness

| 項目 | 內容 |
|------|------|
| **檔案** | `bridge_consciousness.dart` |
| **行號** | L78-101 |
| **現狀** | 關鍵字 map：累/倦/沒力→疲憊。「很多力」包含「力」→ 誤判 |
| **SemanticIntentService** | Phase 3 計畫 `detectEmotion()` |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | ✅ **可安全替換** |
| **分析** | 情緒偵測是典型的語意理解任務——「累」可以是疲憊也可以是「累積」。LLM 在此處價值明確。`observeConversation()` 已是 async，可直接整合。情緒偵測結果影響觀察記錄和連續情緒追蹤，不影響核心流程 |
| **風險** | 低。背景執行 |
| **成本** | LLM 呼叫 200-500ms，背景執行無 UX 影響 |
| **建議** | Phase 3 實作 `detectEmotion()` |

---

#### #17 記憶提取 — MemoryStore

| 項目 | 內容 |
|------|------|
| **檔案** | `memory_store.dart` |
| **行號** | L194-359 |
| **現狀** | ~30 個 RegExp 抓「記住：」「我叫…」「我喜歡…」等。使用者不會用精確格式說話 |
| **SemanticIntentService** | Phase 3 計畫 `extractMemoryItems()` |
| **接線狀態** | ⚠️ 已有 LLM 慢車道。`SmartMemoryExtractor`（`smart_memory_extractor.dart`）已實作 LLM 二次提取 |
| **替換判定** | 🛡️ **應保留 regex（作為快車道）** |
| **分析** | 記憶系統已有雙軌道架構：正則快車道（`MemoryStore.regexExtract()`，零延遲）+ LLM 慢車道（`SmartMemoryExtractor`，200-500ms）。正則快車道處理明確指令（「記住：」「我叫」），LLM 慢車道處理隱含記憶。**問題不在於正則本身，而在於正則覆蓋面太窄**。正確方向是保留正則快車道（處理明確格式），讓 LLM 慢車道覆蓋更多隱含記憶。已有架構正確，只需確保 LLM 慢車道被確實呼叫 |
| **風險** | 若移除正則快車道：所有記憶提取都走 LLM，明確指令也 +200-500ms。使用者說「記住：明天開會」應該零延遲記住 |
| **成本** | 保留正則 = 零成本。移除正則改全 LLM = 每則訊息 +200-500ms |
| **建議** | **保留正則快車道**。Phase 3 的 `extractMemoryItems()` 應作為 LLM 慢車道的統一入口，不是替換正則。可考慮將正則提取結果傳給 LLM 做「品質校驗」（過濾誤提取），但不移除正則 |

---

#### #18 文件類型偵測 — LocalDocumentAdapter + BridgeMediaStore

| 項目 | 內容 |
|------|------|
| **檔案** | `local_document_adapter.dart` + `bridge_media_store.dart` |
| **行號** | L130-153 / L200-216 |
| **現狀** | 7 個 RegExp：prd/企劃/報告/規則/摘要/清單/簡報。兩處重複維護 |
| **SemanticIntentService** | Phase 2 計畫 `detectDocumentType()` |
| **接線狀態** | ❌ 未接線 |
| **替換判定** | 🛡️ **應保留 regex** |
| **分析** | 文件類型偵測的目的是決定文件存入哪個子目錄（`/rules/`、`/reports/` 等）。這是分類任務，正則在此處的表現已足夠——「PRD」「企劃」「報告」這些詞幾乎不會在其他語境出現。使用者說「幫我寫個東西」→ 全部不中，但這只影響目錄分類（fallback 到 `general/`），不影響文件產出本身。**兩處重複維護是真正的問題**——應先合併為一個共用方法，而非改用 LLM。LLM 在此處的邊際效益低（分類精度提升有限），但成本高（文件產出流程已是 async，但增加 LLM 呼叫會延遲文件生成） |
| **風險** | 低。誤判只影響目錄分類 |
| **成本** | LLM 不划算。目錄分類不需要語意理解 |
| **建議** | **保留正則**。優先解決兩處重複維護問題——提取為共用方法（如 `DocumentTypeClassifier.classify(prompt)`），兩處共用。若要提升分類品質，可在 LLM 生成文件時順帶輸出類型（已有 `ApiService.generateDocumentMarkdown()` 呼叫 LLM），不需單獨的 LLM 分類呼叫 |

---

## 替換優先序建議

### 第一優先：已完成（Phase 1，門系統 #1-5）

✅ `detectDoorIntent` / `extractDoorTitle` / `detectDoorDrift` 已實作且已接線。

**行動**：無需額外工作。真機測試驗證 LLM 門偵測+命名+漂移的實際效果。

### 第二優先：Phase 2 路由（#7-11, #13）

建議實作 `classifyRoutingIntent()` + `inferBridgeAction()`，一次 LLM 呼叫覆蓋多個路由判斷：

| 方法 | 覆蓋 | LLM 輸出 JSON |
|------|------|--------------|
| `classifyRoutingIntent()` | #4, #7, #8, #9, #10, #11 | `{projectDoor, assetReuse, managedFolderRule, capabilitySetup, goalNeedsIntake, isAnalysis, confidence}` |
| `inferBridgeAction()` | #13 | `{bridgeType, shouldAnalyzeFirst, confidence}` |

**關鍵設計約束**：
- L1 正則必須短路 ≥80% 的明確情況（影片/音樂/文件等關鍵字明確時不走 LLM）
- LLM 只在 L1 未命中或信心 <0.7 時觸發
- `IntentSpineService.analyze()` 保持同步，在上層注入 async 語意結果

### 第三優先：Phase 3 記憶（#15, #16）

實作 `extractOpenIntention()` + `detectEmotion()`。背景執行，無延遲約束。

### 不替換（#12, #14, #17, #18）

| # | 原因 |
|---|------|
| #12 | 即時查詢關鍵字高度結構化，修排除規則即可 |
| #14 | UI 文字生成，LLM 邊際效益低 |
| #17 | 已有雙軌道架構（正則快+LLM 慢），保留正則快車道 |
| #18 | 目錄分類不需語意理解，優先合併重複代碼 |

---

## 風險矩陣

| # | 影響面 | 延遲敏感 | 誤判成本 | LLM 價值 | 替換判定 |
|---|--------|---------|---------|---------|---------|
| 1 | 門命名 | 中 | 高 | 高 | ✅ 已完成 |
| 2 | 門偵測 | 中 | 高 | 高 | ✅ 已完成 |
| 3 | 門標題 | 中 | 中 | 高 | ✅ 已完成 |
| 4 | 意圖路由 | 高 | 中 | 高 | ⚠️ 需確認 |
| 5 | 門漂移 | 低 | 中 | 高 | ✅ 已完成 |
| 6 | 橋接需求 | 中 | 低 | 中 | ⚠️ 需確認 |
| 7 | 資產重用 | 高 | 中 | 中 | ⚠️ 需確認 |
| 8 | 規則重用 | 高 | 中 | 中 | ⚠️ 需確認 |
| 9 | 能力設定 | 高 | 低 | 高 | ✅ 可替換 |
| 10 | 目標釐清 | 高 | 中 | 高 | ✅ 可替換 |
| 11 | 分析判斷 | 高 | 中 | 中 | ✅ 可替換 |
| 12 | 即時查詢 | 高 | 中 | 低 | 🛡️ 保留 |
| 13 | 橋接路由 | 高 | 高 | 中 | ⚠️ 需確認 |
| 14 | 思維面板 | 中 | 低 | 低 | 🛡️ 保留 |
| 15 | 未完成意圖 | 低 | 低 | 高 | ✅ 可替換 |
| 16 | 情緒偵測 | 低 | 低 | 高 | ✅ 可替換 |
| 17 | 記憶提取 | 高 | 中 | 中 | 🛡️ 保留快車道 |
| 18 | 文件分類 | 中 | 低 | 低 | 🛡️ 保留 |

---

## 給 使用者 的決策清單

以下 6 處需要 使用者 確認是否接受 LLM 延遲成本：

1. **#4 `_looksLikeProjectDoor()`**：是否接受在 `IntentSpineService` 路由中引入 async 語意偵測？建議在上層注入而非改 `analyze()` 簽名。
2. **#6 `bridgesForContext()`**：是否將 `requiredBridges` 納入 `detectDoorIntent()` 的 JSON 輸出？還是單獨方法？
3. **#7+#8 資產/規則重用**：是否合併到 `classifyRoutingIntent()` 一次 LLM 呼叫？
4. **#13 `inferChatBridgeActionForRequest()`**：核心路由函數，L1 短路門檻建議 ≥0.9。是否接受？
5. **Phase 2 整體**：是否接受每則訊息最多一次 LLM 呼叫（200-500ms）用於路由分類？L1 短路 ≥80% 的情況。
6. **#17 記憶提取**：確認保留正則快車道 + LLM 慢車道的雙軌道架構，不移除正則。

---

## 附錄：SemanticIntentService 現有方法與待實作方法

### 已實作（Phase 1）

| 方法 | L1 策略 | L3 策略 | 狀態 |
|------|---------|---------|------|
| `detectDoorIntent()` | 明確指令短路 (≥0.95) | prompt JSON | ✅ |
| `extractDoorTitle()` | 四規則短路 (≥0.85) | prompt JSON | ✅ |
| `detectDoorDrift()` | 關鍵詞不漂移短路 (≥0.85) | L1 報漂移→L3 二次確認 | ✅ |

### 待實作（Phase 2-3）

| 方法 | 覆蓋 # | 預期 L1 策略 | 預期 L3 策略 |
|------|--------|-------------|-------------|
| `classifyRoutingIntent()` | 4,7,8,9,10,11 | 關鍵字交集短路 (≥0.9) | prompt JSON 多欄位 |
| `inferBridgeAction()` | 13 | 橋接類型關鍵字短路 (≥0.9) | prompt JSON |
| `detectDocumentType()` | 18 | RegExp 分類 (≥0.95) | 不建議 L3 |
| `extractMemoryItems()` | 17 | 正則快車道保留 | LLM 慢車道已存在 |
| `detectEmotion()` | 16 | 關鍵字 map 短路 (≥0.9) | prompt JSON |
| `extractOpenIntention()` | 15 | RegExp 短路 (≥0.9) | prompt JSON |

---

*本報告基於 2026-07-10 的程式碼狀態產出。commit fa75082 已將 feature flag 預設開啟。*
