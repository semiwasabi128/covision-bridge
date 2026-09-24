# ADR 0004: 整合 Matt Pocock Skills 工作流

## Status
Proposed → Accepted (2026-05-27)

## Context
橋樑需要從「聊天 App」進化為「自帶工程思維的 AI 夥伴」。Matt Pocock 的 skills.sh 提供了一套經過驗證的工作流：/grill-me、/grill-with-docs、/to-prd、/to-issues、/tdd、/diagnose。

## Decision
將 Matt Pocock Skills 的核心工作流整合進橋樑，讓教練 Agent具備「結構化思考」的能力。

### 整合方式
不是直接複製技能文件，而是：
1. **提取核心模式**：每個 skill 的「觸發條件 → 執行步驟 → 完成標準」
2. **融入 persona**：把 skill 的思考方式融入對應的靈魂個性
3. **提供主動入口**：在 UI 上提供「/grill-me」「/to-prd」等快捷觸發

### Skill → Persona 對應
| Skill | 對應 Persona | 使用場景 |
|-------|-------------|---------|
| /grill-me | 預設夥伴 | 用戶提出模糊需求時 |
| /grill-with-docs | 嚴格紀錄者 | 建立專案詞彙和決策 |
| /to-prd | 嚴格紀錄者 | 對話結束後產出規格 |
| /to-issues | 嚴格紀錄者 | PRD 產出後拆解任務 |
| /tdd | 挑戰質疑者 | 開發時的測試驅動 |
| /diagnose | 挑戰質疑者 | 遇到 bug 時的系統化排查 |
| /prototype | 創意連結者 | 快速驗證想法 |
| /zoom-out | 預設夥伴 | 跳出細節看全局 |

## Consequences

### Positive
- 用戶獲得經過驗證的工程思維框架
- 對話從「閒聊」進化為「結構化協作」
- 產出物（PRD、Issue 列表）可直接進入開發流程

### Negative
- System prompt 變長（每個 persona 需要包含對應 skill 的思維模式）
- 用戶需要學習新詞彙（CONTEXT.md）
- 過度結構化可能讓閒聊變僵硬

## Mitigations
- Skill 觸發是「主動」不是「強制」——用戶可以選擇不用
- 閒聊模式（預設夥伴）保持輕鬆，只在用戶明確需求時切換
- 提供「/help」讓用戶快速了解有哪些 skill 可用

## Related
- CONTEXT.md: 「Skill」詞彙定義
- ADR 0002: 動態靈魂切換（skill 觸發是靈魂切換的延伸）
