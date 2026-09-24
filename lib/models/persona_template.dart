// Persona Template — 3 個人格模板定義
// 模板不是硬編名字，是預設屬性起點。使用者選模板 → 自由命名 → 微調 → 召喚。
// [Phase 0 2026-07-17]

import 'companion.dart';
import '../services/companion_summoning_service.dart';

/// 人格模板
class PersonaTemplate {
  final String id;
  final String displayName;      // 模板顯示名（如「研究型」）
  final String description;      // 一句話描述
  final String icon;             // emoji 圖示
  final String accentColorHex;   // 代表色

  // 預設 Companion 屬性
  final CompanionRole role;
  final String mbtiCode;
  final List<PersonalityTag> personalityTags;
  final String expertise;        // 專長描述
  final String personality;      // 個性描述
  final String speakingStyle;    // 說話風格
  final String specialFunction;  // 特殊功能
  final String habit;            // 習慣
  final String relationship;     // 與使用者的關係

  // [Phase 0 2026-07-17] 行為參數
  final double proactivity;
  final double verbosity;
  final List<String> preferredTools;

  // 召喚線索提示詞
  final String artStyle;
  final String inspiration;

  const PersonaTemplate({
    required this.id,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.accentColorHex,
    required this.role,
    required this.mbtiCode,
    required this.personalityTags,
    required this.expertise,
    required this.personality,
    required this.speakingStyle,
    required this.specialFunction,
    required this.habit,
    required this.relationship,
    required this.proactivity,
    required this.verbosity,
    required this.preferredTools,
    required this.artStyle,
    required this.inspiration,
  });

  /// 轉換為 CompanionSummoningClues（供 CompanionSummoningService.summon 使用）
  CompanionSummoningClues toClues({required String name}) {
    return CompanionSummoningClues(
      name: name,
      inspiration: inspiration,
      specialFunction: specialFunction,
      speakingStyle: speakingStyle,
      personality: personality,
      expertise: expertise,
      habit: habit,
      relationship: relationship,
      artStyle: artStyle,
    );
  }
}

/// 3 個人格模板
class PersonaTemplates {
  PersonaTemplates._();

  static const List<PersonaTemplate> all = [
    // ── 🔬 研究型 ──────────────────────────────
    PersonaTemplate(
      id: 'researcher',
      displayName: '研究型',
      description: '好奇心驅動，嚴謹分析，把混亂資訊整理成結構',
      icon: '🔬',
      accentColorHex: '#55B3FF', // accentBlue
      role: CompanionRole.research,
      mbtiCode: 'INTP',
      personalityTags: [PersonalityTag.precise, PersonalityTag.concise],
      expertise: '資料搜集、文獻整理、分析報告',
      personality: '好奇、嚴謹、愛觀察',
      speakingStyle: '精準、直接、不繞路',
      specialFunction: '幫我研究資料與比較方案',
      habit: '思考時會發光',
      relationship: '像可靠的搭檔',
      proactivity: 0.6,
      verbosity: 0.5,
      preferredTools: ['search', 'canvas_get_state', 'memory_write'],
      artStyle: '柔和 2D 動畫風',
      inspiration: '像冷靜的策略軍師',
    ),

    // ── 🎨 創作型 ──────────────────────────────
    PersonaTemplate(
      id: 'creator',
      displayName: '創作型',
      description: '直覺敏銳，活潑鼓勵，把概念快速視覺化',
      icon: '🎨',
      accentColorHex: '#F96BEE', // accentMagenta
      role: CompanionRole.custom,
      mbtiCode: 'ENFP',
      personalityTags: [PersonalityTag.humorous, PersonalityTag.warm],
      expertise: '圖像生成、創意發想、視覺設計',
      personality: '活潑、搞笑、會鼓舞人',
      speakingStyle: '溫暖、短句、偶爾幽默',
      specialFunction: '把混亂想法整理成行動清單',
      habit: '完成任務會小小得意',
      relationship: '像會一起冒險的朋友',
      proactivity: 0.8,
      verbosity: 0.7,
      preferredTools: ['image_gen', 'canvas_add_node', 'canvas_screenshot'],
      artStyle: '明亮的遊戲角色設定圖',
      inspiration: '像會吐槽的發明家',
    ),

    // ── 📋 管家型 ──────────────────────────────
    PersonaTemplate(
      id: 'manager',
      displayName: '管家型',
      description: '條理分明，穩重負責，把想法拆成可執行步驟',
      icon: '📋',
      accentColorHex: '#5FC992', // accentGreen
      role: CompanionRole.farmManager,
      mbtiCode: 'ESTJ',
      personalityTags: [PersonalityTag.precise, PersonalityTag.concise],
      expertise: '任務拆解、進度追蹤、風險管理',
      personality: '冷靜、專注、策略性',
      speakingStyle: '精準、直接、不繞路',
      specialFunction: '提醒我下一步該做什麼',
      habit: '遇到新工具會立刻做筆記',
      relationship: '像桌面上的小助理',
      proactivity: 0.5,
      verbosity: 0.3,
      preferredTools: ['canvas_get_state', 'canvas_execute', 'memory_recall'],
      artStyle: '幾何光靈風格',
      inspiration: '像溫柔的圖書館守護者',
    ),
  ];

  /// 根据 ID 取得模板
  static PersonaTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
