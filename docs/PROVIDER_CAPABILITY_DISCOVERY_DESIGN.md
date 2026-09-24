# Bridge App Provider Capability Auto-Discovery 設計

> **狀態**：2026-08-07 · Design draft
> **目的**：API key 輸入時自動偵測該 provider 支援的所有能力（圖片生成、文字對話、TTS、embedding...），自動開通候選使用。
> **代號**：Capability Discovery Layer

---

## 1. 問題

使用者 的願景：
> 輸入任何新的 API key 時，系統偵測出這把鑰匙能調用多少能力跟工具，然後幫她把這把鑰匙的全部能力開通。

現實：
- OpenAI `/v1/models` 只回 model ID，不回能力（community 要求多年仍未實作）
- Gemini `/v1/models` 有部分 metadata 但不標準化
- MiniMax 沒有 `/models` endpoint
- Replicate 有 model 描述但格式不統一

**結論**：不能靠 API 自動偵測能力。需要我們維護一層 capability registry。

---

## 2. 設計

### 2.1 ProviderCapabilityRegistry

一個靜態對照表，記錄每個 provider 支援哪些能力 + 怎麼呼叫：

```dart
class ProviderCapability {
  final String providerId;       // 'openai', 'gemini', 'minimax', 'replicate'
  final String displayName;      // 'OpenAI', 'Google Gemini', 'MiniMax'
  final Set<Capability> capabilities;
  final String modelsEndpoint;   // '/v1/models' or null
  final Map<Capability, String> defaultModels;  // capability → default model ID
}

enum Capability {
  textChat,
  imageGeneration,
  imageEditing,
  tts,
  stt,
  embedding,
  videoGeneration,
  musicGeneration,
}
```

### 2.2 流程

```
使用者輸入 API key + 選 provider
  → ProviderCapabilityRegistry.lookup(providerId)
  → 取得該 provider 支援的 capabilities
  → 對每個 capability：
    - 如果有 adapter → 自動註冊到 BridgeAdapterRegistry
    - 如果沒有 adapter → 標記「即將支援」但不啟用
  → 設定頁顯示：「這把鑰匙開通了 N 項能力」
```

### 2.3 已知 provider 能力對照（2026-08-07）

| Provider | textChat | imageGen | imageEdit | TTS | STT | embedding | video | music |
|---|---|---|---|---|---|---|---|---|
| OpenAI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Gemini | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| MiniMax | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Replicate | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Anthropic | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 2.4 與現有系統的接點

- `BridgeAdapterRegistry` — 已有，新增 adapter 註冊在這裡
- `CapabilityAdvisor` — 已有，會根據已註冊的 adapter 列出可用能力
- 設定頁 — 已有 API key 輸入，需要加「能力偵測結果」顯示

---

## 3. 分期

### Phase P1-1：MiniMax + Gemini image adapter（現在）
- 先手動實作這兩個 adapter
- 驗證 API 格式、model ID、request/response
- 註冊到 BridgeAdapterRegistry

### Phase P2-1：ProviderCapabilityRegistry（接著）
- 建立靜態對照表
- API key 輸入時查表 + 自動註冊已有 adapter
- 設定頁顯示能力清單

### Phase P3-1：動態 model 發現（未來）
- 呼叫 `/v1/models` 取得最新 model 清單
- 用 heuristic 判斷新 model 的能力（model name 含 'image' → imageGen）
- 社群可貢獻新的 provider capability 定義
