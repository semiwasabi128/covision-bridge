// vault_templates.dart
// 範本系統 — 預設工作流範本
// [教練 Agent 2026-07-24 v3] 根據 8 張截圖比對，重寫編排邏輯
//
// 編排原則：
// 1. 嚴格左到右，x 隨資料流遞增
// 2. 分支對稱展開：主線 y=400，上分支 y=100，下分支 y=700
// 3. 分支後節點 x 必須錯開遞增（這是之前重疊的根因！）
// 4. 合併點在分支最後節點的右側中央
// 5. LLM 大節點獨立一列，前後留 500px

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // [刀 5] 自訂範本持久化

class WorkflowTemplate {
  final String id;
  final String name;
  final String description;
  final String category;
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> connections;
  final String icon;
  final bool isTutorialEntry;

  const WorkflowTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.nodes,
    required this.connections,
    required this.icon,
    this.isTutorialEntry = false,
  });
}

class VaultTemplateService {
  VaultTemplateService._();
  static final VaultTemplateService instance = VaultTemplateService._();

  List<WorkflowTemplate> getBuiltinTemplates() {
    return [
      // ── 1. 角色扮演 IG ──────────────────────────────────────
      // 直線：input → llm → imageGen → output
      // 4 節點同一 y，x 等距 500px
      WorkflowTemplate(
        id: 'ig_post',
        name: '角色扮演 IG',
        description: '選一個角色 → AI 用角色語氣寫 IG 貼文 → 生成配圖',
        category: '社群',
        icon: '📸',
        nodes: [
          {'type': 'input', 'x': 100, 'y': 400, 'params': {'label': '角色與素材', 'content': ''}},
          {'type': 'llm', 'x': 480, 'y': 400, 'params': {
            'model': 'glm-5.2',
            'prompt': '你是一個角色扮演 IG 小編。使用者會給你一個角色（寵物、物品、心情等）和一些素材。'
                '請用那個角色的第一人稱視角寫一篇 150-250 字的 IG 貼文。'
                '要有個性、有趣、有畫面感。不要官腔。\n\n素材：{input}',
            'temperature': 0.7,
          }},
          {'type': 'imageGen', 'x': 860, 'y': 400, 'params': {
            'prompt': '根據以下貼文內容生成一張配圖，風格溫暖有質感：{input}',
            'size': '1024x1024',
          }},
          // [小葵 2026-09-24 Blue 令·去重] 移除「配圖預覽」——機制端自動落地
          {'type': 'output', 'x': 1240, 'y': 400, 'params': {'label': 'IG 貼文', 'displayMode': 'text'}},
        ],
        connections: [
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'input'},
          {'from': 1, 'fromPort': 'output', 'to': 2, 'toPort': 'prompt'},
          {'from': 2, 'fromPort': 'output', 'to': 3, 'toPort': 'input'},
        ],
      ),

      // ── 2. 晨間情報站 ────────────────────────────────────
      // input → tool×2（上下）→ merge → llm → output
      // 分支：input 分到兩個 tool（同 x=600，y=100/700）
      // 合併：merge 在 tool 右側中央（x=1100, y=400）
      WorkflowTemplate(
        id: 'knowledge_digest',
        name: '晨間情報站',
        description: '搜尋網路新聞 + 搜尋本地檔案 → 合併 → AI 整理成一份每日情報日報',
        category: '知識管理',
        icon: '📰',
        nodes: [
          {'type': 'input', 'x': 100, 'y': 400, 'params': {'label': '今日主題', 'content': ''}},
          {'type': 'tool', 'x': 480, 'y': 200, 'params': {'label': '搜尋網路', 'toolName': 'browse', 'args': '{}'}},
          {'type': 'tool', 'x': 480, 'y': 600, 'params': {'label': '搜尋本地檔案', 'toolName': 'browse', 'args': '{}'}},
          {'type': 'merge', 'x': 860, 'y': 400, 'params': {'label': '合併資料源', 'mode': 'concat'}},
          {'type': 'llm', 'x': 1240, 'y': 400, 'params': {
            'model': 'glm-5.2',
            'prompt': '你是晨間情報站編輯。根據以下資料整理一份結構化日報。'
                '格式：\n1. 今日要聞\n2. 本地相關筆記\n3. AI 建議\n\n資料：{input}',
            'temperature': 0.3,
          }},
          {'type': 'output', 'x': 1620, 'y': 400, 'params': {'label': '晨間日報', 'displayMode': 'text'}},
        ],
        connections: [
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'input'},
          {'from': 0, 'fromPort': 'output', 'to': 2, 'toPort': 'input'},
          {'from': 1, 'fromPort': 'output', 'to': 3, 'toPort': 'a'},
          {'from': 2, 'fromPort': 'output', 'to': 3, 'toPort': 'b'},
          {'from': 3, 'fromPort': 'output', 'to': 4, 'toPort': 'input'},
          {'from': 4, 'fromPort': 'output', 'to': 5, 'toPort': 'input'},
        ],
      ),

      // ── 3. 短影音製作所 ────────────────────────────────────
      // input → llm → condition → {true: imageGen→tts, false: videoGen→musicGen} → merge → output
      //
      // 關鍵：分支後每個節點 x 遞增！
      // condition(x=1100) → imageGen(x=1600) → tts(x=2100) → merge(x=2600)
      // condition(x=1100) → videoGen(x=1600) → musicGen(x=2100) → merge(x=2600)
      WorkflowTemplate(
        id: 'memory_review',
        name: '短影音製作所',
        description: '輸入主題 → 寫腳本 → 判斷風格 → 分支產出圖文語音或影片配樂 → 合併短影音',
        category: '影音',
        icon: '🎬',
        nodes: [
          {'type': 'input', 'x': 100, 'y': 420, 'params': {'label': '短影音主題', 'content': ''}},
          {'type': 'llm', 'x': 480, 'y': 420, 'params': {
            'model': 'glm-5.2',
            'prompt': '你是短影音腳本編劇。根據以下主題寫一段 30 秒短影音腳本。'
                '在腳本最後標注 [知識型] 或 [感性型] 來決定製作方向。'
                '格式：\n標題：...\n旁白：...\n視覺：...\n風格標注：[知識型] 或 [感性型]\n\n主題：{input}',
            'temperature': 0.8,
          }},
          {'type': 'condition', 'x': 860, 'y': 420, 'params': {'label': '判斷風格', 'condition': '知識型'}},
          // [教練 Agent 2026-08-15 使用者 佈局回饋] 四個生成節點垂直排列在右側，
          // condition 扇出（截圖三樣態）——線整齊不交叉。
          // true 分支（知識型）：解說圖 + 語音旁白
          {'type': 'imageGen', 'x': 1320, 'y': 40, 'params': {
            'label': '解說圖',
            'prompt': '根據以下腳本生成一張知識型解說圖：{input}',
            'size': '1024x1024',
          }},
          {'type': 'tts', 'x': 1320, 'y': 300, 'params': {'label': '語音旁白', 'text': '', 'voice': 'default', 'speed': 1.0}},
          // false 分支（感性型）：影片 + 配樂
          {'type': 'videoGen', 'x': 1320, 'y': 560, 'params': {
            'label': '影片片段',
            'prompt': '根據以下腳本生成一段感性影片：{input}',
            'duration': 5,
          }},
          {'type': 'musicGen', 'x': 1320, 'y': 820, 'params': {
            'label': '配樂',
            'prompt': '根據以下腳本生成一段配樂：{input}',
            'duration': 30,
          }},
          // cascade merge：對齊各分組重心，線不交叉
          {'type': 'merge', 'x': 1860, 'y': 170, 'params': {'label': '合併視聽 A', 'mode': 'concat'}},
          {'type': 'merge', 'x': 1860, 'y': 690, 'params': {'label': '合併視聽 B', 'mode': 'concat'}},
          {'type': 'merge', 'x': 2300, 'y': 430, 'params': {'label': '合併總成', 'mode': 'concat'}},
          {'type': 'output', 'x': 2720, 'y': 430, 'params': {'label': '短影音成品', 'displayMode': 'text'}},
        ],
        connections: [
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'input'},
          {'from': 1, 'fromPort': 'output', 'to': 2, 'toPort': 'input'},
          // condition true → 上分支：腳本文字（text）分給 imageGen 與 tts
          // [教練 Agent 2026-08-15 修復] 原本 imageGen.output(圖片)→tts.text(文字)
          // 型別不匹配（洋紅線接藍點的元兇）。正確語意：腳本文字→語音旁白，
          // imageGen 的圖不該餵給 TTS。
          {'from': 2, 'fromPort': 'true', 'to': 3, 'toPort': 'prompt'},
          {'from': 2, 'fromPort': 'true', 'to': 4, 'toPort': 'text'},
          // condition false → 下分支：腳本文字餵 videoGen 與 musicGen
          // [教練 Agent 2026-08-15 修復] 原本 videoGen.output(影片)→musicGen.prompt(文字)
          // 型別不匹配（紅線接藍點）。正確語意：同一份腳本→影片＋配樂。
          {'from': 2, 'fromPort': 'false', 'to': 5, 'toPort': 'prompt'},
          {'from': 2, 'fromPort': 'false', 'to': 6, 'toPort': 'prompt'},
          // [教練 Agent 2026-08-15 孤兒修復] 四個產出全部接進 cascade merge：
          // mA(imageGen,tts) → 總成.a；mB(videoGen,musicGen) → 總成.b
          {'from': 3, 'fromPort': 'output', 'to': 7, 'toPort': 'a'},
          {'from': 4, 'fromPort': 'output', 'to': 7, 'toPort': 'b'},
          {'from': 5, 'fromPort': 'output', 'to': 8, 'toPort': 'a'},
          {'from': 6, 'fromPort': 'output', 'to': 8, 'toPort': 'b'},
          {'from': 7, 'fromPort': 'output', 'to': 9, 'toPort': 'a'},
          {'from': 8, 'fromPort': 'output', 'to': 9, 'toPort': 'b'},
          {'from': 9, 'fromPort': 'output', 'to': 10, 'toPort': 'input'},
        ],
      ),

      // ── 4. 多重宇宙簡報 ──────────────────────────────────
      // input → subWorkflow×3（上中下）→ cascade merge → llm → condition
      //   → true: merge.a / false: llm2 → merge.b → output
      //
      // [教練 Agent 2026-08-16 使用者 調版] 門→三宇宙間距拉開（~460px），
      // 橋₁ 移到 A/B 宇宙之間（x=500）——前六節點不再擁擠。
      WorkflowTemplate(
        id: 'multi_model',
        name: '多重宇宙簡報',
        description: '同一主題在三個平行宇宙用三種方式呈現 → AI 觀察者合成多重宇宙簡報',
        category: '進階',
        icon: '🌐',
        nodes: [
          {'type': 'input', 'x': -340, 'y': 400, 'params': {'label': '🚪 門 — 輸入主題', 'content': ''}},
          // 三條子工作流 — 同 x=120，y=200/400/600
          {'type': 'subWorkflow', 'x': 120, 'y': 200, 'params': {'label': '🌊 宇宙 A：角色扮演', 'workflowRef': 'ig_post'}},
          {'type': 'subWorkflow', 'x': 120, 'y': 400, 'params': {'label': '🌊 宇宙 B：情報日報', 'workflowRef': 'knowledge_digest'}},
          {'type': 'subWorkflow', 'x': 120, 'y': 600, 'params': {'label': '🌊 宇宙 C：短影音', 'workflowRef': 'memory_review'}},
          // cascade merge — 橋₁ 在 A/B 之間，橋₂ 在 B/C 右側
          {'type': 'merge', 'x': 500, 'y': 300, 'params': {'label': '🌉 橋₁ — A+B', 'mode': 'concat'}},
          {'type': 'merge', 'x': 860, 'y': 500, 'params': {'label': '🌉 橋₂ — 橋₁+C', 'mode': 'concat'}},
          // 鐘擺 — 觀察者 LLM — x=1600
          {'type': 'llm', 'x': 1240, 'y': 400, 'params': {
            'label': '⚖️ 鐘擺 — 觀察者',
            'model': 'glm-5.2',
            'prompt': '你是「多重宇宙觀察者」。你正在觀察同一個主題在三個平行宇宙中的發展。'
                '以下是三個宇宙的結果：\n\n{input}\n\n'
                '請寫一份多重宇宙簡報：\n'
                '1. 描述每個宇宙怎麼詮釋這個主題\n'
                '2. 找出三個宇宙之間的共鳴和差異\n'
                '3. 給出觀察：哪種呈現最有力？哪種最有趣？\n'
                '4. 一句話總結\n\n'
                '語氣：像一個看了很多世界的觀察者，有洞察力但不說教，偶爾幽默。',
            'temperature': 0.6,
          }},
          // 品質判斷 condition — x=2100
          {'type': 'condition', 'x': 1620, 'y': 400, 'params': {'label': '⚖️ 品質校驗', 'condition': '共鳴'}},
          // false 分支 → 補充觀察 LLM — x=2000, y=600（往下，不擋 true 直通路徑）
          {'type': 'llm', 'x': 2000, 'y': 600, 'params': {
            'label': '⚖️ 補充觀察',
            'model': 'glm-5.2',
            'prompt': '前面的觀察不夠完整。請補充：\n'
                '1. 三個宇宙之間有沒有遺漏的矛盾點？\n'
                '2. 哪個宇宙的呈現最出乎意料？為什麼？\n\n內容：{input}',
            'temperature': 0.5,
          }},
          // 匯流 merge — x=2600, y=400（condition true 直通 a，補充觀察走 b）
          {'type': 'merge', 'x': 2380, 'y': 400, 'params': {'label': '🌉 匯流', 'mode': 'concat'}},
          // 心腦 — 輸出 — x=3100
          {'type': 'output', 'x': 2760, 'y': 400, 'params': {'label': '💗🧠 心腦 — 多重宇宙簡報', 'displayMode': 'text'}},
        ],
        connections: [
          // 門 → 三條水流
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'trigger'},
          {'from': 0, 'fromPort': 'output', 'to': 2, 'toPort': 'trigger'},
          {'from': 0, 'fromPort': 'output', 'to': 3, 'toPort': 'trigger'},
          // 水流 → cascade merge（A→m1.a, B→m1.b, m1→m2.a, C→m2.b）
          {'from': 1, 'fromPort': 'output', 'to': 4, 'toPort': 'a'},
          {'from': 2, 'fromPort': 'output', 'to': 4, 'toPort': 'b'},
          {'from': 4, 'fromPort': 'output', 'to': 5, 'toPort': 'a'},
          {'from': 3, 'fromPort': 'output', 'to': 5, 'toPort': 'b'},
          // 橋 → 鐘擺觀察者
          {'from': 5, 'fromPort': 'output', 'to': 6, 'toPort': 'input'},
          // 觀察者 → 品質判斷
          {'from': 6, 'fromPort': 'output', 'to': 7, 'toPort': 'input'},
          // 品質判斷 true → merge.a（直通）
          {'from': 7, 'fromPort': 'true', 'to': 9, 'toPort': 'a'},
          // 品質判斷 false → 補充觀察（往上）
          {'from': 7, 'fromPort': 'false', 'to': 8, 'toPort': 'input'},
          // 補充觀察 → merge.b（往下彎）
          {'from': 8, 'fromPort': 'output', 'to': 9, 'toPort': 'b'},
          // merge → 心腦輸出
          {'from': 9, 'fromPort': 'output', 'to': 10, 'toPort': 'input'},
        ],
      ),

      // ── 5. 完整互動教學 ──────────────────────────────────
      WorkflowTemplate(
        id: 'full_tutorial',
        name: '完整互動教學',
        description: '包含以上四種示範工作流的完整教學流程，隨時可以重新啟動',
        category: '教學',
        icon: '🎓',
        isTutorialEntry: true,
        nodes: [],
        connections: [],
      ),

      // ── 6. Honeycomb 測試（故意重疊） ─────────────────────
      // [教練 Agent 2026-08-15 刪除] 測試期產物——使用者 指示清理測試用範本。
      // 兩個 LLM 節點座標幾乎一樣，用來測試 Honeycomb 自動偵測。
      // 歷史貢獻：驗證了 Honeycomb 偵測+修復，功成身退。

      // ── 7. 連線交叉測試 ─────────────────────────────────
      // [教練 Agent 2026-08-15 刪除] 測試期產物——測 canvas_detect_crossings 用，功成身退。

      // ══════════════════════════════════════════════════════
      // [教練 Agent 2026-08-01] 影像創作模板群
      // ══════════════════════════════════════════════════════

      // ── 6. 角色設定圖產線 ──────────────────────────────
      // input → imageGen(角色原圖) → [🖼️ 原圖預覽] → vision(分析特徵)
      //   → characterLock×3(正面/側面/表情) → [🖼️ 各視角預覽×3] → merge → output
      //
      // 核心用途：給角色描述 → 生成角色圖 → AI 分析 → 用原圖當參考
      // 生成三個不同角度的一致風格角色圖
      // [教練 Agent 2026-08-16 使用者 調版] 主幹線 y≈400，vision 上移高台（y=-80），
      // 三視角 y=140/455/765 扇出，輸出 y≈120——線不再交叉纏繞。
      // [小葵 2026-09-22 共視鐵則·Blue 令] 每個生成階段都要有即時預覽視窗
      // 節點——主形象生成後立刻看到、三視角各自看到，落地的成果節點
      // （output displayMode=gallery）直接放在各生成節點下方。
      WorkflowTemplate(
        id: 'character_sheet',
        name: '角色設定圖產線',
        description: '輸入角色描述 → 生成角色圖 → AI 分析特徵 → 用參考圖產出三個角度（正面/側面/表情），每階段即時預覽',
        category: '影像創作',
        icon: '🎨',
        nodes: [
          // 0: 輸入角色描述
          {'type': 'input', 'x': -48, 'y': 400, 'params': {
            'label': '📝 角色描述', 'content': '',
          }},
          // 1: 生成角色原圖
          {'type': 'imageGen', 'x': 400, 'y': 400, 'params': {
            'label': '🎨 角色原圖',
            'serviceId': 'minimax_image', // [教練 Agent 2026-08-26] OpenAI 停用，範本改 MiniMax
            'prompt': '角色設定圖，全身轉面圖，多個視角，乾淨背景，精緻細節：{input}',
            'size': '1024x1024',
          }},
          // [小葵 2026-09-24 Blue 令·去重] 移除靜態「主形象預覽」節點——
          // 機制端已自動為每個付費生成落地成果節點（2026-09-22 白名單），
          // 靜態預覽造成重複。以下三個視角預覽同理由移除。
          // 2: Vision 分析角色特徵 — 高台（y=-80）
          {'type': 'vision', 'x': 834, 'y': -80, 'params': {
            'label': '👁️ 分析特徵',
            'serviceId': 'openai_vision',
            'prompt': '詳細分析這個角色以製作角色設定表。描述：髮型與髮色、眼睛顏色、'
                '五官特徵、服裝、配件、體型、畫風。描述要精確——'
                '這份描述將用於生成一致的角色圖像。',
          }},
          // 3: 正面視角
          {'type': 'characterLock', 'x': 1600, 'y': 100, 'params': {
            'label': '🔐 正面視角',
            'serviceId': 'openai_character',
            'prompt': '正面視角，站姿，中性表情，與參考圖是同一個角色',
            'size': '1024x1024',
          }},
          // 4: 側面視角
          {'type': 'characterLock', 'x': 1600, 'y': 500, 'params': {
            'label': '🔐 側面視角',
            'serviceId': 'openai_character',
            'prompt': '側面視角，與參考圖是同一個角色，全身轉面圖',
            'size': '1024x1024',
          }},
          // 5: 表情特寫
          {'type': 'characterLock', 'x': 1600, 'y': 900, 'params': {
            'label': '🔐 表情特寫',
            'serviceId': 'openai_character',
            'prompt': '頭肩肖像：這個角色的頭部與肩膀，溫暖的微笑，眼睛有神，與參考圖是同一個角色',
            'size': '1024x1024',
          }},
          // 6: 匯出
          // [教練 Agent 2026-08-16 使用者 微調] 三視角 y 100/500/900 對稱展開，
          // 輸出移到高台層（與 vision 同高 y≈-80）——上排收齊。
          {'type': 'output', 'x': 2400, 'y': -80, 'params': {
            'label': '📦 角色設定圖組', 'displayMode': 'gallery',
          }},
        ],
        connections: [
          // input → imageGen
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'prompt'},
          // imageGen → vision（圖片傳遞）
          {'from': 1, 'fromPort': 'output', 'to': 2, 'toPort': 'image'},
          // [教練 Agent 2026-08-15 使用者 抓包] 視角與特寫應接在「分析特徵」後面——
          // 舊定義三條全從角色原圖拉，分析特徵的輸出沒人吃，
          // 視角節點拿不到特徵描述。修：分析特徵 → 三視角 prompt，
          // 角色原圖保留 reference（鎖角色長相用）。
          //
          // [教練 Agent 2026-08-16 使用者 調線序] 依畫布實測順序重排——
          // reference 群 → output 匯流群 → prompt 群。
          // fan-out 分點依列表順序編號，順序影響同 port 上線的站位，
          // 群組集中視覺更順暢。
          {'from': 1, 'fromPort': 'output', 'to': 3, 'toPort': 'reference'},
          {'from': 1, 'fromPort': 'output', 'to': 4, 'toPort': 'reference'},
          {'from': 1, 'fromPort': 'output', 'to': 5, 'toPort': 'reference'},
          // vision → output（文字分析結果）
          {'from': 2, 'fromPort': 'output', 'to': 6, 'toPort': 'input'},
          // characterLock×3 → output（圖片 URL 傳遞）
          {'from': 3, 'fromPort': 'output', 'to': 6, 'toPort': 'input'},
          {'from': 4, 'fromPort': 'output', 'to': 6, 'toPort': 'input'},
          {'from': 5, 'fromPort': 'output', 'to': 6, 'toPort': 'input'},
          // vision → 三視角 prompt
          {'from': 2, 'fromPort': 'output', 'to': 3, 'toPort': 'prompt'},
          {'from': 2, 'fromPort': 'output', 'to': 4, 'toPort': 'prompt'},
          {'from': 2, 'fromPort': 'output', 'to': 5, 'toPort': 'prompt'},
        ],
      ),

      // ── 7. IG 貼文產線 v2 ──────────────────────────────
      // input → llm(寫文案) → imageGen(配圖) → vision(檢查配圖) → output
      //
      // 比舊版多了 Vision 節點：AI 先看圖，確認圖片和文案匹配
      WorkflowTemplate(
        id: 'ig_post_v2',
        name: 'IG 貼文產線 v2',
        description: '輸入主題 → AI 寫文案 + 生成配圖 → Vision 檢查圖文一致性 → 匯出',
        category: '影像創作',
        icon: '📸',
        nodes: [
          {'type': 'input', 'x': 100, 'y': 400, 'params': {
            'label': '📝 主題與素材', 'content': '',
          }},
          {'type': 'llm', 'x': 480, 'y': 400, 'params': {
            'model': 'glm-5.2',
            'prompt': '你是 IG 貼文寫手。根據以下主題寫一篇 150-250 字的貼文。'
                '要有個性、有趣、有畫面感。最後附上一行圖片描述（英文）。\n\n'
                '格式：\n貼文：...\n圖片描述：...\n\n主題：{input}',
            'temperature': 0.7,
          }},
          {'type': 'imageGen', 'x': 860, 'y': 400, 'params': {
            'label': '🎨 配圖',
            'serviceId': 'minimax_image', // [教練 Agent 2026-08-26] OpenAI 停用，範本改 MiniMax
            'prompt': '{input}',
            'size': '1024x1024',
          }},
          // [小葵 2026-09-24 Blue 令·去重] 移除「配圖預覽」——機制端自動落地
          {'type': 'vision', 'x': 1240, 'y': 400, 'params': {
            'label': '👁️ 圖文一致性檢查',
            'serviceId': 'openai_vision',
            'prompt': '檢查這張圖片是否與上方描述的貼文內容相符。'
                '請給出 1-10 分的匹配評分，並簡短說明原因。用繁體中文回答。',
          }},
          {'type': 'output', 'x': 1620, 'y': 400, 'params': {
            'label': '📤 IG 貼文成品', 'displayMode': 'text',
          }},
        ],
        connections: [
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'input'},
          {'from': 1, 'fromPort': 'output', 'to': 2, 'toPort': 'prompt'},
          // [小葵 2026-09-24] imageGen → vision 檢查（預覽由機制端自動落地）
          {'from': 2, 'fromPort': 'output', 'to': 3, 'toPort': 'image'},
          {'from': 3, 'fromPort': 'output', 'to': 4, 'toPort': 'input'},
        ],
      ),

      // ── 8. 分鏡腳本產線 ────────────────────────────────
      // input → llm(寫分鏡) → imageGen(逐鏡生成) → output
      //
      // LLM 寫出結構化分鏡腳本，每個鏡頭有獨立的視覺描述
      WorkflowTemplate(
        id: 'storyboard',
        name: '分鏡腳本產線',
        description: '輸入故事概念 → AI 寫結構化分鏡腳本 → 逐鏡生成畫面',
        category: '影像創作',
        icon: '🎬',
        nodes: [
          {'type': 'input', 'x': 100, 'y': 400, 'params': {
            'label': '🎬 故事概念', 'content': '',
          }},
          {'type': 'llm', 'x': 480, 'y': 400, 'params': {
            'model': 'glm-5.2',
            'prompt': '你是分鏡師。根據以下故事概念寫 3 個鏡頭的分鏡腳本。'
                '每個鏡頭格式：\n'
                '---\n鏡頭N：[標題]\n畫面：[英文視覺描述，用於 AI 圖片生成]\n旁白：[中文旁白]\n---\n\n'
                '故事概念：{input}',
            'temperature': 0.8,
          }},
          {'type': 'imageGen', 'x': 860, 'y': 400, 'params': {
            'label': '🎨 逐鏡畫面',
            'serviceId': 'minimax_image', // [教練 Agent 2026-08-26] OpenAI 停用，範本改 MiniMax
            'prompt': '電影感分鏡畫面：{input}',
            'size': '1792x1024',
          }},
          // [小葵 2026-09-24 Blue 令·去重] 移除「分鏡畫面預覽」——機制端自動落地
          {'type': 'output', 'x': 1240, 'y': 400, 'params': {
            'label': '📤 分鏡成品', 'displayMode': 'gallery',
          }},
        ],
        connections: [
          {'from': 0, 'fromPort': 'output', 'to': 1, 'toPort': 'input'},
          {'from': 1, 'fromPort': 'output', 'to': 2, 'toPort': 'prompt'},
          {'from': 2, 'fromPort': 'output', 'to': 3, 'toPort': 'input'},
        ],
      ),
    ];
  }

  List<WorkflowTemplate> getTemplatesByCategory(String category) {
    return getBuiltinTemplates().where((t) => t.category == category).toList();
  }

  List<String> getCategories() {
    return getBuiltinTemplates().map((t) => t.category).toSet().toList()..sort();
  }

  String toJson(WorkflowTemplate template) {
    return jsonEncode({
      'id': template.id,
      'name': template.name,
      'description': template.description,
      'nodes': template.nodes,
      'connections': template.connections,
    });
  }

  WorkflowTemplate? fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return WorkflowTemplate(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String,
        category: map['category'] as String? ?? '自訂',
        icon: map['icon'] as String? ?? '📄',
        isTutorialEntry: map['isTutorialEntry'] as bool? ?? false,
        nodes: (map['nodes'] as List).cast<Map<String, dynamic>>(),
        connections: (map['connections'] as List).cast<Map<String, dynamic>>(),
      );
    } catch (e) {
      debugPrint('[VaultTemplateService] fromJson 失敗: $e');
      return null;
    }
  }

  // ═══ [刀 5 D5.2 2026-09-08] 自訂範本持久化（示範錄製落地處） ═══

  static const _customKey = 'vault_custom_templates';
  List<WorkflowTemplate>? _customCache;

  /// 儲存自訂範本（示範錄製的範本落這裡）
  Future<void> saveCustomTemplate(WorkflowTemplate t) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getCustomTemplates();
    // 同 id 覆寫（重錄同名範本＝更新）
    final kept = all.where((e) => e.id != t.id).toList();
    kept.add(t);
    await prefs.setStringList(
      _customKey,
      kept.map((e) => toJson(e)).toList(),
    );
    _customCache = null; // 清快取
    debugPrint('[VaultTemplateService] 自訂範本已存：${t.name}（共 ${kept.length} 個）');
  }

  /// 取得自訂範本（快取——UI 列表用）
  Future<List<WorkflowTemplate>> getCustomTemplates() async {
    if (_customCache != null) return _customCache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_customKey) ?? [];
    _customCache = raw
        .map((s) => fromJson(s))
        .whereType<WorkflowTemplate>()
        .toList();
    return _customCache!;
  }

  /// 刪除自訂範本
  Future<void> deleteCustomTemplate(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getCustomTemplates();
    final kept = all.where((e) => e.id != id).toList();
    await prefs.setStringList(_customKey, kept.map((e) => toJson(e)).toList());
    _customCache = null;
  }
}
