import '../models/agent_activity.dart';
import '../models/companion.dart';

class CompanionAssetManifestService {
  static const schema = 'bridge.companion-assets.v0.1';
  static const renderEngine = 'bridge.flutter-procedural.v0.1';

  const CompanionAssetManifestService();

  Map<String, dynamic> buildManifest({
    required String companionId,
    required String name,
    required String mbtiCode,
    required int seed,
    required String appearancePrompt,
    required String appearanceDescription,
    List<String> characterSheetPrompts = const [],
    List<CompanionAssetStateSpec>? assetStates,
    String? primaryImagePath,
    String? primaryAnimationPath,
  }) {
    final states = assetStates == null
        ? _stateSpecs(
            companionId: companionId,
            name: name,
            mbtiCode: mbtiCode,
            seed: seed,
            characterSheetPrompts: characterSheetPrompts,
          )
        : [
            for (var index = 0; index < assetStates.length; index++)
              assetStates[index].toManifestState(
                assetId: _assetId(
                  companionId,
                  'state_${assetStates[index].stateId}',
                ),
                mbtiCode: mbtiCode,
                seed: seed + index,
                fallbackPrompt: '$name 的${assetStates[index].label}狀態角色圖',
              ),
          ];

    return {
      'schema': schema,
      'renderEngine': renderEngine,
      'version': '0.1.0',
      'companionId': companionId,
      'name': name,
      'seed': seed,
      'appearance': {
        'mbtiCode': mbtiCode,
        'prompt': appearancePrompt,
        'description': appearanceDescription,
      },
      'primaryAvatar': _assetId(companionId, 'avatar'),
      'primaryAvatarImagePath': primaryImagePath ?? '',
      'primaryAvatarAnimation': {
        'assetId': _assetId(companionId, 'avatar_animation'),
        'status':
            (primaryAnimationPath == null ||
                primaryAnimationPath.trim().isEmpty)
            ? 'planned'
            : 'ready',
        'formatPreference': [
          'bridge_motion',
          'animated_webp',
          'gif',
          'png_sequence',
        ],
        'path': primaryAnimationPath ?? '',
      },
      'states': states,
      'desktop': {
        'idleLoop': _assetId(companionId, 'state_idle'),
        'walkCycle': _assetId(companionId, 'state_wandering'),
        'workLoop': _assetId(companionId, 'state_reading'),
        'bridgeLoop': _assetId(companionId, 'state_bridging'),
        'celebrationLoop': _assetId(companionId, 'state_celebrating'),
      },
      'exportTargets': [
        'flutter_canvas',
        'png_sequence',
        'animated_webp',
        'gif',
        'companion_pack',
      ],
      'includedAssets': [
        _assetId(companionId, 'avatar'),
        if (primaryAnimationPath != null &&
            primaryAnimationPath.trim().isNotEmpty)
          _assetId(companionId, 'avatar_animation'),
        for (final state in states) state['id'],
        for (final state in states)
          if ((state['animation'] as Map<String, dynamic>?)?['path']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true)
            (state['animation'] as Map<String, dynamic>)['assetId'],
      ],
    };
  }

  Map<String, dynamic> buildForCompanion(
    Companion companion, {
    List<CompanionAssetStateSpec>? assetStates,
    String? primaryImagePath,
    String? primaryAnimationPath,
  }) {
    final resolvedAssetStates =
        assetStates ??
        (companion.stateImagePaths.isEmpty &&
                companion.stateAnimationPaths.isEmpty
            ? null
            : _assetStatesFromCompanion(companion));
    return buildManifest(
      companionId: companion.id,
      name: companion.name,
      mbtiCode: companion.mbtiCode,
      seed: 0, // [教練 Agent 2026-08-04] appearanceSeed 已刪除，固定為 0
      appearancePrompt: companion.appearancePrompt,
      appearanceDescription: companion.appearanceDescription,
      characterSheetPrompts: const [], // [教練 Agent 2026-08-04] appearanceHistory 已刪除
      assetStates: resolvedAssetStates,
      primaryImagePath: primaryImagePath ?? companion.avatarImagePath,
      primaryAnimationPath:
          primaryAnimationPath ?? companion.avatarAnimationPath,
    );
  }

  List<CompanionAssetStateSpec> _assetStatesFromCompanion(Companion companion) {
    final definitions =
        <
          String,
          ({String label, AgentCompanionMood mood, AgentCompanionAction action})
        >{
          'idle': (
            label: '待機',
            mood: AgentCompanionMood.idle,
            action: AgentCompanionAction.standing,
          ),
          'reading': (
            label: '閱讀',
            mood: AgentCompanionMood.focused,
            action: AgentCompanionAction.reading,
          ),
          'writing': (
            label: '編寫中',
            mood: AgentCompanionMood.focused,
            action: AgentCompanionAction.reading,
          ),
          'stuck': (
            label: '卡住了',
            mood: AgentCompanionMood.waiting,
            action: AgentCompanionAction.standing,
          ),
          'idea': (
            label: '有好點子了',
            mood: AgentCompanionMood.proud,
            action: AgentCompanionAction.pointing,
          ),
          'pointing': (
            label: '指路',
            mood: AgentCompanionMood.routing,
            action: AgentCompanionAction.pointing,
          ),
          'bridging': (
            label: '橋接',
            mood: AgentCompanionMood.bridging,
            action: AgentCompanionAction.spinning,
          ),
          'celebrating': (
            label: '慶祝',
            mood: AgentCompanionMood.proud,
            action: AgentCompanionAction.bouncing,
          ),
          'wandering': (
            label: '漫遊',
            mood: AgentCompanionMood.curious,
            action: AgentCompanionAction.wandering,
          ),
        };
    final stateIds = {
      ...companion.stateImagePaths.keys,
      ...companion.stateAnimationPaths.keys,
    };
    return [
      for (final stateId in stateIds)
        CompanionAssetStateSpec(
          stateId: stateId,
          label: definitions[stateId]?.label ?? stateId,
          kind: definitions.containsKey(stateId) ? 'core' : 'custom',
          behavior: '依照 ${definitions[stateId]?.label ?? stateId} 狀態行動。',
          expression: '依照 ${definitions[stateId]?.label ?? stateId} 狀態表情。',
          mood: definitions[stateId]?.mood ?? AgentCompanionMood.curious,
          action:
              definitions[stateId]?.action ?? AgentCompanionAction.wandering,
          trigger: CompanionAssetTriggerRule(
            keywords: const [],
            stages: [
              (definitions[stateId]?.mood ?? AgentCompanionMood.curious).name,
              (definitions[stateId]?.action ?? AgentCompanionAction.wandering)
                  .name,
            ],
            intentTags: [stateId],
            scene: '依照 ${definitions[stateId]?.label ?? stateId} 狀態觸發。',
            priority: 50,
            cooldownSeconds: 10,
            fallbackStateId: 'idle',
          ),
          imagePath: companion.stateImagePaths[stateId],
          animationPath: companion.stateAnimationPaths[stateId],
        ),
    ];
  }

  List<Map<String, dynamic>> _stateSpecs({
    required String companionId,
    required String name,
    required String mbtiCode,
    required int seed,
    required List<String> characterSheetPrompts,
  }) {
    final stages = [
      // [教練 Agent 2026-07-03] 刪除 idle（待機）— 主形象圖即為待機圖，不額外生成
      _VisualStateSpec(
        key: 'reading',
        label: '閱讀',
        kind: 'core',
        behavior: '整理上下文與記憶，像在翻閱筆記或光頁。',
        expression: '專注、沉穩、思考中。',
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        trigger: CompanionAssetTriggerRule(
          stages: ['context'],
          intentTags: ['reading', 'research', 'summarize'],
          scene: '正在讀取、整理、摘要或壓縮上下文時。',
          priority: 50,
        ),
      ),
      _VisualStateSpec(
        key: 'writing',
        label: '編寫中',
        kind: 'core',
        behavior: '用電腦或筆記本把想法整理成文字、程式或草稿。',
        expression: '努力的編寫樣子。',
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        trigger: CompanionAssetTriggerRule(
          stages: ['composing'],
          intentTags: ['writing', 'coding', 'drafting', 'execution'],
          scene: '正在寫程式、寫文案、寫草稿或執行內容產出時。',
          priority: 70,
        ),
      ),
      _VisualStateSpec(
        key: 'stuck',
        label: '卡住了',
        kind: 'core',
        behavior: '苦惱中雙手交在胸前，正在重新思考問題。',
        expression: '苦惱中的樣子。',
        mood: AgentCompanionMood.waiting,
        action: AgentCompanionAction.standing,
        trigger: CompanionAssetTriggerRule(
          stages: ['waiting'],
          intentTags: ['blocked', 'waiting', 'error', 'needs_input'],
          scene: '遇到卡點、等待外部條件、需要使用者補充，或重複錯誤循環時。',
          priority: 85,
        ),
      ),
      _VisualStateSpec(
        key: 'idea',
        label: '有好點子了',
        kind: 'core',
        behavior: '一隻手指向上方，上方有一個發亮的燈泡。',
        expression: '微笑、驚喜、調皮。',
        mood: AgentCompanionMood.proud,
        action: AgentCompanionAction.pointing,
        trigger: CompanionAssetTriggerRule(
          stages: ['composing'],
          intentTags: ['idea', 'insight', 'solution', 'breakthrough'],
          scene: '有好主意、好點子、好方法出現，或找到正確方向時。',
          priority: 88,
        ),
      ),
      _VisualStateSpec(
        key: 'pointing',
        label: '指路',
        kind: 'core',
        behavior: '伸手指向下一座橋或下一個任務方向。',
        expression: '清楚、有方向感、帶著鼓勵。',
        mood: AgentCompanionMood.routing,
        action: AgentCompanionAction.pointing,
        trigger: CompanionAssetTriggerRule(
          stages: ['routing'],
          intentTags: ['route', 'next_step', 'guide'],
          scene: '正在判斷下一步、選工具或引導使用者時。',
          priority: 60,
        ),
      ),
      _VisualStateSpec(
        key: 'bridging',
        label: '橋接',
        kind: 'core',
        behavior: '正在連接外部能力，身邊有穩定發光或能量流。',
        expression: '認真、可靠、正在施展能力。',
        mood: AgentCompanionMood.bridging,
        action: AgentCompanionAction.spinning,
        trigger: CompanionAssetTriggerRule(
          stages: ['bridge'],
          intentTags: ['tool_call', 'api', 'external_service'],
          scene: '正在呼叫 API、連接外部服務或執行橋接任務時。',
          priority: 80,
        ),
      ),
      _VisualStateSpec(
        key: 'celebrating',
        label: '慶祝',
        kind: 'core',
        behavior: '任務完成後小幅跳起、揮手或發光。',
        expression: '開心、得意、像完成一件好事。',
        mood: AgentCompanionMood.proud,
        action: AgentCompanionAction.bouncing,
        trigger: CompanionAssetTriggerRule(
          keywords: ['完成', '成功', '太棒了'],
          stages: ['completed', 'composing'],
          intentTags: ['celebration', 'success'],
          scene: '任務完成、使用者稱讚或需要慶祝回饋時。',
          priority: 90,
          cooldownSeconds: 20,
        ),
      ),
      _VisualStateSpec(
        key: 'wandering',
        label: '漫遊',
        kind: 'core',
        behavior: '在桌面自由走動，帶一點俏皮小動作。',
        expression: '好奇、輕鬆、正在探索。',
        mood: AgentCompanionMood.curious,
        action: AgentCompanionAction.wandering,
        trigger: CompanionAssetTriggerRule(
          stages: ['understanding', 'idle'],
          intentTags: ['explore', 'casual'],
          scene: '平時陪伴、輕鬆探索或剛開始理解使用者意圖時。',
          priority: 20,
        ),
      ),
    ];

    return [
      for (var index = 0; index < stages.length; index++)
        {
          'id': _assetId(companionId, 'state_${stages[index].key}'),
          'stateId': stages[index].key,
          'kind': stages[index].kind,
          'label': stages[index].label,
          'mbtiCode': mbtiCode,
          'seed': seed + index,
          'mood': stages[index].mood.name,
          'action': stages[index].action.name,
          'behavior': stages[index].behavior,
          'expression': stages[index].expression,
          'trigger': stages[index].trigger.toJson(),
          'prompt': index < characterSheetPrompts.length
              ? characterSheetPrompts[index]
              : '$name 的${stages[index].label}狀態角色圖。'
                  '構圖指示：${stateImagePoseGuides[stages[index].key] ?? ''}',
          'still': {
            'assetId': _assetId(companionId, 'state_${stages[index].key}'),
            'format': 'png',
            'path': '',
          },
          'animation': {
            'assetId': _assetId(
              companionId,
              'state_${stages[index].key}_animation',
            ),
            'status': 'planned',
            'formatPreference': [
              'bridge_motion',
              'animated_webp',
              'gif',
              'png_sequence',
            ],
            'path': '',
            'prompt':
                '$name 的${stages[index].label}狀態循環動圖：${stages[index].behavior} ${stages[index].expression}。透明背景，短循環，保持同一角色。',
          },
          'recommendedSize': {'width': 256, 'height': 256},
        },
    ];
  }

  String _assetId(String companionId, String key) {
    return 'asset.$companionId.$key';
  }
}

class _VisualStateSpec {
  final String key;
  final String label;
  final String kind;
  final String behavior;
  final String expression;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final CompanionAssetTriggerRule trigger;

  const _VisualStateSpec({
    required this.key,
    required this.label,
    required this.kind,
    required this.behavior,
    required this.expression,
    required this.mood,
    required this.action,
    required this.trigger,
  });
}

class CompanionAssetStateSpec {
  final String stateId;
  final String label;
  final String kind;
  final String behavior;
  final String expression;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final CompanionAssetTriggerRule trigger;
  final String? imagePath;
  final String? animationPath;
  final String? animationMotion;
  final String? animationPrompt;
  final String? prompt;

  const CompanionAssetStateSpec({
    required this.stateId,
    required this.label,
    required this.kind,
    required this.behavior,
    required this.expression,
    required this.mood,
    required this.action,
    required this.trigger,
    this.imagePath,
    this.animationPath,
    this.animationMotion,
    this.animationPrompt,
    this.prompt,
  });

  Map<String, dynamic> toManifestState({
    required String assetId,
    required String mbtiCode,
    required int seed,
    required String fallbackPrompt,
  }) {
    return {
      'id': assetId,
      'stateId': stateId,
      'kind': kind,
      'label': label,
      'mbtiCode': mbtiCode,
      'seed': seed,
      'mood': mood.name,
      'action': action.name,
      'behavior': behavior,
      'expression': expression,
      if (animationMotion != null && animationMotion!.trim().isNotEmpty)
        'animationMotion': animationMotion,
      'trigger': trigger.toJson(),
      'prompt': (prompt == null || prompt!.trim().isEmpty)
          ? fallbackPrompt
          : prompt,
      'imagePath': ?imagePath,
      'still': {'assetId': assetId, 'format': 'png', 'path': imagePath ?? ''},
      'animation': {
        'assetId': '${assetId}_animation',
        'status': (animationPath == null || animationPath!.trim().isEmpty)
            ? 'planned'
            : 'ready',
        'formatPreference': [
          'bridge_motion',
          'animated_webp',
          'gif',
          'png_sequence',
        ],
        'path': animationPath ?? '',
        'prompt': (animationPrompt == null || animationPrompt!.trim().isEmpty)
            ? '$fallbackPrompt 的短循環動圖，透明背景，保持同一角色。'
            : animationPrompt,
      },
      'recommendedSize': {'width': 512, 'height': 512},
    };
  }
}

class CompanionAssetTriggerRule {
  final List<String> keywords;
  final List<String> stages;
  final List<String> intentTags;
  final String scene;
  final int priority;
  final int cooldownSeconds;
  final String fallbackStateId;

  const CompanionAssetTriggerRule({
    this.keywords = const [],
    this.stages = const [],
    this.intentTags = const [],
    this.scene = '',
    this.priority = 50,
    this.cooldownSeconds = 12,
    this.fallbackStateId = 'idle',
  });

  Map<String, dynamic> toJson() {
    return {
      'keywords': keywords,
      'stages': stages,
      'intentTags': intentTags,
      'scene': scene,
      'priority': priority,
      'cooldownSeconds': cooldownSeconds,
      'fallbackStateId': fallbackStateId,
    };
  }
}
