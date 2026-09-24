# ADR 0001: 橋樑 MVP 使用 Flutter

## Status
Accepted

## Context
橋樑計畫需要同時支援 iOS 和 Android，並且需要快速開發 MVP 驗證概念。

## Decision
使用 Flutter 作為橋樑 MVP 的技術棧。

## Consequences

### Positive
- 一套程式碼同時覆蓋 iOS/Android
- OpenClaw 的 Node SDK 邏輯可以跨平台共用
- 熱重載加速開發迭代
- 豐富的 UI 元件庫

### Negative
- 原生功能（Apple Intelligence、Android Gemini Nano）需要平台通道
- 最終可能需要遷移到原生以獲得最佳性能
- Web 版本的 accessibility tree 不完整（影響自動化測試）

## Alternatives Considered
- **原生雙軌（Swift + Kotlin）**：性能最好，但開發速度最慢
- **React Native**：生態成熟，但橋接原生較複雜
- **純 Web（PWA）**：最輕量，但無法使用原生功能

## Related
- ADR 0002: 動態靈魂切換
- CONTEXT.md: 「大腦容器」詞彙定義
