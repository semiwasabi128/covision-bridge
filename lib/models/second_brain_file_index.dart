enum SecondBrainRoom { self, projects, files, doors, bridges, companions }

extension SecondBrainRoomLabel on SecondBrainRoom {
  String get label {
    switch (this) {
      case SecondBrainRoom.self:
        return 'Self';
      case SecondBrainRoom.projects:
        return 'Projects';
      case SecondBrainRoom.files:
        return 'Files';
      case SecondBrainRoom.doors:
        return 'Doors';
      case SecondBrainRoom.bridges:
        return 'Bridges';
      case SecondBrainRoom.companions:
        return 'Companions';
    }
  }

  String get zhLabel {
    switch (this) {
      case SecondBrainRoom.self:
        return '自我房間';
      case SecondBrainRoom.projects:
        return '計畫房間';
      case SecondBrainRoom.files:
        return '檔案房間';
      case SecondBrainRoom.doors:
        return '門房間';
      case SecondBrainRoom.bridges:
        return '橋樑房間';
      case SecondBrainRoom.companions:
        return '夥伴房間';
    }
  }

  static SecondBrainRoom fromJson(String? value) {
    return SecondBrainRoom.values.firstWhere(
      (room) => room.label == value,
      orElse: () => SecondBrainRoom.files,
    );
  }
}

class SecondBrainFileEntry {
  final String id;
  final String title;
  final String path;
  final SecondBrainRoom room;
  final String summary;
  final String contentDigest;
  final String contentExcerpt;
  final List<String> tags;
  final List<String> keywords;
  final DateTime indexedAt;
  final DateTime? lastUsedAt;
  final int useCount;
  final int trustScore;
  final int usefulFeedbackCount;
  final int irrelevantFeedbackCount;
  final bool pinned;
  final bool muted;
  final String lastFeedbackLabel;
  final DateTime? lastFeedbackAt;
  // [以利沙 P0 修復十七輪 2026-06-27] agentId 欄位，記錄是哪個 companion 產生的記憶
  final String? agentId;

  const SecondBrainFileEntry({
    required this.id,
    required this.title,
    required this.path,
    required this.room,
    required this.summary,
    this.contentDigest = '',
    this.contentExcerpt = '',
    this.tags = const [],
    this.keywords = const [],
    required this.indexedAt,
    this.lastUsedAt,
    this.useCount = 0,
    this.trustScore = 60,
    this.usefulFeedbackCount = 0,
    this.irrelevantFeedbackCount = 0,
    this.pinned = false,
    this.muted = false,
    this.lastFeedbackLabel = '',
    this.lastFeedbackAt,
    this.agentId,
  });

  SecondBrainFileEntry copyWith({
    String? id,
    String? title,
    String? path,
    SecondBrainRoom? room,
    String? summary,
    String? contentDigest,
    String? contentExcerpt,
    List<String>? tags,
    List<String>? keywords,
    DateTime? indexedAt,
    DateTime? lastUsedAt,
    int? useCount,
    int? trustScore,
    int? usefulFeedbackCount,
    int? irrelevantFeedbackCount,
    bool? pinned,
    bool? muted,
    String? lastFeedbackLabel,
    DateTime? lastFeedbackAt,
    bool clearLastFeedbackAt = false,
    String? agentId,
  }) {
    return SecondBrainFileEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      room: room ?? this.room,
      summary: summary ?? this.summary,
      contentDigest: contentDigest ?? this.contentDigest,
      contentExcerpt: contentExcerpt ?? this.contentExcerpt,
      tags: tags ?? this.tags,
      keywords: keywords ?? this.keywords,
      indexedAt: indexedAt ?? this.indexedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      useCount: useCount ?? this.useCount,
      trustScore: trustScore ?? this.trustScore,
      usefulFeedbackCount: usefulFeedbackCount ?? this.usefulFeedbackCount,
      irrelevantFeedbackCount:
          irrelevantFeedbackCount ?? this.irrelevantFeedbackCount,
      pinned: pinned ?? this.pinned,
      muted: muted ?? this.muted,
      lastFeedbackLabel: lastFeedbackLabel ?? this.lastFeedbackLabel,
      lastFeedbackAt: clearLastFeedbackAt
          ? null
          : lastFeedbackAt ?? this.lastFeedbackAt,
      agentId: agentId ?? this.agentId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'room': room.label,
      'summary': summary,
      'contentDigest': contentDigest,
      'contentExcerpt': contentExcerpt,
      'tags': tags,
      'keywords': keywords,
      'indexedAt': indexedAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'useCount': useCount,
      'trustScore': trustScore,
      'usefulFeedbackCount': usefulFeedbackCount,
      'irrelevantFeedbackCount': irrelevantFeedbackCount,
      'pinned': pinned,
      'muted': muted,
      'lastFeedbackLabel': lastFeedbackLabel,
      'lastFeedbackAt': lastFeedbackAt?.toIso8601String(),
      'agentId': agentId,
    };
  }

  factory SecondBrainFileEntry.fromJson(Map<String, dynamic> json) {
    final indexedAt = DateTime.tryParse(json['indexedAt']?.toString() ?? '');
    final lastUsedAt = DateTime.tryParse(json['lastUsedAt']?.toString() ?? '');
    final lastFeedbackAt = DateTime.tryParse(
      json['lastFeedbackAt']?.toString() ?? '',
    );
    return SecondBrainFileEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      room: SecondBrainRoomLabel.fromJson(json['room']?.toString()),
      summary: json['summary']?.toString() ?? '',
      contentDigest: json['contentDigest']?.toString() ?? '',
      contentExcerpt: json['contentExcerpt']?.toString() ?? '',
      tags:
          (json['tags'] as List?)?.map((tag) => tag.toString()).toList() ??
          const [],
      keywords:
          (json['keywords'] as List?)
              ?.map((keyword) => keyword.toString())
              .toList() ??
          const [],
      indexedAt: indexedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastUsedAt: lastUsedAt,
      useCount: (json['useCount'] as num?)?.round() ?? 0,
      trustScore: (json['trustScore'] as num?)?.round() ?? 60,
      usefulFeedbackCount: (json['usefulFeedbackCount'] as num?)?.round() ?? 0,
      irrelevantFeedbackCount:
          (json['irrelevantFeedbackCount'] as num?)?.round() ?? 0,
      pinned: json['pinned'] == true,
      muted: json['muted'] == true,
      lastFeedbackLabel: json['lastFeedbackLabel']?.toString() ?? '',
      lastFeedbackAt: lastFeedbackAt,
      agentId: json['agentId'] as String?,
    );
  }
}
