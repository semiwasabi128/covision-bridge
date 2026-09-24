# Bridge Adapter Contract v0

Bridge adapter 是正式橋能力的最小執行單位。社群插件可以用同一份合約接入新的 AI 服務，而不需要改動聊天 UI、思維儀表或第二大腦資料結構。

## 目標

- 讓能力目錄知道「這座橋能做什麼、缺什麼、由誰執行」。
- 讓聊天任務能從使用者自然語言路由到 adapter。
- 讓 adapter 回傳一致的 `BridgeActionResult`，供證據卡、任務回流與思維儀表讀取。
- 讓開源社群可以分享 provider adapter、桌面插件或能力卡。

## Dart Adapter 介面

所有直接執行的 provider adapter 需要實作：

```dart
abstract class BridgeActionAdapter {
  String get id;
  String get displayName;
  Set<BridgeActionType> get supportedTypes;
  bool canHandle(BridgeAction action, String provider);
  Future<BridgeActionResult> execute(BridgeAction action);
}
```

基本要求：

- `id` 必須穩定，例如 `openai`、`replicate`、`local_document`。
- `supportedTypes` 必須宣告支援的橋，例如 `browse`、`vision`、`generateImage`。
- `execute` 必須回傳 `BridgeActionResult`，不要直接操作 UI。
- 若缺 API key 或桌面權限，回傳 `BridgeActionStatus.needsProvider`。
- 若成功產出媒體，使用 `mediaUrl` 或本地保存路徑。

## Metadata 標準

每個 adapter 至少要回傳：

```json
{
  "type": "browse | vision | generate_image | document",
  "kind": "web_search | vision | image | document | capability_gap",
  "provider": "provider-id",
  "adapter": "Human readable adapter name"
}
```

不同能力需要補充：

- Search：`query`、`searchSources`、`sourceCount`、`fetchedAt`、`timeSensitive`
- Vision：`imageCount`、`model`
- Image：`model`、`quality`、`mode`、`storage`
- Document：`path`、`generationMode`
- Capability gap：`setupRoute`、`requestedProvider`

這些欄位會被：

- 聊天證據卡顯示
- 思維儀表讀取
- 待回流任務保存
- 第二大腦 Bridges 房間索引

## 能力目錄欄位

每座橋要有一張 `CapabilityDefinition`：

- `id`：能力卡 ID
- `name`：使用者看到的名稱
- `kind`：能力分類
- `actionType`：對應 `BridgeActionType`
- `triggerPhrases`：自然語言觸發線索
- `providers`：可選 provider 名稱
- `v0Scope`：目前做到哪裡
- `adapterContract`：社群 adapter 要遵守什麼
- `communityPluginNote`：社群可如何共享與擴充
- `evidenceKind`：成功後的證據格式
- `setupSteps`：缺能力時怎麼引導使用者

## 社群插件建議

插件應提供：

- 能力卡 JSON 或 Dart 註冊程式
- Adapter 實作或桌面插件連接器
- 權利與成本說明
- 支援的輸入/輸出格式
- 測試用 fixture，不需要真實 API key
- 失敗時的 `needsProvider` 引導

插件不應：

- 繞過使用者 API key 或授權
- 在未確認下操作本機檔案
- 回傳沒有來源或權利說明的商用素材
- 把 provider token 寫進分享包

## 目前內建與預留

- 已內建：OpenAI Web Search、OpenAI Vision、OpenAI Images、Replicate Image、Local Markdown Document
- 預留：Music、Video、Animation、Desktop File Operations、Custom Bridge
- 下一步：把每個預留橋接成獨立 adapter package，讓 SemiDAO 社群可以分享與評分。
