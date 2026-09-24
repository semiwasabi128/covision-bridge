// open_canvas_node.dart
// 泛用畫布節點——支援任意 Entity 類型（不限 Memory）
// B3 Phase 1.5 Open Canvas 拖放互動系統
//
// 與 S18a CanvasNode 的差異：
// - CanvasNode 只綁 Memory，OpenCanvasNode 綁任意 Entity
// - OpenCanvasNode 支援 Entity 來源標記（human/agent/suggestion）
// - 圓形節點（Memory）vs 矩形節點（Asset/Door/Annotation）由 type 決定

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:flutter/material.dart';

/// [教練 Agent 2026-07-25] 節點實際渲染尺寸快取
///
/// NodeWidget 渲染後測量實際尺寸，存到這裡。
/// estimatedRenderSize 優先讀取此 cache，fallback 到估算值。
/// 這樣 hitTest、snapshot、fitToContent 都能用實際尺寸而非估算。
class ActualSizeCache {
  ActualSizeCache._();
  static final ActualSizeCache _instance = ActualSizeCache._();
  factory ActualSizeCache() => _instance;

  final Map<String, Size> _sizes = {};

  static Size? get(String nodeId) => _instance._sizes[nodeId];
  static void set(String nodeId, Size size) => _instance._sizes[nodeId] = size;
  static void remove(String nodeId) => _instance._sizes.remove(nodeId);
  static void clear() => _instance._sizes.clear();
}

/// 畫布上的泛用節點，對應一個 [Entity]。
///
/// 包含世界座標位置與衍生視覺屬性。
/// 位置由拖曳或初始佈局產生，不由 Entity 自帶。
class OpenCanvasNode {
  /// 對應的 Entity ID
  final String id;

  /// 世界座標位置
  final Offset position;

  /// 節點寬度（世界座標）
  final double width;

  /// 節點高度（世界座標）
  final double height;

  /// 底層 Entity
  final Entity entity;

  /// 是否被拖曳中（由 widget state 管理）
  final bool isDragging;

  /// 是否被選中
  final bool isSelected;

  /// 是否為 Agent 建議節點（半透明 + 確認按鈕）
  final bool isSuggestion;

  OpenCanvasNode({
    required this.id,
    required this.position,
    required this.entity,
    this.width = 120.0,
    this.height = 70.0,
    this.isDragging = false,
    this.isSelected = false,
    this.isSuggestion = false,
  });

  /// 從 CanvasEntry 建構（Entity + CanvasProps）
  factory OpenCanvasNode.fromCanvasEntry(
    Entity entity,
    CanvasProps props, {
    bool isSelected = false,
  }) {
    // 確保 entity 帶有 canvasProps（fallback entity 可能剛被設上）
    final entityWithProps = entity.canvasProps != null
        ? entity
        : Entity(
            id: entity.id,
            type: entity.type,
            title: entity.title,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            companionId: entity.companionId,
            source: entity.source,
            tags: entity.tags,
            relations: entity.relations,
            canvasProps: props,
            underlying: entity.underlying,
          );
    return OpenCanvasNode(
      id: entity.id,
      position: Offset(props.x, props.y),
      width: props.width,
      height: props.height,
      entity: entityWithProps,
      isSelected: isSelected,
      isSuggestion: entity.source == EntitySource.agent,
    );
  }

  // ── 衍生視覺屬性 ──

  /// Entity 類型對應的主色
  Color get color => typeColor(entity.type);

  /// Entity 類型配色
  static Color typeColor(EntityType type) {
    switch (type) {
      case EntityType.memory:
        return const Color(0xFFCE93D8); // 紫
      case EntityType.asset:
        return const Color(0xFF4FC3F7); // 淺藍
      case EntityType.door:
        return const Color(0xFFFFB74D); // 橙
      case EntityType.flowstep:
        return const Color(0xFF66BB6A); // 綠
      case EntityType.screencapture:
        return const Color(0xFFEF5350); // 紅
      case EntityType.annotation:
        return const Color(0xFFFFCA28); // 琥珀
    }
  }

  /// Entity 類型圖示 emoji
  String get icon {
    switch (entity.type) {
      case EntityType.memory:
        return '🧠';
      case EntityType.asset:
        return '📦';
      case EntityType.door:
        return '🚪';
      case EntityType.flowstep:
        return '✅';
      case EntityType.screencapture:
        return '📸';
      case EntityType.annotation:
        return '📝';
    }
  }

  /// 標籤文字（截斷的 title）
  String get label {
    final text = entity.title.trim();
    if (text.length <= 40) return text;
    return '${text.substring(0, 37)}...';
  }

  /// 節點中心點
  Offset get center => position + Offset(width / 2, height / 2);

  /// [教練 Agent 2026-07-24] 估算實際渲染尺寸
  /// model 的 width/height 是預設 120x70，但 IntrinsicWidth 會根據 inline widgets 撐開
  /// 這裡按節點類型估算，用於 fitToContent / hitTest
  ///
  /// [教練 Agent 2026-07-25] 改為優先使用實際渲染尺寸（由 NodeWidget 測量後寫入 cache）
  /// fallback 到估算值
  (double, double) get estimatedRenderSize {
    // 優先用實際測量值
    final actual = ActualSizeCache.get(id);
    if (actual != null) return (actual.width, actual.height);

    final nodeType = entity.canvasProps?.nodeType;
    if (nodeType == null) {
      final w = width < 100 ? 160.0 : width;
      final h = height < 60 ? 80.0 : height;
      return (w, h);
    }
    return switch (nodeType) {
      WorkflowNodeType.llm => (322.0, 300.0),       // 實測：maxWidth:320 + border
      WorkflowNodeType.tool => (322.0, 220.0),       // 同 maxWidth
      WorkflowNodeType.imageGen => (322.0, 220.0),   // 實測
      WorkflowNodeType.vision => (322.0, 200.0),     // [教練 Agent 2026-08-01]
      WorkflowNodeType.characterLock => (322.0, 240.0), // [教練 Agent 2026-08-01]
      WorkflowNodeType.videoGen => (322.0, 240.0),
      WorkflowNodeType.musicGen => (322.0, 240.0),
      WorkflowNodeType.tts => (322.0, 180.0),
      WorkflowNodeType.move => (322.0, 160.0), // 🥋 [Blue 拍板] 招式節點
      WorkflowNodeType.condition => (322.0, 100.0),  // maxWidth:320 影響
      WorkflowNodeType.merge => (322.0, 100.0),
      WorkflowNodeType.subWorkflow => (322.0, 100.0),
      WorkflowNodeType.input => (200.0, 146.0),      // 實測
      WorkflowNodeType.output => (200.0, 146.0),     // 實測
      WorkflowNodeType.schedule => (322.0, 120.0),
      WorkflowNodeType.knowledge => (322.0, 220.0),  // [教練 Agent 2026-08-16] vault 知識節點
      WorkflowNodeType.materialPool => (322.0, 300.0), // [教練 Agent 2026-08-25 F-1] 素材池（含採用UI）
    };
  }

  /// 點擊測試：世界座標 [point] 是否在節點範圍內
  bool hitTest(Offset point) {
    final (w, h) = estimatedRenderSize;
    final rect = Rect.fromLTWH(position.dx, position.dy, w, h);
    return rect.contains(point);
  }

  /// 是否為 Agent 建的節點
  bool get isFromAgent => entity.source == EntitySource.agent;

  /// 邊框樣式：Agent 建的用虛線，人的用實線，建議用半透明
  bool get isDashedBorder => isFromAgent;

  OpenCanvasNode copyWith({
    Offset? position,
    double? width,
    double? height,
    Entity? entity,
    bool? isDragging,
    bool? isSelected,
    bool? isSuggestion,
  }) {
    return OpenCanvasNode(
      id: id,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      entity: entity ?? this.entity,
      isDragging: isDragging ?? this.isDragging,
      isSelected: isSelected ?? this.isSelected,
      isSuggestion: isSuggestion ?? this.isSuggestion,
    );
  }

  @override
  String toString() =>
      'OpenCanvasNode(id: $id, type: ${entity.type.name}, '
      'pos: ${position.dx.toStringAsFixed(0)},${position.dy.toStringAsFixed(0)})';
}

// ── WorkflowNodeType 共用 helpers ──────────────────────────

/// 工作流節點類型的中文標籤。
String workflowNodeTypeLabel(WorkflowNodeType type) {
  switch (type) {
    case WorkflowNodeType.input: return '輸入';
    case WorkflowNodeType.llm: return 'LLM 推論';
    case WorkflowNodeType.tool: return '工具呼叫';
    case WorkflowNodeType.imageGen: return '圖片生成';
    case WorkflowNodeType.vision: return '圖片理解'; // [教練 Agent 2026-08-01]
    case WorkflowNodeType.characterLock: return '角色一致性'; // [教練 Agent 2026-08-01]
    case WorkflowNodeType.videoGen: return '影片生成';
    case WorkflowNodeType.musicGen: return '音樂生成';
    case WorkflowNodeType.tts: return '語音合成';
    case WorkflowNodeType.move: return '🥋 招式';
    case WorkflowNodeType.condition: return '條件分支';
    case WorkflowNodeType.merge: return '合併';
    case WorkflowNodeType.output: return '輸出';
    case WorkflowNodeType.subWorkflow: return '子工作流';
    case WorkflowNodeType.schedule: return '排程任務';
    case WorkflowNodeType.knowledge: return 'Vault 知識'; // [教練 Agent 2026-08-16]
    case WorkflowNodeType.materialPool: return '素材池'; // [教練 Agent 2026-08-25 F-1]
  }
}

/// 工作流節點類型的說明文字。
String workflowNodeTypeDescription(WorkflowNodeType type) {
  switch (type) {
    case WorkflowNodeType.input: return '文字/圖片/檔案輸入，工作流起點';
    case WorkflowNodeType.llm: return '選擇模型 + Prompt，進行 AI 推論';
    case WorkflowNodeType.tool: return '呼叫 Agent 工具（搜尋、檔案、記憶等）';
    case WorkflowNodeType.imageGen: return '生成圖片';
    case WorkflowNodeType.vision: return '分析圖片內容、辨識角色、OCR'; // [教練 Agent 2026-08-01]
    case WorkflowNodeType.characterLock: return '參考圖 + Prompt → 角色一致的新圖'; // [教練 Agent 2026-08-01]
    case WorkflowNodeType.videoGen: return '生成影片';
    case WorkflowNodeType.musicGen: return '生成音樂';
    case WorkflowNodeType.tts: return '文字轉語音朗讀';
    case WorkflowNodeType.move: return '使出訓練AI夥伴錄製的招式（全電腦代操作）';
    case WorkflowNodeType.condition: return 'if/else 條件分支';
    case WorkflowNodeType.merge: return '多個輸入合併為一';
    case WorkflowNodeType.output: return '結果展示/匯出，工作流終點';
    case WorkflowNodeType.subWorkflow: return '嵌入另一個工作流';
    case WorkflowNodeType.schedule: return '每天/每週/指定日期時間觸發任務';
    case WorkflowNodeType.materialPool: return 'AI 產候選發想，人採用→共視產物'; // [教練 Agent 2026-08-25 F-1]
    case WorkflowNodeType.knowledge: return 'vault 向量庫檢索，把大腦記憶變成工作流原料'; // [教練 Agent 2026-08-16]
  }
}

/// 工作流節點類型的 emoji 圖示。
String workflowNodeTypeIcon(WorkflowNodeType type) {
  switch (type) {
    case WorkflowNodeType.input: return '📥';
    case WorkflowNodeType.llm: return '🧠';
    case WorkflowNodeType.tool: return '🔧';
    case WorkflowNodeType.imageGen: return '🎨';
    case WorkflowNodeType.vision: return '👁️'; // [教練 Agent 2026-08-01]
    case WorkflowNodeType.characterLock: return '🔐'; // [教練 Agent 2026-08-01]
    case WorkflowNodeType.videoGen: return '🎬';
    case WorkflowNodeType.musicGen: return '🎵';
    case WorkflowNodeType.tts: return '🗣️';
    case WorkflowNodeType.move: return '🥋'; // [Blue 拍板] 招式節點
    case WorkflowNodeType.condition: return '🔀';
    case WorkflowNodeType.merge: return '🔗';
    case WorkflowNodeType.output: return '📤';
    case WorkflowNodeType.subWorkflow: return '📦';
    case WorkflowNodeType.schedule: return '⏰';
    case WorkflowNodeType.knowledge: return '📚'; // [教練 Agent 2026-08-16] vault 知識節點
    case WorkflowNodeType.materialPool: return '💡'; // [教練 Agent 2026-08-25 F-1] 素材池
  }
}

/// 工作流節點類型的主色。
Color workflowNodeTypeColor(WorkflowNodeType type) {
  switch (type) {
    case WorkflowNodeType.input: return const Color(0xFF66BB6A); // 綠
    case WorkflowNodeType.llm: return const Color(0xFFCE93D8); // 紫
    case WorkflowNodeType.tool: return const Color(0xFFFFB74D); // 橙
    case WorkflowNodeType.imageGen: return const Color(0xFFEF5350); // 紅
    case WorkflowNodeType.vision: return const Color(0xFF26A69A); // 蒼綠 [教練 Agent 2026-08-01]
    case WorkflowNodeType.characterLock: return const Color(0xFFFF7043); // 深橙 [教練 Agent 2026-08-01]
    case WorkflowNodeType.videoGen: return const Color(0xFF42A5F5); // 藍
    case WorkflowNodeType.musicGen: return const Color(0xFFAB47BC); // 深紫
    case WorkflowNodeType.tts: return const Color(0xFFFFCA28); // 琥珀
    case WorkflowNodeType.move: return const Color(0xFFFF8A65); // 深橙紅 [Blue 拍板] 招式
    case WorkflowNodeType.condition: return const Color(0xFF26C6DA); // 青
    case WorkflowNodeType.merge: return const Color(0xFF78909C); // 灰藍
    case WorkflowNodeType.output: return const Color(0xFF9CCC65); // 黃綠
    case WorkflowNodeType.subWorkflow: return const Color(0xFF8D6E63); // 棕
    case WorkflowNodeType.schedule: return const Color(0xFFFF7043); // 深橙
    case WorkflowNodeType.knowledge: return const Color(0xFF5C6BC0); // 靛紫 [教練 Agent 2026-08-16] vault 知識節點
    case WorkflowNodeType.materialPool: return const Color(0xFFFFD54F); // 金黃 [教練 Agent 2026-08-25 F-1] 素材池（共視產物色）
  }
}

/// 畫布上的泛用邊，對應一條 [EntityRelation]。
class OpenCanvasEdge {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final RelationType relationType;

  OpenCanvasEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.relationType,
  });

  /// 關聯類型配色
  Color get color {
    switch (relationType) {
      case RelationType.relates:
        return const Color(0xFF9CCC65); // 黃綠
      case RelationType.depends:
        return const Color(0xFF42A5F5); // 藍
      case RelationType.derives:
        return const Color(0xFFAB47BC); // 紫
      case RelationType.blocks:
        return const Color(0xFFEF5350); // 紅
      case RelationType.contains:
        return const Color(0xFFFFCA28); // 琥珀
      case RelationType.references:
        return const Color(0xFF78909C); // 灰藍
    }
  }

  double get strokeWidth => 1.5;

  bool get isDashed => relationType == RelationType.relates;

  double get opacity => 0.5;

  @override
  String toString() =>
      'OpenCanvasEdge($fromNodeId →${relationType.name}→ $toNodeId)';
}
