// canvas_metadata.dart
// D11: 畫布元資料模型 — 管理畫布與對話、專案的綁定關係
//
// 設計文件: d11-project-canvas-conversation-design.md §2.2

/// 畫布狀態。
enum CanvasStatus {
  /// 計畫中
  planning,
  /// 執行中
  executing,
  /// 已完成
  completed,
  /// 暫停
  paused;

  String get label => switch (this) {
        planning => 'planning',
        executing => 'executing',
        completed => 'completed',
        paused => 'paused',
      };

  static CanvasStatus fromString(String? s) => switch (s) {
        'executing' => executing,
        'completed' => completed,
        'paused' => paused,
        _ => planning,
      };

  String get displayName => switch (this) {
        planning => '計畫中',
        executing => '執行中',
        completed => '已完成',
        paused => '暫停',
      };
}

/// 畫布元資料。
///
/// 管理畫布與對話 thread（1:1）、專案門（1:1）的綁定關係。
/// 每次存檔都會更新 projectDoorId 對應的 flowSteps，
/// 確保專案頁面永遠顯示最新結果。
class CanvasMetadata {
  final String id;
  final String title;
  final String? conversationId;
  final String? projectDoorId;
  final CanvasStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// D12: 畫布節點 ID → flowStep ID 的映射
  final Map<String, String> flowStepMapping;

  /// SemiCanvas: 塗鴉筆畫 JSON（持久化用，不直接存 DoodleStroke 物件以避免模型耦合）
  final List<Map<String, dynamic>> doodleStrokes;
  /// SemiCanvas: 塗鴉文字 JSON（持久化用）
  final List<Map<String, dynamic>> doodleTexts;

  CanvasMetadata({
    required this.id,
    required this.title,
    this.conversationId,
    this.projectDoorId,
    this.status = CanvasStatus.planning,
    required this.createdAt,
    required this.updatedAt,
    this.flowStepMapping = const {},
    this.doodleStrokes = const [],
    this.doodleTexts = const [],
  });

  factory CanvasMetadata.create({
    required String title,
    String? conversationId,
  }) {
    final now = DateTime.now();
    return CanvasMetadata(
      id: 'canvas-${now.microsecondsSinceEpoch}',
      title: title,
      conversationId: conversationId,
      createdAt: now,
      updatedAt: now,
    );
  }

  CanvasMetadata copyWith({
    String? title,
    String? conversationId,
    String? projectDoorId,
    CanvasStatus? status,
    DateTime? updatedAt,
    Map<String, String>? flowStepMapping,
    List<Map<String, dynamic>>? doodleStrokes,
    List<Map<String, dynamic>>? doodleTexts,
  }) =>
      CanvasMetadata(
        id: id,
        title: title ?? this.title,
        conversationId: conversationId ?? this.conversationId,
        projectDoorId: projectDoorId ?? this.projectDoorId,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        flowStepMapping: flowStepMapping ?? this.flowStepMapping,
        doodleStrokes: doodleStrokes ?? this.doodleStrokes,
        doodleTexts: doodleTexts ?? this.doodleTexts,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (conversationId != null) 'conversationId': conversationId,
        if (projectDoorId != null) 'projectDoorId': projectDoorId,
        'status': status.label,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (flowStepMapping.isNotEmpty) 'flowStepMapping': flowStepMapping,
        if (doodleStrokes.isNotEmpty) 'doodleStrokes': doodleStrokes,
        if (doodleTexts.isNotEmpty) 'doodleTexts': doodleTexts,
      };

  factory CanvasMetadata.fromJson(Map<String, dynamic> json) => CanvasMetadata(
        id: json['id'] as String,
        title: json['title'] as String,
        conversationId: json['conversationId'] as String?,
        projectDoorId: json['projectDoorId'] as String?,
        status: CanvasStatus.fromString(json['status'] as String?),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        flowStepMapping: (json['flowStepMapping'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)) ??
            const {},
        doodleStrokes: (json['doodleStrokes'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
            const [],
        doodleTexts: (json['doodleTexts'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
            const [],
      );
}
