// semantic_result.dart
// 語意理解結果的基礎類別。
// SemanticResultBase 是所有 domain 結果的抽象基底；
// DoorIntentResult 是門偵測 domain 的具體結果，含 L1/L3 共用欄位。

/// 語意理解結果的抽象基底。
abstract class SemanticResultBase {
  /// 信心分數 0-1
  final double confidence;

  /// LLM 或規則引擎的推理說明
  final String reasoning;

  const SemanticResultBase({
    required this.confidence,
    this.reasoning = '',
  });
}

/// 標題來源類型——門偵測結果中 projectName 的命名來源。
enum TitleSource {
  /// 使用者明確命名（如引號中的名稱）
  userNamed,
  /// LLM 推斷（未明確命名但語意明顯）
  inferred,
  /// 語意模糊，無法確定命名
  ambiguous,
}

/// 門偵測結果——L1 規則引擎與 L3 LLM 引擎共用。
class DoorIntentResult extends SemanticResultBase {
  /// 是否應建立新門
  final bool shouldCreateDoor;

  /// 專案名稱（可能為 null）
  final String? projectName;

  /// 標題來源
  final TitleSource? titleSource;

  /// 是否需要向使用者澄清
  final bool shouldClarify;

  /// 澄清提示（shouldClarify=true 時提供）
  final String? clarificationPrompt;

  /// [Phase 2 #6] 需要的橋接類型列表（由 LLM 從使用者語意推斷）
  final List<String> requiredBridges;

  const DoorIntentResult({
    required super.confidence,
    required this.shouldCreateDoor,
    this.projectName,
    this.titleSource,
    super.reasoning,
    this.shouldClarify = false,
    this.clarificationPrompt,
    this.requiredBridges = const [],
  });

  /// 從 LLM 回傳的 JSON map 組裝。
  factory DoorIntentResult.fromJson(Map<String, dynamic> json) {
    return DoorIntentResult(
      shouldCreateDoor: json['shouldCreateDoor'] as bool? ?? false,
      projectName: json['projectName'] as String?,
      // [以西結審查 A] .toString() 避免非字串型別拋 TypeError
      titleSource: _parseTitleSource(json['titleSource']?.toString()),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
      shouldClarify: json['shouldClarify'] as bool? ?? false,
      clarificationPrompt: json['clarificationPrompt'] as String?,
      requiredBridges: (json['requiredBridges'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  static TitleSource? _parseTitleSource(String? value) {
    switch (value) {
      case 'user_named':
        return TitleSource.userNamed;
      case 'inferred':
        return TitleSource.inferred;
      case 'ambiguous':
        return TitleSource.ambiguous;
      default:
        return null;
    }
  }
}

/// 門命名結果——從使用者訊息中提取專案門的名稱。
/// 由 L1RuleEngine.extractDoorTitle() 與 L3LlmEngine.extractDoorTitle() 共用。
class DoorTitleResult extends SemanticResultBase {
  /// 提取出的門名稱（可能為 null，表示無法提取）
  final String? title;

  /// 名稱來源
  final TitleSource? titleSource;

  const DoorTitleResult({
    required super.confidence,
    this.title,
    this.titleSource,
    super.reasoning,
  });

  /// 從 LLM 回傳的 JSON map 組裝（null-aware cast）。
  factory DoorTitleResult.fromJson(Map<String, dynamic> json) {
    return DoorTitleResult(
      title: json['title'] as String?,
      // [以西結審查 A] .toString() 避免非字串型別拋 TypeError
      titleSource: _parseTitleSource(json['titleSource']?.toString()),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

/// 門漂移偵測結果——判斷使用者訊息是否偏離當前門主題。
/// 由 L1RuleEngine.detectDoorDrift() 與 L3LlmEngine.detectDoorDrift() 共用。
class DoorDriftResult extends SemanticResultBase {
  /// 是否偵測到漂移（true = 訊息偏離門主題）
  final bool isDrifting;

  /// 給使用者的建議（如「是否要開新門？」）
  final String? suggestion;

  const DoorDriftResult({
    required super.confidence,
    required this.isDrifting,
    this.suggestion,
    super.reasoning,
  });

  /// 從 LLM 回傳的 JSON map 組裝（null-aware cast）。
  factory DoorDriftResult.fromJson(Map<String, dynamic> json) {
    return DoorDriftResult(
      isDrifting: json['isDrifting'] as bool? ?? false,
      suggestion: json['suggestion'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

// ============================================================
// Phase 2: RoutingIntentResult —— 路由意圖分類結果
// ============================================================

/// 路由意圖分類結果——一次 LLM 呼叫覆蓋 #4, #7, #8, #9, #10, #11。
/// 由 L1RuleEngine.classifyRoutingIntent() 與 L3LlmEngine.classifyRoutingIntent() 共用。
class RoutingIntentResult extends SemanticResultBase {
  /// 是否意圖建立/分岔專案門 (#4)
  final bool projectDoor;

  /// 是否意圖調用既有資產 (#7)
  final bool assetReuse;

  /// 是否意圖使用已存整理規則 (#8)
  final bool managedFolderRule;

  /// 是否意圖設定能力/金鑰 (#9)
  final bool capabilitySetup;

  /// 是否目標需要釐清 (#10)
  final bool goalNeedsIntake;

  /// 是否為分析/可行性問題 (#11)
  final bool isAnalysis;

  const RoutingIntentResult({
    required super.confidence,
    this.projectDoor = false,
    this.assetReuse = false,
    this.managedFolderRule = false,
    this.capabilitySetup = false,
    this.goalNeedsIntake = false,
    this.isAnalysis = false,
    super.reasoning,
  });

  factory RoutingIntentResult.fromJson(Map<String, dynamic> json) {
    return RoutingIntentResult(
      projectDoor: json['projectDoor'] as bool? ?? false,
      assetReuse: json['assetReuse'] as bool? ?? false,
      managedFolderRule: json['managedFolderRule'] as bool? ?? false,
      capabilitySetup: json['capabilitySetup'] as bool? ?? false,
      goalNeedsIntake: json['goalNeedsIntake'] as bool? ?? false,
      isAnalysis: json['isAnalysis'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

// ============================================================
// Phase 2: BridgeActionInferenceResult —— 橋接行動推斷結果
// ============================================================

/// 橋接行動推斷結果——覆蓋 #13。
/// 由 L1RuleEngine.inferBridgeAction() 與 L3LlmEngine.inferBridgeAction() 共用。
class BridgeActionInferenceResult extends SemanticResultBase {
  /// 推斷的橋接類型字串（對應 BridgeActionType.name，或 'none'）
  final String bridgeType;

  /// 是否應先分析再執行橋接
  final bool shouldAnalyzeFirst;

  const BridgeActionInferenceResult({
    required super.confidence,
    required this.bridgeType,
    this.shouldAnalyzeFirst = false,
    super.reasoning,
  });

  factory BridgeActionInferenceResult.fromJson(Map<String, dynamic> json) {
    return BridgeActionInferenceResult(
      bridgeType: json['bridgeType'] as String? ?? 'none',
      shouldAnalyzeFirst: json['shouldAnalyzeFirst'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

// ============================================================
// Phase 3: OpenIntentionResult —— 未完成意圖偵測結果
// ============================================================

/// 未完成意圖偵測結果——覆蓋 #15。
class OpenIntentionResult extends SemanticResultBase {
  /// 是否偵測到未完成意圖
  final bool hasOpenIntention;

  /// 提取出的意圖內容（如「寫完那份企劃」）
  final String? intention;

  const OpenIntentionResult({
    required super.confidence,
    this.hasOpenIntention = false,
    this.intention,
    super.reasoning,
  });

  factory OpenIntentionResult.fromJson(Map<String, dynamic> json) {
    return OpenIntentionResult(
      hasOpenIntention: json['hasOpenIntention'] as bool? ?? false,
      intention: json['intention'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

// ============================================================
// Phase 3: EmotionResult —— 情緒偵測結果
// ============================================================

/// 情緒偵測結果——覆蓋 #16。
class EmotionResult extends SemanticResultBase {
  /// 偵測到的情緒（'焦慮', '興奮', '疲憊', '困惑', 'neutral'）
  final String emotion;

  const EmotionResult({
    required super.confidence,
    this.emotion = 'neutral',
    super.reasoning,
  });

  factory EmotionResult.fromJson(Map<String, dynamic> json) {
    return EmotionResult(
      emotion: json['emotion'] as String? ?? 'neutral',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }
}

/// TitleSource 字串解析——DoorIntentResult 與 DoorTitleResult 共用。
TitleSource? _parseTitleSource(String? value) {
  switch (value) {
    case 'user_named':
      return TitleSource.userNamed;
    case 'inferred':
      return TitleSource.inferred;
    case 'ambiguous':
      return TitleSource.ambiguous;
    default:
      return null;
  }
}
