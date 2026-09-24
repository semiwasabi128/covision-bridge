// 橋樑 App — 角色定稿室
import '../core/responsive.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/agent_activity.dart';
import '../models/bridge_action.dart';
import '../models/companion.dart';
import '../services/bridge_action_executor.dart';
import '../services/companion_asset_manifest_service.dart';
import '../services/companion_store.dart';
import '../services/image_provider_resolver.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../widgets/companion_avatar_image.dart';
import '../widgets/companion_rig.dart';
import '../widgets/companion_rig_animator.dart';
import '../widgets/companion_art.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class CompanionAppearanceScreen extends StatefulWidget {
  final String companionId;
  final String? returnTo;
  final bool hideAppBar; // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏
  final VoidCallback? onBack; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式返回 callback
  final void Function(String page)? onNavigateTo; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式導航 callback

  const CompanionAppearanceScreen({
    super.key,
    required this.companionId,
    this.returnTo,
    this.hideAppBar = false,
    this.onBack,
    this.onNavigateTo,
  });

  @override
  State<CompanionAppearanceScreen> createState() =>
      _CompanionAppearanceScreenState();
}

class _CompanionAppearanceScreenState extends State<CompanionAppearanceScreen> {
  final _promptController = TextEditingController();
  final List<_Variation> _history = [];

  Companion? _companion;
  bool _isGenerating = false;
  int _currentSeed = 0;

  final List<String> _quickTags = const [
    '更有守護感',
    '更像桌面寵物',
    '加入發光標誌',
    '工作時更專注',
    '慶祝時更活潑',
    '更像稀有角色',
  ];

  @override
  void initState() {
    super.initState();
    _loadCompanion();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _loadCompanion() {
    final companion = CompanionStore().getById(widget.companionId);
    if (companion == null) return;
    setState(() {
      _companion = companion;
      _currentSeed = companion.appearanceSeed;
      _promptController.text = companion.appearancePrompt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final companion = _companion;
    if (companion == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28), // [P1-12 修復 2026-06-30] 統一返回箭頭
          onPressed: () => context.go('/companions'),
        ),
        title: const Text('角色定稿室'),
        backgroundColor: BridgeDSColors.of(context).canvas,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // [教練 Agent 2026-08-06] 用 Responsive helper 取代硬編碼 920
            final isWide = Responsive.isDesktop(context) ||
                constraints.maxWidth >= 920;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildRefinementColumn(companion)),
                        const SizedBox(width: AppTheme.spacingM),
                        SizedBox(
                          width: 430,
                          child: _buildAssetColumn(companion),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRefinementColumn(companion),
                        const SizedBox(height: AppTheme.spacingM),
                        _buildAssetColumn(companion),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRefinementColumn(Companion companion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroPreview(companion),
        const SizedBox(height: AppTheme.spacingL),
        _buildQuickTags(),
        const SizedBox(height: AppTheme.spacingL),
        _buildPromptEditor(),
        const SizedBox(height: AppTheme.spacingM),
        _buildRegenerateButton(),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingL),
          _buildVariationRail(companion),
        ],
        const SizedBox(height: AppTheme.spacingL),
        _buildCompleteButton(),
      ],
    );
  }

  Widget _buildHeroPreview(Companion companion) {
    final mbti = companion.mbtiType;
    final color = mbti != null
        ? Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')))
        : BridgeDSColors.of(context).accentBlue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.14),
            BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.10),
            BridgeDSColors.of(context).surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_fix_high, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companion.name,
                      style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(fontWeight: FontWeight.w900,
                        color: BridgeDSColors.of(context).textPrimary,),
                    ),
                    Text(
                      '${companion.mbtiCode} ${mbti?.name ?? ''} · ${companion.roleName}',
                      style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            // [小葵 2026-09-13] rig 分支封存（Blue 拍板回歸靜態圖）——重啟=恢復上面分支
            child: CompanionAvatarImage(
                    companion: companion,
                    mbtiCode: companion.mbtiCode,
                    seed: _currentSeed,
                    name: companion.name,
                    mood: AgentCompanionMood.proud,
                    action: AgentCompanionAction.bouncing,
                    size: 300,
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            _descriptionFor(companion),
            style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.42,),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTags() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in _quickTags)
          ActionChip(
            avatar: const Icon(Icons.auto_awesome, size: 15),
            label: Text(tag),
            onPressed: () {
              final current = _promptController.text.trim();
              _promptController.text = current.isEmpty ? tag : '$current，$tag';
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _buildPromptEditor() {
    return TextField(
      controller: _promptController,
      decoration: InputDecoration(
        labelText: '微調造型線索',
        hintText: '例如：更像桌面上的守護光靈，工作時眼睛會發亮',
        hintStyle: TextStyle(
        color: BridgeDSColors.of(context).textMuted
      ),
        filled: true,
        fillColor: BridgeDSColors.of(context).surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide:  BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1.4),
        ),
        contentPadding: const EdgeInsets.all(AppTheme.spacingM),
      ),
      maxLines: 3,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildRegenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isGenerating ? null : _onRegenerate,
        icon: _isGenerating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        label: const Text('重新生成這個造型'),
      ),
    );
  }

  Widget _buildVariationRail(Companion companion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text(
          '上一輪造型',
          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
            color: BridgeDSColors.of(context).textPrimary,),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _history.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final variation = _history[index];
              return InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                onTap: () {
                  setState(() {
                    _currentSeed = variation.seed;
                    _promptController.text = variation.prompt;
                  });
                },
                child: Container(
                  width: 96,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                      color: _currentSeed == variation.seed
                          ? BridgeDSColors.of(context).accentBlue
                          : BridgeDSColors.of(context).borderSubtle,
                      width: _currentSeed == variation.seed ? 2 : 1,
                    ),
                  ),
                  child: CompanionArt(
                    mbtiCode: companion.mbtiCode,
                    seed: variation.seed,
                    name: companion.name,
                    mood: AgentCompanionMood.curious,
                    action: AgentCompanionAction.wandering,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssetColumn(Companion companion) {
    final manifest = _manifestFor(companion);
    final states = (manifest['states'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    final includedAssets = (manifest['includedAssets'] as List<dynamic>)
        .whereType<String>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: BridgeDSColors.of(context).accentBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                   Expanded(
                    child: Text(
                      '定稿資產包',
                      style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.w900,
                        color: BridgeDSColors.of(context).textPrimary,),
                    ),
                  ),
                  Text(
                    '${includedAssets.length} assets',
                    style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,
                      fontWeight: FontWeight.w800,),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CompanionArtSheet(
                mbtiCode: companion.mbtiCode,
                seed: _currentSeed,
                name: companion.name,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildChip('Engine', manifest['renderEngine'] as String),
                  _buildChip('Seed', '$_currentSeed'),
                  _buildChip('Pack', 'Companion Pack'),
                ],
              ),
              const SizedBox(height: 12),
              for (final state in states.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 15,
                        color: BridgeDSColors.of(context).accentGreen,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${state['label']} · ${state['mood']} / ${state['action']}',
                          style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Text(
        '$label: $value',
        style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(fontWeight: FontWeight.w700,
          color: BridgeDSColors.of(context).textSecondary,),
      ),
    );
  }

  Widget _buildCompleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: _onComplete,
        icon: const Icon(Icons.verified),
        label: const Text('定稿並啟用夥伴'),
      ),
    );
  }

  Map<String, dynamic> _manifestFor(Companion companion) {
    return const CompanionAssetManifestService().buildManifest(
      companionId: companion.id,
      name: companion.name,
      mbtiCode: companion.mbtiCode,
      seed: _currentSeed,
      appearancePrompt: _promptController.text,
      appearanceDescription: _descriptionFor(companion),
      characterSheetPrompts: companion.appearanceHistory,
      primaryImagePath: companion.avatarImagePath,
      primaryAnimationPath: companion.avatarAnimationPath,
    );
  }

  String _descriptionFor(Companion companion) {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return companion.appearanceDescription;
    return '${companion.appearanceDescription} 微調線索：$prompt';
  }

  void _onRegenerate() {
    final companion = _companion;
    if (companion == null || _isGenerating) return;

    final hasPrimary =
        companion.avatarImagePath?.trim().isNotEmpty == true;
    final hasSheets = companion.stateImagePaths.values
        .any((p) => p.trim().isNotEmpty);

    // [小葵 2026-09-14] 覆蓋確認——已有主形象/狀態圖時提醒會被覆蓋（Blue 要求）
    Future<void> doRegenerate() async {
      setState(() => _isGenerating = true);
      try {
        // [小葵 2026-09-14] 真實 API 調用——原本是假按鈕（只改 seed + 650ms 假等待），
        // 違反「功能必須真正可用（非 UI 殼）」鐵則。
        final models = await ImageProviderResolver.resolveAll();
        final model = models.isNotEmpty ? models.first : null;
        final prompt = 'Create a polished character portrait for an AI '
            'desktop companion. Name: ${companion.name}. '
            'Visual clues: ${_promptController.text.trim().isEmpty ? companion.appearancePrompt : _promptController.text.trim()} '
            'Full body, transparent background, PNG sprite asset, centered, '
            'no text, no logo.';
        final executor = BridgeActionExecutor();
        final result = await executor.execute(
          BridgeAction(
            type: BridgeActionType.generateImage,
            prompt: prompt,
            provider: model?.providerId,
            model: model?.defaultModel,
            imageQuality: model?.quality,
          ),
        );
        if (!mounted) return;
        if (result.status == BridgeActionStatus.completed &&
            result.mediaUrl != null &&
            result.mediaUrl!.trim().isNotEmpty) {
          final updated = companion.copyWith(
            avatarImagePath: result.mediaUrl,
            appearanceSeed:
                DateTime.now().millisecondsSinceEpoch % 10000,
          );
          await CompanionStore().update(updated);
          setState(() {
            _companion = updated;
            _history.insert(
              0,
              _Variation(seed: _currentSeed, prompt: _promptController.text),
            );
            if (_history.length > 5) _history.removeLast();
            _currentSeed = updated.appearanceSeed;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('重新生成失敗：${result.message}')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重新生成失敗：$e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isGenerating = false);
      }
    }

    if (hasPrimary || hasSheets) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重新生成主形象'),
          content: const Text(
            '將會把原有主形象與狀態圖覆蓋，確定要這麼做嗎？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                doRegenerate();
              },
              child: const Text('確定覆蓋'),
            ),
          ],
        ),
      );
      return;
    }
    doRegenerate();
  }

  Future<void> _onComplete() async {
    final companion = _companion;
    if (companion == null) return;

    final updated = companion.copyWith(
      appearancePrompt: _promptController.text,
      appearanceDescription: _descriptionFor(companion),
      appearanceSeed: _currentSeed,
    );

    await CompanionStore().update(updated);
    await CompanionStore().setActive(updated.id);
    if (!mounted) return;
    context.go('/companions');
  }
}

class _Variation {
  final int seed;
  final String prompt;

  const _Variation({required this.seed, required this.prompt});
}
