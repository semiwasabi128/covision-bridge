import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bridge_action.dart';
import '../models/capability_catalog.dart';
import '../models/second_brain_file_index.dart';
import 'capability_health_service.dart';
import 'second_brain_file_index_store.dart';

class CapabilityCatalogService {
  static const String _customKey = 'bridge_custom_capability_catalog_v1';

  final CapabilityHealthService healthService;
  final SecondBrainFileIndexStore secondBrainStore;

  CapabilityCatalogService({
    CapabilityHealthService? healthService,
    this.secondBrainStore = const SecondBrainFileIndexStore(),
  }) : healthService = healthService ?? CapabilityHealthService();

  List<CapabilityDefinition> builtInDefinitions() => _builtInCapabilities;

  Future<List<CapabilityDefinition>> customDefinitions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                CapabilityDefinition.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<CapabilityDefinition>> definitions() async {
    final custom = await customDefinitions();
    return [..._builtInCapabilities, ...custom];
  }

  Future<List<CapabilityRuntimeStatus>> inspect() async {
    final health = await _safeHealthInspect();
    final definitions = await this.definitions();
    return definitions
        .map((definition) => _runtimeStatus(definition, health))
        .toList();
  }

  Future<BrainSkillRegistrySnapshot> buildBrainSkillRegistry(
    String request, {
    BridgeAction? bridgeAction,
  }) async {
    final statuses = await inspect();
    final recommendations = recommend(
      request,
      statuses: statuses,
      bridgeAction: bridgeAction,
    );
    return BrainSkillRegistrySnapshot(
      capabilities: statuses,
      recommendations: recommendations,
      summary: _summaryFor(recommendations, statuses),
    );
  }

  Future<List<CapabilityHealthItem>> _safeHealthInspect() async {
    try {
      return await healthService.inspect();
    } catch (_) {
      return const [];
    }
  }

  List<BrainSkillRecommendation> recommend(
    String request, {
    required List<CapabilityRuntimeStatus> statuses,
    BridgeAction? bridgeAction,
  }) {
    final normalized = request.toLowerCase();
    final scored =
        <({CapabilityRuntimeStatus status, int score, String reason})>[];

    for (final status in statuses) {
      var score = 0;
      final definition = status.definition;
      if (bridgeAction != null && definition.actionType == bridgeAction.type) {
        score += 80;
      }
      for (final phrase in definition.triggerPhrases) {
        final token = phrase.trim().toLowerCase();
        if (token.isEmpty) continue;
        if (normalized.contains(token)) score += token.length >= 3 ? 12 : 8;
      }
      if (score <= 0) continue;
      final reason =
          bridgeAction != null && definition.actionType == bridgeAction.type
          ? '目前任務已被路由成「${definition.name}」，這座橋最貼近需求。'
          : '使用者需求命中「${definition.triggerPhrases.take(3).join('、')}」等能力線索。';
      scored.add((status: status, score: score, reason: reason));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored
        .take(3)
        .map(
          (item) => BrainSkillRecommendation(
            capability: item.status,
            reason: item.reason,
            confidence: item.score.clamp(0, 100),
          ),
        )
        .toList();
  }

  Future<CapabilityDefinition> registerCustomCapability({
    required String name,
    required String description,
    required List<String> triggerPhrases,
    List<String> providers = const [],
    String inputFormat = '自然語言需求',
    String outputFormat = '文字或媒體結果',
    String setupRoute = '/golden-keys',
  }) async {
    final normalizedName = name.trim();
    final id = _idFor(
      'custom-$normalizedName-${DateTime.now().millisecondsSinceEpoch}',
    );
    final definition = CapabilityDefinition(
      id: id,
      name: normalizedName.isEmpty ? '未命名自訂能力橋' : normalizedName,
      kind: CapabilityKind.custom,
      actionType: BridgeActionType.unknown,
      description: description.trim().isEmpty
          ? '使用者建立的自訂能力橋。'
          : description.trim(),
      triggerPhrases: triggerPhrases
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      providers: providers
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      setupRoute: setupRoute,
      brainRoom: SecondBrainRoom.bridges.label,
      inputFormat: inputFormat,
      outputFormat: outputFormat,
      builtIn: false,
    );
    final custom = [...await customDefinitions(), definition];
    await _saveCustom(custom);
    await _upsertSecondBrainBridge(definition);
    return definition;
  }

  Future<void> syncBuiltInsToSecondBrain() async {
    for (final definition in _builtInCapabilities) {
      await _upsertSecondBrainBridge(definition);
    }
  }

  Future<void> clearCustomForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customKey);
  }

  CapabilityRuntimeStatus _runtimeStatus(
    CapabilityDefinition definition,
    List<CapabilityHealthItem> health,
  ) {
    final item = _healthFor(definition, health);
    if (item == null) {
      final availability = definition.builtIn
          ? CapabilityAvailability.planned
          : CapabilityAvailability.needsSetup;
      return CapabilityRuntimeStatus(
        definition: definition,
        availability: availability,
        providerLabel: definition.providers.isEmpty
            ? '尚未指定'
            : definition.providers.join(' / '),
        detail: definition.builtIn ? '能力已登錄，等待執行橋或插件接入。' : '自訂能力已登錄，尚未完成執行橋接線。',
        nextStep: definition.builtIn
            ? '到金鑰匙中心檢查可用服務。'
            : '補上服務、API Key、輸入與輸出格式後即可進入執行橋實作。',
      );
    }

    final availability = switch (item.status) {
      CapabilityHealthStatus.ready => CapabilityAvailability.ready,
      CapabilityHealthStatus.needsSetup => CapabilityAvailability.needsSetup,
      CapabilityHealthStatus.unsupported => CapabilityAvailability.unsupported,
    };
    return CapabilityRuntimeStatus(
      definition: definition,
      availability: availability,
      providerLabel: item.providerLabel,
      detail: item.detail,
      nextStep: switch (availability) {
        CapabilityAvailability.ready => '可直接執行，並把結果回寫任務與第二大腦。',
        CapabilityAvailability.needsSetup =>
          '前往${definition.setupRoute}開通或測試金鑰。',
        CapabilityAvailability.unsupported => '等待插件或新增執行橋。',
        CapabilityAvailability.planned => '先保留為未來能力。',
      },
    );
  }

  CapabilityHealthItem? _healthFor(
    CapabilityDefinition definition,
    List<CapabilityHealthItem> health,
  ) {
    if (definition.kind == CapabilityKind.desktop) {
      return health.cast<CapabilityHealthItem?>().firstWhere(
        (item) =>
            item?.label.contains('桌面') == true ||
            item?.label.contains('搜尋') == true,
        orElse: () => null,
      );
    }
    return health.cast<CapabilityHealthItem?>().firstWhere(
      (item) =>
          item?.type == definition.actionType &&
          (definition.kind != CapabilityKind.search ||
              item?.label.contains('搜尋') == true ||
              item?.label.contains('瀏覽') == true),
      orElse: () => null,
    );
  }

  Future<void> _saveCustom(List<CapabilityDefinition> definitions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customKey,
      jsonEncode(definitions.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _upsertSecondBrainBridge(CapabilityDefinition definition) async {
    final now = DateTime.now();
    await secondBrainStore.upsert(
      SecondBrainFileEntry(
        id: 'capability-${definition.id}',
        title: '${definition.name} 能力橋',
        path: 'brain://capabilities/${definition.id}',
        room: SecondBrainRoom.bridges,
        summary: definition.description,
        contentDigest:
            '能力：${definition.name}\n情境：${definition.triggerPhrases.join('、')}\nProvider：${definition.providers.join('、')}\n輸入：${definition.inputFormat}\n輸出：${definition.outputFormat}\n證據：${definition.evidenceKind}\nv0 範圍：${definition.v0Scope}\nAdapter：${definition.adapterContract}\n社群插件：${definition.communityPluginNote}',
        contentExcerpt: definition.description,
        tags: ['能力橋', definition.kind.label, if (!definition.builtIn) '自訂橋'],
        keywords: [
          definition.name,
          definition.kind.label,
          ...definition.triggerPhrases,
          ...definition.providers,
        ],
        indexedAt: now,
        trustScore: definition.builtIn ? 72 : 62,
      ),
    );
  }

  String _summaryFor(
    List<BrainSkillRecommendation> recommendations,
    List<CapabilityRuntimeStatus> statuses,
  ) {
    if (recommendations.isEmpty) {
      final readyCount = statuses.where((item) => item.ready).length;
      return '目前沒有明確命中的能力橋；已開通 $readyCount 座能力，可視需求建立新橋。';
    }
    final top = recommendations.first.capability;
    return '大腦建議使用「${top.definition.name}」，狀態：${top.availability.label}。';
  }

  String _idFor(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return normalized.isEmpty ? 'custom-capability' : normalized;
  }
}

const _builtInCapabilities = [
  CapabilityDefinition(
    id: 'browse-news',
    name: '新聞與網頁搜尋橋',
    kind: CapabilityKind.search,
    actionType: BridgeActionType.browse,
    description: '查新聞、找資料、整理網頁來源與即時資訊。',
    triggerPhrases: ['新聞', '搜尋', '查', '查詢', '時刻表', '最新', '網頁', '天氣', '匯率'],
    providers: ['OpenAI Web Search', 'Bridge Desktop'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    speedNote: '即時搜尋會受服務與網路影響。',
    qualityNote: '需要列出來源與不確定處。',
    evidenceKind: 'web_search',
    v0Scope: '可執行搜尋、回傳摘要、來源、查詢時間與時間敏感提醒。',
    adapterContract: '搜尋執行橋接收搜尋任務，必須回傳摘要、來源、查詢詞、查詢時間與時間敏感資訊。',
    communityPluginNote: '社群可新增不同搜尋來源執行橋，例如新聞、學術、論壇、社群平台或本地瀏覽器搜尋。',
    setupSteps: [
      '設定支援網頁搜尋的主腦或搜尋服務。',
      '測試搜尋能力是否能回傳來源。',
      '完成後自動回到原本新聞、時刻表或資料查詢任務。',
    ],
    officialEntryHints: ['OpenAI Platform', 'Bridge Desktop 搜尋插件'],
  ),
  CapabilityDefinition(
    id: 'vision',
    name: '圖片理解橋',
    kind: CapabilityKind.vision,
    actionType: BridgeActionType.vision,
    description: '讀取圖片、截圖、畫面內容、文字與視覺問題。',
    triggerPhrases: ['圖片', '截圖', '看圖', '辨識', '識別', '畫面', '圖中'],
    providers: ['OpenAI Vision'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    evidenceKind: 'vision',
    v0Scope: '可讀取上傳圖片、描述內容、整理截圖文字與可見問題。',
    adapterContract: '圖片理解執行橋接收圖片路徑，回傳繁中分析文字、圖片數量、模型與服務證據。',
    communityPluginNote: '社群可接 Gemini、Claude、在地 OCR 或專門截圖理解模型，但需保留圖片數量與模型證據。',
    setupSteps: [
      '設定支援圖像理解的服務。',
      '上傳圖片後先詢問使用者用途，不自動浪費一次分析。',
      '使用者補上目的後執行 Vision 橋並留下圖片證據。',
    ],
    officialEntryHints: ['OpenAI Platform', '可支援圖片理解的雲端模型'],
  ),
  CapabilityDefinition(
    id: 'image-generation',
    name: '圖像生成橋',
    kind: CapabilityKind.image,
    actionType: BridgeActionType.generateImage,
    description: '生成角色形象、參考圖、視覺素材與設計草圖。',
    triggerPhrases: ['生成圖片', '畫一張', '形象', '角色圖', '視覺', '插圖'],
    providers: ['OpenAI Images', 'Replicate', 'Gemini Imagen'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    qualityNote: '可依品質模式、參考圖與透明背景需求調整。',
    evidenceKind: 'image',
    v0Scope: '可從聊天任務化生成圖片，回傳服務、模型、品質與保存位置。',
    adapterContract: '圖片生成執行橋接收提示詞、模型、品質模式與參考圖，回傳圖片位置與圖片證據。',
    communityPluginNote: '社群可接各家圖像生成與 image-to-image 服務，並分享透明背景、角色資產包、風格一致性插件。',
    setupSteps: ['設定支援圖像生成的服務。', '選擇品質模式、模型與參考圖策略。', '生成後把圖像保存成可追蹤素材。'],
    officialEntryHints: [
      'OpenAI Images',
      'Replicate / FLUX',
      'Gemini / Imagen',
    ],
  ),
  CapabilityDefinition(
    id: 'music-generation',
    name: '音樂生成橋',
    kind: CapabilityKind.music,
    actionType: BridgeActionType.generateMusic,
    description: '產生配樂、讀書音樂、音效、旋律或歌曲草稿。',
    triggerPhrases: ['音樂', '配樂', '作曲', '歌曲', '音效', '讀書音樂'],
    providers: ['MiniMax Music 2.6'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    evidenceKind: 'audio',
    v0Scope: '可從聊天或工作流生成音樂，回傳音訊位置、模型與服務證據。',
    adapterContract: '音樂執行橋接收提示詞、歌詞與風格，回傳音訊位置、模型、時長與服務證據。',
    communityPluginNote: '社群可各自接常用音樂生成服務，插件需明確標示商用權利與輸出格式。',
    setupSteps: [
      '前往 platform.minimaxi.com 註冊 MiniMax 帳號。',
      '在 API Keys 頁面建立 API Key。',
      '到 App 設定頁的金鑰匙中心，貼上 MiniMax API Key 並測試連線。',
      '回到原任務產生音樂草稿。',
    ],
    officialEntryHints: ['https://platform.minimaxi.com'],
  ),
  CapabilityDefinition(
    id: 'video-generation',
    name: '影片生成橋',
    kind: CapabilityKind.video,
    actionType: BridgeActionType.generateVideo,
    description: '產生短片、分鏡、動態素材或影片草稿。',
    triggerPhrases: ['影片', '短片', '分鏡', '動畫影片', 'video'],
    providers: ['MiniMax Hailuo 2.3'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    evidenceKind: 'video',
    v0Scope: '可從聊天或工作流生成影片，回傳影片位置、模型、時長與服務證據。',
    adapterContract: '影片執行橋接收提示詞、模型與時長，回傳影片位置、任務狀態與來源證據。',
    communityPluginNote: '社群可接短片、分鏡、動態素材服務；插件需支援長任務狀態、成本提醒與權利護照。',
    setupSteps: [
      '前往 platform.minimaxi.com 註冊 MiniMax 帳號。',
      '在 API Keys 頁面建立 API Key。',
      '到 App 設定頁的金鑰匙中心，貼上 MiniMax API Key 並測試連線。',
      '回到原任務產生分鏡或影片草稿。',
    ],
    officialEntryHints: ['https://platform.minimaxi.com'],
  ),
  // [教練 Agent 2026-07-23] TTS 能力定義
  CapabilityDefinition(
    id: 'tts',
    name: '語音合成橋',
    kind: CapabilityKind.music,
    actionType: BridgeActionType.generateMusic,
    description: '將文字轉為自然語音，可用於朗讀、配音或語音訊息。',
    triggerPhrases: ['語音', '朗讀', '配音', '唸出來', 'tts', '語音合成'],
    providers: ['MiniMax Speech 2.8 HD'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    evidenceKind: 'audio',
    v0Scope: '可從聊天或工作流合成語音，回傳音檔位置、模型與語音 ID。',
    adapterContract: '語音合成橋接收文字、語音 ID 與速度，回傳音檔位置、模型與時長。',
    communityPluginNote: '社群可接不同 TTS 服務（如 OpenAI TTS、ElevenLabs），但需保留語音 ID 與服務證據。',
    setupSteps: [
      '前往 platform.minimaxi.com 註冊 MiniMax 帳號。',
      '在 API Keys 頁面建立 API Key。',
      '到 App 設定頁的金鑰匙中心，貼上 MiniMax API Key 並測試連線。',
      '回到原任務合成語音。',
    ],
    officialEntryHints: ['https://platform.minimaxi.com'],
  ),
  CapabilityDefinition(
    id: 'document-output',
    name: '文件產出橋',
    kind: CapabilityKind.document,
    actionType: BridgeActionType.document,
    description: '產出報告、清單、企劃、筆記、規格與 Markdown 文件。',
    triggerPhrases: ['文件', '報告', '清單', '企劃', '整理成', '輸出檔案'],
    providers: ['Local Document', 'Cloud Brain'],
    setupRoute: '/system',
    brainRoom: 'Bridges',
    outputFormat: 'Markdown / 文件草稿',
    evidenceKind: 'document',
    v0Scope: '可產出 Markdown 文件；雲端失敗時用本地模板保底。',
    adapterContract: '文件執行橋接收自然語言文件任務，回傳本機位置、產出方式與服務證據。',
    communityPluginNote: '社群可擴充 PDF、DOCX、簡報、試算表 exporter，並保留輸出位置與來源證據。',
    setupSteps: ['可先使用本地文件模板，不一定需要雲端。', '若要更高品質，設定主腦服務。', '文件產出後顯示保存路徑與附件卡。'],
    officialEntryHints: ['本地文件引擎', '主腦服務文件生成'],
  ),
  CapabilityDefinition(
    id: 'desktop-files',
    name: '桌面檔案橋',
    kind: CapabilityKind.desktop,
    actionType: BridgeActionType.desktopFiles,
    description: '讀取、分類、命名、整理本機檔案與資料夾。',
    triggerPhrases: ['桌面', '檔案', '資料夾', '本機', '整理資料', '找檔案'],
    providers: ['Bridge Desktop'],
    setupRoute: '/desktop-shell?returnTo=/chat',
    brainRoom: 'Bridges',
    requiresDesktopBridge: true,
    inputFormat: '本機檔案任務與授權範圍',
    outputFormat: '整理結果、檔案清單、移動或命名計畫',
    evidenceKind: 'desktop_file_plan',
    v0Scope: '先以只讀方式掃描授權資料夾、產生分類與整理計畫；移動、改名、刪除需下一階段確認。',
    adapterContract: '桌面執行橋需透過 Bridge Desktop 權限邊界執行檔案列舉、搬移、改名或整理，回傳可審核行動計畫。',
    communityPluginNote: '社群可做不同 OS、NAS、雲端硬碟與專案資料夾插件，但必須保留使用者確認與可回復紀錄。',
    setupSteps: [
      '啟動 Bridge Desktop。',
      '授權可讀取或整理的資料夾。',
      '回到原任務產生檔案清單、整理計畫或執行動作。',
    ],
    officialEntryHints: ['Bridge Desktop', '本機資料夾授權'],
  ),
  CapabilityDefinition(
    id: 'ipfs-pinning',
    name: 'IPFS 存證橋（Pinata）',
    kind: CapabilityKind.custom,
    actionType: BridgeActionType.unknown,
    description: '將資產包上傳到 IPFS 去中心化存儲，取得 CID 作為鏈上存證。',
    triggerPhrases: ['IPFS', '存證', 'Pinata', 'CID', '資產發佈', '上鏈', 'pin'],
    providers: ['Pinata'],
    setupRoute: '/system',
    brainRoom: 'Bridges',
    inputFormat: '資產 JSON 或檔案',
    outputFormat: 'IPFS CID + 存證記錄',
    evidenceKind: 'ipfs_pin',
    v0Scope: '資產發佈到 SemiDAO 時，自動 pin 到 IPFS 取得 CID。未設定 JWT 時 fallback 到本地模擬。',
    adapterContract: 'IPFS 執行橋接收內容，透過 Pinata API pin 到 IPFS，回傳 CID、pin 大小與時間戳。',
    communityPluginNote: '社群可替換為自建 IPFS node 或其他 pinning 服務（如 nft.storage、web3.storage）。',
    setupSteps: [
      '前往 pinata.cloud 註冊免費帳號（1GB 免費額度）。',
      '在 API Keys 頁面建立 API Key，取得 JWT token。',
      '在 App 設定頁貼上 Pinata JWT 並測試連線。',
    ],
    officialEntryHints: ['https://app.pinata.cloud/'],
  ),
  CapabilityDefinition(
    id: 'custom-bridge',
    name: '自訂能力橋',
    kind: CapabilityKind.custom,
    actionType: BridgeActionType.unknown,
    description: '讓使用者把新的 AI 服務登錄成能力橋，供大腦未來主動調用。',
    triggerPhrases: ['新服務', '新的 AI', '建立橋', '自訂能力', '接 API'],
    providers: ['User Defined'],
    setupRoute: '/golden-keys',
    brainRoom: 'Bridges',
    inputFormat: '服務名稱、能力描述、觸發情境、API 或登入方式',
    outputFormat: '可被大腦讀取的能力卡',
    evidenceKind: 'custom_capability',
    v0Scope: '可建立自訂能力卡並寫入 Second Brain Bridges 房間；執行橋另行接入。',
    adapterContract: '自訂執行橋需把自訂能力卡映射到 BridgeActionAdapter 或桌面插件，並宣告輸入、輸出與證據格式。',
    communityPluginNote: '社群玩家可分享能力卡與執行橋，讓其他使用者匯入後由大腦技能表辨識並建議使用。',
    setupSteps: [
      '輸入服務名稱、觸發情境與服務。',
      '保存後寫入 Second Brain Bridges 房間。',
      '未來需求命中時由思維儀表提醒可建立或接上執行橋。',
    ],
    officialEntryHints: ['使用者指定的官方服務頁', 'SemiDAO 社群插件'],
  ),
];
