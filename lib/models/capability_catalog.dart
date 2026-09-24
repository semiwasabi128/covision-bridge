import 'bridge_action.dart';

enum CapabilityKind {
  search,
  vision,
  image,
  music,
  video,
  document,
  desktop,
  animation,
  custom,
}

extension CapabilityKindLabel on CapabilityKind {
  String get label {
    switch (this) {
      case CapabilityKind.search:
        return '搜尋與即時資料';
      case CapabilityKind.vision:
        return '圖片辨識';
      case CapabilityKind.image:
        return '圖像生成';
      case CapabilityKind.music:
        return '音樂生成';
      case CapabilityKind.video:
        return '影片生成';
      case CapabilityKind.document:
        return '文件產出';
      case CapabilityKind.desktop:
        return '桌面與本機檔案';
      case CapabilityKind.animation:
        return '角色動態';
      case CapabilityKind.custom:
        return '自訂能力';
    }
  }

  static CapabilityKind fromName(String? value) {
    return CapabilityKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => CapabilityKind.custom,
    );
  }
}

enum CapabilityAvailability { ready, needsSetup, unsupported, planned }

extension CapabilityAvailabilityLabel on CapabilityAvailability {
  String get label {
    switch (this) {
      case CapabilityAvailability.ready:
        return '可用';
      case CapabilityAvailability.needsSetup:
        return '需開通';
      case CapabilityAvailability.unsupported:
        return '待接入';
      case CapabilityAvailability.planned:
        return '預留';
    }
  }
}

class CapabilityDefinition {
  final String id;
  final String name;
  final CapabilityKind kind;
  final BridgeActionType actionType;
  final String description;
  final List<String> triggerPhrases;
  final List<String> providers;
  final String setupRoute;
  final String brainRoom;
  final String costNote;
  final String speedNote;
  final String qualityNote;
  final String inputFormat;
  final String outputFormat;
  final String evidenceKind;
  final String v0Scope;
  final String adapterContract;
  final String communityPluginNote;
  final List<String> setupSteps;
  final List<String> officialEntryHints;
  final bool builtIn;
  final bool requiresDesktopBridge;

  const CapabilityDefinition({
    required this.id,
    required this.name,
    required this.kind,
    required this.actionType,
    required this.description,
    required this.triggerPhrases,
    required this.providers,
    required this.setupRoute,
    required this.brainRoom,
    this.costNote = '依 provider 計費',
    this.speedNote = '依 provider 與任務大小而定',
    this.qualityNote = '可由使用者回饋逐步校準',
    this.inputFormat = '自然語言需求',
    this.outputFormat = '文字或媒體結果',
    this.evidenceKind = 'bridge_result',
    this.v0Scope = '能力登錄、缺口引導、任務回流與結果證據。',
    this.adapterContract =
        '實作 BridgeActionAdapter，宣告 supportedTypes，回傳 BridgeActionResult 與 metadata。',
    this.communityPluginNote = '未來可由社群提供 provider adapter 或桌面插件。',
    this.setupSteps = const [],
    this.officialEntryHints = const [],
    this.builtIn = true,
    this.requiresDesktopBridge = false,
  });

  factory CapabilityDefinition.fromJson(Map<String, dynamic> json) {
    return CapabilityDefinition(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      kind: CapabilityKindLabel.fromName(json['kind']?.toString()),
      actionType: BridgeActionTypeX.fromCommand(
        json['actionType']?.toString() ?? 'unknown',
      ),
      description: json['description']?.toString() ?? '',
      triggerPhrases:
          (json['triggerPhrases'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      providers:
          (json['providers'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      setupRoute: json['setupRoute']?.toString() ?? '/golden-keys',
      brainRoom: json['brainRoom']?.toString() ?? 'Bridges',
      costNote: json['costNote']?.toString() ?? '依 provider 計費',
      speedNote: json['speedNote']?.toString() ?? '依 provider 與任務大小而定',
      qualityNote: json['qualityNote']?.toString() ?? '可由使用者回饋逐步校準',
      inputFormat: json['inputFormat']?.toString() ?? '自然語言需求',
      outputFormat: json['outputFormat']?.toString() ?? '文字或媒體結果',
      evidenceKind: json['evidenceKind']?.toString() ?? 'bridge_result',
      v0Scope: json['v0Scope']?.toString() ?? '能力登錄、缺口引導、任務回流與結果證據。',
      adapterContract:
          json['adapterContract']?.toString() ??
          '實作 BridgeActionAdapter，宣告 supportedTypes，回傳 BridgeActionResult 與 metadata。',
      communityPluginNote:
          json['communityPluginNote']?.toString() ??
          '未來可由社群提供 provider adapter 或桌面插件。',
      setupSteps:
          (json['setupSteps'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      officialEntryHints:
          (json['officialEntryHints'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      builtIn: json['builtIn'] != false,
      requiresDesktopBridge: json['requiresDesktopBridge'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'actionType': actionType.legacyType,
    'description': description,
    'triggerPhrases': triggerPhrases,
    'providers': providers,
    'setupRoute': setupRoute,
    'brainRoom': brainRoom,
    'costNote': costNote,
    'speedNote': speedNote,
    'qualityNote': qualityNote,
    'inputFormat': inputFormat,
    'outputFormat': outputFormat,
    'evidenceKind': evidenceKind,
    'v0Scope': v0Scope,
    'adapterContract': adapterContract,
    'communityPluginNote': communityPluginNote,
    'setupSteps': setupSteps,
    'officialEntryHints': officialEntryHints,
    'builtIn': builtIn,
    'requiresDesktopBridge': requiresDesktopBridge,
  };
}

class CapabilityRuntimeStatus {
  final CapabilityDefinition definition;
  final CapabilityAvailability availability;
  final String providerLabel;
  final String detail;
  final String nextStep;

  const CapabilityRuntimeStatus({
    required this.definition,
    required this.availability,
    required this.providerLabel,
    required this.detail,
    required this.nextStep,
  });

  bool get ready => availability == CapabilityAvailability.ready;
}

class BrainSkillRecommendation {
  final CapabilityRuntimeStatus capability;
  final String reason;
  final int confidence;

  const BrainSkillRecommendation({
    required this.capability,
    required this.reason,
    required this.confidence,
  });
}

class BrainSkillRegistrySnapshot {
  final List<CapabilityRuntimeStatus> capabilities;
  final List<BrainSkillRecommendation> recommendations;
  final String summary;

  const BrainSkillRegistrySnapshot({
    this.capabilities = const [],
    this.recommendations = const [],
    this.summary = '',
  });

  bool get hasRecommendations => recommendations.isNotEmpty;

  bool get hasVisibleSignal =>
      capabilities.isNotEmpty || recommendations.isNotEmpty;
}
