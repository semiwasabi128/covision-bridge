/// Provider 能力設定 v2 — 策略模式
///
/// 角色：告訴 Agent Loop「怎麼跟這隻模型打交道最好」，
/// 不替使用者決定模型「能做到哪裡」。
///
/// ## 設計原則（使用者 2026-07-30）
/// 1. 有金鑰的模型 = unlimited=true，不設任何限制
/// 2. 策略參數是「建議」不是「限制」
/// 3. 使用者指定模型時，所有限制預設放寬
/// 4. 使用者可自訂「調用原則」，覆蓋內建策略
///
/// 設計文件：02-架構設計/provider-profile-strategy-refactor.md
///
/// ## 欄位區分
/// - 辨識欄位：provider、model、tier
/// - 策略參數（建議，非限制）：suggestedMaxTurns、suggestedTaskChunkSize、promptNudge
/// - API 參數：apiParams（純傳遞，不再放 max_tokens / max_completion_tokens）
/// - 旗標：unlimited（預設 true）、supportsReasoningContent、visionModel、tested
///
/// ## 測試數據來源
/// 見 docs/provider_benchmark_report.md
///
/// ## 更新方式
/// 將來多測幾輪後，更新對應的 tier 和建議值即可。
/// 測試方法見 /tmp/bridge_provider_benchmark.py
library;

/// Provider 能力分層
enum ProviderTier {
  /// Tier 1：完整多步驟工具使用。收到工具結果後直接分析+修復。
  /// 可派 20+ 項批量任務。
  /// 實測：gpt-4o, glm-5
  tier1,

  /// Tier 2：能使用工具但不直接修復。收到工具結果後多繞一步確認。
  /// 拆成 5-7 項小任務，prompt 加「直接修復不要確認」。
  /// 實測：gpt-5, kimi-k3
  tier2,

  /// Tier 3：API 不穩定或能力不足。只派單一明確任務。
  /// 實測：kimi-k2.5（API 400）, glm-4.5（超時）, local 模型
  tier3}

/// Provider 能力設定
/// [教練 Agent 2026-07-30 v2] 策略模式：限制參數標 @Deprecated 並保留讀寫，
/// 新調用應改用 suggestedMaxTurns / suggestedTaskChunkSize / unlimited。
class ProviderProfile {
  final String provider;
  final String model;
  final ProviderTier tier;

  /// API 參數（必要技術參數）
  ///
  /// 注意：這裡不再放 max_tokens / max_completion_tokens。
  /// 留放的：`temperature`、`chat_template_kwargs` 等「模型性格／格式」參數。
  /// 各 provider 的溫度規則見設計文件 §B.3。
  final Map<String, dynamic> apiParams;

  // ───── 策略參數（建議，非限制）─────

  /// 軟警告門檻（不是 hard stop）。null = 不警告，交給 Agent Loop 內部 hardMaxTurns。
  /// Agent Loop 讀到非 null 時可顯示「此模型建議不要超過 N 輪」之類的提醒，
  /// 但實際上限仍由 Agent Loop 內部 hardMaxTurns=200 守護。
  final int? suggestedMaxTurns;

  /// App Agent 拆任務時的參考值。null = 讓 Agent 自行判斷任務粒度。
  final int? suggestedTaskChunkSize;

  /// 額外的 prompt 提示（注入到 perception prompt）。
  /// 讓模型在該 provider 上表現更好，模型自己決定是否採納（不是 force）。
  final String? promptNudge;

  // ───── 旗標 ─────

  /// 有金鑰 = true：完全不設任何限制。
  /// 沒金鑰 / demo 模式 = false：走保守預設。
  ///
  /// 預設 true — 所有有金鑰的 provider 自動 unlimited，
  /// 只有保守預設（conservativeProfile）才設 false。
  final bool unlimited;

  /// 是否回 reasoning_content 而非 content
  /// kimi-k2.5 等模型會把思考放在 reasoning_content，content 為空
  final bool supportsReasoningContent;

  /// Vision 模型名稱（如果主模型不支援 image_url）
  /// GLM-5.2 是純文字 reasoning 模型，不支援 image_url
  /// 遇到截圖時自動 fallback 到此 vision 模型
  /// null = 主模型自己支援 vision（如 gpt-5.4）
  final String? visionModel;

  /// 是否已經過基準測試
  /// false = 使用保守預設，原生 Agent可用 test_provider_capability 工具測試後更新
  /// true = 已測試，數據可靠
  final bool tested;

  /// [教練 Agent 2026-08-16 教練模式] 備用模型——429/額度滿時 Agent Loop 自動切。
  /// null = 沒有備用，由呼叫端自行處理。
  /// 5.3 預設綁 5-turbo（強制思考型額度滿時降級到快速型）。
  final String? suggestsFallbackModel;

  /// [教練 Agent 2026-07-30 v2] 策略模式建構子
  ///
  /// 設計：所有欄位都是獨立命名參數，沒有任何從舊欄位推導的 magic。
  /// 舊欄位（maxTurns / taskChunkSize / forceToolUse）已從建構子移除——
  /// 若舊 JSON 載入時帶有這些欄位，必須在 [`agent_profile_store.dart`] 顯式遷移。
  /// 呼叫端一律用 suggestedMaxTurns / suggestedTaskChunkSize / unlimited。
  const ProviderProfile({
    required this.provider,
    required this.model,
    required this.tier,
    this.apiParams = const {},
    this.suggestedMaxTurns,
    this.suggestedTaskChunkSize,
    this.promptNudge,
    this.unlimited = true,
    this.supportsReasoningContent = false,
    this.visionModel,
    this.tested = true,
    this.suggestsFallbackModel,
  });

  // 保留舊欄位的讀取 getter（向後相容：舊程式讀 p.maxTurns 仍能拿到建議值）
  @Deprecated('v2: use suggestedMaxTurns')
  int? get maxTurns => suggestedMaxTurns;

  @Deprecated('v2: use suggestedTaskChunkSize')
  int? get taskChunkSize => suggestedTaskChunkSize;

  // 舊 forceToolUse=true ＝ 保守（要 nudge）；新 unlimited=false ＝ 保守。
  // 反向推導：unlimited = false ⟹ 舊式 caller 期望 forceToolUse = true
  @Deprecated('v2: forceToolUse removed; check unlimited instead')
  bool get forceToolUse => !unlimited;

  /// 保守預設（無金鑰、demo 模式）
  ///
  /// 命名改成 conservativeProfile 凸顯語義——這是「保守」不是「預設」。
  /// 預設值其實是 unlimited，只要呼叫端沒給任何 profile 就走 unlimited。
  static const conservativeProfile = ProviderProfile(
    provider: 'unknown',
    model: 'unknown',
    tier: ProviderTier.tier3,
    apiParams: {'temperature': 0.3},
    unlimited: false,  // demo 模式才限制
    suggestedMaxTurns: 15,
    suggestedTaskChunkSize: 3,
    promptNudge: '這個模型尚未經過能力測試，請一次只做一個明確的任務。',
  );

  /// 依 provider + model 取得 profile
  /// 會做模糊匹配：先找完全匹配，再找 provider 匹配，最後用預設值
  static ProviderProfile forModel(String provider, String model) {
    final key = '${provider}_$model'.toLowerCase();

    // 完全匹配
    if (_profiles.containsKey(key)) {
      return _profiles[key]!;
    }

    // 模糊匹配：用 provider + model pattern
    for (final entry in _profiles.entries) {
      final profileKey = entry.key;
      if (profileKey.contains(provider.toLowerCase()) &&
          _modelMatches(profileKey, model.toLowerCase())) {
        return entry.value;
      }
    }

    // provider 預設
    final providerDefault = _providerDefaults[provider.toLowerCase()];
    if (providerDefault != null) {
      return providerDefault;
    }

    // [教練 Agent 2026-07-30 v2] 找不到時回傳 unlimited=true 的空白 profile，
    // 不再貶低為 tier3 + forceToolUse=true 的保守預設。
    // 哲學：呼叫端既然有金鑰跑這個模型，就信任它，不要 PUA 它。
    return ProviderProfile(
      provider: provider,
      model: model,
      tier: ProviderTier.tier1,
      unlimited: true,
    );
  }

  /// 模型名稱模糊匹配
  static bool _modelMatches(String profileKey, String model) {
    // 從 profile key 中提取 model 部分
    final parts = profileKey.split('_');
    if (parts.length < 2) return false;
    // model 部分可能是 "gpt-5" 或 "kimi-k3" 等
    final modelPart = parts.sublist(1).join('_');
    return model.contains(modelPart) || modelPart.contains(model);
  }

  /// 各 provider 的預設 profile（當沒有精確 model 匹配時）
  /// [教練 Agent 2026-07-30 v2] 全部 unlimited=true（說明見設計文件 §B.3）
  static const _providerDefaults = {
    'openai': ProviderProfile(
      provider: 'openai',
      model: 'gpt-4o',
      tier: ProviderTier.tier1,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 20,
    ),
    'glm': ProviderProfile(
      provider: 'glm',
      model: 'glm-5',
      tier: ProviderTier.tier1,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 15,
    ),
    'kimi': ProviderProfile(
      provider: 'kimi',
      model: 'kimi-k3',
      tier: ProviderTier.tier2,
      // [教練 Agent 2026-07-30] kimi-k3 是 reasoning model，temperature 固定 1，不支援自訂
      // 注意：必須用 int 1 而非 double 1.0，Kimi API 嚴格區分整數與浮點數
      apiParams: {'temperature': 1},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 15,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    ),
    'minimax': ProviderProfile(
      provider: 'minimax',
      model: 'MiniMax-M3',
      tier: ProviderTier.tier2,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 7,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    ),
    'local': ProviderProfile(
      provider: 'local',
      model: 'llama3.1:8b',
      tier: ProviderTier.tier3,
      // [教練 Agent 2026-07-22] Qwen3.5-4B 等模型預設啟用 thinking mode，
      // 會把回應卡在 reasoning_content 裡導致 content 永遠為空。
      // 加 chat_template_kwargs 關閉 thinking mode。
      apiParams: {
        'temperature': 0.3,
        'chat_template_kwargs': {'enable_thinking': false},
      },
      suggestedMaxTurns: 10,
      suggestedTaskChunkSize: 1,
      promptNudge: '一次只做一個明確的任務。使用 <<<​tool_call>>> 格式呼叫工具。',
    )};

  /// 精確 model profile（基於基準測試數據）
  /// key 格式：provider_model（小寫）
  /// [教練 Agent 2026-07-30 v2] 全部 unlimited=true，移除 max_tokens / max_completion_tokens。
  static const _profiles = {
    // === OpenAI ===
    'openai_gpt-4o': ProviderProfile(
      provider: 'openai',
      model: 'gpt-4o',
      tier: ProviderTier.tier1,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 20,
    ),
    'openai_gpt-4o-mini': ProviderProfile(
      provider: 'openai',
      model: 'gpt-4o-mini',
      tier: ProviderTier.tier2,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 7,
    ),
    'openai_gpt-5': ProviderProfile(
      provider: 'openai',
      model: 'gpt-5',
      tier: ProviderTier.tier2,
      // gpt-5 不支援 temperature，不設 max_tokens（全面開通）
      apiParams: {},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 10,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    ),
    'openai_gpt-5-mini': ProviderProfile(
      provider: 'openai',
      model: 'gpt-5-mini',
      tier: ProviderTier.tier2,
      apiParams: {},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 7,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    ),

    // [教練 Agent 2026-07-29] OpenAI 最新模型（2026-07）
    'openai_gpt-5.6': ProviderProfile(
      provider: 'openai',
      model: 'gpt-5.6',
      tier: ProviderTier.tier1,
      apiParams: {},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 20,
      tested: false,
    ),
    'openai_gpt-5.5': ProviderProfile(
      provider: 'openai',
      model: 'gpt-5.5',
      tier: ProviderTier.tier1,
      apiParams: {},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 20,
      tested: false,
    ),
    'openai_gpt-5.4': ProviderProfile(
      provider: 'openai',
      model: 'gpt-5.4',
      tier: ProviderTier.tier1,
      apiParams: {},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 15,
      // gpt-5.4 支援 vision（image_url），不需 fallback visionModel
      visionModel: null,
      tested: false,
    ),

    // === GLM（智譜 AI）===
    'glm_glm-5': ProviderProfile(
      provider: 'glm',
      model: 'glm-5',
      tier: ProviderTier.tier1,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 15,
    ),
    'glm_glm-5.2': ProviderProfile(
      provider: 'glm',
      model: 'glm-5.2',
      tier: ProviderTier.tier1,
      // [教練 Agent 2026-08-16 使用者 抓包] z.ai glm-5.x 系列強制思考模式——
      // 實測 5.2 每次 16-23 秒、思考 585-858 tokens，AgentLoop 十幾輪
      // 等於燒 5 分鐘還不出動作。thinking.disabled 對 5.2 無效（照樣思考），
      // 但對 4.6/5-turbo 有效（0 思考 tokens、秒級回應）。
      // 這裡仍帶 disabled：z.ai 未來放寬時自動受益。
      apiParams: {
        'temperature': 0.3,
        'thinking': {'type': 'disabled'},
      },
      suggestedMaxTurns: 25,
      suggestedTaskChunkSize: 15,
      supportsReasoningContent: true,
      visionModel: 'glm-4.6v',
      promptNudge: '你是 GLM-5.2，Tier 1 高能力推理模型。直接執行任務，多步驟工具使用。',
    ),
    'glm_glm-4.7': ProviderProfile(
      provider: 'glm',
      model: 'glm-4.7',
      tier: ProviderTier.tier2,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 7,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    ),
    'glm_glm-4.5': ProviderProfile(
      provider: 'glm',
      model: 'glm-4.5',
      tier: ProviderTier.tier3,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 15,
      suggestedTaskChunkSize: 3,
    ),

    // === Kimi（Moonshot）===
    'kimi_kimi-k3': ProviderProfile(
      provider: 'kimi',
      model: 'kimi-k3',
      tier: ProviderTier.tier2,
      // [教練 Agent 2026-07-30] kimi-k3 是 reasoning model，temperature 固定 1
      // 注意：必須用 int 1 而非 double 1.0，Kimi API 嚴格區分整數與浮點數
      apiParams: {'temperature': 1},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 15,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    ),
    'kimi_kimi-k2.5': ProviderProfile(
      provider: 'kimi',
      model: 'kimi-k2.5',
      tier: ProviderTier.tier3,
      // kimi-k2.5 回 reasoning_content，content 可能為空
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 15,
      suggestedTaskChunkSize: 3,
      supportsReasoningContent: true,
      promptNudge: '一次只做一個明確的任務。使用 <<<​tool_call>>> 格式呼叫工具。',
    ),

    // === MiniMax ===
    'minimax_minimax-m2.5': ProviderProfile(
      provider: 'minimax',
      model: 'MiniMax-M3',
      tier: ProviderTier.tier2,
      apiParams: {'temperature': 0.3},
      suggestedMaxTurns: 20,
      suggestedTaskChunkSize: 7,
      promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
    )};

  // ═══════════════════════════════════════════════════
  // [教練 Agent 2026-07-30 v2] 策略模式：HTTP body 安全過濾
  // ═══════════════════════════════════════════════════

  /// 不准送進 HTTP body 的 apiParams 鍵集合。
  ///
  /// 規則：max_tokens / max_completion_tokens 一律不送——全面開通，
  /// 由 provider 預設決定上限（Anthropic 8K、OpenAI 16K、OpenAI Reasoning 無上限）。
  /// 保留：temperature、chat_template_kwargs 等技術／性格參數。
  static const _httpFilterKeys = {
    'max_tokens',
    'max_completion_tokens',
  };

  /// [小葵 2026-09-19 小橋復活手術] 部分模型（reasoning 系、GLM 相容層）
  /// 只支援預設 temperature=1，帶 0.3 會整包 400 unsupported_value。
  /// 模型掛點標記：當 provider 曾因此被拒，剔除 temperature 重試。
  static final Set<String> _temperatureBlockedModels = {};
  static void markTemperatureUnsupported(String modelId) {
    _temperatureBlockedModels.add(modelId);
  }

  bool get _shouldDropTemperature => _temperatureBlockedModels.contains(model);

  /// 給 HTTP body 用的 apiParams 拷貝——已過濾掉限制參數。
  ///
  /// apiParams 本身保持原樣（profile 內部資料），只有對外送出才過濾。
  /// 這樣即使舊 JSON 帶有 max_tokens（不該有），也不會漏到 HTTP 請求。
  Map<String, dynamic> get apiParamsForHttp {
    if (apiParams.isEmpty) return const {};
    final out = Map<String, dynamic>.from(apiParams)
      ..removeWhere((k, _) => _httpFilterKeys.contains(k));
    if (_shouldDropTemperature) out.remove('temperature');
    return out;
  }

  /// 取得 tier 的中文名稱
  String get tierName {
    switch (tier) {
      case ProviderTier.tier1:
        return 'Tier 1（完整多步驟工具使用）';
      case ProviderTier.tier2:
        return 'Tier 2（需拆分小任務）';
      case ProviderTier.tier3:
        return 'Tier 3（單一明確任務）';
    }
  }

  /// 取得適配建議（給原生 Agent自己看）
  String get adaptationGuide {
    final chunkDesc = suggestedTaskChunkSize == null
        ? '自行判斷任務粒度'
        : '一次處理 $suggestedTaskChunkSize 個修復項目';
    final turnDesc = suggestedMaxTurns == null
        ? '無限輪（建議交由 Agent Loop 內部安全閥管理）'
        : '最多 $suggestedMaxTurns 輪';
    switch (tier) {
      case ProviderTier.tier1:
        return '你目前使用的是 Tier 1 強模型（$provider/$model），具備完整多步驟工具使用能力。'
            '可以連續執行多步驟任務，$chunkDesc。'
            '收到工具結果後直接分析並修復，不需要先做額外確認。'
            '（$turnDesc）';
      case ProviderTier.tier2:
        return '你目前使用的是 Tier 2 中等模型（$provider/$model），具備工具使用能力但需要拆分任務。'
            '建議$chunkDesc，'
            '收到工具結果後直接分析並修復，不要先做額外確認。'
            '（$turnDesc）';
      case ProviderTier.tier3:
        return '你目前使用的是 Tier 3 基礎模型（$provider/$model），能力有限。'
            '請一次只做一個明確的任務，使用 <<<​tool_call>>> 格式呼叫工具。'
            '（$turnDesc）';
    }
  }
}
