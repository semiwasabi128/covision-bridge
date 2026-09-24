import 'dart:math';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import 'appearance_generator.dart';

class CompanionSummoningClues {
  final String name;
  final String inspiration;
  final String specialFunction;
  final String speakingStyle;
  final String personality;
  final String expertise;
  final String habit;
  final String relationship;
  final String artStyle;
  final String species;
  final String freeform;
  final List<String> referenceImagePaths;

  const CompanionSummoningClues({
    this.name = '',
    this.inspiration = '',
    this.specialFunction = '',
    this.speakingStyle = '',
    this.personality = '',
    this.expertise = '',
    this.habit = '',
    this.relationship = '',
    this.artStyle = '',
    this.species = '',
    this.freeform = '',
    this.referenceImagePaths = const [],
  });

  bool get hasAnySignal =>
      [
        name,
        inspiration,
        specialFunction,
        speakingStyle,
        personality,
        expertise,
        habit,
        relationship,
        artStyle,
        species,
        freeform,
      ].any((value) => value.trim().isNotEmpty) ||
      referenceImagePaths.isNotEmpty;
}

class CompanionSummoningCandidate {
  final String name;
  final String mbtiCode;
  final CompanionRole role;
  final List<PersonalityTag> personalityTags;
  final int seed;
  final String appearancePrompt;
  final String appearanceDescription;
  final String? generatedImagePath;
  final String? visualGenerationMessage;
  final Map<String, String> generatedSheetImagePaths;
  final Map<String, String> sheetGenerationMessages;
  final List<String> characterSheetPrompts;

  const CompanionSummoningCandidate({
    required this.name,
    required this.mbtiCode,
    required this.role,
    required this.personalityTags,
    required this.seed,
    required this.appearancePrompt,
    required this.appearanceDescription,
    this.generatedImagePath,
    this.visualGenerationMessage,
    this.generatedSheetImagePaths = const {},
    this.sheetGenerationMessages = const {},
    required this.characterSheetPrompts,
  });

  CompanionSummoningCandidate copyWith({
    String? generatedImagePath,
    String? visualGenerationMessage,
    Map<String, String>? generatedSheetImagePaths,
    Map<String, String>? sheetGenerationMessages,
  }) {
    return CompanionSummoningCandidate(
      name: name,
      mbtiCode: mbtiCode,
      role: role,
      personalityTags: personalityTags,
      seed: seed,
      appearancePrompt: appearancePrompt,
      appearanceDescription: appearanceDescription,
      generatedImagePath: generatedImagePath ?? this.generatedImagePath,
      visualGenerationMessage:
          visualGenerationMessage ?? this.visualGenerationMessage,
      generatedSheetImagePaths:
          generatedSheetImagePaths ?? this.generatedSheetImagePaths,
      sheetGenerationMessages:
          sheetGenerationMessages ?? this.sheetGenerationMessages,
      characterSheetPrompts: characterSheetPrompts,
    );
  }
}

class CompanionSummoningService {
  CompanionSummoningService({AppearanceGenerator? appearanceGenerator})
    : _appearanceGenerator =
          appearanceGenerator ?? getDefaultAppearanceGenerator();

  final AppearanceGenerator _appearanceGenerator;

  CompanionSummoningCandidate summon(
    CompanionSummoningClues clues, {
    int? salt,
  }) {
    final seed = _seedFor(clues, salt: salt);
    final mbti = _mbtiFor(clues, seed);
    final prompt = _buildAppearancePrompt(clues);
    final name = clues.name.trim().isEmpty
        ? _fallbackName(clues, seed)
        : clues.name.trim();

    return CompanionSummoningCandidate(
      name: name,
      mbtiCode: mbti.code,
      role: _roleFor(clues),
      personalityTags: _tagsFor(clues),
      seed: seed,
      appearancePrompt: prompt,
      appearanceDescription: _appearanceGenerator.generateDescription(
        mbti,
        prompt,
        seed,
      ),
      characterSheetPrompts: _buildCharacterSheetPrompts(clues, name, prompt),
    );
  }

  CompanionSummoningClues randomClues({int? seed}) {
    final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    String pick(List<String> values) => values[rng.nextInt(values.length)];

    return CompanionSummoningClues(
      name: pick(_names),
      inspiration: pick(_inspirations),
      specialFunction: pick(_specialFunctions),
      speakingStyle: pick(_speakingStyles),
      personality: pick(_personalities),
      expertise: pick(_expertise),
      habit: pick(_habits),
      relationship: pick(_relationships),
      artStyle: pick(_artStyles),
      species: pick(_species),
      freeform: pick(_freeforms),
    );
  }

  int _seedFor(CompanionSummoningClues clues, {int? salt}) {
    final text = [
      clues.name,
      clues.inspiration,
      clues.specialFunction,
      clues.speakingStyle,
      clues.personality,
      clues.expertise,
      clues.habit,
      clues.relationship,
      clues.artStyle,
      clues.species,
      clues.freeform,
      clues.referenceImagePaths.join(','),
      salt?.toString() ?? '',
    ].join('|');

    var hash = 0;
    for (final unit in text.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % 10000;
  }

  MBTIType _mbtiFor(CompanionSummoningClues clues, int seed) {
    final text =
        '${clues.personality} ${clues.speakingStyle} ${clues.relationship} ${clues.freeform}';
    String code;
    if (_containsAny(text, ['策略', '冷靜', '精準', '分析'])) {
      code = 'INTJ';
    } else if (_containsAny(text, ['溫暖', '照顧', '守護', '陪伴'])) {
      code = 'ISFJ';
    } else if (_containsAny(text, ['幽默', '活潑', '搞笑', '表演'])) {
      code = 'ESFP';
    } else if (_containsAny(text, ['創意', '夢幻', '想像', '自由'])) {
      code = 'INFP';
    } else if (_containsAny(text, ['行動', '衝刺', '冒險', '快節奏'])) {
      code = 'ESTP';
    } else {
      code = MBTIType.allTypes[seed % MBTIType.allTypes.length].code;
    }
    return MBTIType.fromCode(code) ?? MBTIType.allTypes.first;
  }

  CompanionRole _roleFor(CompanionSummoningClues clues) {
    final text =
        '${clues.specialFunction} ${clues.expertise} ${clues.freeform}';
    if (_containsAny(text, ['研究', '搜尋', '分析', '資料'])) {
      return CompanionRole.research;
    }
    if (_containsAny(text, ['寫作', '文案', '故事', '文件'])) {
      return CompanionRole.writing;
    }
    if (_containsAny(text, ['翻譯', '語言', '英文', '日文'])) {
      return CompanionRole.translation;
    }
    if (_containsAny(text, ['農場', '植物', '生態', '田'])) {
      return CompanionRole.farmManager;
    }
    return CompanionRole.custom;
  }

  List<PersonalityTag> _tagsFor(CompanionSummoningClues clues) {
    final text =
        '${clues.personality} ${clues.speakingStyle} ${clues.freeform}';
    final tags = <PersonalityTag>{};
    if (_containsAny(text, ['簡潔', '短句', '俐落'])) {
      tags.add(PersonalityTag.concise);
    }
    if (_containsAny(text, ['詳細', '完整', '一步一步'])) {
      tags.add(PersonalityTag.detailed);
    }
    if (_containsAny(text, ['幽默', '搞笑', '吐槽'])) {
      tags.add(PersonalityTag.humorous);
    }
    if (_containsAny(text, ['精準', '嚴謹', '專業'])) {
      tags.add(PersonalityTag.precise);
    }
    if (_containsAny(text, ['溫暖', '溫柔', '陪伴'])) {
      tags.add(PersonalityTag.warm);
    }
    if (_containsAny(text, ['直接', '直率', '不繞路'])) {
      tags.add(PersonalityTag.direct);
    }
    return tags.isEmpty ? [PersonalityTag.warm] : tags.toList();
  }

  String _buildAppearancePrompt(CompanionSummoningClues clues) {
    final parts = <String>[
      if (clues.inspiration.trim().isNotEmpty)
        '人物名人靈感：${clues.inspiration.trim()}',
      if (clues.specialFunction.trim().isNotEmpty)
        '特殊功能：${clues.specialFunction.trim()}',
      if (clues.speakingStyle.trim().isNotEmpty)
        '說話風格：${clues.speakingStyle.trim()}',
      if (clues.personality.trim().isNotEmpty) '個性：${clues.personality.trim()}',
      if (clues.expertise.trim().isNotEmpty) '專長：${clues.expertise.trim()}',
      if (clues.habit.trim().isNotEmpty) '習慣：${clues.habit.trim()}',
      if (clues.relationship.trim().isNotEmpty)
        '與使用者的關係：${clues.relationship.trim()}',
      if (clues.artStyle.trim().isNotEmpty) '畫風：${clues.artStyle.trim()}',
      if (clues.species.trim().isNotEmpty) '種族：${clues.species.trim()}',
      if (clues.freeform.trim().isNotEmpty) '自由敘述：${clues.freeform.trim()}',
      if (clues.referenceImagePaths.isNotEmpty)
        '使用者已上傳 ${clues.referenceImagePaths.length} 張視覺參考圖，請只把 reference images 當成低權重素材庫，用來抽取少量輪廓、配色、服裝符號或種族線索；最終畫風、個性、角色氣質與行為必須由上方文字線索主導，並生成全新的 AI 夥伴角色。',
    ];
    if (parts.isEmpty) {
      return '獨一無二的橋樑 Agent 夥伴，帶有驚喜感、可愛但可靠。';
    }
    return parts.join('；');
  }

  List<String> _buildCharacterSheetPrompts(
    CompanionSummoningClues clues,
    String name,
    String basePrompt,
  ) {
    final style = clues.artStyle.trim().isEmpty ? '乾淨角色設定圖' : clues.artStyle;
    // [教練 Agent 2026-07-03] 狀態圖多樣性：每個狀態加獨特姿勢/構圖/視角描述
    // 角色特徵（臉、服裝、配色）由 basePrompt + reference image 鎖定，
    // 但姿勢、構圖、視角、場景氛圍由 poseGuide 主導，確保 8 張圖有明顯差異
    return [
      '角色設定圖：$name，正面、側面、背面，$style，$basePrompt',
      for (final stage in agentActivityStages)
        '${stage.shortLabel}階段表情與動作：$name，${stage.label}，${stage.detail}，$style。'
        '構圖指示：${stateImagePoseGuides[_stageToPoseKey(stage.shortLabel)] ?? ''}',
      '桌面自由行為圖組：$name，自由走動、原地彈跳、指路、翻閱記憶、橋接發光，$style',
    ];
  }

  /// [教練 Agent 2026-07-03] 把 agentActivityStages 的 shortLabel 對應到 poseGuide key
  /// stages 清單：理解→reading, 上下文→reading, 路由→pointing,
  /// 回應→wandering, 整理→writing, 橋樑→bridging
  static String _stageToPoseKey(String shortLabel) {
    switch (shortLabel) {
      case '理解':
        return 'wandering';
      case '上下文':
        return 'reading';
      case '路由':
        return 'pointing';
      case '回應':
        return 'stuck';
      case '整理':
        return 'writing';
      case '橋樑':
        return 'bridging';
      default:
        return 'wandering';
    }
  }

  String _fallbackName(CompanionSummoningClues clues, int seed) {
    final species = clues.species.trim();
    if (species.isNotEmpty) {
      return '$species ${seed.toString().padLeft(4, '0')}';
    }
    return _names[seed % _names.length];
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any((needle) => text.contains(needle));
  }

  static const _names = ['霧橋', '星槌', '珀光', '迴音', '檸核', '墨羽'];

  static const _inspirations = [
    '像溫柔的圖書館守護者',
    '像會吐槽的發明家',
    '像冷靜的策略軍師',
    '像小型舞台魔術師',
  ];

  static const _specialFunctions = [
    '幫我串接新的 AI 服務',
    '把混亂想法整理成行動清單',
    '替我研究資料與比較方案',
    '提醒我下一步該做什麼',
  ];

  static const _speakingStyles = [
    '溫暖、短句、偶爾幽默',
    '精準、直接、不繞路',
    '像朋友一樣陪我推進',
    '有一點神秘但很好懂',
  ];

  static const _personalities = [
    '好奇、可靠、愛觀察',
    '冷靜、專注、策略性',
    '活潑、搞笑、會鼓舞人',
    '溫柔、守護、細心',
  ];

  static const _expertise = ['AI 工具導航', '寫作與規格整理', '研究分析', '創意發想'];

  static const _habits = ['思考時會發光', '完成任務會小小得意', '閒著時會在桌面散步', '遇到新工具會立刻做筆記'];

  static const _relationships = [
    '像可靠的搭檔',
    '像桌面上的小助理',
    '像會一起冒險的朋友',
    '像守護我的替身使者',
  ];

  static const _artStyles = ['明亮的遊戲角色設定圖', '柔和 2D 動畫風', '幾何光靈風格', '像素桌面寵物風格'];

  static const _species = ['光靈', '機械妖精', '星塵使者', '橋樑守護獸'];

  static const _freeforms = [
    '平時有點調皮，但工作時非常可靠。',
    '像抽到稀有角色一樣，有獨特輪廓和標誌物。',
    '能理解我的偏好，幫我跨過複雜設定。',
    '看起來小小的，但能連接很多巨大的 AI 服務。',
  ];
}
