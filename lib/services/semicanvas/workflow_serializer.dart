// workflow_serializer.dart
// SemiCanvas Phase 1.5c: 工作流序列化/反序列化
// 將畫布上的節點 + 連線序列化為 .bridge-workflow JSON 格式
// 支援匯出（存檔）和匯入（載入）
//
// 設計文件: semicanvas-design.md §2.5

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';

/// .bridge-workflow 檔案的根結構。
@immutable
class WorkflowAsset {
  /// 格式識別碼（固定值）
  static const String formatId = 'bridge-workflow';

  /// 格式版本
  final String version;

  /// 資產包元資料
  final WorkflowMetadata metadata;

  /// 所有節點
  final List<WorkflowNodeData> nodes;

  /// 所有連線
  final List<WorkflowEdgeData> edges;

  const WorkflowAsset({
    this.version = '1.0',
    required this.metadata,
    required this.nodes,
    required this.edges,
  });

  /// 序列化為 JSON Map
  Map<String, dynamic> toJson() => {
        'format': formatId,
        'version': version,
        'metadata': metadata.toJson(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  /// 序列化為 JSON 字串
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 從 JSON Map 反序列化
  factory WorkflowAsset.fromJson(Map<String, dynamic> json) {
    return WorkflowAsset(
      version: json['version'] as String? ?? '1.0',
      metadata: WorkflowMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>),
      nodes: (json['nodes'] as List?)
              ?.map((n) =>
                  WorkflowNodeData.fromJson(n as Map<String, dynamic>))
              .toList() ??
          [],
      edges: (json['edges'] as List?)
              ?.map((e) =>
                  WorkflowEdgeData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 從 JSON 字串反序列化
  factory WorkflowAsset.fromJsonString(String jsonStr) {
    return WorkflowAsset.fromJson(
        json.decode(jsonStr) as Map<String, dynamic>);
  }
}

/// 資產包元資料。
@immutable
class WorkflowMetadata {
  final String name;
  final String? author;
  final String? description;
  final List<String> tags;
  final String? license;
  final double price;
  final String? created;
  final String? engineVersion;
  final String? derivedFrom;

  const WorkflowMetadata({
    required this.name,
    this.author,
    this.description,
    this.tags = const [],
    this.license,
    this.price = 0,
    this.created,
    this.engineVersion,
    this.derivedFrom,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (author != null) 'author': author,
        if (description != null) 'description': description,
        if (tags.isNotEmpty) 'tags': tags,
        if (license != null) 'license': license,
        'price': price,
        if (created != null) 'created': created,
        if (engineVersion != null) 'engineVersion': engineVersion,
        if (derivedFrom != null) 'derivedFrom': derivedFrom,
      };

  factory WorkflowMetadata.fromJson(Map<String, dynamic> m) {
    return WorkflowMetadata(
      name: m['name'] as String? ?? '未命名工作流',
      author: m['author'] as String?,
      description: m['description'] as String?,
      tags: (m['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      license: m['license'] as String?,
      price: (m['price'] as num?)?.toDouble() ?? 0,
      created: m['created'] as String?,
      engineVersion: m['engineVersion'] as String?,
      derivedFrom: m['derivedFrom'] as String?,
    );
  }
}

/// 工作流節點的序列化資料。
@immutable
class WorkflowNodeData {
  final String id;
  final String? nodeType;
  final double x;
  final double y;
  final double width;
  final double height;
  final String? title;
  final Map<String, dynamic> params;
  final List<Map<String, dynamic>> ports;

  const WorkflowNodeData({
    required this.id,
    this.nodeType,
    required this.x,
    required this.y,
    this.width = 120.0,
    this.height = 80.0,
    this.title,
    this.params = const {},
    this.ports = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        if (nodeType != null) 'nodeType': nodeType,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        if (title != null) 'title': title,
        if (params.isNotEmpty) 'params': params,
        if (ports.isNotEmpty) 'ports': ports,
      };

  factory WorkflowNodeData.fromJson(Map<String, dynamic> m) {
    return WorkflowNodeData(
      id: m['id'] as String,
      nodeType: m['nodeType'] as String?,
      x: (m['x'] as num?)?.toDouble() ?? 0.0,
      y: (m['y'] as num?)?.toDouble() ?? 0.0,
      width: (m['width'] as num?)?.toDouble() ?? 120.0,
      height: (m['height'] as num?)?.toDouble() ?? 80.0,
      title: m['title'] as String?,
      params: (m['params'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {},
      ports: (m['ports'] as List?)
              ?.map((p) => p as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }

  /// 從 Entity + CanvasProps 建構
  factory WorkflowNodeData.fromEntity(Entity entity, CanvasProps props) {
    return WorkflowNodeData(
      id: entity.id,
      nodeType: props.nodeType?.name,
      x: props.x,
      y: props.y,
      width: props.width,
      height: props.height,
      title: entity.title,
      params: Map<String, dynamic>.from(props.params),
      ports: props.ports.map((p) => p.toJson()).toList(),
    );
  }

  /// 轉為 CanvasProps
  CanvasProps toCanvasProps() {
    return CanvasProps(
      x: x,
      y: y,
      width: width,
      height: height,
      nodeType: nodeType != null
          ? WorkflowNodeType.values.byName(nodeType!)
          : null,
      params: params,
      ports: ports.map((p) => PortDef.fromJson(p)).toList(),
    );
  }
}

/// 工作流連線的序列化資料。
@immutable
class WorkflowEdgeData {
  final String source;
  final String target;
  final String relationType;
  final String? dataType;
  final String? sourcePort;
  final String? targetPort;

  const WorkflowEdgeData({
    required this.source,
    required this.target,
    required this.relationType,
    this.dataType,
    this.sourcePort,
    this.targetPort,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        'target': target,
        'relationType': relationType,
        if (dataType != null) 'dataType': dataType,
        if (sourcePort != null) 'sourcePort': sourcePort,
        if (targetPort != null) 'targetPort': targetPort,
      };

  factory WorkflowEdgeData.fromJson(Map<String, dynamic> m) {
    return WorkflowEdgeData(
      source: m['source'] as String,
      target: m['target'] as String,
      relationType: m['relationType'] as String? ?? 'depends',
      dataType: m['dataType'] as String?,
      sourcePort: m['sourcePort'] as String?,
      targetPort: m['targetPort'] as String?,
    );
  }

  /// 從 EntityRelation 建構
  factory WorkflowEdgeData.fromRelation(EntityRelation rel) {
    return WorkflowEdgeData(
      source: rel.sourceId,
      target: rel.targetId,
      relationType: rel.type.name,
      dataType: rel.dataType?.name,
      sourcePort: rel.sourcePort,
      targetPort: rel.targetPort,
    );
  }

  /// 轉為 EntityRelation
  EntityRelation toRelation() {
    return EntityRelation(
      sourceId: source,
      targetId: target,
      type: RelationType.values.byName(relationType),
      dataType: dataType != null
          ? PortDataType.values.byName(dataType!)
          : null,
      sourcePort: sourcePort,
      targetPort: targetPort,
    );
  }
}

/// 工作流序列化服務。
///
/// 負責將 EntityGraphService 的畫布狀態序列化為 .bridge-workflow 檔案，
/// 以及從檔案反序列化重建畫布。
class WorkflowSerializer {
  final EntityGraphService entityGraph;

  WorkflowSerializer({required this.entityGraph});

  /// 匯出當前畫布為 WorkflowAsset
  Future<WorkflowAsset> export({
    required String name,
    String? author,
    String? description,
    List<String> tags = const [],
    String? license,
    String? derivedFrom,
  }) async {
    final canvasEntries = await entityGraph.getCanvasNodes();

    final nodes = canvasEntries.map((entry) {
      return WorkflowNodeData.fromEntity(entry.entity, entry.props);
    }).toList();

    // 收集所有畫布上節點之間的關聯
    final edges = <WorkflowEdgeData>[];
    final nodeIds = nodes.map((n) => n.id).toSet();
    for (final node in nodes) {
      final relations = await entityGraph.getRelations(node.id);
      for (final rel in relations) {
        if (nodeIds.contains(rel.targetId)) {
          edges.add(WorkflowEdgeData.fromRelation(rel));
        }
      }
    }

    return WorkflowAsset(
      version: '1.0',
      metadata: WorkflowMetadata(
        name: name,
        author: author,
        description: description,
        tags: tags,
        license: license,
        created: DateTime.now().toIso8601String(),
        engineVersion: '1.0',
        derivedFrom: derivedFrom,
      ),
      nodes: nodes,
      edges: edges,
    );
  }

  /// 匯出為 JSON 字串
  Future<String> exportToJsonString({
    required String name,
    String? author,
    String? description,
    List<String> tags = const [],
    String? license,
    String? derivedFrom,
  }) async {
    final asset = await export(
      name: name,
      author: author,
      description: description,
      tags: tags,
      license: license,
      derivedFrom: derivedFrom,
    );
    return asset.toJsonString();
  }

  /// 匯出為檔案
  Future<File> exportToFile({
    required String filePath,
    required String name,
    String? author,
    String? description,
    List<String> tags = const [],
    String? license,
    String? derivedFrom,
  }) async {
    final jsonStr = await exportToJsonString(
      name: name,
      author: author,
      description: description,
      tags: tags,
      license: license,
      derivedFrom: derivedFrom,
    );
    final file = File(filePath);
    return file.writeAsString(jsonStr);
  }

  /// 從 JSON 字串匯入
  ///
  /// 注意：匯入後節點 ID 可能需要重新生成以避免衝突。
  /// 如果 [newIds] 為 true（預設），會為所有節點生成新 ID 並重映射連線。
  Future<WorkflowAsset> importFromString(String jsonStr,
      {bool newIds = true}) async {
    final asset = WorkflowAsset.fromJsonString(jsonStr);
    if (!newIds) return asset;

    // 重新生成 ID
    final idMap = <String, String>{};
    final now = DateTime.now().microsecondsSinceEpoch;
    var counter = 0;
    final newNodes = <WorkflowNodeData>[];
    for (final node in asset.nodes) {
      final newId = 'wf-${now}-${counter++}';
      idMap[node.id] = newId;
      newNodes.add(WorkflowNodeData(
        id: newId,
        nodeType: node.nodeType,
        x: node.x,
        y: node.y,
        width: node.width,
        height: node.height,
        title: node.title,
        params: node.params,
        ports: node.ports,
      ));
    }

    final newEdges = <WorkflowEdgeData>[];
    for (final edge in asset.edges) {
      final newSource = idMap[edge.source];
      final newTarget = idMap[edge.target];
      if (newSource != null && newTarget != null) {
        newEdges.add(WorkflowEdgeData(
          source: newSource,
          target: newTarget,
          relationType: edge.relationType,
          dataType: edge.dataType,
          sourcePort: edge.sourcePort,
          targetPort: edge.targetPort,
        ));
      }
    }

    return WorkflowAsset(
      version: asset.version,
      metadata: asset.metadata,
      nodes: newNodes,
      edges: newEdges,
    );
  }

  /// 從檔案匯入
  Future<WorkflowAsset> importFromFile(String filePath,
      {bool newIds = true}) async {
    final file = File(filePath);
    final jsonStr = await file.readAsString();
    return importFromString(jsonStr, newIds: newIds);
  }
}
