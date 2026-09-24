// Desktop Welcome Screen — 桌面版首次開啟歡迎頁
// BridgeDS 暗色風格 × 桌面寬版雙欄佈局
// [Phase 0 2026-07-17] [Phase 1 2026-07-17 修正：S23 API 設定細節全帶回 + 桌面版面]
//
// 流程：歡迎 → 設定 API Key（測試→儲存→綠鎖）→ 前往召喚
// S23 細節：每 provider 獨立測試/儲存狀態、切 provider 存前一個 token、
//          暫停 listener 避免誤觸發、沒測試不能儲存、綠鎖持久、模型清單

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/bridge_design_system.dart';
import '../theme/bridge_motion.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class DesktopWelcomeScreen extends StatefulWidget {
  const DesktopWelcomeScreen({super.key});

  @override
  State<DesktopWelcomeScreen> createState() => _DesktopWelcomeScreenState();
}

class _DesktopWelcomeScreenState extends State<DesktopWelcomeScreen> {
  // ── API 設定（S23 完整版）──────────────────────────────
  final _apiUrlController = TextEditingController();
  final _apiTokenController = TextEditingController();
  String _apiProvider = 'minimax';
  bool _apiSaving = false;
  bool _apiTesting = false;
  // 每個 provider 獨立記住：是否已測試通過、是否已儲存、測試結果
  final Map<String, bool> _providerTested = {};
  final Map<String, bool> _providerSaved = {};
  final Map<String, List<String>> _providerTestModels = {};
  final Map<String, String?> _providerTestError = {};
  List<String>? get _apiTestModels => _providerTestModels[_apiProvider];
  String? get _apiTestError => _providerTestError[_apiProvider];
  bool get _apiTested => _providerTested[_apiProvider] ?? false;
  bool get _apiSaved => _providerSaved[_apiProvider] ?? false;
  bool _obscureToken = true;

  static const _providers = [
    ('minimax', 'MiniMax', 'https://platform.minimaxi.com/', '有免費額度，台灣可直接使用'),
    ('kimi', 'Kimi', 'https://platform.moonshot.cn/', '中文能力強，有免費額度'),
    ('glm', 'GLM', 'https://open.bigmodel.cn/', '智譜 AI，中文優秀'),
    ('openai', 'OpenAI', 'https://platform.openai.com/', '功能最完整，需付費'),
    ('gemini', 'Gemini', 'https://aistudio.google.com/', 'Google AI'),
    ('claude', 'Claude', 'https://console.anthropic.com/', 'Anthropic'),
  ];

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = _defaultApiUrl(_apiProvider);
    _apiUrlController.addListener(_onApiInputChanged);
    _apiTokenController.addListener(_onApiInputChanged);
    _loadSavedConfig();
    // [Phase 1 2026-07-17] 定期印出 UI 狀態——模擬原生 Agent 環境感知
    _debugPrintState();
  }

  /// [Phase 1 2026-07-17] 印出當前 UI 狀態——給外部觀察用
  void _debugPrintState() {
    Future.delayed(const Duration(seconds: 2), () {
      debugPrint('[AgentSensor] provider=$_apiProvider, '
          'tokenLen=${_apiTokenController.text.trim().length}, '
          'tested=$_apiTested, saved=$_apiSaved, '
          'testing=$_apiTesting, saving=$_apiSaving, '
          'urlField=${_apiUrlController.text.trim()}');
    });
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  /// 載入已存的 API 設定（重開 App 時恢復）
  Future<void> _loadSavedConfig() async {
    final provider = await StorageService.getProvider() ?? 'minimax';
    final url = await StorageService.getGatewayUrl();
    final token = await StorageService.getToken(provider: provider);
    // 暫停 listener
    _apiUrlController.removeListener(_onApiInputChanged);
    _apiTokenController.removeListener(_onApiInputChanged);
    if (mounted) {
      setState(() {
        _apiProvider = provider;
        _apiUrlController.text = url ?? _defaultApiUrl(provider);
        _apiTokenController.text = token ?? '';
      });
    }
    _apiUrlController.addListener(_onApiInputChanged);
    _apiTokenController.addListener(_onApiInputChanged);
  }

  /// 使用者修改了 URL 或 Token，清除目前 provider 的「已儲存」和「已測試」狀態
  /// [Phase 1 2026-07-17 修正] 必須 setState 讓按鈕重新評估 onPressed（否則貼 token 後按鈕仍 disabled）
  void _onApiInputChanged() {
    debugPrint('[AgentSensor] _onApiInputChanged 觸發: url=${_apiUrlController.text.trim().length}chars, token=${_apiTokenController.text.trim().length}chars');
    if (_providerTested[_apiProvider] == true ||
        _providerSaved[_apiProvider] == true) {
      setState(() {
        _providerTested[_apiProvider] = false;
        _providerSaved[_apiProvider] = false;
        _providerTestModels.remove(_apiProvider);
        _providerTestError.remove(_apiProvider);
      });
    } else {
      // 即使沒有測試/儲存狀態要清，也要重建讓按鈕 onPressed 更新
      setState(() {});
    }
  }

  String _defaultApiUrl(String provider) {
    switch (provider) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'kimi':
        return 'https://api.moonshot.cn/v1';
      case 'minimax':
        return 'https://api.minimax.io/v1';
      case 'claude':
        return 'https://api.anthropic.com/v1';
      case 'gemini':
        return 'https://generativelanguage.googleapis.com/v1beta/openai';
      case 'glm':
        return 'https://open.bigmodel.cn/api/paas/v4';
      case 'replicate':
        return 'https://api.replicate.com/v1';
      case 'local':
        return 'http://127.0.0.1:18789';
      default:
        return '';
    }
  }

  /// 切 provider：存前一個 token → 載入新 token → 暫停 listener 避免誤觸發
  Future<void> _selectProvider(String provider) async {
    debugPrint('[DesktopWelcome] _selectProvider 開始: $_apiProvider → $provider');
    final previousProvider = _apiProvider;
    final previousToken = _apiTokenController.text.trim();
    // 先更新 UI，避免 secure storage 操作卡住時 UI 無反應
    String nextToken = '';
    try {
      // 儲存前一個 provider 的 token
      debugPrint('[DesktopWelcome] 存前一個 token: provider=$previousProvider, tokenLen=${previousToken.length}');
      await StorageService.saveToken(previousToken, provider: previousProvider);
      debugPrint('[DesktopWelcome] 存 token 完成');
      // 載入新 provider 的 token
      nextToken = await StorageService.getToken(provider: provider) ?? '';
      debugPrint('[DesktopWelcome] 載入新 token: provider=$provider, tokenLen=${nextToken.length}');
    } catch (e) {
      debugPrint('[DesktopWelcome] _selectProvider secure storage 錯誤: $e');
    }
    // 暫停 listener 避免載入觸發清除
    _apiUrlController.removeListener(_onApiInputChanged);
    _apiTokenController.removeListener(_onApiInputChanged);
    if (mounted) {
      setState(() {
        _apiProvider = provider;
        _apiUrlController.text = _defaultApiUrl(provider);
        _apiTokenController.text = nextToken;
      });
      debugPrint('[DesktopWelcome] setState 完成, _apiProvider=$provider');
    }
    // 恢復 listener
    _apiUrlController.addListener(_onApiInputChanged);
    _apiTokenController.addListener(_onApiInputChanged);
  }

  /// 測試連線：先用畫面上的值測試 → 通過才存 secure storage
  /// [Phase 1 2026-07-17] 修正：不再讓 secure storage 失敗阻斷測試
  Future<void> _testConnection() async {
    debugPrint('[AgentSensor] _testConnection 被觸發!');
    setState(() {
      _apiTesting = true;
      _providerTestModels.remove(_apiProvider);
      _providerTestError.remove(_apiProvider);
    });
    try {
      // 1. 先用畫面上的值直接測試——不經過 secure storage
      final baseUrl = _apiUrlController.text.trim();
      final token = _apiTokenController.text.trim();
      final models = await ApiService.testConnectionWith(baseUrl, token);

      // 2. 測試成功 → 同時注入 ApiService override（讓 Agent 能用）
      ApiService.setOverrideConfig(baseUrl: baseUrl, token: token);

      // 3. 嘗試持久化（失敗不影響測試結果）
      try {
        await StorageService.saveGatewayUrl(baseUrl);
        await StorageService.saveProvider(_apiProvider);
        await StorageService.saveToken(token, provider: _apiProvider);
      } catch (e) {
        debugPrint('[DesktopWelcome] secure storage 持久化失敗（測試仍成功）: $e');
      }

      if (mounted) {
        setState(() {
          _providerTestModels[_apiProvider] = models;
          _providerTested[_apiProvider] = true;
          _providerTestError.remove(_apiProvider);
          _apiTesting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _providerTestError[_apiProvider] = e.toString();
          _apiTesting = false;
        });
      }
    }
  }

  /// 儲存設定：必須先測試通過才能儲存
  /// [教練 Agent 2026-08-10] 修復信任鏈——saveToken 失敗時不能標記為已儲存
  Future<void> _saveConfig() async {
    if (!_apiTested) {
      setState(() {
        _providerTestError[_apiProvider] = '請先按「測試連線」確認金鑰可用，再儲存。';
      });
      return;
    }
    setState(() {
      _apiSaving = true;
      _providerSaved[_apiProvider] = false;
    });
    try {
      await StorageService.saveGatewayUrl(_apiUrlController.text.trim());
      // [教練 Agent 2026-08-10] 不在 saveConfig 裡覆蓋全域 provider——每個 provider 獨立存自己的 token
      // saveProvider 只在使用者明確選擇主 LLM 時才呼叫
      final token = _apiTokenController.text.trim();
      if (token.isNotEmpty) {
        await StorageService.saveToken(token, provider: _apiProvider);
        // 驗證：讀回來確認真的存進去了
        final verify = await StorageService.getToken(provider: _apiProvider);
        if (verify == null || verify.trim().isEmpty) {
          throw Exception('Token 存入後驗證失敗——讀回為空');
        }
        debugPrint('[DesktopWelcome] ✅ $_apiProvider token 已確認持久化 (len=${verify.length})');
      }
      if (mounted) {
        setState(() {
          _apiSaving = false;
          _providerSaved[_apiProvider] = true;
        });
      }
    } catch (e) {
      debugPrint('[DesktopWelcome] ❌ _saveConfig 失敗: $e');
      if (mounted) {
        setState(() {
          _apiSaving = false;
          _providerSaved[_apiProvider] = false;
          _providerTestError[_apiProvider] = '儲存失敗：$e';
        });
      }
    }
  }

  /// 是否已有任一 provider 設定完成（用於判斷步驟 02 是否可用）
  bool get _anyProviderReady => _providerSaved.values.any((v) => v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BridgeDS.spaceXXL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Hero 區 ──────────────────────────
                  _buildHero(),
                  const SizedBox(height: BridgeDS.spaceXXL),

                  // ── 雙欄佈局：左 API 設定 / 召喚入口 ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左欄：API 設定
                      Expanded(
                        flex: 3,
                        child: _buildStepCard(
                          index: '01',
                          title: '設定 AI 服務',
                          subtitle: '讓你的夥伴有大腦可以運作',
                          child: _buildApiSetup(),
                        ),
                      ),
                      const SizedBox(width: BridgeDS.spaceLG),
                      // 右欄：召喚入口
                      Expanded(
                        flex: 2,
                        child: _buildStepCard(
                          index: '02',
                          title: '召喚你的夥伴',
                          subtitle: '選擇人格、命名、生成形象',
                          active: _anyProviderReady,
                          child: _buildSummonEntry(),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: BridgeDS.spaceXL),

                  // ── 資料主權字卡（09-14 Blue 拍板）──────────
                  // 主動權的交付儀式：第一天就知道，也第一天就能關。
                  _buildSovereigntyCard(),
                  SizedBox(height: BridgeDS.spaceXL),

                  // ── Footer ──────────────────────────
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Hero 區
  // ═══════════════════════════════════════════════════

  Widget _buildHero() {
    return BridgeScaleIn(
      beginScale: 0.85,
      child: Column(
        children: [
          BridgePulseDot(
            color: BridgeDSColors.of(context).accentBlue,
            size: 10,
            active: true,
          ),
          SizedBox(height: BridgeDS.spaceLG),
          Text(
            '橋樑',
            style: BridgeDSColors.of(context).display.copyWith(
              fontSize: 64,
              color: BridgeDSColors.of(context).textPrimary,
            ),
          ),
          SizedBox(height: BridgeDS.spaceSM),
          BridgeSlideIn(
            direction: const Offset(0, 0.1),
            delay: const Duration(milliseconds: 200),
            child: Text(
              '你的 AI 夥伴住在這裡',
              style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(height: BridgeDS.spaceMD),
          BridgeSlideIn(
            direction: const Offset(0, 0.1),
            delay: const Duration(milliseconds: 400),
            child: Text(
              '設定 AI 服務後，召喚第一位夥伴——\n它會記住你、理解你，跟你一起建造。',
              textAlign: TextAlign.center,
              style: BridgeDSColors.of(context).body.copyWith(
                color: BridgeDSColors.of(context).textTertiary,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ── 資料主權字卡 ──────────────────────────
  Widget _buildSovereigntyCard() {
    final colors = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: colors.accentGreen, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('你的數位資產與隱私，受你掌控',
                    style: TierStyle.of(context, Tier.cardHeroTitle)
                        .toTextStyle()),
                const SizedBox(height: 6),
                Text(
                  '你的對話、記憶與資料，只存在你自己的電腦上。\n'
                  '· 機密內容可以完全走本地模型（🟢 本地封閉迴路，不出這台機器）\n'
                  '· 使用雲端 AI 時，用你自己的金鑰直連（🟡 橋樑不經手、不看內容）\n'
                  '· 白名單以外的任何外傳，會被直接攔截，並在「系統設定 → 資料路徑總覽」留下紀錄\n'
                  '· 每天自動清理外傳暫存——你隨時可以在系統設定中調整或關閉',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                      .copyWith(height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 步驟卡片
  // ═══════════════════════════════════════════════════

  Widget _buildStepCard({
    required String index,
    required String title,
    required String subtitle,
    required Widget child,
    bool active = true,
  }) {
    final color = active ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textQuaternary;
    return BridgeSlideIn(
      direction: const Offset(0.05, 0.05),
      delay: Duration(milliseconds: 100 * (int.tryParse(index) ?? 1)),
      child: Container(
        padding: const EdgeInsets.all(BridgeDS.spaceLG),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(BridgeDS.roundWide),
          border: Border.all(
            color: active
                ? BridgeDSColors.of(context).borderDefault
                : BridgeDSColors.of(context).borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                  ),
                  child: Text(
                    index,
                    style: BridgeDSColors.of(context).labelMono.copyWith(color: color),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(
                          color: active
                              ? BridgeDSColors.of(context).textPrimary
                              : BridgeDSColors.of(context).textTertiary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: BridgeDSColors.of(context).caption.copyWith(
                          color: BridgeDSColors.of(context).textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: BridgeDS.spaceMD),
            child,
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // API 設定區（S23 完整版）
  // ═══════════════════════════════════════════════════

  Widget _buildApiSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Provider 選擇
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _providers.map((p) {
            final isSelected = _apiProvider == p.$1;
            final isLocked = _providerSaved[p.$1] == true;
            return _ProviderChip(
              id: p.$1,
              label: p.$2,
              isSelected: isSelected,
              isLocked: isLocked,
              onTap: () => _selectProvider(p.$1),
            );
          }).toList(),
        ),
        SizedBox(height: BridgeDS.spaceMD),

        // 註冊連結
        Builder(builder: (context) {
          final provider = _providers.firstWhere((p) => p.$1 == _apiProvider);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).tagInfoBg,
              borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: BridgeDSColors.of(context).tagInfoFg),
                SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${provider.$2} — ${provider.$4}\n',
                          style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).tagInfoFg),
                        ),
                        TextSpan(
                          text: provider.$3,
                          style: BridgeDSColors.of(context).code.copyWith(
                            color: BridgeDSColors.of(context).accentBlue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        SizedBox(height: BridgeDS.spaceMD),

        // API URL + API Key 雙欄（桌面寬版）
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API URL
            Expanded(
              child: TextField(
                controller: _apiUrlController,
                style: BridgeDSColors.of(context).code.copyWith(color: BridgeDSColors.of(context).textPrimary),
                decoration: InputDecoration(
                  labelText: 'API URL',
                  labelStyle: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted),
                  filled: true,
                  fillColor: BridgeDSColors.of(context).canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                    borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                    borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                    borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 02),
                ),
              ),
            ),
            SizedBox(width: BridgeDS.spaceMD),
            // API Key
            Expanded(
              child: TextField(
                controller: _apiTokenController,
                obscureText: _obscureToken,
                style: BridgeDSColors.of(context).code.copyWith(color: BridgeDSColors.of(context).textPrimary),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  labelStyle: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted),
                  filled: true,
                  fillColor: BridgeDSColors.of(context).canvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                    borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                    borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                    borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 02),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureToken
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: BridgeDSColors.of(context).textMuted,
                    ),
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: BridgeDS.spaceMD),

        // 按鈕列：測試連線 + 儲存
        Row(
          children: [
            // 測試連線按鈕
            BridgeGlowButton(
              label: _apiTesting ? '測試中...' : '測試連線',
              icon: Icons.electrical_services,
              state: _apiTested
                  ? BridgeGlowButtonState.locked
                  : _apiTesting
                      ? BridgeGlowButtonState.testing
                      : BridgeGlowButtonState.idle,
              onPressed: _apiTesting || _apiTokenController.text.trim().isEmpty
                  ? null
                  : _testConnection,
            ),
            SizedBox(width: 16),

            // 儲存按鈕 or 綠鎖
            if (_apiSaved)
              Row(
                children: [
                  Icon(Icons.lock, color: BridgeDSColors.of(context).accentGreen, size: 16),
                  SizedBox(width: 8),
                  Text(
                    '已安全儲存',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen,
                    ),
                  ),
                ],
              )
            else
              BridgeGlowButton(
                label: _apiSaving ? '儲存中...' : '儲存',
                icon: Icons.save_outlined,
                state: BridgeGlowButtonState.idle,
                onPressed: _apiSaving ? null : _saveConfig,
              ),

            // 進度指示器
            if (_apiTesting || _apiSaving) ...[
              SizedBox(width: 16),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: BridgeDSColors.of(context).accentBlue,
                ),
              ),
            ],
          ],
        ),

        // 測試成功：綠勾 + 模型清單
        if (_apiTestModels != null) ...[
          SizedBox(height: BridgeDS.spaceMD),
          Row(
            children: [
              Icon(Icons.check_circle, color: BridgeDSColors.of(context).accentGreen, size: 16),
              SizedBox(width: 8),
              Text(
                '連線成功，可用模型：',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          ..._apiTestModels!.take(10).map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 0, left: 04),
                  child: SelectableText(
                    m,
                    style: BridgeDSColors.of(context).code.copyWith(
                      fontSize: 14,
                      color: BridgeDSColors.of(context).textSecondary,
                    ),
                  ),
                ),
              ),
        ],

        // 測試錯誤
        if (_apiTestError != null) ...[
          SizedBox(height: BridgeDS.spaceMD),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: BridgeDSColors.of(context).accentRed, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  _apiTestError!,
                  style: BridgeDSColors.of(context).code.copyWith(
                    fontSize: 14,
                    color: BridgeDSColors.of(context).accentRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // 召喚入口
  // ═══════════════════════════════════════════════════

  Widget _buildSummonEntry() {
    final ready = _anyProviderReady;
    return AnimatedOpacity(
      opacity: ready ? 1.0 : 0.4,
      duration: BridgeDS.durationNormal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: ready
                ? () => context.go('/desktop-summon')
                : null,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('召喚第一位夥伴'),
            style: FilledButton.styleFrom(
              backgroundColor: ready ? BridgeDSColors.of(context).accentMiro : BridgeDSColors.of(context).surfaceElevated,
              foregroundColor: ready ? BridgeDSColors.of(context).textPrimary : BridgeDSColors.of(context).textMuted,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          SizedBox(height: BridgeDS.spaceMD),
          if (!ready)
            Text(
              '請先完成左方的 API 設定（測試 + 儲存）',
              style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted),
            )
          else
            Text(
              'API 已設定完成，可以召喚了！',
              style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).accentGreen),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Footer
  // ═══════════════════════════════════════════════════

  Widget _buildFooter() {
    return BridgeSlideIn(
      delay: const Duration(milliseconds: 600),
      child: Center(
        child: Text(
          '橋樑計畫 · AI 夥伴的家',
          style: BridgeDSColors.of(context).labelMono.copyWith(color: BridgeDSColors.of(context).textQuaternary),
        ),
      ),
    );
  }
}

/// Provider 選擇 chip — 有鎖定狀態指示
class _ProviderChip extends StatelessWidget {
  final String id;
  final String label;
  final bool isSelected;
  final bool isLocked; // 已儲存 = 綠鎖
  final VoidCallback onTap;

  _ProviderChip({
    required this.id,
    required this.label,
    required this.isSelected,
    this.isLocked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BridgeDS.durationFast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12)
              : BridgeDSColors.of(context).surfaceElevated,
          borderRadius: BorderRadius.circular(BridgeDS.roundPill),
          border: Border.all(
            color: isSelected
                ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.4)
                : BridgeDSColors.of(context).borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocked) ...[
              Icon(Icons.lock, size: 12, color: BridgeDSColors.of(context).accentGreen),
              SizedBox(width: 8),
            ],
            Text(
              label,
              style: BridgeDSColors.of(context).caption.copyWith(
                color: isSelected ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textTertiary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
