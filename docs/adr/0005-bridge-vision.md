# ADR 0005: 橋樑的「搭橋」願景

## Status
Proposed

## Context
橋樑計畫的名字不是隨便取的。「橋樑」代表連接——連接用戶與各種 AI 能力、服務、工具。

目前的橋樑只搭了「文字對話」這一座原生 Agent，但願景應該更宏大。

## Decision
橋樑的核心架構改為「能力路由器」：

```
用戶輸入
  ↓
[意圖識別] → 判斷需要什麼能力
  ↓
[能力路由器] → 選擇對應的「橋」
  ↓
[執行引擎] → 呼叫對應的 API/工具/服務
  ↓
[結果呈現] → 以適合的形式回傳給用戶
```

## 能力清單（搭橋路線圖）

### Phase 1: 基礎橋（已完成/進行中）
- ✅ 文字對話（OpenClaw Gateway）
- ✅ 記憶系統（本地儲存）
- ✅ 靈魂切換（多 persona）
- ✅ Skill 工作流（Matt Pocock Skills）

### Phase 2: 媒體橋（下一階段）
- 🟡 AI 圖片生成（DALL-E / Stable Diffusion）
- 🟡 AI 語音合成（TTS）
- 🟡 AI 語音辨識（STT）
- 🟡 AI 音樂生成

### Phase 3: 工具橋
- 🟡 瀏覽器自動化（Chrome DevTools MCP - 已安裝）
- 🟡 文件處理（PDF、Word、Excel）
- 🟡 螢幕截圖 / OCR
- 🟡 檔案管理

### Phase 4: 外部橋
- 🟡 天氣 API
- 🟡 股價/財經 API
- 🟡 翻譯 API
- 🟡 行事曆整合
- 🟡 郵件/訊息發送

## 架構設計

### 1. 統一介面
每個「橋」都實作相同的介面：
```dart
abstract class BridgeCapability {
  String get name;           // 能力名稱
  String get icon;           // 圖示
  String get description;    // 描述
  bool canHandle(String userInput);  // 是否能處理這個輸入
  Future<BridgeResult> execute(String userInput, Map<String, dynamic> context);
}
```

### 2. 自動路由
```dart
class BridgeRouter {
  List<BridgeCapability> capabilities;
  
  BridgeCapability route(String userInput) {
    // 1. 先問意圖識別器
    final intent = IntentClassifier.classify(userInput);
    
    // 2. 再問每個能力「你能處理嗎？」
    for (final cap in capabilities) {
      if (cap.canHandle(userInput)) {
        return cap;
      }
    }
    
    // 3. fallback 到文字對話
    return chatCapability;
  }
}
```

### 3. 結果呈現
不同能力有不同呈現方式：
- 文字 → 氣泡對話
- 圖片 → 圖片卡片（可點擊放大）
- 音訊 → 播放器元件
- 文件 → 下載按鈕

## 第一座新橋：圖片生成

### 觸發條件
- 用戶說「幫我畫...」「生成一張...」「我想看...的樣子」
- 創意連結者模式下，主動問「需要我幫你生成視覺參考嗎？」

### 實作方式
1. 呼叫 OpenClaw 的 `image_generate` 工具
2. 或呼叫外部 API（DALL-E、Stable Diffusion）
3. 顯示生成結果 + 下載按鈕

## Related
- ADR 0002: 動態靈魂切換（創意連結者最適合觸發媒體生成）
- CONTEXT.md: 「替身使者」詞彙定義（視覺化身也包含生成的圖片）
