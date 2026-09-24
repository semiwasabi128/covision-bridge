// Companion Voice Settings — 夥伴專屬語音設定資料模型
//
// [教練 Agent 2026-08-03] Phase 1 (C1)
//
// 設計理念：
// 每個夥伴有獨立的語音設定（聲音、語速、情緒、進階選項）
// 透過 SharedPreferences 持久化（Phase 1 簡單優先）
// 之後要遷移 SQLite 也很容易（把 JSON 拆成欄位）
//
// 對應的語音設定 UI 樹狀圖（Part 3.3）：
// 夥伴設定 > 語音設定
// ├─ 🎙️ 聲音選擇（primary/secondary/blend）
// ├─ ⚡ 語速（baseSpeed/emotionSpeedCoupling）
// ├─ 😊 情緒表達（enabled/sensitivity/enabledEmotions）
// └─ 進階（timeAware/emotionMemory）

import 'dart:convert';

/// 5 種 Kokoro 支援的情緒（與 python/kokoro_server.py 對齊）
const Set<String> kSupportedEmotions = {
  'amused',     // 開心
  'neutral',    // 中性
  'sleepiness', // 放鬆
  'anger',      // 憤怒
  'disgust',    // 厭惡
};

/// 情緒中文對照（給 UI 顯示用）
const Map<String, String> kEmotionLabels = {
  'amused': '開心',
  'neutral': '中性',
  'sleepiness': '放鬆',
  'anger': '憤怒',
  'disgust': '厭惡',
};

/// 8 個 Kokoro 中文聲音（與 KokoroTtsService 對齊）
const List<String> kAvailableVoices = [
  'zf_xiaoxiao',  // 小曉
  'zf_xiaobei',   // 小貝
  'zf_xiaoni',    // 小霓
  'zf_xiaoyi',    // 小藝
  'zm_yunjian',   // 雲健
  'zm_yunxi',     // 雲希
  'zm_yunxia',    // 雲夏
  'zm_yunyang',   // 雲揚
  // [小葵 2026-09-24 Blue 抓包①] MiniMax T2A 音色（H3 克隆/ttv- 設計音色）。
  // 之前不在此清單 → isValid false → load() 靜默回傳預設 zf_xiaoxiao
  // → 聲音分流永遠走 Kokoro（語音對話不是小葵的聲音）。ttv- 前綴的
  // 動態克隆音色用 startsWith 判定（見 isValid）。
  'xiaokui_video_voice', // 小葵（H3 影片同源聲音，pitch+1 定案）
];

/// 聲音中文對照
const Map<String, String> kVoiceLabels = {
  'zf_xiaoxiao': '小曉',
  'zf_xiaobei': '小貝',
  'zf_xiaoni': '小霓',
  'zf_xiaoyi': '小藝',
  'zm_yunjian': '雲健',
  'zm_yunxi': '雲希',
  'zm_yunxia': '雲夏',
  'zm_yunyang': '雲揚',
};

/// 夥伴語音設定
class CompanionVoiceSettings {
  /// 夥伴 ID
  final String companionId;

  // ─── 聲音選擇 ───
  /// 主聲音（必填，預設小曉）
  final String primaryVoice;

  /// 副聲音（混合用，null = 不混合）
  final String? secondaryVoice;

  /// 混合比例（0.0~1.0，primary 佔比）
  /// 1.0 = 全主聲音（無混合）
  /// 0.7 = 70% 主 + 30% 副
  /// 0.0 = 全副聲音
  final double voiceBlend;

  // ─── 語速 ───
  /// 基礎語速 0.5~2.0
  final double baseSpeed;

  /// 情緒連動語速（開心自動 +10%，困倦自動 -15%）
  final bool emotionSpeedCoupling;

  // ─── 情緒表達 ───
  /// 情緒總開關
  final bool emotionEnabled;

  /// 情緒敏感度 0.0~1.0
  /// sensitivity = 0.5 → confidence > 0.5 才採信
  /// sensitivity = 0.8 → confidence > 0.2 就採信
  final double emotionSensitivity;

  /// 可用情緒清單（5 種的子集）
  final Set<String> enabledEmotions;

  // ─── 進階 ───
  /// 時間感知（22:00-06:00 自動 sleepiness）
  final bool timeAware;

  /// 情緒記憶（跨對話情緒延續）
  final bool emotionMemory;

  const CompanionVoiceSettings({
    required this.companionId,
    this.primaryVoice = 'zf_xiaoxiao',
    this.secondaryVoice,
    this.voiceBlend = 1.0,
    this.baseSpeed = 1.0,
    this.emotionSpeedCoupling = true,
    this.emotionEnabled = true,
    this.emotionSensitivity = 0.5,
    this.enabledEmotions = const {'amused', 'neutral', 'sleepiness'},
    this.timeAware = true,
    this.emotionMemory = true,
  });

  /// 預設設定
  factory CompanionVoiceSettings.defaultsFor(String companionId) {
    return CompanionVoiceSettings(companionId: companionId);
  }

  // ─── 序列化 ───

  Map<String, dynamic> toJson() {
    return {
      'companionId': companionId,
      'primaryVoice': primaryVoice,
      'secondaryVoice': secondaryVoice,
      'voiceBlend': voiceBlend,
      'baseSpeed': baseSpeed,
      'emotionSpeedCoupling': emotionSpeedCoupling,
      'emotionEnabled': emotionEnabled,
      'emotionSensitivity': emotionSensitivity,
      'enabledEmotions': enabledEmotions.toList(),
      'timeAware': timeAware,
      'emotionMemory': emotionMemory,
    };
  }

  factory CompanionVoiceSettings.fromJson(Map<String, dynamic> json) {
    return CompanionVoiceSettings(
      companionId: json['companionId'] as String,
      primaryVoice: json['primaryVoice'] as String? ?? 'zf_xiaoxiao',
      secondaryVoice: json['secondaryVoice'] as String?,
      voiceBlend: (json['voiceBlend'] as num?)?.toDouble() ?? 1.0,
      baseSpeed: (json['baseSpeed'] as num?)?.toDouble() ?? 1.0,
      emotionSpeedCoupling: json['emotionSpeedCoupling'] as bool? ?? true,
      emotionEnabled: json['emotionEnabled'] as bool? ?? true,
      emotionSensitivity: (json['emotionSensitivity'] as num?)?.toDouble() ?? 0.5,
      enabledEmotions: (json['enabledEmotions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          {'amused', 'neutral', 'sleepiness'},
      timeAware: json['timeAware'] as bool? ?? true,
      emotionMemory: json['emotionMemory'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory CompanionVoiceSettings.fromJsonString(String jsonStr) {
    return CompanionVoiceSettings.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  // ─── 拷貝 ───

  CompanionVoiceSettings copyWith({
    String? primaryVoice,
    Object? secondaryVoice = _sentinel,
    double? voiceBlend,
    double? baseSpeed,
    bool? emotionSpeedCoupling,
    bool? emotionEnabled,
    double? emotionSensitivity,
    Set<String>? enabledEmotions,
    bool? timeAware,
    bool? emotionMemory,
  }) {
    return CompanionVoiceSettings(
      companionId: companionId,
      primaryVoice: primaryVoice ?? this.primaryVoice,
      secondaryVoice: identical(secondaryVoice, _sentinel)
          ? this.secondaryVoice
          : secondaryVoice as String?,
      voiceBlend: voiceBlend ?? this.voiceBlend,
      baseSpeed: baseSpeed ?? this.baseSpeed,
      emotionSpeedCoupling: emotionSpeedCoupling ?? this.emotionSpeedCoupling,
      emotionEnabled: emotionEnabled ?? this.emotionEnabled,
      emotionSensitivity: emotionSensitivity ?? this.emotionSensitivity,
      enabledEmotions: enabledEmotions ?? this.enabledEmotions,
      timeAware: timeAware ?? this.timeAware,
      emotionMemory: emotionMemory ?? this.emotionMemory,
    );
  }

  // ─── 邊界檢查 ───

  /// 驗證所有欄位在合理範圍
  bool get isValid {
    // [小葵 2026-09-24 Blue 抓包①] ttv- 前綴的動態克隆音色（MiniMax 設計音色）
    // 不在靜態清單——用前綴判定合法。
    bool voiceAllowed(String v) =>
        kAvailableVoices.contains(v) || v.startsWith('ttv-');
    if (!voiceAllowed(primaryVoice)) return false;
    if (secondaryVoice != null && !voiceAllowed(secondaryVoice!)) return false;
    if (voiceBlend < 0.0 || voiceBlend > 1.0) return false;
    if (baseSpeed < 0.5 || baseSpeed > 2.0) return false;
    if (emotionSensitivity < 0.0 || emotionSensitivity > 1.0) return false;
    if (!enabledEmotions.every((e) => kSupportedEmotions.contains(e))) return false;
    if (enabledEmotions.isEmpty) return false; // 至少要有一個情緒
    return true;
  }

  @override
  String toString() {
    return 'CompanionVoiceSettings(companion=$companionId, voice=$primaryVoice'
        '${secondaryVoice != null ? '+${secondaryVoice}@${voiceBlend.toStringAsFixed(2)}' : ''}'
        ', speed=${baseSpeed.toStringAsFixed(2)}'
        ', emotion=$emotionEnabled'
        '(${enabledEmotions.length} types, sens=${emotionSensitivity.toStringAsFixed(2)})'
        ')';
  }
}

/// copyWith 用的 sentinel
const Object _sentinel = Object();
