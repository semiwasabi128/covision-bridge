/// 使用者自訂模型調用原則
///
/// 設計目標（見 02-架構設計/custom-routing-policy-design.md §B.1）：
/// - overrides 只覆寫指定欄位，其餘沿用內建 Profile（避免使用者每改一次就要重寫整個 profile）
/// - isActive 切換：新原則啟動時舊的立即棄用（自動機制，不需 App Agent 提醒）
/// - description 保留自然語言，方便日後查閱「我當初為什麼這樣設」
///
/// ## 欄位生命週期
/// - v1.0：`id` / `name` / `description` / `createdAt` / `provider` / `model` / `isActive` / `overrides`
/// - v1.1 預留：`taskRouting`（場景 2 任務分流）、`flowOverride`（場景 4 流程覆寫）——保留欄位但不實作邏輯
///
/// ## overrides 支援的鍵（見設計文件 §B.2）
/// - `tier`: ProviderTier（`'tier1'` / `'tier2'` / `'tier3'`）
/// - `maxTurns`: int
/// - `forceToolUse`: bool
/// - `taskChunkSize`: int
/// - `apiParams`: `Map<String, dynamic>`（**深度合併**，不完全替換）
/// - `promptNudge`: `String?`
/// - `supportsReasoningContent`: bool
/// - `visionModel`: `String?`
///
/// [教練 Agent 2026-07-30 Phase 4] 自訂調用原則資料類別
library;

class CustomRoutingPolicy {
  /// 唯一 ID（建議命名：`crp_<provider>_<short_slug>_<timestamp>`）
  final String id;

  /// 使用者命名的易記名稱（顯示在設定頁）
  final String name;

  /// 自然語言描述（App Agent 幫忙生成的說明 + 使用者原話摘要）
  final String description;

  /// 建立時間
  final DateTime createdAt;

  /// 套用的 provider（多個 policy 可並存，但同一個 provider 同時只有一個 active）
  final String provider;

  /// 套用的 model（null = 該 provider 下所有 model 都套用）
  final String? model;

  /// 是否活躍
  /// - 只有活躍的原則會被 ProviderProfileStore 套用
  /// - 同一 provider 切換 active 時，舊的自動 isActive = false
  final bool isActive;

  /// 覆寫欄位（只覆寫指定欄位，其餘沿用內建 Profile）
  /// 支援的鍵見類別註解
  final Map<String, dynamic> overrides;

  /// [v1.1 預留] 任務分流規則（場景 2 用）
  /// v1.0 不實作，但保留欄位以避免日後破壞性變更
  final Map<String, dynamic>? taskRouting;

  /// [v1.1 預留] 整流程覆寫（場景 4 用）
  /// v1.0 不實作
  final Map<String, dynamic>? flowOverride;

  const CustomRoutingPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.provider,
    this.model,
    required this.isActive,
    required this.overrides,
    this.taskRouting,
    this.flowOverride,
  });

  /// 複製並修改指定欄位（用於切換 active）
  ///
  /// 目前只支援 [isActive] 覆寫——v1.0 的唯一動態操作就是「啟用/停用」。
  /// 其他欄位變更走「建立新版 + 停用舊版」流程（見設計文件 §E.3 流程 C）。
  CustomRoutingPolicy copyWith({bool? isActive}) {
    return CustomRoutingPolicy(
      id: id,
      name: name,
      description: description,
      createdAt: createdAt,
      provider: provider,
      model: model,
      isActive: isActive ?? this.isActive,
      overrides: overrides,
      taskRouting: taskRouting,
      flowOverride: flowOverride,
    );
  }

  /// 序列化為 JSON（供 ProviderProfileStore 寫入 provider_profiles.json）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'provider': provider,
      if (model != null) 'model': model,
      'isActive': isActive,
      'overrides': overrides,
      if (taskRouting != null) 'taskRouting': taskRouting,
      if (flowOverride != null) 'flowOverride': flowOverride,
    };
  }

  /// 從 JSON 反序列化（容錯設計：缺欄位用合理預設，避免舊資料破壞新版本）
  factory CustomRoutingPolicy.fromJson(Map<String, dynamic> json) {
    return CustomRoutingPolicy(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
          ?? DateTime.now(),
      provider: json['provider'] as String? ?? 'unknown',
      model: json['model'] as String?,
      isActive: json['isActive'] as bool? ?? false,
      overrides: Map<String, dynamic>.from(
        json['overrides'] as Map? ?? const {},
      ),
      taskRouting: json['taskRouting'] != null
          ? Map<String, dynamic>.from(json['taskRouting'] as Map)
          : null,
      flowOverride: json['flowOverride'] != null
          ? Map<String, dynamic>.from(json['flowOverride'] as Map)
          : null,
    );
  }

  /// 給設定頁用的簡要字串（debug / log 用）
  @override
  String toString() {
    final modelStr = model ?? '*';
    return 'CustomRoutingPolicy($id: $name, $provider/$modelStr, '
        'isActive=$isActive, overrides=${overrides.length} keys)';
  }
}