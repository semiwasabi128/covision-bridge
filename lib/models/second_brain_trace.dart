class SecondBrainTrace {
  final String brainName;
  final String? agentName;
  final List<SecondBrainMemoryTrace> recalledMemories;
  final List<SecondBrainNewInsightTrace> newInsights;
  final List<SecondBrainOutputTrace> outputs;
  final List<String> associations;

  const SecondBrainTrace({
    this.brainName = 'Bridge Brain',
    this.agentName,
    this.recalledMemories = const [],
    this.newInsights = const [],
    this.outputs = const [],
    this.associations = const [],
  });

  bool get hasActivity =>
      recalledMemories.isNotEmpty ||
      newInsights.isNotEmpty ||
      outputs.isNotEmpty ||
      associations.isNotEmpty;
}

enum SecondBrainMemoryFeedback { useful, irrelevant, pin, mute }

enum SecondBrainAssociationFeedback { useful, wrong }

extension SecondBrainAssociationFeedbackLabel
    on SecondBrainAssociationFeedback {
  String get label {
    switch (this) {
      case SecondBrainAssociationFeedback.useful:
        return '連得好';
      case SecondBrainAssociationFeedback.wrong:
        return '連錯了';
    }
  }
}

extension SecondBrainMemoryFeedbackLabel on SecondBrainMemoryFeedback {
  String get label {
    switch (this) {
      case SecondBrainMemoryFeedback.useful:
        return '有用';
      case SecondBrainMemoryFeedback.irrelevant:
        return '不相關';
      case SecondBrainMemoryFeedback.pin:
        return '常引用';
      case SecondBrainMemoryFeedback.mute:
        return '不要引用';
    }
  }
}

class SecondBrainMemoryTrace {
  final String content;
  final String room;
  final String sourceLabel;
  final String? sourcePath;
  final String reason;
  final List<String> retrievalSignals;
  final String freshnessLabel;
  final String sourcePreview;
  final List<String> tags;
  final int trustScore;

  const SecondBrainMemoryTrace({
    required this.content,
    required this.room,
    required this.sourceLabel,
    required this.reason,
    this.sourcePath,
    this.retrievalSignals = const [],
    this.freshnessLabel = '',
    this.sourcePreview = '',
    this.tags = const [],
    this.trustScore = 50,
  });
}

class SecondBrainNewInsightTrace {
  final String content;
  final String room;
  final List<String> tags;

  const SecondBrainNewInsightTrace({
    required this.content,
    required this.room,
    this.tags = const [],
  });
}

class SecondBrainOutputTrace {
  final String title;
  final String kind;
  final String? path;

  const SecondBrainOutputTrace({
    required this.title,
    required this.kind,
    this.path,
  });
}
