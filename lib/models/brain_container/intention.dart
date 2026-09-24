// intention.dart
// 意圖 model + 記憶-意圖關聯 model
// 建立日期: 2026-07-02

const _sentinel = Object();

/// 使用者的意圖/問題。
///
/// 記憶可以連結到某個 intention，表示「這則記憶回應了這個意圖」。
class Intention {
  final String id;
  final String title;
  final String description;
  final String question;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const Intention({
    required this.id,
    required this.title,
    required this.description,
    required this.question,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  factory Intention.fromMap(Map<String, dynamic> map) {
    return Intention(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      question: map['question'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      resolvedAt: (map['resolved_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['resolved_at'] as int?)!)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'question': question,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch,
      'resolved_at': resolvedAt?.millisecondsSinceEpoch,
    };
  }

  Intention copyWith({
    String? id,
    String? title,
    String? description,
    String? question,
    String? status,
    DateTime? createdAt,
    Object? resolvedAt = _sentinel,
  }) {
    return Intention(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      question: question ?? this.question,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt == _sentinel
          ? this.resolvedAt
          : resolvedAt as DateTime?,
    );
  }
}

/// 記憶與意圖的中間關聯。
class MemoryIntentionLink {
  final String memoryId;
  final String intentionId;
  final DateTime linkedAt;
  final bool userMarked;

  const MemoryIntentionLink({
    required this.memoryId,
    required this.intentionId,
    required this.linkedAt,
    required this.userMarked,
  });

  factory MemoryIntentionLink.fromMap(Map<String, dynamic> map) {
    return MemoryIntentionLink(
      memoryId: map['memory_id'] as String? ?? '',
      intentionId: map['intention_id'] as String? ?? '',
      linkedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['linked_at'] as int?) ?? 0),
      userMarked: (map['user_marked'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'memory_id': memoryId,
      'intention_id': intentionId,
      'linked_at': linkedAt.millisecondsSinceEpoch,
      'user_marked': userMarked ? 1 : 0,
    };
  }

  MemoryIntentionLink copyWith({
    String? memoryId,
    String? intentionId,
    DateTime? linkedAt,
    bool? userMarked,
  }) {
    return MemoryIntentionLink(
      memoryId: memoryId ?? this.memoryId,
      intentionId: intentionId ?? this.intentionId,
      linkedAt: linkedAt ?? this.linkedAt,
      userMarked: userMarked ?? this.userMarked,
    );
  }
}
