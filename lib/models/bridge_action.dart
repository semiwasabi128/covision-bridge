enum BridgeActionType {
  generateImage,
  generateAnimation,
  generateMusic,
  generateVideo,
  browse,
  vision,
  document,
  desktopFiles,
  unknown,
}

extension BridgeActionTypeX on BridgeActionType {
  String get command {
    switch (this) {
      case BridgeActionType.generateImage:
        return 'GENERATE_IMAGE';
      case BridgeActionType.generateAnimation:
        return 'GENERATE_ANIMATION';
      case BridgeActionType.generateMusic:
        return 'GENERATE_MUSIC';
      case BridgeActionType.generateVideo:
        return 'GENERATE_VIDEO';
      case BridgeActionType.browse:
        return 'BROWSE';
      case BridgeActionType.vision:
        return 'VISION';
      case BridgeActionType.document:
        return 'DOCUMENT';
      case BridgeActionType.desktopFiles:
        return 'DESKTOP_FILES';
      case BridgeActionType.unknown:
        return 'UNKNOWN';
    }
  }

  String get legacyType => command.toLowerCase();

  String get displayLabel {
    switch (this) {
      case BridgeActionType.generateImage:
        return '生成圖片';
      case BridgeActionType.generateAnimation:
        return '生成動圖';
      case BridgeActionType.generateMusic:
        return '生成音樂';
      case BridgeActionType.generateVideo:
        return '生成影片';
      case BridgeActionType.browse:
        return '瀏覽網頁';
      case BridgeActionType.vision:
        return '圖片辨識';
      case BridgeActionType.document:
        return '產出文件';
      case BridgeActionType.desktopFiles:
        return '桌面整理';
      case BridgeActionType.unknown:
        return '執行動作';
    }
  }

  static BridgeActionType fromCommand(String value) {
    switch (value.toUpperCase()) {
      case 'GENERATE_IMAGE':
      case 'GENERATEIMAGE':
      case 'GENERATE_IMAGE:':
        return BridgeActionType.generateImage;
      case 'GENERATE_ANIMATION':
      case 'GENERATEANIMATION':
      case 'GENERATE_ANIMATION:':
        return BridgeActionType.generateAnimation;
      case 'GENERATE_MUSIC':
      case 'GENERATEMUSIC':
        return BridgeActionType.generateMusic;
      case 'GENERATE_VIDEO':
      case 'GENERATEVIDEO':
        return BridgeActionType.generateVideo;
      case 'BROWSE':
      case 'WEB_SEARCH':
      case 'GOOGLE_SEARCH':
      case 'SEARCH':
        return BridgeActionType.browse;
      case 'VISION':
      case 'IMAGE_RECOGNITION':
      case 'IMAGE_RECOGNITION:':
        return BridgeActionType.vision;
      case 'DOCUMENT':
        return BridgeActionType.document;
      case 'DESKTOP_FILES':
      case 'DESKTOPFILES':
      case 'DESKTOP_FILE':
      case 'LOCAL_FILES':
      case 'FILE_ORGANIZE':
        return BridgeActionType.desktopFiles;
      default:
        return BridgeActionType.unknown;
    }
  }
}

enum BridgeActionRunStatus { pending, running, completed, failed }

extension BridgeActionRunStatusX on BridgeActionRunStatus {
  String get value {
    switch (this) {
      case BridgeActionRunStatus.pending:
        return 'pending';
      case BridgeActionRunStatus.running:
        return 'running';
      case BridgeActionRunStatus.completed:
        return 'completed';
      case BridgeActionRunStatus.failed:
        return 'failed';
    }
  }

  String get displayLabel {
    switch (this) {
      case BridgeActionRunStatus.pending:
        return '待執行';
      case BridgeActionRunStatus.running:
        return '執行中';
      case BridgeActionRunStatus.completed:
        return '已完成';
      case BridgeActionRunStatus.failed:
        return '失敗，可重試';
    }
  }

  static BridgeActionRunStatus fromValue(String value) {
    switch (value.toLowerCase()) {
      case 'running':
        return BridgeActionRunStatus.running;
      case 'completed':
        return BridgeActionRunStatus.completed;
      case 'failed':
        return BridgeActionRunStatus.failed;
      case 'pending':
      default:
        return BridgeActionRunStatus.pending;
    }
  }
}

class BridgeAction {
  static final tagPattern = RegExp(
    r'\[(GENERATE_IMAGE|GENERATE_ANIMATION|GENERATE_MUSIC|GENERATE_VIDEO|BROWSE|WEB_SEARCH|GOOGLE_SEARCH|SEARCH|VISION|DOCUMENT|DESKTOP_FILES|LOCAL_FILES|FILE_ORGANIZE):\s*([^\]]+)\]',
    caseSensitive: false,
  );

  static final _directImageCommandPattern = RegExp(
    r'^(?:/image|/img|/imagine)\s+(.+)$',
    caseSensitive: false,
    dotAll: true,
  );

  static final _directChineseImagePattern = RegExp(
    r'^(?:生成圖片|產生圖片|圖片生成|畫一張|幫我畫|幫我生成圖片)\s*[：:，,]?\s*(.+)$',
    dotAll: true,
  );

  static final _directDocumentCommandPattern = RegExp(
    r'^(?:/doc|/document)\s+(.+)$',
    caseSensitive: false,
    dotAll: true,
  );

  static final _directChineseDocumentPattern = RegExp(
    r'^(?:產出文件|生成文件|建立文件|寫成文件|整理成文件|產出報告|生成報告|建立報告|輸出報告|產出PDF|生成PDF|輸出PDF|幫我產出(?:一份)?(?:文件|報告|PDF)|幫我生成(?:一份)?(?:文件|報告|PDF))\s*[：:，,]?\s*(.+)$',
    dotAll: true,
  );

  static final _directDesktopFilesPattern = RegExp(
    r'^(?:整理桌面檔案|整理桌面|整理檔案|整理資料夾|掃描桌面檔案|掃描桌面|掃描檔案|掃描資料夾|幫我整理桌面檔案|幫我整理桌面|幫我整理檔案|幫我掃描桌面檔案|幫我掃描桌面|幫我掃描檔案|找桌面檔案|查看桌面檔案|看一下桌面檔案|列出桌面檔案)\s*[：:，,]?\s*(.*)$',
    dotAll: true,
  );

  final BridgeActionType type;
  final String prompt;
  final String? provider;
  final String? model;
  final String? imageQuality;
  final List<String> referenceImagePaths;
  final bool requiresConfirmation;
  final BridgeActionRunStatus runStatus;
  final String? statusMessage;

  const BridgeAction({
    required this.type,
    required this.prompt,
    this.provider,
    this.model,
    this.imageQuality,
    this.referenceImagePaths = const [],
    this.requiresConfirmation = false,
    this.runStatus = BridgeActionRunStatus.pending,
    this.statusMessage,
  });

  factory BridgeAction.fromTagMatch(RegExpMatch match) {
    return BridgeAction(
      type: BridgeActionTypeX.fromCommand(match.group(1) ?? ''),
      prompt: match.group(2)?.trim() ?? '',
    );
  }

  static BridgeAction? tryParseDirectCommand(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final taggedAction = tagPattern.firstMatch(text);
    if (taggedAction != null) return BridgeAction.fromTagMatch(taggedAction);

    final commandMatch = _directImageCommandPattern.firstMatch(text);
    final chineseMatch = _directChineseImagePattern.firstMatch(text);
    final imagePrompt =
        commandMatch?.group(1)?.trim() ?? chineseMatch?.group(1)?.trim();
    if (imagePrompt != null && imagePrompt.isNotEmpty) {
      return BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: imagePrompt,
      );
    }

    final documentCommandMatch = _directDocumentCommandPattern.firstMatch(text);
    final documentChineseMatch = _directChineseDocumentPattern.firstMatch(text);
    final documentPrompt =
        documentCommandMatch?.group(1)?.trim() ??
        documentChineseMatch?.group(1)?.trim();
    if (documentPrompt != null && documentPrompt.isNotEmpty) {
      return BridgeAction(
        type: BridgeActionType.document,
        prompt: documentPrompt,
      );
    }

    final desktopFilesMatch = _directDesktopFilesPattern.firstMatch(text);
    if (desktopFilesMatch != null) {
      final desktopPrompt = desktopFilesMatch.group(1)?.trim();
      return BridgeAction(
        type: BridgeActionType.desktopFiles,
        prompt: desktopPrompt == null || desktopPrompt.isEmpty
            ? text
            : desktopPrompt,
      );
    }

    return null;
  }

  factory BridgeAction.fromJson(Map<String, dynamic> json) {
    return BridgeAction(
      type: BridgeActionTypeX.fromCommand(json['type']?.toString() ?? ''),
      prompt: json['prompt']?.toString() ?? '',
      provider: json['provider']?.toString(),
      model: json['model']?.toString(),
      imageQuality: json['imageQuality']?.toString(),
      referenceImagePaths:
          (json['referenceImagePaths'] as List<dynamic>?)
              ?.map((path) => path.toString())
              .where((path) => path.trim().isNotEmpty)
              .toList() ??
          const [],
      requiresConfirmation: json['requiresConfirmation'] == true,
      runStatus: BridgeActionRunStatusX.fromValue(
        json['runStatus']?.toString() ?? 'pending',
      ),
      statusMessage: json['statusMessage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.legacyType,
    'prompt': prompt,
    if (provider != null) 'provider': provider,
    if (model != null) 'model': model,
    if (imageQuality != null) 'imageQuality': imageQuality,
    if (referenceImagePaths.isNotEmpty)
      'referenceImagePaths': referenceImagePaths,
    'requiresConfirmation': requiresConfirmation,
    'runStatus': runStatus.value,
    if (statusMessage != null) 'statusMessage': statusMessage,
  };

  String get displayType => type.displayLabel;

  bool get canExecute =>
      runStatus == BridgeActionRunStatus.pending ||
      runStatus == BridgeActionRunStatus.failed;

  BridgeAction copyWith({
    BridgeActionType? type,
    String? prompt,
    String? provider,
    String? model,
    String? imageQuality,
    List<String>? referenceImagePaths,
    bool? requiresConfirmation,
    BridgeActionRunStatus? runStatus,
    String? statusMessage,
  }) {
    return BridgeAction(
      type: type ?? this.type,
      prompt: prompt ?? this.prompt,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      imageQuality: imageQuality ?? this.imageQuality,
      referenceImagePaths: referenceImagePaths ?? this.referenceImagePaths,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      runStatus: runStatus ?? this.runStatus,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
