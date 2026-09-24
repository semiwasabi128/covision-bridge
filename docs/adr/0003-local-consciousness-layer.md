# ADR 0003: 本地意識層（最小可行版）

## Status
Accepted

## Context
橋樑需要「不只是回覆，還能主動觀察」的能力。但雲端 AI 服務有延遲、有成本、有隱私風險。

## Decision
在 App 本地實作輕量的「意識層」，基於規則分析用戶對話，產生觀察和提醒。

### 設計原則
1. **本地優先**：所有分析在裝置上完成，不傳輸到雲端
2. **最小可行**：第一版只實作三種觀察：未完成意圖、情緒傾向、重複模式
3. **不干擾**：觀察以輕量方式呈現（SnackBar），不打斷用戶流程

### 架構
```dart
class BridgeConsciousness {
  observeConversation(userMsg, aiReply) → List<Observation>
  generateInsight() → String?
  getUnreadObservations() → List<Observation>
}
```

## Consequences

### Positive
- 隱私安全（不離開裝置）
- 無網路延遲（即時反應）
- 零額外成本（不調用 AI API）

### Negative
- 分析能力有限（規則-based，無法理解深層語義）
- 無法跨裝置同步（觀察存在 localStorage）
- 可能產生誤報（規則太寬鬆）

## Future Work
- 未來可考慮「邊緣 AI」在本地跑小型模型做更精準的分析
- 跨裝置同步可透過 OpenClaw Gateway 的記憶系統實現

## Related
- CONTEXT.md: 「意識層」詞彙定義
