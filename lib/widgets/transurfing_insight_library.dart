import 'package:flutter/material.dart';

import '../models/brain_container/brain_room.dart';
import '../services/brain_progress_store.dart';
import '../services/memory_store.dart';
import '../theme/app_theme.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../theme/bridge_design_system.dart';

enum TransurfingInsightFilter { all, accurate, unreviewed, muted, inaccurate }

class TransurfingInsightLibrary extends StatefulWidget {
  final List<TransurfingInsightRecord> records;
  final BrainProgressSnapshot? progress;
  final Future<void> Function(
    String insight,
    TransurfingInsightFeedback feedback,
  )
  onFeedback;
  final Future<void> Function(String insight) onDelete;

  const TransurfingInsightLibrary({
    super.key,
    required this.records,
    this.progress,
    required this.onFeedback,
    required this.onDelete,
  });

  @override
  State<TransurfingInsightLibrary> createState() =>
      _TransurfingInsightLibraryState();
}

class _TransurfingInsightLibraryState extends State<TransurfingInsightLibrary> {
  TransurfingInsightFilter _filter = TransurfingInsightFilter.all;
  // [教練 Agent 2026-07-05] 按大腦房間分組折疊：每組獨立展開/收合狀態
  final Set<BrainRoom?> _expandedRooms = {};
  static const int _collapsedLimit = 3;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.records.where(_matchesFilter).toList();

    // [教練 Agent 2026-07-05] 按 BrainRoom 分組
    final grouped = <BrainRoom?, List<TransurfingInsightRecord>>{};
    for (final record in filtered) {
      grouped.putIfAbsent(record.room, () => []).add(record);
    }

    // 排序：有房間的按 BrainRoom.values 順序，null 排最後
    final sortedRooms = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        return a.index.compareTo(b.index);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_motion_outlined,
                color: AppTheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '洞察卡片庫',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,),
                ),
              ),
              Text(
                '${widget.records.length}',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,),
              ),
            ],
          ),
          if (widget.progress != null) ...[
            const SizedBox(height: 10),
            _BrainProgressBanner(progress: widget.progress!),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: TransurfingInsightFilter.values.map((filter) {
                final selected = filter == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_filterLabel(filter)),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = filter),
                    visualDensity: VisualDensity.compact,
                    labelStyle: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                      color: selected ? BridgeDSColors.of(context).textPrimary : AppTheme.textSecondary,),
                    selectedColor: AppTheme.primary,
                    backgroundColor: AppTheme.background,
                    side: BorderSide(
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.border.withValues(alpha: 0.8),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '這個分類目前沒有洞察',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted),
                ),
              ),
            )
          else
            // [教練 Agent 2026-07-05] 按房間分組折疊渲染
            ...sortedRooms.map((room) => _buildRoomSection(room, grouped[room]!)),
        ],
      ),
    );
  }

  /// 構建單一房間的分組區塊（可折疊）。
  Widget _buildRoomSection(BrainRoom? room, List<TransurfingInsightRecord> records) {
    final isExpanded = _expandedRooms.contains(room);
    final visibleRecords = isExpanded ? records : records.take(_collapsedLimit).toList();
    final hasMore = records.length > _collapsedLimit;
    final roomLabel = room?.displayName ?? '未分類';
    final roomIcon = room?.icon ?? '📋';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 房間標題列（可點擊折疊）
          GestureDetector(
            onTap: () => setState(() {
              if (isExpanded) {
                _expandedRooms.remove(room);
              } else {
                _expandedRooms.add(room);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Row(
                children: [
                  Text(roomIcon, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      roomLabel,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                        color: AppTheme.primary,),
                    ),
                  ),
                  Text(
                    '${records.length}',
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 卡片列表
          ...visibleRecords.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _InsightCard(
                record: record,
                onFeedback: widget.onFeedback,
                onDelete: widget.onDelete,
              ),
            ),
          ),
          // 展開/收合按鈕
          if (hasMore)
            GestureDetector(
              onTap: () => setState(() {
                if (isExpanded) {
                  _expandedRooms.remove(room);
                } else {
                  _expandedRooms.add(room);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  isExpanded
                      ? '收合 $roomLabel'
                      : '還有 ${records.length - _collapsedLimit} 條，展開全部',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                    color: AppTheme.primary,),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _matchesFilter(TransurfingInsightRecord record) {
    switch (_filter) {
      case TransurfingInsightFilter.all:
        return true;
      case TransurfingInsightFilter.accurate:
        return record.feedback == TransurfingInsightFeedback.accurate;
      case TransurfingInsightFilter.unreviewed:
        return record.feedback == null;
      case TransurfingInsightFilter.muted:
        return record.feedback == TransurfingInsightFeedback.muted;
      case TransurfingInsightFilter.inaccurate:
        return record.feedback == TransurfingInsightFeedback.inaccurate;
    }
  }

  String _filterLabel(TransurfingInsightFilter filter) {
    switch (filter) {
      case TransurfingInsightFilter.all:
        return '全部';
      case TransurfingInsightFilter.accurate:
        return '準確';
      case TransurfingInsightFilter.unreviewed:
        return '未校準';
      case TransurfingInsightFilter.muted:
        return '暫停';
      case TransurfingInsightFilter.inaccurate:
        return '不準';
    }
  }
}

class _InsightCard extends StatelessWidget {
  final TransurfingInsightRecord record;
  final Future<void> Function(
    String insight,
    TransurfingInsightFeedback feedback,
  )
  onFeedback;
  final Future<void> Function(String insight) onDelete;

  const _InsightCard({
    required this.record,
    required this.onFeedback,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = _status(record.feedback);
    final trust = _trust(record.trustScore);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: status.color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(status.icon, size: 17, color: status.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.insight,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.35,
                    color: AppTheme.textSecondary,),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TrustMeter(score: record.trustScore, trust: trust),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(status: status),
              _CardActionButton(
                label: '準確',
                icon: Icons.check_circle_outline,
                selected:
                    record.feedback == TransurfingInsightFeedback.accurate,
                onTap: () => onFeedback(
                  record.insight,
                  TransurfingInsightFeedback.accurate,
                ),
              ),
              _CardActionButton(
                label: '不準',
                icon: Icons.cancel_outlined,
                selected:
                    record.feedback == TransurfingInsightFeedback.inaccurate,
                onTap: () => onFeedback(
                  record.insight,
                  TransurfingInsightFeedback.inaccurate,
                ),
              ),
              _CardActionButton(
                label: '先別用',
                icon: Icons.visibility_off_outlined,
                selected: record.feedback == TransurfingInsightFeedback.muted,
                onTap: () => onFeedback(
                  record.insight,
                  TransurfingInsightFeedback.muted,
                ),
              ),
              IconButton(
                tooltip: '刪除',
                onPressed: () => onDelete(record.insight),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppTheme.error,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrainProgressBanner extends StatelessWidget {
  final BrainProgressSnapshot progress;

  const _BrainProgressBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    final color = _brainLevelColor(progress.level);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: color.withValues(alpha: 0.34)),
                ),
                child: Icon(
                  Icons.psychology_alt_outlined,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bridge Brain Lv ${progress.level}',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(fontWeight: FontWeight.w900,
                        color: color,),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '同步率 ${progress.currentLevelXp}/${progress.nextLevelXp} XP',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,),
                    ),
                  ],
                ),
              ),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: AppTheme.background.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: color, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '${(progress.progress * 100).round()}%',
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(fontWeight: FontWeight.w900,
                        color: color,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              color: color,
              backgroundColor: AppTheme.background.withValues(alpha: 0.74),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustMeter extends StatelessWidget {
  final int score;
  final _TrustTier trust;

  const _TrustMeter({required this.score, required this.trust});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: trust.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: trust.color.withValues(alpha: 0.24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.military_tech_outlined,
                    size: 13,
                    color: trust.color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Lv ${_levelFor(score)}',
                    style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(fontWeight: FontWeight.w900,
                      color: trust.color,),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${trust.label} $score%',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                  color: trust.color,),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 7,
            color: trust.color,
            backgroundColor: AppTheme.border.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CardActionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? AppTheme.primary : AppTheme.textSecondary,
        side: BorderSide(
          color: selected
              ? AppTheme.primary
              : AppTheme.border.withValues(alpha: 0.85),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        minimumSize: const Size(0, 32),
        textStyle: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _InsightStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: status.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 13, color: status.color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
              color: status.color,),
          ),
        ],
      ),
    );
  }
}

class _InsightStatus {
  final String label;
  final IconData icon;
  final Color color;

  const _InsightStatus({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _TrustTier {
  final String label;
  final Color color;

  const _TrustTier({required this.label, required this.color});
}

_TrustTier _trust(int score) {
  if (score >= 80) {
    return const _TrustTier(label: '高信任', color: AppTheme.success);
  }
  if (score >= 50) {
    return const _TrustTier(label: '穩定', color: AppTheme.primary);
  }
  if (score >= 20) {
    return const _TrustTier(label: '待觀察', color: AppTheme.warning);
  }
  return const _TrustTier(label: '低信任', color: AppTheme.error);
}

int _levelFor(int score) {
  return (score / 20).ceil().clamp(1, 5).toInt();
}

Color _brainLevelColor(int level) {
  if (level >= 5) return AppTheme.secondary;
  if (level >= 3) return AppTheme.primaryDark;
  return AppTheme.primary;
}

_InsightStatus _status(TransurfingInsightFeedback? feedback) {
  switch (feedback) {
    case TransurfingInsightFeedback.accurate:
      return const _InsightStatus(
        label: '準確',
        icon: Icons.verified_outlined,
        color: AppTheme.success,
      );
    case TransurfingInsightFeedback.inaccurate:
      return const _InsightStatus(
        label: '不準',
        icon: Icons.report_gmailerrorred_outlined,
        color: AppTheme.error,
      );
    case TransurfingInsightFeedback.muted:
      return const _InsightStatus(
        label: '暫停',
        icon: Icons.visibility_off_outlined,
        color: AppTheme.warning,
      );
    case null:
      return const _InsightStatus(
        label: '未校準',
        icon: Icons.radio_button_unchecked,
        color: AppTheme.textMuted,
      );
  }
}
