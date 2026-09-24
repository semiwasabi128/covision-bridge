import 'second_brain_file_index.dart';

enum DigitalAssetKind {
  companionCharacter,
  mediaAsset,
  documentAsset,
  scriptAsset,
  codeTool,
  capabilityPlugin,
  projectPlaybook,
  workflowEngine,
  bridgeAdapter,
  knowledgePack,
}

extension DigitalAssetKindLabel on DigitalAssetKind {
  String get label {
    switch (this) {
      case DigitalAssetKind.companionCharacter:
        return '人物資產';
      case DigitalAssetKind.mediaAsset:
        return '圖像影音資產';
      case DigitalAssetKind.documentAsset:
        return '文件資產';
      case DigitalAssetKind.scriptAsset:
        return '腳本資產';
      case DigitalAssetKind.codeTool:
        return '小程式資產';
      case DigitalAssetKind.capabilityPlugin:
        return '功能插件資產';
      case DigitalAssetKind.projectPlaybook:
        return '專案玩法資產';
      case DigitalAssetKind.workflowEngine:
        return '工作流引擎資產';
      case DigitalAssetKind.bridgeAdapter:
        return '能力橋 Adapter';
      case DigitalAssetKind.knowledgePack:
        return '知識包資產';
    }
  }

  SecondBrainRoom get defaultRoom {
    switch (this) {
      case DigitalAssetKind.companionCharacter:
        return SecondBrainRoom.companions;
      case DigitalAssetKind.mediaAsset:
      case DigitalAssetKind.documentAsset:
      case DigitalAssetKind.scriptAsset:
      case DigitalAssetKind.codeTool:
      case DigitalAssetKind.knowledgePack:
        return SecondBrainRoom.files;
      case DigitalAssetKind.capabilityPlugin:
      case DigitalAssetKind.bridgeAdapter:
        return SecondBrainRoom.bridges;
      case DigitalAssetKind.projectPlaybook:
      case DigitalAssetKind.workflowEngine:
        return SecondBrainRoom.projects;
    }
  }

  static DigitalAssetKind fromName(String? value) {
    return DigitalAssetKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => DigitalAssetKind.projectPlaybook,
    );
  }
}

class DigitalAsset {
  final String id;
  final String title;
  final DigitalAssetKind kind;
  final String summary;
  final String sourceProjectDoorId;
  final String sourceConversationId;
  final String sourceLabel;
  final List<String> capabilities;
  final List<String> reusableScenes;
  final List<String> tags;
  final List<String> purposeTags;
  final List<String> locationTags;
  final List<String> propertyTags;
  final List<String> creativeTags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String secondBrainEntryId;
  final bool reusableByProjects;
  final bool reusableByAgents;

  const DigitalAsset({
    required this.id,
    required this.title,
    required this.kind,
    required this.summary,
    this.sourceProjectDoorId = '',
    this.sourceConversationId = '',
    this.sourceLabel = '',
    this.capabilities = const [],
    this.reusableScenes = const [],
    this.tags = const [],
    this.purposeTags = const [],
    this.locationTags = const [],
    this.propertyTags = const [],
    this.creativeTags = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.secondBrainEntryId,
    this.reusableByProjects = true,
    this.reusableByAgents = true,
  });

  bool get isValid => id.trim().isNotEmpty && title.trim().isNotEmpty;

  String get registryPath => 'brain://digital-assets/$id';

  DigitalAsset copyWith({
    String? title,
    DigitalAssetKind? kind,
    String? summary,
    String? sourceProjectDoorId,
    String? sourceConversationId,
    String? sourceLabel,
    List<String>? capabilities,
    List<String>? reusableScenes,
    List<String>? tags,
    List<String>? purposeTags,
    List<String>? locationTags,
    List<String>? propertyTags,
    List<String>? creativeTags,
    DateTime? updatedAt,
    String? secondBrainEntryId,
    bool? reusableByProjects,
    bool? reusableByAgents,
  }) {
    return DigitalAsset(
      id: id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      summary: summary ?? this.summary,
      sourceProjectDoorId: sourceProjectDoorId ?? this.sourceProjectDoorId,
      sourceConversationId: sourceConversationId ?? this.sourceConversationId,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      capabilities: capabilities ?? this.capabilities,
      reusableScenes: reusableScenes ?? this.reusableScenes,
      tags: tags ?? this.tags,
      purposeTags: purposeTags ?? this.purposeTags,
      locationTags: locationTags ?? this.locationTags,
      propertyTags: propertyTags ?? this.propertyTags,
      creativeTags: creativeTags ?? this.creativeTags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      secondBrainEntryId: secondBrainEntryId ?? this.secondBrainEntryId,
      reusableByProjects: reusableByProjects ?? this.reusableByProjects,
      reusableByAgents: reusableByAgents ?? this.reusableByAgents,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'summary': summary,
    'sourceProjectDoorId': sourceProjectDoorId,
    'sourceConversationId': sourceConversationId,
    'sourceLabel': sourceLabel,
    'capabilities': capabilities,
    'reusableScenes': reusableScenes,
    'tags': tags,
    'purposeTags': purposeTags,
    'locationTags': locationTags,
    'propertyTags': propertyTags,
    'creativeTags': creativeTags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'secondBrainEntryId': secondBrainEntryId,
    'reusableByProjects': reusableByProjects,
    'reusableByAgents': reusableByAgents,
  };

  factory DigitalAsset.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return DigitalAsset(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      kind: DigitalAssetKindLabel.fromName(json['kind']?.toString()),
      summary: json['summary']?.toString() ?? '',
      sourceProjectDoorId: json['sourceProjectDoorId']?.toString() ?? '',
      sourceConversationId: json['sourceConversationId']?.toString() ?? '',
      sourceLabel: json['sourceLabel']?.toString() ?? '',
      capabilities:
          (json['capabilities'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      reusableScenes:
          (json['reusableScenes'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      tags:
          (json['tags'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      purposeTags:
          (json['purposeTags'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      locationTags:
          (json['locationTags'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      propertyTags:
          (json['propertyTags'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      creativeTags:
          (json['creativeTags'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      secondBrainEntryId: json['secondBrainEntryId']?.toString() ?? '',
      reusableByProjects: json['reusableByProjects'] != false,
      reusableByAgents: json['reusableByAgents'] != false,
    );
  }
}
