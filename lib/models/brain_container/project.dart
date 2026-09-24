// project.dart
// 專案 model
// 建立日期: 2026-07-02

import 'dart:convert';

/// 專案/任務容器。
///
/// 記憶可以歸屬於某個 project，用於按專案篩選與聚合。
class Project {
  final String id;
  final String name;
  final String description;
  final String status;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory Project.fromMap(Map<String, dynamic> map) {
    // tags JSON 反序列化防護（改善 6）
    List<String> tags;
    try {
      tags = (jsonDecode(map['tags'] as String? ?? '[]') as List)
          .cast<String>();
    } catch (_) {
      tags = [];
    }

    return Project(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as int?) ?? 0),
      completedAt: (map['completed_at'] as int?) != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['completed_at'] as int?)!)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'status': status,
      'tags': jsonEncode(tags),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
    };
  }

  Project copyWith({
    String? id,
    String? name,
    String? description,
    String? status,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = _sentinel,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      tags: tags ?? List<String>.from(this.tags),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }
}

const _sentinel = Object();
