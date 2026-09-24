---
name: gemini-api-official
description: Google Gemini API 官方權威指引——unified SDK、Live Realtime、legacy SDK 淘汰警告
trigger_keywords:
  - gemini
  - google api
  - gemini api
trigger_patterns:
  - "(gemini|google).*(api|sdk|整合|呼叫|串接)"
priority: high
version: 1
source: https://github.com/google/skills/tree/main/skills/cloud/gemini-api
synced: 2026-09-20
---

# Gemini API 官方指引（蒸餾版）

## 鐵則
- **用 unified SDK**：Python `google-genai` / JS-TS `@google/genai` / Go `google.golang.org/genai` / Java `com.google.genai` / C# `Google.GenAI`
- **Legacy SDK 已淘汰，不要用**：`google-cloud-aiplatform`、`@google-cloud/vertexai`、`google-generativeai` 全部 deprecated

## 核心能力
- Text / multimodal（文字+影像+音訊混合輸入）
- Function calling（tool use）
- Structured output（JSON schema 約束）
- Context caching（長 context 節費）
- Embeddings
- **Live Realtime API**：雙向 streaming（語音對話場景首選）
- Batch Prediction（離線大量處理）

## 完整文件
https://github.com/google/skills/tree/main/skills/cloud/gemini-api
同系列：gemini-live-api / gemini-agents-api / gemini-interactions-api
