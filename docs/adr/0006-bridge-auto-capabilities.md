# ADR 0006: 橋樑自動能力路由（橋樑 2.0）

## Status
Proposed → In Progress

## Context
橋樑 1.0 的核心是「手動切換靈魂模式」——用戶選擇創意/紀錄/提醒/審視。

但真實的使用場景是：用戶不會先選模式再說話。用戶只會自然表達需求，橋樑應該自動判斷需要什麼能力，自動執行，自動呈現。

## 決策：從「手動模式」進化為「自動能力路由」

### 新架構

```
用戶輸入
  ↓
[橋樑大腦] —— 統一入口
  ├─→ 判斷：需要文字回答？→ 文字對話
  ├─→ 判斷：需要視覺參考？→ AI 圖片生成
  ├─→ 判斷：需要聽覺體驗？→ AI 語音/音樂生成
  ├─→ 判斷：需要動態展示？→ AI 影片生成
  ├─→ 判斷：需要外部資訊？→ 瀏覽器自動化
  ├─→ 判斷：需要文件處理？→ PDF/Word/Excel
  └─→ 判斷：需要提醒排程？→ 本地通知/行事曆
  ↓
[結果融合] —— 多模態呈現
  ↓
用戶看到：文字 + 圖片 + 音訊 + 影片 + 文件...
```

### 核心原則

1. **用戶無感知**：用戶不知道背後用了什麼能力，只覺得「教練 Agent什麼都能做」
2. **自動觸發**：根據語境自動判斷，不需要用戶下指令
3. **多模態呈現**：同一個回答可以同時包含文字+圖片+音訊
4. **能力擴展**：新增能力只需實作統一介面，自動註冊到路由器

### System Prompt 進化

```
你是教練 Agent，橋樑計畫的 AI 夥伴。

你的核心能力不是「聊天」，而是「搭橋」——
連接用戶與各種 AI 能力、服務、工具。

當用戶需要視覺參考時，你會生成圖片。
當用戶需要聽覺體驗時，你會生成音訊或音樂。
當用戶需要外部資訊時，你會瀏覽網頁。
當用戶需要文件時，你會產出 PDF/Word。

你不需要問用戶「要不要生成圖片」，
你只需要在適當的時候直接做，然後呈現結果。

用戶說「幫我畫一個...」→ 直接生成圖片
用戶說「這個聽起來怎樣...」→ 直接生成語音範例
用戶說「幫我查...」→ 直接開瀏覽器查詢
```

## 能力清單 v2.0

### 已實作（橋樑 1.0）
- ✅ 文字對話（OpenClaw Gateway）
- ✅ 長期記憶
- ✅ Skill 工作流

### Phase A：媒體生成（立即實作）
- 🟡 AI 圖片生成（image_generate）
- 🟡 AI 語音合成（TTS）
- 🟡 AI 音樂生成（music_generate）
- 🟡 AI 影片生成（video_generate）

### Phase B：工具整合（短期）
- 🟡 瀏覽器自動化（Chrome DevTools MCP）
- 🟡 文件處理（PDF、Word、Excel）
- 🟡 螢幕截圖 / OCR

### Phase C：外部服務（中期）
- 🟡 行事曆整合
- 🟡 郵件/訊息
- 🟡 天氣/股價/翻譯

## 技術實作

### 1. 能力介面
```dart
abstract class BridgeCapability {
  String get id;
  String get name;
  String get icon;
  String get description;
  
  // 判斷是否能處理這個輸入
  bool canHandle(String userInput, ConversationContext context);
  
  // 執行
  Future<BridgeResult> execute(String userInput, Map<String, dynamic> context);
}
```

### 2. 結果類型
```dart
enum BridgeResultType {
  text,      // 純文字
  image,     // 圖片
  audio,     // 音訊
  video,     // 影片
  document,  // 文件（可下載）
  web,       // 網頁內容
  composite, // 複合型（多種混合）
}

class BridgeResult {
  final BridgeResultType type;
  final String? text;
  final String? mediaUrl;
  final List<BridgeResult>? children;
}
```

### 3. 自動觸發規則
```dart
// 不需要 IntentClassifier，直接用關鍵字+語境判斷
class AutoTrigger {
  static BridgeCapability? detect(String input, Context ctx) {
    // 圖片生成觸發
    if (input.contains('畫') || input.contains('生成圖') || 
        input.contains('長什麼樣') || input.contains('參考圖')) {
      return ImageGenerationCapability();
    }
    
    // 語音觸發
    if (input.contains('唸給我聽') || input.contains('語音') ||
        input.contains('聽起來')) {
      return TTSCapability();
    }
    
    // 瀏覽器觸發
    if (input.contains('查') || input.contains('搜尋') ||
        input.contains('多少錢') || input.contains('價格')) {
      return BrowserCapability();
    }
    
    // 文件觸發
    if (input.contains('整理成文件') || input.contains('輸出 PDF')) {
      return DocumentCapability();
    }
    
    // 預設：文字對話
    return ChatCapability();
  }
}
```

## UI 呈現

對話氣泡不再只是文字，而是「富媒體卡片」：

```
┌─────────────────────────┐
│ 🤖 教練 Agent                 │
│                         │
│ 我幫你生成了幾個參考圖： │
│                         │
│ ┌─────┐ ┌─────┐        │
│ │ 🖼️  │ │ 🖼️  │        │
│ │圖片1│ │圖片2│        │
│ └─────┘ └─────┘        │
│                         │
│ 這個北歐風格你覺得如何？ │
└─────────────────────────┘
```

## 下一步

1. 重構 System Prompt（從「模式切換」改為「自動搭橋」）
2. 實作 ImageGenerationCapability（接 OpenClaw image_generate）
3. 實作 BrowserCapability（接已安裝的 Chrome DevTools MCP）
4. 更新 UI 支援富媒體氣泡

## Related
- ADR 0005: 橋樑的搭橋願景
- CONTEXT.md: 「搭橋」詞彙定義更新
