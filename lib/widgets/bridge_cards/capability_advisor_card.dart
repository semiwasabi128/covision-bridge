import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/capability_advisor.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';
import 'advisor_solution_comparison.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../screens/bridge_desktop_screen.dart';

class CapabilityAdvisorCard extends StatefulWidget {
  final CapabilityAdvisorCardData data;

  // 回呼
  final VoidCallback? onConfirmIntent;
  // [以利沙 P1 修復 2026-06-26] browseGapDetected 專用：啟動子搜尋流程
  final VoidCallback? onStartBrowseSubFlow;
  final void Function(String correctedIntent)? onCorrectIntent;
  final void Function(String candidateId)? onSelectSolution;
  final void Function(String url)? onOpenUrl;
  final VoidCallback? onVerify;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onReturnToTask;

  const CapabilityAdvisorCard({
    super.key,
    required this.data,
    this.onConfirmIntent,
    this.onStartBrowseSubFlow,
    this.onCorrectIntent,
    this.onSelectSolution,
    this.onOpenUrl,
    this.onVerify,
    this.onRetry,
    this.onCancel,
    this.onReturnToTask,
  });

  @override
  State<CapabilityAdvisorCard> createState() => _CapabilityAdvisorCardState();
}

class _CapabilityAdvisorCardState extends State<CapabilityAdvisorCard> {
  final _intentCorrectionController = TextEditingController();
  bool _showIntentCorrection = false;

  @override
  void dispose() {
    _intentCorrectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.data.currentStep;

    return Container(
      width: 520,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: _borderColorForStep(step),
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: _buildBodyForStep(step),
    );
  }

  Color _borderColorForStep(CapabilityAdvisorStep step) {
    switch (step) {
      case CapabilityAdvisorStep.failed:
        return AppTheme.error.withValues(alpha: 0.42);
      case CapabilityAdvisorStep.verified:
        return AppTheme.success.withValues(alpha: 0.42);
      case CapabilityAdvisorStep.cancelled:
        return AppTheme.textMuted.withValues(alpha: 0.3);
      case CapabilityAdvisorStep.solutionSelected:
      case CapabilityAdvisorStep.presentingComparison:
      case CapabilityAdvisorStep.awaitingSelection:
        return AppTheme.primary.withValues(alpha: 0.36);
      default:
        return AppTheme.warning.withValues(alpha: 0.42);
    }
  }

  Widget _buildBodyForStep(CapabilityAdvisorStep step) {
    switch (step) {
      case CapabilityAdvisorStep.idle:
      case CapabilityAdvisorStep.checkingBrowse:
        return _buildLoading('正在確認搜尋能力...');

      case CapabilityAdvisorStep.browseGapDetected:
        return _buildBrowseGapDetected();

      case CapabilityAdvisorStep.searching:
        return _buildLoading('正在搜尋市面方案...');

      case CapabilityAdvisorStep.analyzing:
        return _buildLoading('正在分析方案貼合度...');

      case CapabilityAdvisorStep.presentingComparison:
        return _buildPresentingComparison();

      case CapabilityAdvisorStep.awaitingSelection:
        return _buildAwaitingSelection();

      case CapabilityAdvisorStep.solutionSelected:
        return _buildSolutionSelected();

      case CapabilityAdvisorStep.verifying:
        return _buildVerifying();

      case CapabilityAdvisorStep.verified:
        return _buildVerified();

      case CapabilityAdvisorStep.returningToTask:
        return _buildLoading('正在回到主線任務...');

      case CapabilityAdvisorStep.failed:
        return _buildFailed();

      case CapabilityAdvisorStep.cancelled:
        return _buildCancelled();
    }
  }

  // ── 載入中 ──

  Widget _buildLoading(String message) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                message,
                style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle().copyWith(color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,),
              ),
            ),
          ],
        ),
        if (widget.data.statusMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            widget.data.statusMessage,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
              height: 1.4,),
          ),
        ],
      ],
    );
  }

  // ── browseGapDetected ──

  Widget _buildBrowseGapDetected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: Icons.travel_explore,
          title: '需要先開通搜尋能力',
          subtitle: '我需要先能上網，才能幫你查有哪些可用的服務。讓我們先把「聯網能力」打開。',
          pillLabel: '前置步驟',
          pillColor: AppTheme.warning,
        ),
        const SizedBox(height: 12),
        if (widget.data.suspendedGap != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: SelectableText(
              '原始需求「${widget.data.suspendedGap!.gapLabel}」會在搜尋能力開通後繼續處理。',
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
                height: 1.35,),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                // [以利沙 P1 修復 2026-06-26]
                // 改用 onStartBrowseSubFlow，直接推進 searching 子流程，
                // 避免 candidates 為空時誤入 awaitingSelection。
                onPressed: widget.onStartBrowseSubFlow,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('好，先開通聯網能力'),
              ),
              OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('取消'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── presentingComparison ──

  Widget _buildPresentingComparison() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: Icons.lightbulb_outline,
          title: '方案比較分析',
          subtitle: '我搜尋並分析了以下方案，請確認我的理解是否正確。',
          pillLabel: '分析完成',
          pillColor: AppTheme.primary,
        ),

        // AI 推斷意圖
        if (widget.data.inferredIntent != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '我理解你的需求',
                      style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.primary,
                        fontWeight: FontWeight.w900,),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  widget.data.inferredIntent!,
                  style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    height: 1.4,),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),
        AdvisorSolutionComparison(
          candidates: widget.data.candidates,
          inferredIntent: widget.data.inferredIntent,
          selectedCandidateId: widget.data.selectedCandidateId,
        ),

        const SizedBox(height: 12),

        // 確認 / 修正按鈕
        if (_showIntentCorrection) ...[
          TextField(
            controller: _intentCorrectionController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: '請輸入你的真實需求...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () {
                  final text = _intentCorrectionController.text.trim();
                  if (text.isNotEmpty) {
                    widget.onCorrectIntent?.call(text);
                    setState(() => _showIntentCorrection = false);
                  }
                },
                child: Text('送出修正', style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() => _showIntentCorrection = false);
                },
                child: Text('取消修正', style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
              ),
            ],
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: widget.onConfirmIntent,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('理解正確，繼續選擇'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _intentCorrectionController.clear();
                    setState(() => _showIntentCorrection = true);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('修正我的需求'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('取消'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── awaitingSelection ──

  Widget _buildAwaitingSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: Icons.checklist,
          title: '請選擇方案',
          subtitle: widget.data.confirmedIntent ?? widget.data.statusMessage,
          pillLabel: '等待選擇',
          pillColor: AppTheme.primary,
        ),
        const SizedBox(height: 12),
        // [以利沙 修復四 2026-06-27] 若有推薦方案，加速選擇按鈕
        if (widget.data.candidates.any((c) => c.isRecommended)) ...[
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('幫我選 AI 推薦的方案'),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDS.orange700,
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: () {
              final recommended = widget.data.candidates.firstWhere((c) => c.isRecommended);
              widget.onSelectSolution?.call(recommended.id);
            },
          ),
          const SizedBox(height: 12),
        ],
        AdvisorSolutionComparison(
          candidates: widget.data.candidates,
          inferredIntent: widget.data.confirmedIntent,
          selectedCandidateId: widget.data.selectedCandidateId,
          onSelect: widget.onSelectSolution,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('取消'),
          ),
        ),
      ],
    );
  }

  // ── solutionSelected ──

  Widget _buildSolutionSelected() {
    final selected = widget.data.selectedCandidate;
    if (selected == null) {
      return _buildLoading('正在準備方案...');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: selected.deploymentType == SolutionDeploymentType.local
              ? Icons.dns_outlined
              : Icons.cloud_outlined,
          title: '已選定：${selected.name}',
          subtitle: selected.provider,
          pillLabel: selected.deploymentType == SolutionDeploymentType.local
              ? '本地部署'
              : selected.deploymentType == SolutionDeploymentType.hybrid
              ? '混合部署'
              : '雲端服務',
          pillColor: AppTheme.primary,
        ),

        // 開通步驟
        if (selected.setupSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '開通步驟',
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,),
          ),
          const SizedBox(height: 6),
          for (final entry in selected.setupSteps.asMap().entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${entry.key + 1}',
                      style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.primary,
                        fontWeight: FontWeight.w900,),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: SelectableText(
                      entry.value,
                      style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        height: 1.35,
                        fontWeight: FontWeight.w600,),
                    ),
                  ),
                ],
              ),
            ),
        ],

        // 驗證失敗訊息
        if (widget.data.verificationPassed == false &&
            widget.data.verificationResult != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    widget.data.verificationResult!,
                    style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.error,
                      height: 1.35,),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // 官方連結按鈕 或 本地部署完成按鈕
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (selected.officialUrl.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _launchUrl(selected.officialUrl),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('前往官方網站'),
                ),
              FilledButton.tonalIcon(
                onPressed: widget.onVerify,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('已完成開通，驗證'),
              ),
              OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('取消'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── verifying ──

  Widget _buildVerifying() {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                '正在驗證能力是否已開通...',
                style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle().copyWith(color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,),
              ),
            ),
          ],
        ),
        if (widget.data.statusMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            widget.data.statusMessage,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,),
          ),
        ],
      ],
    );
  }

  // ── verified ──

  Widget _buildVerified() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: Icons.check_circle,
          title: '驗證通過！',
          subtitle: widget.data.verificationResult ??
              '${widget.data.gapLabel}已成功開通。',
          pillLabel: '完成',
          pillColor: AppTheme.success,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.onReturnToTask,
            icon: const Icon(Icons.play_arrow_rounded, size: 17),
            label: const Text('回到主線任務'),
          ),
        ),
        // [以利沙 P2 修復十輪 2026-06-27] 二次 CTA：快捷前往設定確認 Ollama
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => BridgeDesktopScreen.navigateTo('system'),
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: const Text('前往確認設定'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: const BorderSide(color: Colors.white24),
            ),
          ),
        ),
      ],
    );
  }

  // ── failed ──

  Widget _buildFailed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: Icons.error_outline,
          title: '功能未開通',
          subtitle: '這項功能需要先在本機電腦設定才能使用',
          pillLabel: '提示',
          pillColor: AppTheme.textMuted,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCancel,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('知道了'),
          ),
        ),
      ],
    );
  }

  // ── cancelled ──

  Widget _buildCancelled() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          icon: Icons.cancel_outlined,
          title: '已取消',
          subtitle: widget.data.statusMessage,
          pillLabel: '已結束',
          pillColor: AppTheme.textMuted,
        ),
      ],
    );
  }

  // ── 共用標頭 ──

  Widget _buildHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required String pillLabel,
    required Color pillColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: pillColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                title,
                style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,),
              ),
              const SizedBox(height: 2),
              SelectableText(
                subtitle,
                style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.3,),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Text(
            pillLabel,
            style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: pillColor,
              fontWeight: FontWeight.w700,),
          ),
        ),
      ],
    );
  }

  // ── URL 啟動 ──

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // 通知 chat_screen 層
    widget.onOpenUrl?.call(url);

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 靜默失敗，chat_screen 的 onOpenUrl 可以做 fallback
    }
  }
}
