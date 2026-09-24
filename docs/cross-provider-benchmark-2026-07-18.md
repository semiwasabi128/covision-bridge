# 跨 Provider 基準測試報告（2026-07-18）

## 測試方法
- 同一個標準化 prompt（設計審查任務 + 工具清單 + `<<<tool_call>>>` 格式說明）
- 2 輪多步驟對話（T1 發起任務 → T2 給工具結果看是否繼續執行）
- 並行測試所有 provider
- 評分維度：T1 工具呼叫 / T2 工具呼叫 / T2 直接修復 / 速度

## 測試結果

| Provider | Model | T1工具 | T2工具 | T2直接修復 | 速度 | Tier |
|----------|-------|--------|--------|-----------|------|------|
| **OpenAI** | gpt-4o | ✅ | ✅ | ✅ | 最快 1-2s | 1 |
| **GLM** | glm-5 | ✅ | ✅ | ✅ | 中等 6-17s | 1 |
| OpenAI | gpt-5 | ✅ | ✅ | ❌（多繞一步） | 快 1-3s | 2 |
| Kimi | kimi-k3 | ✅ | ✅ | ❌（多繞一步） | 慢 7-13s | 2 |
| Kimi | kimi-k2.5 | ❌ | - | - | API 400 | 3 |
| GLM | glm-4.7 | ✅ | ❌ | - | 429 限流 | 3 |
| GLM | glm-4.5 | ✅ | ❌ | - | 超時 | 3 |

## 關鍵發現

1. **架構是 provider-agnostic 的 ✅**：所有成功的模型都能正確使用 `<<<tool_call>>>` 格式
2. **多步驟能力分三層**：Tier 1 直接修復 / Tier 2 多繞一步 / Tier 3 API 不穩
3. **意外發現：glm-5 表現跟 gpt-4o 一樣好**——國內 provider，台灣使用者註冊方便

## API 相容性陷阱

- gpt-5：不支援 `temperature`，用 `max_completion_tokens` 代替 `max_tokens`
- kimi-k2.5：回 `reasoning_content` 而非 `content`
- GLM：端點 `/api/paas/v4`，模型 ID `glm-5/glm-4.7/glm-4.5`
- Kimi：`KIMI_API_KEY` 和 `MOONSHOT_API_KEY` 是不同的 key，`MOONSHOT_KEY` 才有效

## GPT-4o vs GPT-5.4 深度對比（task_018，相同測試任務）

| 維度 | GPT-4o | GPT-5.4 |
|------|--------|---------|
| 設計審查報告長度 | 385 字元 | 6842 字元 |
| 報告內容 | 籠統摘要，無行號 | 每項有行號+程式碼片段+分析 |
| 顏色修復 | 修 7 個停了，引入 2 個語法 bug | 修 24 個全對，零 bug |
| 間距修復 | 修 7 個停了 | 修了很多但未全修完，零 bug |
| 工具使用 | 有時描述計畫不執行 | 連續執行 grep+patch |
| 報告結構 | 無結構 | 精確列出改動+未修項+下一步建議 |

## 未來測試方向

使用者 期望：將來多測幾輪，數據跟分層方式會更客觀準確。
- 待測：GPT-5.5、GPT-5.4-pro、GPT-5.4-mini、MiniMax（需補 key）
- 測試場景可擴展：UX 按鈕測試、程式碼修復、多步驟推理
