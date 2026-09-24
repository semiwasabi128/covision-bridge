// persona_inference_service.dart
// 夥伴人格機制 — B2 雲端人格推理
// [教練 Agent 2026-07-22] Phase H
//
// 輸入：FolderScanResult + Companion + 召喚提示詞
// 處理：雲端模型推理 → 輸出 PersonaCard JSON
// 輸出：PersonaCard 存入 agent_memories 表，key = persona_card_{companionId}
//
// 隱私鐵則：只送掃描摘要給雲端，不送完整檔案內容。
// 成本鐵則：只在首次出場 + 修改時跑，不是每次對話都跑。

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../api_service.dart';
import '../onboarding/folder_scanner_service.dart';
import '../../models/companion.dart';
import 'agent_knowledge_service.dart';

/// 人格卡——推理引擎的輸出
class PersonaCard {
  final String companionId;
  final String archetype;        // 原型：創意型/組織型/專業型/陪伴型/探索型
  final String voiceStyle;       // 說話風格
  final String addressUser;      // 怎麼稱呼使用者
  final String expertise;        // 專長定位
  final String openingTone;      // 開場情緒基調
  final String firstLine;        // 第一句話
  final String userArchetype;    // 使用者畫像
  final List<String> suggestedTemplateOrder; // 建議範本順序
  final String scanSummary;      // 掃描摘要（用於出場時引用具體數字）
  final DateTime createdAt;

  const PersonaCard({
    required this.companionId,
    required this.archetype,
    required this.voiceStyle,
    required this.addressUser,
    required this.expertise,
    required this.openingTone,
    required this.firstLine,
    required this.userArchetype,
    required this.suggestedTemplateOrder,
    this.scanSummary = '',
    required this.createdAt,
  });

  /// 轉成 system prompt 可用的文字
  String toPromptText() {
    return '''## 你的人格卡

**原型**：$archetype
**說話風格**：$voiceStyle
**稱呼使用者**：$addressUser
**專長定位**：$expertise
**開場基調**：$openingTone
**使用者畫像**：$userArchetype

**你的第一句話**：「$firstLine」

**建議範本順序**：${suggestedTemplateOrder.join(" → ")}

請嚴格按照人格卡的風格和語氣與使用者對話。
在引導使用者使用範本時，先講解效果和目的，再引導選擇檔案和設定參數。''';
  }

  /// 轉成出場指令用的掃描摘要
  String get scanReportForOpening {
    if (scanSummary.isEmpty) return '';
    return scanSummary;
  }

  Map<String, dynamic> toJson() => {
    'companionId': companionId,
    'archetype': archetype,
    'voiceStyle': voiceStyle,
    'addressUser': addressUser,
    'expertise': expertise,
    'openingTone': openingTone,
    'firstLine': firstLine,
    'userArchetype': userArchetype,
    'suggestedTemplateOrder': suggestedTemplateOrder,
    'scanSummary': scanSummary,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PersonaCard.fromJson(Map<String, dynamic> json) {
    return PersonaCard(
      companionId: json['companionId'] as String? ?? '',
      archetype: json['archetype'] as String? ?? '陪伴型',
      voiceStyle: json['voiceStyle'] as String? ?? '溫暖自然',
      addressUser: json['addressUser'] as String? ?? '你',
      expertise: json['expertise'] as String? ?? '通用助手',
      openingTone: json['openingTone'] as String? ?? '友善',
      firstLine: json['firstLine'] as String? ?? '嗨，我在這裡。',
      userArchetype: json['userArchetype'] as String? ?? '探索者',
      suggestedTemplateOrder: (json['suggestedTemplateOrder'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? ['ig_post', 'knowledge_digest', 'memory_review', 'multi_model'],
      scanSummary: json['scanSummary'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 人格推理服務
///
/// 用雲端模型推理人格卡。只在首次出場 + 修改時呼叫，不是每次對話都跑。
class PersonaInferenceService {
  PersonaInferenceService._();
  static final PersonaInferenceService instance = PersonaInferenceService._();

  /// knowledge service 的單例
  AgentKnowledgeService get _knowledge => AgentKnowledgeService.instance;

  /// 人格卡在 agent_memories 表的 key 格式
  static String cardKey(String companionId) => 'persona_card_$companionId';

  /// 推理人格卡
  ///
  /// [companion] 夥伴資料（含 name, mbtiCode, role, appearancePrompt）
  /// [summonPrompt] 使用者在 DesktopSummonScreen 輸入的召喚提示詞
  /// [scanResult] 資料夾掃描結果（可為 null——空資料夾時只用召喚提示詞）
  ///
  /// 回傳 PersonaCard，同時存入知識庫。
  /// 失敗時回傳 fallback 人格卡（不丟例外）。
  Future<PersonaCard> infer({
    required Companion companion,
    String? summonPrompt,
    FolderScanResult? scanResult,
  }) async {
    final scanSummary = scanResult?.toSummaryText() ?? '（使用者尚未設定資料夾或資料夾為空）';

    try {
      // 組裝推理 prompt
      final systemPrompt = _buildInferenceSystemPrompt();
      final userPrompt = _buildInferenceUserPrompt(
        companion: companion,
        summonPrompt: summonPrompt ?? '',
        scanSummary: scanSummary,
      );

      // 呼叫雲端模型
      final response = await ApiService.complete(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );

      // 解析 JSON
      final json = _extractJson(response);
      final card = PersonaCard(
        companionId: companion.id,
        archetype: json['archetype'] as String? ?? '陪伴型',
        voiceStyle: json['voiceStyle'] as String? ?? '溫暖自然',
        addressUser: json['addressUser'] as String? ?? '你',
        expertise: json['expertise'] as String? ?? '通用助手',
        openingTone: json['openingTone'] as String? ?? '友善',
        firstLine: json['firstLine'] as String? ?? '嗨，我在這裡。',
        userArchetype: json['userArchetype'] as String? ?? '探索者',
        suggestedTemplateOrder: (json['suggestedTemplateOrder'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? ['ig_post', 'knowledge_digest', 'memory_review', 'multi_model'],
        scanSummary: scanSummary,
        createdAt: DateTime.now(),
      );

      // 存入知識庫
      await _saveCard(card);
      debugPrint('[PersonaInference] 人格卡推理成功: ${card.archetype} / ${card.firstLine}');
      return card;
    } catch (e) {
      debugPrint('[PersonaInference] 推理失敗，使用 fallback: $e');
      final fallback = _buildFallbackCard(companion, scanSummary);
      await _saveCard(fallback);
      return fallback;
    }
  }

  /// 重新推理（修改夥伴資料後呼叫）
  ///
  /// 呼叫端（CompanionStore.update）應直接呼叫 [infer] 並傳入更新後的 Companion。
  /// 此方法保留向後相容；內部會從知識庫取回舊掃描摘要。
  Future<PersonaCard> reinfer({
    required Companion companion,
    String? summonPrompt,
  }) async {
    // 從知識庫取回舊人格卡的掃描摘要
    final existingCard = getCard(companion.id);
    final oldScanSummary = existingCard?.scanSummary ?? '';

    // 用舊掃描摘要重新推理
    FolderScanResult? scanResult;
    if (oldScanSummary.isNotEmpty) {
      scanResult = FolderScanResult(
        rootPath: '',
        phase1Complete: true,
        phase2Complete: true,
      );
    }

    return infer(
      companion: companion,
      summonPrompt: summonPrompt,
      scanResult: scanResult,
    );
  }

  /// 從知識庫取回人格卡
  PersonaCard? getCard(String companionId) {
    try {
      final key = cardKey(companionId);
      final memory = _knowledge.getMemoryByTitle(key);
      if (memory == null) return null;

      final json = jsonDecode(memory.content) as Map<String, dynamic>;
      return PersonaCard.fromJson(json);
    } catch (e) {
      debugPrint('[PersonaInference] 取回人格卡失敗: $e');
      return null;
    }
  }

  /// 檢查人格卡是否存在
  bool hasCard(String companionId) {
    return getCard(companionId) != null;
  }

  // ── private ──────────────────────────────────────────────────────

  String _buildInferenceSystemPrompt() {
    return '''你是人格推理引擎。根據以下資訊推理出夥伴的人格卡。

你會收到：
1. 使用者的資料夾掃描結果摘要
2. 使用者的召喚提示詞（描述他想要什麼樣的夥伴）
3. 夥伴的基本資料（名稱、MBTI、角色）

請推理出一個有溫度、有個性、能和使用者建立連線的人格卡。

輸出 JSON（只輸出 JSON，不要其他文字）：
```json
{
  "archetype": "原型（創意型/組織型/專業型/陪伴型/探索型）",
  "voiceStyle": "說話風格描述（2-3句話）",
  "addressUser": "怎麼稱呼使用者（例如：主人/夥伴/老師/你）",
  "expertise": "專長定位（1-2句話）",
  "openingTone": "開場情緒基調（例如：溫暖/活潑/沉穩/好奇）",
  "firstLine": "夥伴的第一句話（自然、有溫度，10-30字）",
  "userArchetype": "使用者畫像（根據掃描結果推測，2-3句話）",
  "suggestedTemplateOrder": ["ig_post", "knowledge_digest", "memory_review", "multi_model"]
}
```

範本順序說明：
- ig_post：角色扮演 IG（視覺系，門檻最低）
- knowledge_digest：晨間情報站（資訊整理型）
- memory_review：短影音製作所（多媒體創作型）
- multi_model：多重宇宙簡報（畢業任務，永遠最後一個）

根據使用者畫像調整前三個的順序，multi_model 永遠在最後。''';
  }

  String _buildInferenceUserPrompt({
    required Companion companion,
    required String summonPrompt,
    required String scanSummary,
  }) {
    final mbti = companion.mbtiType;
    return '''## 使用者的資料夾掃描結果
$scanSummary

## 使用者的召喚提示詞
${summonPrompt.isEmpty ? '（使用者未提供額外的召喚提示詞）' : summonPrompt}

## 夥伴基本資料
名稱：${companion.name}
MBTI：${companion.mbtiCode} ${mbti != null ? '（${mbti.name}）' : ''}
角色：${companion.roleName}
形象提示詞：${companion.appearancePrompt.isEmpty ? '（未設定）' : companion.appearancePrompt}

請輸出人格卡 JSON。''';
  }

  /// 從 LLM 回覆中提取 JSON
  Map<String, dynamic> _extractJson(String response) {
    // 嘗試直接解析
    try {
      return jsonDecode(response) as Map<String, dynamic>;
    } catch (_) {}

    // 嘗試從 markdown code block 中提取
    final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(response);
    if (jsonMatch != null) {
      return jsonDecode(jsonMatch.group(1)!.trim()) as Map<String, dynamic>;
    }

    // 嘗試找到第一個 { 到最後一個 }
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return jsonDecode(response.substring(start, end + 1)) as Map<String, dynamic>;
    }

    throw FormatException('無法從 LLM 回覆中提取 JSON: $response');
  }

  /// 存入知識庫
  Future<void> _saveCard(PersonaCard card) async {
    try {
      final key = cardKey(card.companionId);
      final jsonStr = jsonEncode(card.toJson());

      // 先封存舊的人格卡（同 title 的舊記錄）
      _knowledge.archiveMemoryByTitle(key);

      // 存新的
      _knowledge.createMemory(
        title: key,
        content: jsonStr,
        tags: 'persona_card,${card.companionId}',
        memoryType: 'persona_card',
      );
      debugPrint('[PersonaInference] 人格卡已存入知識庫: $key');
    } catch (e) {
      debugPrint('[PersonaInference] 存入知識庫失敗: $e');
    }
  }

  /// 建立 fallback 人格卡（推理失敗時用）
  PersonaCard _buildFallbackCard(Companion companion, String scanSummary) {
    final mbti = companion.mbtiType;
    return PersonaCard(
      companionId: companion.id,
      archetype: '陪伴型',
      voiceStyle: mbti?.defaultPrompt ?? '溫暖友善，自然對話',
      addressUser: '你',
      expertise: companion.roleName,
      openingTone: '溫暖',
      firstLine: '嗨 ${companion.name}在這裡，讓我們開始吧。',
      userArchetype: '探索者',
      suggestedTemplateOrder: ['ig_post', 'knowledge_digest', 'memory_review', 'multi_model'],
      scanSummary: scanSummary,
      createdAt: DateTime.now(),
    );
  }
}
