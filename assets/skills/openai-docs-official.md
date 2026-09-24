---
name: openai-docs-official
description: OpenAI 官方文件指引——API/模型選擇/遷移，官方文件優先不憑記憶
trigger_keywords:
  - openai
  - gpt
  - chatgpt api
trigger_patterns:
  - "(openai|gpt).*(api|sdk|整合|呼叫|串接)"
priority: high
version: 1
source: https://github.com/openai/skills/tree/main/skills/.system/openai-docs
synced: 2026-08-30
---

# OpenAI 官方文件指引（蒸餾版）

## 鐵則
- **官方文件優先**：developers.openai.com 是唯一權威來源； fallback 瀏覽也只限 OpenAI 官方網域
- **不憑記憶寫 API 呼叫**——模型名、參數、endpoint 查最新文件
- 模型選擇：依最新模型清單選，不用訓練資料裡的舊名

## 核心模式
- Chat Completions / Responses API
- 串流、tool use、structured output
- 模型遷移：升級模型時查官方 migration 指引（prompt-upgrade guidance）

## 完整文件
https://github.com/openai/skills/tree/main/skills/.system/openai-docs
