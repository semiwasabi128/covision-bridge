# Voice Realtime 架構檢討 — 對標 OpenAI Realtime 語音
> 2026-08-30 · 小葵 · 開源前檢討（Blue 發起）

## 為什麼寫這份

語音功能 2026-07-28 起分五個 Phase 疊加而成，當時不少決策是「先求有」。
08-30 連續挖出三個結構性 bug（寬畫面無入口、自動啟動斷、丟句根因），
都不是孤立失誤，而是架構債的症狀。開源前值得一次系統性重整。

## 現況地圖（真實接線，非理想圖）

```
麥克風 → speech_to_text(系統STT) → VoiceSpeechHandler ─┐
                                                        ├→ VoiceLiveController（VAD+時序）
                                                        │        ↓
                                                        │  VoiceEngine（狀態機+三層回應）
                                                        │        ↓ AgentLoop(LLM)
                                                        │        ↓ 最終回覆（整段）
Kokoro server(18900) ← ──────────── 整段一次合成 ← ──────┘
揚聲器 ← NativeAudioBytesPlayer ← 完整音檔
```

## 對標 OpenAI Realtime：哪些對、哪些是債

### 做對的（保留，不用改）

| 設計 | OpenAI 對應 | 為什麼對 |
|---|---|---|
| 委派架構：語音層只管聽說，推理丟 AgentLoop | Realtime 的 delegation pattern | GPT-Live 證明這條路正確；換 LLM 不動語音層 |
| 情緒由 LLM `<emotion>` 標籤驅動 | 無對應（我們多做） | 0 額外 token、文字接地、Kokoro 情緒向量直接吃 |
| 層 1 狀態語音「我來查查看…」 | 無對應（我們多做） | 填補思考延遲的產品級設計 |
| 雙模式按鈕（短按對話/長按聽寫） | 無對應（我們多做） | 兩種心智模型共存，Blue 定調 |

### 結構債（開源前該還的）

**債 1 — TTS 沒有串流：整段回覆一次合成**
`_handleAgentResult` 把整個回覆丟給 Kokoro 一次合成，完成才開始播。
`voice_streaming_tts.dart` 存在但只接了多模態協調器，主回應路徑沒用它。
200 字回覆 = 等整段合成（數秒）才聽到第一個字。
OpenAI 是邊生成邊出聲。**這是延遲體感最大的單一債。**
另：`_isSynthesizing` 旗標直接「丟棄」重疊請求而非排隊。

**債 2 — 回合判定散落三處，三個時鐘**
VAD 音量閾值+800ms（LiveController）、STT final 等待 1200ms（fallback timer）、
防重複抑制 3s（suppression window）——三個時鐘分屬不同物件，
08-30 的丟句 bug 正是「partialStream 推空字串」這種跨物件默契沒文件化。
OpenAI 的 server-side VAD + endpointing 是單一元件單一權威。

**債 3 — 全雙工是旗標拼裝，不是事件模型**
`_isAgentSpeaking`/`_isUserSpeaking`/`_waitingForFinalResult` 布林散在
LiveController，插嘴=旗標組合判斷。每加一種互動（如背景播報中插話）
都要再加旗標。OpenAI Realtime 是事件流（session events），
任何互動=發事件，不是改狀態。

**債 4 — 服務生命週期各自為政**
三個聊天介面各自 new KokoroTtsService/VoiceEngine；
VoiceEngine.stopConversation() 會停 Kokoro——若它自己是 spawn 者，
會把別的畫面正要重用的 server 殺掉（port-reuse 只擋了部分情況）。
App 級單例 + 引用計數才是正解。

**債 5 — STT 綁死系統套件**
`speech_to_text` 直依賴散在三個 handler。未來換 whisper.cpp
（本地、斷句更準）或 DGX 上的 Qwen3-Omni 要改三處。

## 目標架構（不改哲學，改結構）

```
┌─ RealtimeTurnController（唯一時鐘、事件流）──────────┐
│ 事件：userSpeechStart/End · turnEnd · bargeIn ·       │
│       ttsQueueFlush · agentReplyChunk                 │
│ VAD+endpointing+插嘴語義全在這一層，單一權威          │
└──────┬───────────────────────┬───────────────────────┘
       │ SpeechInAdapter       │ SpeechOutAdapter（介面）
       │  · SystemStt（現在）   │  · KokoroStreamingTts（現在，逐句）
       │  · WhisperCpp（之後）  │  · Qwen3-TTS 97ms（DGX 後）
       │  · Qwen3Omni（DGX 後） │
       └────────┬──────────────┘
                │ 不變
        AgentLoop + <emotion> 標籤 + 向量工作流
```

**逐句串流管線**（債 1 解法）：LLM 回覆 → 標點切句 → 第一句立刻進 Kokoro
→ 邊播邊合成後續句 → 插嘴=flush 佇列。
time-to-first-voice ≈ 首句生成 + ~300ms，體感接近即時。

**DGX Spark 之後的換引擎路徑**：Qwen3-Omni 進來時只是新增一個
SpeechAdapter 組合（S2S adapter 吃 audio 吐 audio），TurnController
和 AgentLoop 完全不動——這就是介面化的回報。

## 遷移路徑（三步，不重寫）

| 步 | 內容 | 風險 | 效果 |
|---|---|---|---|
| 1 | 抽 RealtimeTurnController：合併 LiveController+狀態機+三時鐘 | 中（行為等價重構）| 單一權威，後續改動有了地基 |
| 2 | 主回應路徑接逐句串流 TTS（切句+佇列+插嘴 flush） | 低（純增量）| **體感延遲砍最大一刀** |
| 3 | SpeechIn/OutAdapter 介面化 + Kokoro 服務 App 級單例 | 低 | 開源後社群可換引擎；DGX 接入零重寫 |

順序理由：2 依賴 1 的事件模型（flush 佇列要事件），3 最後做因為
純介面抽取不改行為。每步都有測試護欄（現有 24 個 voice 測試+新增）。

## 明確不做的

- 不追 speech-to-speech 單模型（Moshi 英文 only；Qwen3-Omni 等 DGX Spark，到貨先 spike 一週）
- 不做虛字答腔（07-28 已移除，勿回頭）
- 不動 AgentLoop / 情緒標籤 / 向量工作流——那是對的部分
