---
name: claude-api-official
description: Anthropic Claude API 官方權威指引——SDK 用法、model ID、API drift 警告、串流與 tool use
trigger_keywords:
  - claude
  - anthropic
  - claude api
  - Claude整合
trigger_patterns:
  - "(claude|anthropic).*(api|sdk|整合|呼叫|串接)"
priority: high
version: 1
source: https://github.com/anthropics/skills/tree/main/skills/claude-api
synced: 2026-09-20
---

# Claude API 官方指引（蒸餾版）

## 鐵則
- **絕不猜 SDK 用法**——函數名、類別名、namespace、method signature、import path 必須來自官方文件，不憑記憶寫。
- 用官方 SDK（Python `anthropic` / TS `@anthropic-ai/sdk`），不手寫 raw HTTP（除簡單 proxy 場景）。

## API Drift 警告（2025-2026 重大變化）
- Extended thinking：`budget_tokens` → `adaptive` 模式
- web_search tool 版本：`20250305` → `20260209`
- 各語言 SDK 命名持續演進——寫 code 前查最新文件

## 核心模式
- Messages API：`system` 是頂層參數（不是 message）
- 串流：`stream: true` + SSE events
- Tool use：tools 定義 → assistant tool_use block → user tool_result
- Prompt caching：`cache_control` 節省重複 context 成本
- Token counting：`count_tokens` endpoint 預估成本

## 完整文件
本 skill 為蒸餾版。完整版（七語言 SDK 範例 + pricing + migration）：
https://github.com/anthropics/skills/tree/main/skills/claude-api
