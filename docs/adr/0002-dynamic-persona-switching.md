# ADR 0002: 動態靈魂切換機制

## Status
Accepted

## Context
橋樑的核心願景是「同一個教練 Agent，不同任務有不同靈魂」。需要一個機制讓 AI 根據用戶意圖自動調整回覆風格。

## Decision
採用「意圖識別 + 動態 Prompt 切換」的兩層架構：

1. **本地意圖識別器**：基於規則的輕量分類器（不調用 AI）
2. **動態 System Prompt**：根據意圖載入對應的 persona prompt

### 架構
```
用戶輸入
  ↓
[IntentClassifier] → UserIntent（chat/creative/document/reminder/review）
  ↓
[PersonaPrompt] → 對應的 system prompt
  ↓
[ApiService] → 發送給 AI API
```

## Consequences

### Positive
- 反應快速（本地規則，毫秒級）
- 可解釋（為什麼切換到這個模式，規則明確）
- 用戶可手動覆蓋（提供自主權）

### Negative
- 規則需要持續維護（新增場景時要更新關鍵字列表）
- 邊界案例可能誤判（「這樣合理嗎？」→ 誤判為 review）
- 無法處理混合意圖（「幫我想點子然後記錄下來」→ 只會識別第一個）

## Mitigations
- 定期審查誤判案例，調整規則
- 提供手動覆蓋機制（AppBar 點擊切換）
- 未來可考慮加入 AI 輔助分類作為第二層

## Related
- ADR 0001: Flutter for MVP
- CONTEXT.md: 「靈魂切換」詞彙定義
