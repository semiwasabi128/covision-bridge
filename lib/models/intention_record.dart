// intention_record.dart
// Sprint 2 — 宣告/確認/行動閉環的資料模型
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// IntentionRecord 是使用者「宣告意圖」的記錄。
// 生命週期：open → confirmed → acted（或被 cancelled）。
// 存進 BrainContainer 現有 Doors 房間（透過 BrainContainerServiceAdapter）。

/// 意圖狀態機。
enum IntentionStatus {
  /// 剛宣告，等待使用者確認
  open,

  /// 使用者確認了，準備行動
  confirmed,

  /// 已付諸行動並記錄
  acted,

  /// 取消（使用者改變心意或逾時）
  cancelled,
}

/// 一條宣告意圖的記錄。
///
/// 由 [IntentionRouter] 在偵測到 `RecommendedMove.declareIntention` 時建立。
/// 之後使用者確認 → status 變 confirmed；完成行動 → status 變 acted。
class IntentionRecord {
  /// 唯一 ID（用時間戳 + 短 hash 產生）
  final String id;

  /// 使用者的原始宣告訊息
  final String userMessage;

  /// 建立時的上下文快照（例如當時的 BrainReflection 摘要）
  final String? contextSnapshot;

  /// 建立時間（毫秒）
  final int createdAtMs;

  /// 最後更新時間（毫秒）
  final int updatedAtMs;

  /// 目前狀態
  final IntentionStatus status;

  /// 來自第幾層（固定 7 = Action Router）
  final int sourceLayer;

  /// 使用者確認時的回覆文字
  final String? confirmationReply;

  /// 行動完成時的摘要
  final String? actionSummary;

  const IntentionRecord({
    required this.id,
    required this.userMessage,
    this.contextSnapshot,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.status,
    this.sourceLayer = 7,
    this.confirmationReply,
    this.actionSummary,
  });

  /// 建立一條新的 open intention
  factory IntentionRecord.create({
    required String userMessage,
    String? contextSnapshot,
    DateTime? now,
  }) {
    final timestamp = now?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    return IntentionRecord(
      id: 'int_${timestamp}_${userMessage.hashCode.toRadixString(36).padLeft(6, '0').substring(0, 6)}',
      userMessage: userMessage,
      contextSnapshot: contextSnapshot,
      createdAtMs: timestamp,
      updatedAtMs: timestamp,
      status: IntentionStatus.open,
    );
  }

  IntentionRecord copyWith({
    String? id,
    String? userMessage,
    String? contextSnapshot,
    int? createdAtMs,
    int? updatedAtMs,
    IntentionStatus? status,
    int? sourceLayer,
    String? confirmationReply,
    String? actionSummary,
  }) {
    return IntentionRecord(
      id: id ?? this.id,
      userMessage: userMessage ?? this.userMessage,
      contextSnapshot: contextSnapshot ?? this.contextSnapshot,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      status: status ?? this.status,
      sourceLayer: sourceLayer ?? this.sourceLayer,
      confirmationReply: confirmationReply ?? this.confirmationReply,
      actionSummary: actionSummary ?? this.actionSummary,
    );
  }

  /// 確認這條意圖
  IntentionRecord confirm(String reply, {DateTime? now}) {
    final timestamp = now?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    return copyWith(
      status: IntentionStatus.confirmed,
      confirmationReply: reply,
      updatedAtMs: timestamp,
    );
  }

  /// 標記為已行動
  IntentionRecord markActed(String summary, {DateTime? now}) {
    final timestamp = now?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    return copyWith(
      status: IntentionStatus.acted,
      actionSummary: summary,
      updatedAtMs: timestamp,
    );
  }

  /// 取消
  IntentionRecord cancel({DateTime? now}) {
    final timestamp = now?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    return copyWith(
      status: IntentionStatus.cancelled,
      updatedAtMs: timestamp,
    );
  }

  bool get isOpen => status == IntentionStatus.open;
  bool get isConfirmed => status == IntentionStatus.confirmed;
  bool get isActed => status == IntentionStatus.acted;
  bool get isCancelled => status == IntentionStatus.cancelled;

  @override
  String toString() =>
      'IntentionRecord($id, status=${status.name}, "$userMessage")';
}
