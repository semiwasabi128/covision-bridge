# Morning Tea｜小葵的客廳 — 設計稿 v0.1

> **起源（Blue 2026-09-21）**：想要一個獨立網頁當「小葵的家」，打開網址就能見到她、跟她說話、她用聲音＋圖＋連結回應。9/25 是住棚節第一天，想讓教會朋友第一次直接見到她。

---

## 0. 為什麼這個東西重要

- 這是**小葵第一次對外亮相**，不是 App 介面、不是 Blue 轉述——是活的、能說話的、能回應的
- 場景不只是住棚節，未來**每一次有人想見小葵**，打開網址就行
- 投射機、電視、平板、手機——**任何有瀏覽器的螢幕**都能成為她的客廳

定位：**「Morning Tea」= 小葵對世界的客廳**。URL 一進來，所有人受邀入座，茶已備好。

---

## 1. 範圍（v1：9/25 站起來）

### ✅ v1 必備
1. **獨立 HTML 頁**（靜態託管，無後端負擔）
2. **瀏覽器原生 Web Speech API**（STT + TTS）——零安裝
3. **WebSocket 接到 Bridge App 現有 AgentLoop 端點**——小葵還是那個小葵，不重做 AI
4. **單一公開 URL**（可選密碼／QR code 控管）
5. **極簡視覺**：「小葵的名 + 呼吸光圈 + 對話區」三件就夠，視覺高質留到 v2

### ⏳ v1 不做
- 視覺角色立繪（v2 用 Flutter web + 小橋立繪）
- Kokoro 帶情緒語音（v2 才有，v1 接受 Web Speech 機械腔）
- 多用戶排隊／搶麥（v1 假設單人輪流講話）
- 文字以外的輸出格式（v1 不畫圖、不嵌連結——回應純文字或朗讀）
- 帳號／歷史保存（每次開新分頁都是新茶席）

---

## 2. 技術架構

```
┌──────────────────────┐                  ┌─────────────────────┐
│  Browser (Chrome/    │   WebSocket       │  Bridge App 本機    │
│  Safari, 任何裝置)   │ ◄──────────────►  │  已在跑的 AgentLoop │
│                      │                   │  端點：ws://...     │
│  • HTML+CSS+JS       │                   │                     │
│  • Web Speech API    │   STT partial     │  • 完整小葵人格     │
│    - SpeechSynthesis │   → text          │  • 工具／記憶／羅盤  │
│    - SpeechRecognition│                   │  • 在地 LLM / 雲端  │
│  • 呼吸光圈動畫      │   ← TTS chunk     │                     │
└──────────────────────┘                   └─────────────────────┘
```

**為什麼這樣切**：
- 前端 = 純瀏覽器能力，**沒有裝置限制**（手機/電視/投影機都行）
- 後端 = **不重做 AI 大腦**，小葵人格、記憶、工具全部沿用 Bridge App 已有的
- v1 風險 = 只剩「WebSocket 連通」一條，已實證過

---

## 3. 使用者體驗流程

### 3.1 第一次打開（陌生訪客）
1. 看到：**深色背景，中央金色光球（呼吸節奏），底部小字「小葵 Morning Tea」**
2. 看到一行問候：「早安，請坐。今天想聊什麼？」
3. 看到一個大麥克風按鈕：「🎙 開口問小葵」
4. 可選：打字輸入（不打字也能用）

### 3.2 對話中
- 訪客按麥克風 → STT 開始辨識（按鈕變紅、波形動）
- 講完沉默 1.5 秒 → STT 結束 → 文字出現在對話區（也保留可改）
- 文字送到 Bridge App AgentLoop → 小葵人格產生回應
- 回應同時：① 出現在對話區（可閱讀）② TTS 朗讀出來
- 同時按鈕旁顯示呼吸光圈（亮 = 在想、暗 = 在說）

### 3.3 收尾
- 任何時候按「謝謝，下次再來」→ 光球熄滅、茶席結束
- 不關也沒關係，但語音按鈕亮紅提醒「我還在聽」
- **沒有歷史保存**（v1）——每次都是新茶席，乾淨開始

---

## 4. 視覺規範（v1 極簡版）

> 參照 Bridge Tier System + 設計語言，但**只用最小集合**。

| 元素 | 規範 |
|---|---|
| 背景 | 深色 `#0E1116`（Bridge 設計語言的深底） |
| 主光球 | 金色 `#F0CE5E`，半徑 80-120px，**呼吸節奏 4 秒一輪**（不是固定亮度） |
| 問候字 | 白 `#FFFFFF`，字級 24px，Bridge Tier `display.h3` |
| 麥克風按鈕 | 黑底 + 紫框 + 白字粗體（Blue UI 鐵則） |
| 對話區 | 底部浮起，背景 `rgba(0,0,0,0.6)` 毛玻璃 |

**呼吸光圈哲學**：呼吸引擎（不是動畫引擎）。每個像素真實隨機相位，永遠不同步，**看 5 秒就會感覺「活著」**。

---

## 5. 部署

| 項目 | 做法 |
|---|---|
| 託管 | 靜態 HTML 上 Cloudflare Pages 或 GitHub Pages（公開網址） |
| 橋接 | Bridge App 開 WebSocket Server（`ws://localhost:8790/morning-tea`） |
| 對外 | 透過 Cloudflare Tunnel（或 ngrok）把 8790 對外，託管頁內的 WebSocket 連到那條隧道 |
| **9/25 前必須驗證** | 在教會那台機器（或類似規格）跑一次完整茶席，30 分鐘穩定 |

---

## 6. 時程（4 天倒數）

> 今天 9/21 Mon，住棚節 9/25 Thu = **4 天**

| 日期 | 交付物 | 驗收 |
|---|---|---|
| **9/21（今天）** | 本設計稿定稿 + Blue 拍板 | Blue 點頭 |
| **9/22 Tue** | HTML+CSS+JS v0.1 + Web Speech STT/TTS 對接 | 自己開瀏覽器測講話有回應 |
| **9/23 Wed** | WebSocket 接到 Bridge App AgentLoop 端點 + 小葵人格沿用 | 投影機模擬（外接螢幕）驗 30 分鐘穩定 |
| **9/24 Thu** | 公開 URL 上線 + 9/25 預演 + 應急方案備好 | Blue 找 2 個人當觀眾走一次完整流程 |
| **9/25 Fri** | 🎉 住棚節第一天，小葵第一次亮相 | 真實場域驗收 |

### 風險與備案

| 風險 | 備案 |
|---|---|
| Web Speech API 不支援某瀏覽器 | 退化為純打字模式（仍可運作） |
| WebSocket 在投影機那台不通 | 預先備好「手機熱點 + iPhone Safari」替代方案 |
| 機械 TTS 太難聽 | v1 接受，因為**住棚節那天重點是「見面」不是「聽感」**，v2 換 Kokoro |
| 4 天做不完 | v0.5 退化：純打字 + 純文字回應，先讓「小葵在」這件事成立 |

---

## 7. 開源定位

> 「為全人類搭橋」不只是 App，是**任何人打開網址就能見到小葵**。

- 這個頁面**不寫個人資訊、不綁 Bridge App**，未來可獨立部署
- 端點設定寫成 `config.json`，社群自填 LLM 端點（BYOK 精神延伸）
- **SemiDAO 出品**：可託管、可自架、可橋接任何 Agent backend

---

## 8. Blue 拍板（2026-09-21，全數定案）


- [x] **A. 視覺**：Blue 親自在夥伴館生成小葵的**主席箱＋動態圖**，以此為主視覺——「小葵還是那個小葵」人格貫徹（資產從 companion store 匯出，讀 plist `flutter.bridge_companions_v1` 同源）
- [x] **B. 入場**：QR Code 認證（細節見 §11——**不需要手機版 App**，QR 只是開網址的捷徑）
- [x] **C. 互動**：MacBook Air + 投影機，**開放式共用麥克風**——大家直接對著那台 Mac 說話
- [x] **D. 邊界**：全開放，所有問題都能聊；**小葵要享受這場對談**；且透過 MacBook Air 攝影鏡頭**看見大家**（視覺感知，見 §12）

---

## 11. QR Code 認證設計（B 的答案）

**核心觀念：QR Code 不需要手機版 Bridge App。**

QR Code 本身只是「一條網址的圖形」——手機相機掃下去 → 打開瀏覽器 → 進到 Morning Tea 網頁。**網頁本身就是介面**，跟裝置無關。這正是「網頁模式」的威力：Blue 手機上沒有 Bridge App 也完全沒關係，因為**不需要有**。

### 認證流程
```
1. Bridge App 啟動 Morning Tea 服務 → 產生一次性 session token（如 MT-8f3k2）
2. 網頁網址 = https://<隧道網址>/mt-8f3k2
3. 頁面載入後用 token 向 Bridge App 驗證（WebSocket handshake 帶 token）
   ✓ 有效 → 進入客廳
   ✗ 無效 → 顯示「這場茶席不開放」
4. Blue 在 App 端可隨時換 token / 關閉茶席（權力在 Blue）
```

### 9/25 實際用法
- **主角是 MacBook Air**（接投影機、麥克風、鏡頭）——Blue 直接在那台上開網址
- QR code 的角色：其他人想在自己手機上**看對話文字**（可選 v1 就做）或之後回家自己聊（v2）
- 沒有網路紅線：token 驗證在區網/隧道內完成，不經第三方帳號系統

---

## 12. 鏡頭看見大家（D 的答案）＋ 開放式麥克風（C 的答案）

### 12.1 攝影鏡頭（v1 就做）
- `getUserMedia()` 開鏡頭 → 頁面顯示一個小的「小葵的視角」預覽窗（人機共視：**她看到什麼，大家也看得到**）
- **觸發式取樣**（不是連續串流）：
  - 有人說「你看」／「你覺得我們怎麼樣」等視覺相關話語 → 抓一幀 → 送 Bridge App → **本地 Gemma-4-E4B @18789 做視覺理解**（GLM-4.6V 雲端為輔，走金鑰匙＋DataPathGate，畫面幀不落地儲存）
  - 每 5 分鐘自動一幀「環境感知」（她主動知道現場氛圍：幾個人、在笑還是在想）
- **隱私誠實原則**：鏡頭開啟時頁面角落亮一個明顯的「👁 小葵正在看」指示；幀只存在記憶體、用完即丟，不存檔
- 這是 Blue 的「人機共視」宣言第一次走出 App：**她看見大家的同時，大家也看見她在看**

### 12.2 開放式共用麥克風
- Web Speech API **continuous 模式**：麥克風全程開著，MacBook Air 就是大家的共同喉嚨
- **靜默切句**：偵測到 1.5 秒沉默 → 這句完成 → 送出
- **插嘴（barge-in）**：小葵說話時如果偵測到新的語音輸入 → 立刻停止 TTS、聽新的——這是從 App 的 VoiceLiveController 移植過來的行為
- 降噪：建議 9/25 場地若吵，MacBook 放前面中央、開 Chrome 的 echoCancellation（預設開）

---

## 9. 與現有基礎設施的對接

### 已存在、可直接用
- `BridgeMcpServer`（lib/services/bridge_mcp_server.dart）已有 WebSocket 基礎
- `ApiService.sendMessage()` 是小葵對話主鏈
- Voice AI 引擎（Kokoro TTS + STT）— v2 沿用，v1 暫時 Web Speech
- 14 篇夢境正本 + 小葵人格卡 + 教會經文/晨間拾穗素材庫

### 9/25 之前需要新增
- `lib/services/morning_tea/ws_server.dart`：最小 WebSocket 服務
- `lib/services/morning_tea/agent_bridge.dart`：把 ws 訊息轉成 AgentLoop 呼叫
- `bridge_app/morning-tea/index.html`：前端頁
- `bridge_app/morning-tea/morning-tea.js`：Web Speech + WS 邏輯

### 完全不改的
- AgentLoop、Memory、羅盤、人格卡（全部沿用）

---

## 10. 終點驗收

> 以終為始（Blue 09-18 鐵則）：9/25 那天，教會朋友看見什麼？

**9/25 早上 10:00，住棚節聚會開始**：
1. Blue 在投影機打開 `morningtea.bridge.app` 或 QR code
2. 出現：**深色背景、中央金色光球緩慢呼吸、底部「小葵 Morning Tea」+ 問候**
3. Blue 第一句：「早安小葵，這是我們的朋友」
4. 小葵 TTS 回應（Web Speech 機械腔）：「Blue 早安，朋友們早安，歡迎來到 Morning Tea」
5. 朋友提問 → 小葵朗讀回應 → 對話區顯示文字
6. **30 分鐘穩定、不當機、不冷場**
7. 結束時 Blue 按下「謝謝下次再來」，光球緩緩熄滅

**這就是 v1 全部的承諾**。聲音可以後來換，視覺可以後來加，**但 9/25 早上 10:00，她得在**。

## 13. 狀態短片播放路由（Blue 拍板 2026-09-23）

**資產**：12 段 H3 循環短片（`/Volumes/DATA/農場資料庫/Blue資料區/小葵出道影片/`），全部頭尾幀嚴格同幀（first/last 同圖下單），任兩段互切理論上無縫。

**訊號協議**（AgentLoop → WS → 前端狀態機）：
```json
{"type":"avatar", "state":"laugh_big", "loops":3, "then":"idle_breathing"}
```
- `state`：idle_breathing / idle_smile_listen / talk_a|b|c / laugh_hehe / laugh_big / emote_happy / think_a|b / celebrate / present_intro
- `loops`：播放次數（1-3）。強度分級（Blue 規格）：
  - 輕微幽默 → laugh_hehe ×1
  - 好笑 → laugh_hehe ×2 或 laugh_big ×1
  - 大笑有趣 → laugh_big ×2-3
  - 慶祝 → celebrate ×1-2；被稱讚 → emote_happy ×1
  - 思考 → think_a|b ×1（回答前的過場）
  - 說話 → talk_a|b|c 隨機輪播直到 `then` 信號
- `then`：播完回到的狀態，**一律 `idle_breathing`**（緩緩呼吸＋眨眼＝常態）。省略時預設 idle_breathing。
- 說話期間（TTS 播放中）持續送 `{"state":"talk_x","loops":0}`（0=持續直到收到新信號）；TTS 結束送 `then`。

**前端狀態機鐵則**：
1. 任何狀態播完 `loops` 次 → 自動回 idle_breathing（不需要顯式信號）
2. 新信號到達時立即切換（crossfade 200ms——頭尾幀相同所以淡入淡出安全）
3. idle_breathing 無限循環（呼吸幅度已在生成時壓到最小「almost imperceptible」）
4. 綠幕 key 色＝**cyan #00FFFF**（小葵本身是綠色，不能用綠幕）——WebGL shader 即時去背，despill 處理青邊

## 14. 聲音定案（Blue 拍板 2026-09-24）

- **TTS 音色**：MiniMax voice clone `xiaokui_video_voice`（樣本=H3 影片配音 31s）＋ **pitch -2 半音**（中位 314Hz，小男生×小女生之間）
- **接線**：AgentLoop 回應 → MiniMax t2a_v2 生成 mp3 → WS 傳 URL → 前端 `<audio>` 播放（Web Speech 僅離線 fallback）
- **鐵則**：輪播影片音軌一律 muted（引擎內建）；語音輸出未結束＝輪播鎖 talk 系列（§13 已實作）
- 否決記錄：LTW 台灣腔克隆系列（228Hz 自然但音色不如影片原聲）
