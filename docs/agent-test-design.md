# 橋樑 App Agent 自動化測試方案

> 建立日期：2026-07-03 by 教練 Agent (CEO)
> 目標：讓 Agent 扮演真實使用者，自動測試 App 的行為反應，找出盲點。
> 使用者 原話：「以我的時間，我沒辦法這樣一直跟他聊，然後找出行為反應的盲點。

---

## 一、測試架構總覽

```
┌─────────────────────────────────────────────────┐
│              Agent 自動化測試方案                  │
├──────────┬──────────┬──────────┬────────────────┤
│  Layer 1 │  Layer 2 │  Layer 3 │    Layer 4     │
│ 單元測試  │ 邏輯模擬  │ 模擬器UI │   真機驗證     │
│ (dart)   │ (Agent   │ (Maestro │  (使用者 手動    │
│          │  讀碼)   │  +simctl)│   + 截圖回報)  │
└──────────┴──────────┴──────────┴────────────────┘
```

### Layer 1：單元測試（已建立）
- **工具**：`flutter test`
- **範圍**：純邏輯 — prompt 建構、JSON 解析、去重演算法
- **檔案**：`test/smart_memory_extractor_test.dart`
- **特點**：不依賴 LLM API，純函數測試
- **覆蓋場景**：
  - ✅ 正常 JSON 解析（單條/多條）
  - ✅ 容錯（markdown fence、空陣列、非 JSON、部分欄位缺失）
  - ✅ importance clamp（0→1, 99→5）
  - ✅ category 模糊匹配（中文→英文 key）
  - ✅ content 太短過濾（<3字元）
  - ✅ 8 種記憶提取場景的 prompt 建構驗證

### Layer 2：邏輯模擬測試（Agent 讀碼模擬）
- **工具**：`delegate_task` / `hermes --profile research chat -q`
- **模式**：Agent 扮演虛擬使用者，讀程式碼模擬操作流程
- **人格**：阿志（零基礎）、小恩（有 AI 經驗）、建新（農場主）
- **流程**：見 `bridge-app-agent-test-loop` skill

### Layer 3：模擬器 UI 測試（Maestro + simctl）— ✅ 已完成首輪
- **工具**：`bridge_test_controller.py` + Maestro YAML flow
- **模式**：Agent 透過 CLI 操控 iOS 模擬器
- **能力**：截圖、點擊、滑動、輸入文字、等待動畫
- **限制**：需要 mock 注入繞過 onboarding；無法測真機 API 連線
- **首輪結果（2026-07-03）**：見下方「六、L3 實測報告」

### Layer 4：真機驗證（使用者 手動）
- **模式**：使用者 操作 → 截圖 → alt-text 寫問題 → 傳給 CEO
- **定位**：最終驗證，抓模擬器抓不到的渲染/手感/runtime crash

---

## 二、記憶提取專項測試

### 2.1 單元測試場景（Layer 1，已完成）

| # | 場景 | 使用者語句 | 快車道(正則) | 慢車道(LLM) | 期望結果 |
|---|------|-----------|-------------|-------------|---------|
| 1 | 明確身份宣告 | 「我叫建新」 | ✅ 抓到 | ✅ 也抓到，去重後不重複寫入 | 1 條記憶 |
| 2 | 隱含專案資訊 | 「我最近在搞一個 Flutter app」 | ❌ 漏抓 | ✅ 語意理解抓到 | 1 條記憶 |
| 3 | 明確記憶指令 | 「記住：我女兒叫小星星」 | ✅ 抓到 | ✅ 也抓到，去重 | 1 條記憶 |
| 4 | 即時評論 | 「那個 API 文件寫得真爛」 | ❌ 不抓 | ❌ 判斷不值得 | 0 條記憶 |
| 5 | 穩定偏好 | 「我討厭寫文件」 | 可能抓到 | ✅ 語意理解抓到 | 1 條記憶 |
| 6 | 太短訊息 | 「嗨」 | ❌ 不抓 | ❌ 不呼叫 LLM | 0 條記憶 |
| 7 | 混合訊息 | 「幫我搜尋一下，對了我叫建新」 | 部分抓到 | ✅ 只提取身份部分 | 1 條記憶 |
| 8 | 生活情境 | 「最近搬到台北了」 | 可能抓到 | ✅ 語意理解抓到 | 1 條記憶 |

### 2.2 邏輯模擬測試場景（Layer 2）

以下場景用迦勒（Research Agent）讀碼模擬，驗證雙軌流程的正確性：

#### 場景 A：慢車道不阻塞對話
```
1. 使用者發送「我叫建新」
2. 快車道立即提取 → UI flash 顯示「記住了」
3. AI 回覆正常生成（不被 LLM 提取阻塞）
4. 慢車道在背景完成 → 靜默寫入大腦容器
驗證點：AI 回覆延遲 ≤ 正常回覆時間（慢車道不影響）
```

#### 場景 B：慢車道失敗靜默
```
1. 使用者發送「我最近在搞一個 Flutter app」
2. 快車道抓不到（無前綴詞）
3. 慢車道 LLM 呼叫（模擬 API timeout）
4. 對話正常繼續，使用者無感
驗證點：API 失敗不拋例外、不顯示錯誤、不阻塞下一條訊息
```

#### 場景 C：去重正確
```
1. 使用者發送「記住：我叫建新」
2. 快車道提取 → 「我叫建新」→ 寫入 MemoryStore + BrainContainer
3. 慢車道也提取 → 「使用者名叫建新」
4. 文字相似度比對 → bigram Jaccard > 0.6 → 跳過
5. 向量相似度比對 → cosine > 0.85 → 跳過
驗證點：最終大腦容器只有 1 條相關記憶，不重複
```

#### 場景 D：保守原則 — 不過度提取
```
1. 使用者發送「你好，今天天氣不錯」
2. 快車道不觸發
3. 慢車道 LLM 判斷：打招呼 + 即時評論 → 回傳 []
4. 不寫入任何記憶
驗證點：LLM 回傳空陣列，不寫入
```

### 2.3 模擬器驗證場景（Layer 3）— ✅ 已執行

> 實測日期：2026-07-03 | 模擬器：iPhone 17 (iOS 26.5) | commit: `4e742d6`

**Mock 注入方式**：建立獨立 `lib/main_test.dart`（測試後已刪除），pre-seed：
- SharedPreferences: companion JSON + `onboarding_completed = true`
- Secure Storage: mock API token
- 關鍵修正：`await CompanionStore().init()` 必須在 `runApp` 前執行，否則 router redirect 時 `_companions` 還沒載入

**Semantics label 方案**：在 `chat_input_bar.dart` 的送出按鈕加 `Semantics(label: '送出', button: true)`，讓 Maestro 用 `tapOn: '送出'` 精準定位。比座標點擊穩定得多。

```yaml
# Maestro flow 實際使用的 YAML
appId: farm.semiwasabi.bridgeApp
---
- tapOn:
    point: 50%,90%      # 點輸入框
- inputText: "我叫建新"
- tapOn: "送出"          # Semantics label 定位
```

**驗證結果**：

| 步驟 | 場景 | 結果 | 驗證方式 |
|------|------|------|---------|
| 1 | Mock 注入 → app 直進聊天頁 | ✅ PASS | vision_analyze 截圖確認 |
| 2 | 輸入「我叫建新」 | ✅ PASS | vision_analyze 截圖確認 |
| 3 | Semantics tapOn 送出 | ✅ PASS | Maestro COMPLETED |
| 4 | 訊息送出 + 輸入框清空 | ✅ PASS | vision_analyze 截圖確認 |
| 5 | 快車道記憶寫入 | ✅ PASS | `plutil -p` 讀取 SharedPreferences: `flutter.bridge_memories => ["我叫建新"]` |
| 6 | 慢車道靜默失敗（API 不可達） | ✅ PASS | 第二條訊息未寫入（預期行為） |
| 7 | UI flash 回饋 | ❌ BUG | 快車道成功路徑未設 `_showMemoryFlash = true`（見下方 bug 記錄） |

**關鍵發現**：記憶寫入直接從 SharedPreferences plist 驗證，比 UI 導航更可靠：
```bash
APP_DATA=$(xcrun simctl get_app_container booted farm.semiwasabi.bridgeApp data)
plutil -p "$APP_DATA/Library/Preferences/farm.semiwasabi.bridgeApp.plist" | grep "bridge_memories"
```

---

## 三、Agent 扮演使用者測試

### 3.1 虛擬使用者人格（沿用 test-loop skill）

| 人格 | 背景 | 記憶相關測試重點 |
|------|------|----------------|
| **阿志** | 43歲，零 AI 背景 | 「我叫阿志」→ 確認記住了 |
| **小恩** | 28歲，科技業 | 「我用 ChatGPT 兩年了」→ 確認記住了 |
| **建新** | 農場主，熟悉 AI | 「我在管理 7 個 AI agent」→ 確認記住了 |

### 3.2 迦勒模擬派工格式（記憶提取專項）

```
你是農場的 Research Agent 迦勒。請模擬真實使用者對橋樑 App 的記憶提取功能進行測試。

## 測試目標
驗證 SmartMemoryExtractor 雙軌架構（正則快車道 + LLM 慢車道）

## 相關程式碼
- lib/services/brain_container/extraction/smart_memory_extractor.dart
- lib/services/brain_container/extraction/extraction_prompt.dart
- lib/services/memory_store.dart (extractFromMessage, line 98)
- lib/controllers/chat_controller.dart (_runSmartExtraction, ~line 1855)

## 測試步驟
1. 讀取 smart_memory_extractor.dart，理解 extract() 方法流程
2. 逐步模擬以下使用者訊息的處理流程：
   a. 「我叫建新」— 快車道和慢車道都應抓到
   b. 「我最近在搞一個 Flutter app」— 只有慢車道能抓到
   c. 「記住：我女兒叫小星星」— 快車道抓到，慢車道去重
   d. 「那個 API 文件寫得真爛」— 都不應提取
   e. 「嗨」— 太短，慢車道不呼叫 LLM
3. 對每條訊息，描述：
   - 快車道是否觸發？提取了什麼？
   - 慢車道是否觸發？預期 LLM 回傳什麼？
   - 去重後最終寫入了什麼？
   - 是否有阻塞對話？是否有錯誤？

## 輸出格式（繁體中文）
【場景N】訊息：「...」
  快車道：觸發/未觸發，提取：「...」
  慢車道：觸發/未觸發，預期提取：「...」
  去重：通過/跳過
  最終寫入：N 條
  阻塞風險：有/無
  異常風險：有/無

【整體評估】
- 雙軌流程是否正確隔離
- 去重機制是否有效
- 保守原則是否被遵守
```

### 3.3 模擬器端到端測試流程（已驗證）

> 以下為實際驗證過的可重現流程。`main_test.dart` 為臨時檔案，測試後刪除。

```bash
# 0. 環境設定
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$HOME/.maestro/bin:$PATH"
BOT="python3 ~/Developer/bridge_app/tools/bridge_test_controller.py"
cd ~/Developer/bridge_app

# 1. Mock 注入 — 建立臨時 main_test.dart
#    (pre-seed SharedPreferences companion JSON + onboarding_completed=true)
#    (pre-seed Secure Storage mock token)
#    关鍵：await CompanionStore().init() 必須在 runApp 前執行

# 2. Build + Install + Launch
flutter build ios --debug --simulator -t lib/main_test.dart
$BOT terminate
$BOT install build/ios/iphonesimulator/Runner.app
$BOT launch
sleep 3

# 3. 記憶提取測試 — 使用 Maestro YAML（Semantics label 定位）
cat > /tmp/maestro_memory_test.yaml << 'YAML'
appId: farm.semiwasabi.bridgeApp
---
- tapOn:
    point: 50%,90%
- inputText: "我叫建新"
- tapOn: "送出"
YAML
maestro test /tmp/maestro_memory_test.yaml

# 4. 驗證記憶寫入 — 直接讀 SharedPreferences（比 UI 導航可靠）
APP_DATA=$(xcrun simctl get_app_container booted farm.semiwasabi.bridgeApp data)
plutil -p "$APP_DATA/Library/Preferences/farm.semiwasabi.bridgeApp.plist" \
  | grep -A5 "bridge_memories"
# 預期輸出：flutter.bridge_memories => [ "我叫建新" ]

# 5. 截圖存證
$BOT screenshot /tmp/l3_memory_test.png

# 6. 清理 — 刪除臨時入口
rm lib/main_test.dart
# Semantics label 改動保留（good practice，commit 正式版）
```

---

## 四、測試執行優先順序

| 優先 | 測試項目 | 狀態 | 備註 |
|------|---------|------|------|
| P0 | 單元測試（Layer 1） | ✅ 完成 | 72 tests, `smart_memory_extractor_test.dart` + `memory_guard_test.dart` + `memory_store_test.dart` |
| P1 | 迦勒邏輯模擬（Layer 2） | ✅ 完成 | 找到 6 個問題（P1-P6），全部修復 |
| P2 | 模擬器 UI 測試（Layer 3） | ✅ 首輪完成 | 記憶寫入已驗證；1 個 UI bug 待修（flash 未觸發） |
| P3 | 真機驗證（Layer 4） | 待 使用者 操作 | 模擬器通過後 |

---

## 五、Hermes vs Bridge App 記憶機制比較

> 使用者 問：「Hermes 的記憶提取跟記憶的機制是什麼樣的？跟我們差不多嗎？」

### Hermes 的記憶機制（原始碼確認）

**一句話總結：Hermes 的「提取」完全靠 LLM 自己判斷，沒有自動提取邏輯。**

Hermes 的記憶系統分三層：

| 層 | 機制 | 提取方式 |
|----|------|---------|
| **內建記憶** (MEMORY.md / USER.md) | LLM 主動呼叫 `memory` tool 寫入 | LLM 自行判斷「這句話值得記住」→ 呼叫 tool |
| **外部 Provider** (Honcho/Mem0/Hindsight) | `sync_turn()` 每輪自動寫入 | Provider 自己決定存什麼（通常存全部對話） |
| **Session Search** (FTS5) | 全文搜索過去對話 | 關鍵字匹配，非語意 |

**關鍵差異**：

| 維度 | Hermes | Bridge App（我們） |
|------|--------|-------------------|
| **提取觸發** | LLM 自行判斷 + 主動呼叫 tool | 雙軌：正則快車道（自動）+ LLM 慢車道（自動） |
| **提取智慧** | 完全靠 LLM 的判斷力（system prompt 引導） | 正則處理明確指令 + LLM 處理隱含記憶 |
| **儲存格式** | 純文字（§ 分隔），注入 system prompt | 向量 DB（BrainContainer）+ SharedPreferences |
| **檢索方式** | 全文注入 system prompt（每次都帶） | 向量相似度檢索（只取相關的） |
| **去重** | 精確字串比對（`content in entries`） | 雙重：bigram Jaccard + 向量 cosine |
| **容量限制** | 字元上限 2200（MEMORY）+ 1375（USER） | 向量 DB 無上限 + 衰減週期 |
| **不阻塞** | N/A（LLM 同步呼叫 tool） | ✅ 慢車道 fire-and-forget |
| **安全** | threat pattern 掃描（注入防護） | 無（未實作） |

### 我們比 Hermes 多了什麼

1. **自動提取**：Hermes 靠 LLM 自覺，如果 LLM 忘了呼叫 `memory` tool，記憶就丟了。我們的雙軌是自動的，使用者不用靠 AI 的「記性」。
2. **語意去重**：Hermes 只做精確字串比對。我們有 bigram + 向量雙重去重。
3. **向量檢索**：Hermes 每次都把全部記憶塞進 system prompt（2200 字上限）。我們用向量檢索只取相關的，不受字數限制。
4. **不阻塞**：我們的慢車道在背景跑，不影響對話。Hermes 的 memory tool 是同步的。

### Hermes 比我們多了什麼

1. **安全掃描**：Hermes 的記憶寫入會掃描 threat pattern（防注入）。我們沒有這層防護——如果 LLM 提取到惡意構造的記憶，會直接寫入。
2. **批次操作**：Hermes 支援 `operations` 陣列一次做多個 add/replace/remove。我們目前只能逐筆寫入。
3. **外部 Provider 生態**：Hermes 有 Honcho/Mem0/Hindsight 等外部記憶後端可插拔。我們是大腦容器一條路。
4. **Frozen Snapshot**：Hermes 的記憶在 session 開始時凍結，中途修改不影響 system prompt（保 prefix cache）。我們每次都即時讀取。

### 結論

**我們的架構在「自動提取」和「檢索效率」上比 Hermes 更先進。** Hermes 的哲學是「LLM 自己決定記什麼」，靠 system prompt 引導。我們的是「系統自動提取 + LLM 語意輔助」，不需要 LLM 配合。

但 Hermes 在「安全防護」上做得更完整。這是我們可以學的——在 `writeToBrainContainer` 加一層 threat pattern 掃描。

---

## 六、L3 實測報告（2026-07-03）

### 6.1 環境

| 項目 | 值 |
|------|---|
| 模擬器 | iPhone 17 (B27C4752-D7E1-4F83-A3CD-F369643B11A1) |
| iOS | 26.5 |
| 螢幕 | 1206 × 2622 px (3x scale → 402 × 874 pt) |
| App bundle | `farm.semiwasabi.bridgeApp` |
| Build | `flutter build ios --debug --simulator -t lib/main_test.dart` |
| Commit | `4e742d6` (Semantics label) |

### 6.2 測試結果摘要

| # | 測試項目 | 結果 | 驗證方式 |
|---|---------|------|---------|
| 1 | Mock 注入 → app 直進 `/chat` | ✅ | vision_analyze 截圖 |
| 2 | 輸入「我叫建新」 | ✅ | vision_analyze 截圖 |
| 3 | `tapOn: "送出"` (Semantics) | ✅ | Maestro COMPLETED |
| 4 | 訊息送出 + 輸入框清空 | ✅ | vision_analyze 截圖 |
| 5 | 快車道記憶寫入 SharedPreferences | ✅ | `plutil -p` → `["我叫建新"]` |
| 6 | 慢車道靜默失敗（無 API） | ✅ | 第二條未寫入（預期） |
| 7 | UI flash 回饋 | ❌ BUG | 快車道成功路徑未觸發 flash |

### 6.3 發現的 Bug

**Bug #7：快車道 UI flash 未觸發**
- **位置**：`chat_controller.dart` `_runSmartExtraction()` 快車道成功路徑
- **根因**：正常提取路徑只設了 timer 關閉 flash，但沒有先設 `_showMemoryFlash = true` 和 `_memoryFlashText`
- **影響**：使用者送出含明確記憶的訊息後，看不到「記住了」回饋
- **狀態**：待修（下一個 fix cycle）

### 6.4 測試技巧筆記

1. **Semantics label > 座標點擊**：Maestro 在 iOS 模擬器上的百分比座標有偏差，`tapOn: "送出"` 比 `point: 95%,85%` 可靠
2. **SharedPreferences 直接驗證 > UI 導航**：用 `xcrun simctl get_app_container` + `plutil -p` 直接讀 plist，比導航到長期記憶頁截圖更可靠
3. **`main_test.dart` 時序陷阱**：`CompanionStore().init()` 是非同步的，必須在 `runApp` 前 `await`，否則 router redirect 時 `_companions` 是空的
4. **TextField `newline` mode**：`TextInputAction.newline` + `multiline` 表示 Enter 鍵是換行不是送出，Maestro `pressKey: Enter` 無效
5. **PATH 設定**：Maestro 需要 `JAVA_HOME` + `~/.maestro/bin`，且 `uname`/`xargs` 要在 PATH 裡（`/usr/bin:/bin`）

---

## 七、P1-P6 修復記錄（迦勒 L2 模擬發現）

### P1：短訊息門檻
- **問題**：訊息長度 < 5 字元時，慢車道仍會呼叫 LLM，浪費 token
- **修復**：加門檻檢查，短訊息只走快車道，不觸發 LLM
- **測試**：`P1 回歸` 測試案例

### P2：逗號不分割
- **問題**：「我叫建新，我住台北」快車道只提取整句，不分割逗號分隔的多條記憶
- **修復**：快車道正則支援逗號分割，分別提取
- **測試**：`P2 回歸` 測試案例

### P3：模式 D 缺「我」
- **問題**：場景 D（保守原則）中，「我」開頭的訊息被誤判為即時評論而不提取
- **修復**：修正正則模式，「我」開頭的描述性語句正確觸發快車道
- **測試**：`P3 回歸` 測試案例

### P4：第三人稱改寫去重
- **問題**：快車道提取「我叫建新」，慢車道改寫為「使用者名叫建新」，字串不同所以去重失敗
- **修復**：bigram Jaccard 相似度比對，0.6 閾值可正確識別語意重複
- **測試**：`P4 回歸` 測試案例

### P5：快車道無去重
- **問題**：快車道本身沒有去重邏輯，同一條訊息重複發送會重複寫入
- **修復**：快車道提取後也經過 MemoryStore 去重檢查
- **測試**：`P5 回歸` 測試案例

### P6：短偏好過濾
- **問題**：「我喜歡貓」這類短偏好被 content 太短過濾規則誤殺
- **修復**：偏好類記憶的長度門檻從 3 字元降至 2 字元
- **測試**：`P6 回歸` 測試案例

### 安全掃描 + 批次操作（額外）
- **memory_guard.dart**：5 類威脅 30+ pattern，靈感來自 Hermes 記憶機制比較
- **MemoryStore.batch**：批次 add/remove/replace 操作

### Commit 歷史

| Commit | 內容 |
|--------|------|
| `4bc4f3c` | 智慧記憶提取雙軌架構（正則快車道 + LLM 慢車道） |
| (中間) | 35 單元測試 + Agent 測試方案文件 + Hermes 記憶機制比較 |
| (中間) | P1+P4 修復（短訊息門檻 + 第三人稱改寫去重） |
| `055826b` | P2+P3+P5 修復 + Hermes 風格安全掃描 + 批次操作 |
| `4e742d6` | Semantics label + L3 模擬器測試驗證 |
