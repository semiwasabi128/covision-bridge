import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/achievement_store.dart';
import '../services/brain_progress_store.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class AchievementCollectionScreen extends StatefulWidget {
  const AchievementCollectionScreen({super.key});

  @override
  State<AchievementCollectionScreen> createState() =>
      _AchievementCollectionScreenState();
}

class _AchievementCollectionScreenState
    extends State<AchievementCollectionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('山門徽章'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => context.go('/companions'),
        ),
      ),
      body: FutureBuilder<_AchievementCollectionData>(
        future: _AchievementCollectionData.load(),
        builder: (context, snapshot) {
          // [P2-33 修復 2026-06-30] 處理載入錯誤
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '成就資料載入失敗',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/companions'),
                    child: const Text('返回夥伴館'),
                  ),
                ],
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // [P2-32 修復 2026-06-30] 空狀態處理
          if (AchievementStore.all.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    size: 64,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '還沒有成就',
                    style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '繼續使用橋樑 App，成就會自動解鎖',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              _ProgressHeader(data: data),
              const SizedBox(height: AppTheme.spacingM),
              Text(
                'SemiDAO 綠洲成就',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,),
              ),
              const SizedBox(height: AppTheme.spacingS),
              ...AchievementStore.all.map(
                (achievement) => Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppTheme.spacingM,
                  ), // [P3-14 修復 2026-06-30] 間距 8→16 更舒適
                  child: _AchievementCard(
                    achievement: achievement,
                    unlocked: data.unlockedIds.contains(achievement.id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AchievementCollectionData {
  final BrainProgressSnapshot progress;
  final Set<String> unlockedIds;

  const _AchievementCollectionData({
    required this.progress,
    required this.unlockedIds,
  });

  int get unlockedCount => unlockedIds.length;

  static Future<_AchievementCollectionData> load() async {
    final progress = await BrainProgressStore.getSnapshot();
    final unlockedIds = await AchievementStore.getUnlockedIds();
    return _AchievementCollectionData(
      progress: progress,
      unlockedIds: unlockedIds,
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final _AchievementCollectionData data;

  const _ProgressHeader({required this.data});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ds.accentMiro, ds.accentNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.secondary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  color: AppTheme.accent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '山門DAO / SemiDAO',
                      style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(color: ds.textPrimary,
                        fontWeight: FontWeight.w800,),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '已解鎖 ${data.unlockedCount}/${AchievementStore.all.length} 個徽章',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary.withValues(alpha: 0.7),),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          Row(
            children: [
              _MetricPill(text: 'Bridge Brain Lv ${data.progress.level}'),
              const SizedBox(width: 8),
              _MetricPill(text: '${data.progress.xp} XP'),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: data.progress.progress,
              backgroundColor: ds.canvas.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppTheme.secondary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${data.progress.currentLevelXp}/${data.progress.nextLevelXp} XP 到下一級',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary.withValues(alpha: 0.7),),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final AchievementDefinition achievement;
  final bool unlocked;

  const _AchievementCard({required this.achievement, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? AppTheme.secondary : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: unlocked ? AppTheme.surfaceHighlight : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: unlocked
              ? AppTheme.primary.withValues(alpha: 0.26)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: unlocked ? color : AppTheme.divider,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(
              unlocked ? Icons.emoji_events_outlined : Icons.lock_outline,
              color: unlocked ? AppTheme.accent : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: unlocked
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,),
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.description,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MetricPill(
            text: unlocked ? '+${achievement.xp} XP' : '未解鎖',
            dark: unlocked,
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String text;
  final bool dark;

  const _MetricPill({required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? ds.accentMiro.withValues(alpha: 0.1)
            : ds.textPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
      ),
      child: Text(
        text,
        style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: dark ? ds.accentMiro : ds.textPrimary,
          fontWeight: FontWeight.w800,),
      ),
    );
  }
}
