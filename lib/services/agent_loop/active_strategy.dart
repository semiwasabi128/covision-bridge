/// ActiveStrategy — NativeAgentLoop 查詢「最終生效」的策略結果
///
/// 用途（見 02-架構設計/custom-routing-policy-design.md §C.5）：
/// ProviderProfileStore.resolveActiveStrategy() 會把「內建 Profile + CustomRoutingPolicy 覆寫」
/// 合併成一個 ActiveStrategy 物件，NativeAgentLoop 直接讀這個物件決定：
/// - maxTurns / taskChunkSize 怎麼跑
/// - apiParams 帶什麼送給 LLM API
/// - promptNudge 注入什麼 prompt 前綴
///
/// ## 設計動機
/// 為什麼不直接回傳 ProviderProfile？
/// - ProviderProfile 是「模型能力事實」（由基準測試決定）
/// - ActiveStrategy 是「使用者調用偏好 + 模型能力」的合併結果
/// - 兩者生命週期不同，分開型別避免 NativeAgentLoop 不小心寫到內建 Profile
///
/// ## 與 Phase 2 的關係
/// - `unlimited` 欄位目前固定 false（ProviderProfile 還沒有 unlimited 欄位）
/// - Phase 2 會在 ProviderProfile 加上 unlimited；本類別結構已預留，Phase 2 只需修改 resolveActiveStrategy() 實作
///
/// [教練 Agent 2026-07-30 Phase 4] 自訂調用原則的回傳型別
library;

import 'agent_provider_profile.dart';

class ActiveStrategy {
  /// 是否為「無限制」模式（跳過 maxTurns / taskChunkSize 限制）
  ///
  /// Phase 4 預設 false——ProviderProfile 還沒有 unlimited 欄位。
  /// Phase 2 加上後，resolveActiveStrategy() 會從 ProviderProfile 讀取。
  final bool unlimited;

  /// 建議最大輪數（null = 由 unlimited 決定）
  final int? suggestedMaxTurns;

  /// 單次任務建議拆分大小（null = 由 unlimited 決定）
  final int? suggestedTaskChunkSize;

  /// 額外的 prompt 提示（注入到 perception prompt）
  final String? promptNudge;

  /// API 參數（已與內建 apiParams 深度合併）
  final Map<String, dynamic> apiParams;

  /// 套用的 provider（呼叫者提供的）
  final String provider;

  /// 套用的 model（呼叫者提供的）
  final String model;

  /// 能力分層（從內建 Profile 取得；CustomRoutingPolicy 可用 overrides['tier'] 覆寫）
  final ProviderTier tier;

  const ActiveStrategy({
    required this.unlimited,
    required this.suggestedMaxTurns,
    required this.suggestedTaskChunkSize,
    required this.promptNudge,
    required this.apiParams,
    required this.provider,
    required this.model,
    required this.tier,
  });

  @override
  String toString() {
    return 'ActiveStrategy($provider/$model, '
        'tier=${tier.name}, unlimited=$unlimited, '
        'maxTurns=$suggestedMaxTurns, chunkSize=$suggestedTaskChunkSize, '
        'apiParams=${apiParams.length} keys)';
  }
}