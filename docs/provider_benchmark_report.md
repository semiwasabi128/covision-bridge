# 原生 Agent能力跨 Provider 基準測試報告

**測試日期**: 2026-07-18
**測試方法**: 同一個標準化 prompt，2 輪多步驟對話，並行測試
**測試場景**: 模擬原生 Agent收到「審查 hardcoded 顏色」任務

## 測試設計

### Turn 1（發起任務）
- 給原生 Agent一個設計審查任務 + 工具清單 + `<<<tool_call>>>` 格式說明
- 看模型是否正確發出第一個 `run_terminal` (grep) 工具呼叫

### Turn 2（收到工具結果後繼續執行）
- 喂給模型假的 grep 結果（2 行 hardcoded colors）
- 看模型是否：
  1. 正確分析問題
  2. 引用正確行號
  3. 發出 `patch_source_file` 修復呼叫

## 測試結果總表

| Provider | Model | 狀態 | T1 | T2 | 字數 | T1工具 | T2工具 | T2修復 |
|----------|-------|------|-----|-----|------|--------|--------|--------|
| openai_gpt5 | gpt-5-2025-08-07 | ✅ | 1.8s | 3.3s | 289 | ✅ | ✅ | ❌ |
| openai_gpt4o | gpt-4o-2024-08-06 | ✅ | 1.3s | 2.4s | 1107 | ✅ | ✅ | ✅ |
| kimi_k25 | kimi-k2.5 | ❌ | - | - | - | - | - | - |
| kimi_k3 | kimi-k3 | ✅ | 7.5s | 13.1s | 558 | ✅ | ✅ | ❌ |
| glm_5 | glm-5 | ✅ | 6.1s | 17.3s | 1197 | ✅ | ✅ | ✅ |
| glm_47 | glm-4.7 | ❌ | - | - | - | ✅ | - | - |
| glm_45 | glm-4.5 | ❌ | - | - | - | ✅ | - | - |

## 各模型表現分析

### 🥇 Tier 1：完整多步驟工具使用（T2修復 ✅）

#### gpt-4o（OpenAI）
- **T1**: 1.3s ✅ 立即發出 grep 工具呼叫
- **T2**: 2.4s ✅ 正確分析 2 個問題，引用行號 709/894，發出 patch_source_file 修復
- **特色**: 最快、最精確、直接給出修復方案
- **字數**: 1107（分析詳盡）
- **修復品質**: 建議 `Colors.white → BridgeDS.foregroundPrimary`，`Colors.black87 → BridgeDS.backgroundSecondary`

#### glm-5（智譜 AI）
- **T1**: 6.1s ✅ 發出 grep 工具呼叫
- **T2**: 17.3s ✅ 正確分析問題，用表格列出，發出 patch_source_file 修復
- **特色**: 分析最詳細（1197 字），用 markdown 表格呈現問題清單
- **修復品質**: 建議 `Colors.white → BridgeDS.textPrimary`，`Colors.black87 → BridgeDS.backgroundDark`

### 🥈 Tier 2：能使用工具但不直接修復（T2修復 ❌）

#### gpt-5（OpenAI）
- **T1**: 1.8s ✅ 發出工具呼叫
- **T2**: 3.3s — 沒有直接分析+修復，反而又發了一個 grep 去找 BridgeDS 類別定義
- **特色**: 比較謹慎，想先確認 BridgeDS 有哪些 token 再修復
- **問題**: 回覆字數只有 289，過度簡潔；不直接修復而是多做一步確認
- **注意**: gpt-5 不支援 `temperature` 參數，只支援 `max_completion_tokens`，API 相容性需注意

#### kimi-k3（Moonshot）
- **T1**: 7.5s ✅ 發出工具呼叫
- **T2**: 13.1s — 沒有直接修復，反而發了 2 個 grep 去找 BridgeDS 類別定義和現有用法
- **特色**: 最謹慎——想先確認 BridgeDS 有哪些可用 token 再修復
- **問題**: 不直接給修復方案，多繞一步；字數 558

### ❌ Tier 3：測試失敗

#### kimi-k2.5
- **T1**: HTTP 400 Bad Request
- **原因**: 可能需要特殊參數或模型已棄用
- **注意**: kimi-k2.5 會回 `reasoning_content`（隱藏推理），API 整合需特殊處理

#### glm-4.7
- **T2**: HTTP 429 Too Many Requests
- **原因**: 速率限制

#### glm-4.5
- **T2**: 讀取超時（123.7s）
- **原因**: 模型回應過慢或當機

## 關鍵發現

### 1. 架構是 provider-agnostic 的 ✅
所有成功的模型都能正確使用 `<<<tool_call>>>` 格式——這證明 prompt-based tool calling 設計正確，不依賴任何 provider 的 native function calling。

### 2. 多步驟工具使用能力差異巨大
- **Tier 1**（gpt-4o, glm-5）：收到工具結果後直接分析+修復
- **Tier 2**（gpt-5, kimi-k3）：收到工具結果後多繞一步確認，不直接修復
- 這個差異在單步測試看不出來，只有多步驟測試才顯現

### 3. 速度差異
- OpenAI 最快（1-3s）
- Kimi 中等（7-13s）
- GLM 較慢（6-17s）

### 4. API 相容性陷阱
- **gpt-5**: 不支援 `temperature`，要用 `max_completion_tokens` 代替 `max_tokens`
- **kimi-k2.5**: 回 `reasoning_content` 欄位，`content` 可能為空
- **GLM**: 端點是 `/api/paas/v4`，不是 `/v1`

## 傳承資產包建議

### 分層方案

| 層級 | 模型 | 適配策略 |
|------|------|---------|
| **Tier 1** | gpt-4o, glm-5 | 可直接派多步驟批量任務（修 20+ 項） |
| **Tier 2** | gpt-5, kimi-k3 | 拆成更小任務（一次 5-7 項），允許多繞一步確認 |
| **Tier 3** | kimi-k2.5, glm-4.5 | 只派單一明確任務，不期待多步驟連續執行 |

### 動態參數適配
```
if provider == 'openai' and model.startswith('gpt-5'):
    params = {'max_completion_tokens': 2000}  # 不用 max_tokens, temperature
elif provider == 'kimi' and 'k2.5' in model:
    # 處理 reasoning_content
    content = msg.get('content') or msg.get('reasoning_content')
else:
    params = {'max_tokens': 2000, 'temperature': 0.3}
```

### 任務拆分策略
- Tier 1 模型：可一次派 20+ 項修復
- Tier 2 模型：一次 5-7 項，且 prompt 要明確說「直接修復，不要先確認」
- Tier 3 模型：一次 1 項，每項獨立任務
