// entity.dart
// EntityGraphService 統一 Entity 基底 model
// 建立日期: 2026-07-10
//
// 設計文件: entity-graph-service-design.md §1
//
// Entity 是包裝層，不是繼承——底層 Model 透過 `underlying` 欄位保留原始物件。

/// Entity 類型——對應設計文件的六種 Entity。
enum EntityType {
  memory,        // → MemoryStore
  asset,         // → DigitalAssetRegistryStore
  door,          // → ProjectDoorStore
  flowstep,      // → ProjectDoorStore（內嵌於 Door）
  screencapture, // → 新建 ScreenCaptureStore（Phase 1.5 B4）
  annotation,    // → 新建（Phase 1.5 B3，畫布上的標注）
}

/// Entity 的原始來源。
enum EntitySource { human, agent }

/// Entity 之間的關聯類型。
enum RelationType {
  relates,    // 一般關聯
  depends,    // 依賴（A 需要 B 才能完成）
  derives,    // 衍生（A 從 B 產生）
  blocks,     // 阻擋（A 阻擋 B 進行）
  contains,   // 包含（門包含 flowstep）
  references, // 引用（門引用記憶/資產）
}

/// Entity 之間的關聯。
class EntityRelation {
  final String sourceId;
  final String targetId;
  final RelationType type;

  /// SemiCanvas: 資料流型別（僅 depends 類型的工作流連線使用）
  final PortDataType? dataType;

  /// SemiCanvas: 來源埠名稱（如 "output"）
  final String? sourcePort;

  /// SemiCanvas: 目標埠名稱（如 "prompt", "input"）
  final String? targetPort;

  const EntityRelation({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.dataType,
    this.sourcePort,
    this.targetPort,
  });

  /// 是否為 SemiCanvas 工作流資料流連線
  bool get isDataFlow => type == RelationType.depends && dataType != null;

  /// 序列化為 JSON Map（供 EntityRelationStore 持久化）。
  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'type': type.name,
        if (dataType != null) 'dataType': dataType!.name,
        if (sourcePort != null) 'sourcePort': sourcePort,
        if (targetPort != null) 'targetPort': targetPort,
      };

  /// 從 JSON Map 反序列化。
  factory EntityRelation.fromJson(Map<String, dynamic> json) {
    return EntityRelation(
      sourceId: json['sourceId'] as String,
      targetId: json['targetId'] as String,
      type: RelationType.values.byName(json['type'] as String),
      dataType: json['dataType'] != null
          ? PortDataType.values.byName(json['dataType'] as String)
          : null,
      sourcePort: json['sourcePort'] as String?,
      targetPort: json['targetPort'] as String?,
    );
  }

  @override
  String toString() =>
      'EntityRelation($sourceId →${type.name}→ $targetId'
      '${dataType != null ? ' [${dataType!.name}]' : ''})';
}

/// 統一 Entity 基底。
///
/// 不是繼承現有 Model——是包裝。
/// 底層 Model 透過 `underlying` 欄位保留原始物件。
class Entity {
  final String id;
  final EntityType type;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? companionId;     // 誰產生的（Agent ID 或 'human'）
  final EntitySource source;     // human | agent
  final List<String> tags;
  final List<EntityRelation> relations;
  final CanvasProps? canvasProps; // null = 不在畫布上

  /// 原始底層物件（Memory / ProjectDoor / DigitalAsset / FlowStep 等）
  /// 用 dynamic 避免循環依賴；呼叫端用 type 判斷後 cast。
  final dynamic underlying;

  const Entity({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.companionId,
    required this.source,
    required this.tags,
    required this.relations,
    this.canvasProps,
    this.underlying,
  });

  /// 是否在畫布上。
  bool get isOnCanvas => canvasProps != null;

  @override
  String toString() =>
      'Entity(id: $id, type: $type, title: "$title", onCanvas: $isOnCanvas)';
}

// ── CanvasProps 相關 enum ──────────────────────────────────

/// 畫布節點的視覺狀態。
enum CanvasVisualState { idle, active, done, blocked }

/// 畫布節點的來源（從哪裡拖進來的）。
enum CanvasNodeOrigin { brain, file, assetPack, createdOnCanvas, screenshot }

/// 畫布節點在工作流中的角色。
enum CanvasNodeRole { reference, task, output, decision }

/// SemiCanvas 工作流節點型別。
/// null = 不是工作流節點（普通標注/記憶等）。
enum WorkflowNodeType {
  /// 文字/圖片/檔案輸入 — 工作流起點
  input,
  /// LLM 推論節點 — 選 model + prompt + temperature
  llm,
  /// 工具呼叫節點 — 呼叫 Agent 工具（browse, desktop_files, memory_search...）
  tool,
  /// 圖片生成節點
  imageGen,
  /// 圖片理解節點（Vision）— 接收圖片 + prompt → 分析內容
  /// [教練 Agent 2026-08-01] 影像工作流核心：分鏡分析、角色辨識、OCR
  vision,
  /// 角色一致性節點 — 給參考圖 + prompt → 生成風格一致的新圖
  /// [教練 Agent 2026-08-01] 三層方案：OpenAI(80%) → Flux+IP-Adapter(90%) → ComfyUI(95%)
  characterLock,
  /// 影片生成節點
  videoGen,
  /// 音樂生成節點
  musicGen,
  /// 文字轉語音節點
  tts,
  /// 🥋 招式節點 — 執行訓練AI夥伴錄製的操作序列（SystemRoutine 重播）
  /// [Blue 拍板 2026-09-12] 招式＝訓練教材；可接在 LLM 之後、可進排程
  move,
  /// 條件分支節點 — if/else
  condition,
  /// 多輸入合併節點
  merge,
  /// 結果展示/匯出節點 — 工作流終點
  output,
  /// 子工作流 — 嵌入另一個 .bridge-workflow
  subWorkflow,
  /// 排程任務節點 — 每天/每週/指定日期時間觸發
  schedule,
  /// [教練 Agent 2026-08-16] Vault 知識節點 — 向量庫檢索結果包成節點。
  /// 大腦↔畫布的橋：query 進去、檢索到的知識當原料輸出（text），
  /// 可接 LLM/merge 等任何下游。本地 EmbeddingGemma 語意搜尋，零 API key。
  knowledge,
  /// [教練 Agent 2026-08-25 F-1] 素材池節點 — 共視宣言落地第一棒。
  /// AI 產 N 條候選發想（提議）→ 人採用/跳過（回應）→
  /// 被採用的自動掛 coCreated: true（機制 4 共視產物標記）。
  /// 共識往返的畫布載體（使用者 2026-08-25 簽核：幽靈節點形態不做，素材池承擔）。
  materialPool,
}

/// 資料流型別 — 連線的資料型別。
enum PortDataType { text, image, audio, video, json, file, any }

/// 埠定義 — 節點的輸入或輸出埠。
class PortDef {
  final String name;       // 埠名稱（如 "prompt", "output", "reference"）
  final PortDataType dataType;
  final bool isOutput;     // true = 輸出埠, false = 輸入埠
  final bool required;     // 輸入埠是否必填

  const PortDef({
    required this.name,
    this.dataType = PortDataType.text,
    this.isOutput = false,
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'dataType': dataType.name,
        'isOutput': isOutput,
        'required': required,
      };

  factory PortDef.fromJson(Map<String, dynamic> m) {
    return PortDef(
      name: m['name'] as String,
      dataType: PortDataType.values.byName(m['dataType'] as String? ?? 'text'),
      isOutput: m['isOutput'] as bool? ?? false,
      required: m['required'] as bool? ?? false,
    );
  }
}

/// 畫布上的空間屬性。null = Entity 不在畫布上。
///
/// 與現有 CanvasNode 的差異：
/// - CanvasNode 只綁 Memory，CanvasProps 綁任何 Entity
/// - CanvasProps 需持久化（CanvasNode 目前是 runtime state）
/// - SemiCanvas: nodeType + params + ports 讓畫布從「規劃視覺化」升級為「工作流引擎」
class CanvasProps {
  final double x;
  final double y;
  final double width;
  final double height;
  final CanvasVisualState visualState;
  final CanvasNodeOrigin origin;       // 從哪裡拖進來的
  final CanvasNodeRole roleInWorkflow;  // 在工作流中的角色
  final List<String> agentAnnotationIds; // Agent 加的標注 ID 列表

  /// SemiCanvas: 工作流節點型別（null = 非工作流節點）
  final WorkflowNodeType? nodeType;

  /// SemiCanvas: 節點參數（model, prompt, temperature, toolName 等）
  final Map<String, dynamic> params;

  /// SemiCanvas: 輸入/輸出埠定義
  final List<PortDef> ports;

  /// SemiCanvas: 上次執行結果（臨時，不持久化）
  final String? lastOutput;

  /// 所屬畫布 ID（區分不同畫布的節點）
  final String? canvasId;

  const CanvasProps({
    required this.x,
    required this.y,
    this.width = 120.0,
    this.height = 80.0,
    this.visualState = CanvasVisualState.idle,
    this.origin = CanvasNodeOrigin.createdOnCanvas,
    this.roleInWorkflow = CanvasNodeRole.reference,
    this.agentAnnotationIds = const [],
    this.nodeType,
    this.params = const {},
    this.ports = const [],
    this.lastOutput,
    this.canvasId,
  });

  /// 是否為工作流節點
  bool get isWorkflowNode => nodeType != null;

  /// 輸入埠列表
  List<PortDef> get inputPorts => ports.where((p) => !p.isOutput).toList();

  /// 輸出埠列表
  List<PortDef> get outputPorts => ports.where((p) => p.isOutput).toList();

  /// 複製並修改部分欄位。
  CanvasProps copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    CanvasVisualState? visualState,
    CanvasNodeOrigin? origin,
    CanvasNodeRole? roleInWorkflow,
    List<String>? agentAnnotationIds,
    WorkflowNodeType? nodeType,
    Map<String, dynamic>? params,
    List<PortDef>? ports,
    String? lastOutput,
    String? canvasId,
  }) {
    return CanvasProps(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      visualState: visualState ?? this.visualState,
      origin: origin ?? this.origin,
      roleInWorkflow: roleInWorkflow ?? this.roleInWorkflow,
      agentAnnotationIds: agentAnnotationIds ?? this.agentAnnotationIds,
      nodeType: nodeType ?? this.nodeType,
      params: params ?? this.params,
      ports: ports ?? this.ports,
      lastOutput: lastOutput ?? this.lastOutput,
      canvasId: canvasId ?? this.canvasId,
    );
  }

  /// 序列化為 JSON Map（供 CanvasStateStore 持久化）。
  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'visualState': visualState.name,
        'origin': origin.name,
        'roleInWorkflow': roleInWorkflow.name,
        'agentAnnotationIds': agentAnnotationIds,
        if (nodeType != null) 'nodeType': nodeType!.name,
        if (params.isNotEmpty) 'params': params,
        if (ports.isNotEmpty)
          'ports': ports.map((p) => p.toJson()).toList(),
        if (canvasId != null) 'canvasId': canvasId,
        // lastOutput 不持久化（臨時執行結果）
      };

  /// 從 JSON Map 反序列化。
  factory CanvasProps.fromJson(Map<String, dynamic> m) {
    return CanvasProps(
      x: (m['x'] as num?)?.toDouble() ?? 0.0,
      y: (m['y'] as num?)?.toDouble() ?? 0.0,
      width: (m['width'] as num?)?.toDouble() ?? 120.0,
      height: (m['height'] as num?)?.toDouble() ?? 80.0,
      visualState: CanvasVisualState.values.byName(
          m['visualState'] as String? ?? 'idle'),
      origin: CanvasNodeOrigin.values.byName(
          m['origin'] as String? ?? 'createdOnCanvas'),
      roleInWorkflow: CanvasNodeRole.values.byName(
          m['roleInWorkflow'] as String? ?? 'reference'),
      agentAnnotationIds: (m['agentAnnotationIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      nodeType: m['nodeType'] != null
          ? WorkflowNodeType.values.byName(m['nodeType'] as String)
          : null,
      params: (m['params'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? const {},
      ports: (m['ports'] as List?)
              ?.map((p) => PortDef.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      canvasId: m['canvasId'] as String?,
    );
  }

  @override
  String toString() =>
      'CanvasProps(x: ${x.toStringAsFixed(0)}, y: ${y.toStringAsFixed(0)}, '
      'state: ${visualState.name}${nodeType != null ? ', type: ${nodeType!.name}' : ''})';
}
