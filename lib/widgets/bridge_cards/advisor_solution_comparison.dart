// lib/widgets/bridge_cards/advisor_solution_comparison.dart
// [以利沙 Capability Advisor 2026-06-25]
// 方案比較表子 widget，被 CapabilityAdvisorCard 使用。

import 'package:flutter/material.dart';

import '../../models/capability_advisor.dart';
import '../../theme/app_theme.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class AdvisorSolutionComparison extends StatelessWidget {
  final List<SolutionCandidate> candidates;
  final String? inferredIntent;
  final String? selectedCandidateId;
  final void Function(String candidateId)? onSelect;

  const AdvisorSolutionComparison({
    super.key,
    required this.candidates,
    this.inferredIntent,
    this.selectedCandidateId,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Text(
          '目前沒有可比較的方案。',
          style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final candidate in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CandidateCard(
              candidate: candidate,
              isSelected: candidate.id == selectedCandidateId,
              onSelect: onSelect != null
                  ? () => onSelect!(candidate.id)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final SolutionCandidate candidate;
  final bool isSelected;
  final VoidCallback? onSelect;

  const _CandidateCard({
    required this.candidate,
    required this.isSelected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = candidate.isRecommended
        ? AppTheme.primary
        : isSelected
        ? AppTheme.primary
        : AppTheme.border;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: borderColor,
            width: candidate.isRecommended || isSelected ? 2 : 1,
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題行 ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        candidate.name,
                        style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle().copyWith(color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        candidate.provider,
                        style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,),
                      ),
                    ],
                  ),
                ),
                if (candidate.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Text(
                      'AI 推薦',
                      style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.primary,
                        fontWeight: FontWeight.w700,),
                    ),
                  ),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Text(
                      '已選',
                      style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.success,
                        fontWeight: FontWeight.w700,),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // ── 推薦分數條 ──
            _ScoreBar(
              label: '綜合推薦',
              score: candidate.overallScore,
              color: _scoreColor(candidate.overallScore),
            ),

            const SizedBox(height: 8),

            // ── 四維度比較 ──
            _DimensionRow(
              icon: Icons.payments_outlined,
              label: '預算',
              value: candidate.budgetSummary.isEmpty
                  ? candidate.paidPricingNote
                  : candidate.budgetSummary,
              score: candidate.hasFreeTier ? 80 : 50,
              scoreLabel: candidate.hasFreeTier ? '有免費額度' : '僅付費',
            ),
            const SizedBox(height: 5),
            _DimensionRow(
              icon: Icons.language,
              label: '中文支援',
              value: candidate.chineseSupportLevel,
              score: candidate.chineseSupportScore,
            ),
            const SizedBox(height: 5),
            _DimensionRow(
              icon: Icons.repeat,
              label: '使用頻率',
              value: candidate.usageFrequencyFit,
              score: candidate.usageFrequencyScore,
            ),
            const SizedBox(height: 5),
            _DimensionRow(
              icon: Icons.gps_fixed,
              label: '意圖貼合',
              value: candidate.intentFitNote,
              score: candidate.intentFitScore,
            ),

            // ── AI 評語 ──
            if (candidate.aiNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        candidate.aiNote,
                        style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
                          height: 1.35,),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── 選擇按鈕 ──
            if (onSelect != null && !isSelected) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text('選擇此方案', style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppTheme.success;
    if (score >= 60) return AppTheme.primary;
    if (score >= 40) return AppTheme.warning;
    return AppTheme.error;
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final int score;
  final Color color;

  const _ScoreBar({
    required this.label,
    required this.score,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              backgroundColor: AppTheme.divider,
              color: color,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 28,
          child: Text(
            '$score',
            textAlign: TextAlign.right,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: color,
              fontWeight: FontWeight.w900,),
          ),
        ),
      ],
    );
  }
}

class _DimensionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final int score;
  final String? scoreLabel;

  const _DimensionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.score,
    this.scoreLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppTheme.textMuted),
        const SizedBox(width: 5),
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SelectableText(
            value.isEmpty ? '—' : value,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
              height: 1.3,),
          ),
        ),
      ],
    );
  }
}
